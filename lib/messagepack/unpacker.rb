# frozen_string_literal: true

require_relative 'buffer'
require_relative 'format'

module Messagepack
  # Unpacker deserializes MessagePack binary data into Ruby objects.
  #
  # Usage:
  #   unpacker = Messagepack::Unpacker.new
  #   unpacker.feed(data)
  #   obj = unpacker.read
  #
  # Or for one-shot operations:
  #   obj = Messagepack::Unpacker.new.full_unpack(data)
  #
  class Unpacker
    STACK_CAPACITY = 128

    # Disable dup and clone as they have weird semantics
    undef_method :dup
    undef_method :clone

    # Sentinel to distinguish "no data" from "nil value"
    UNAVAILABLE = Object.new

    attr_reader :buffer, :symbolize_keys, :freeze_objects, :allow_unknown_ext, :optimized_symbols_parsing, :frozen

    # Predicate methods for boolean options
    def symbolize_keys?
      @symbolize_keys
    end

    def freeze?
      @freeze_objects
    end

    def allow_unknown_ext?
      @allow_unknown_ext
    end

    def optimized_symbols_parsing?
      @optimized_symbols_parsing
    end

    def initialize(io = nil, symbolize_keys: false, freeze: false,
                   allow_unknown_ext: false, optimized_symbols_parsing: false, **kwargs)
      @buffer = BinaryBuffer.new(io)
      @symbolize_keys = symbolize_keys
      @freeze_objects = freeze
      @allow_unknown_ext = allow_unknown_ext
      @optimized_symbols_parsing = optimized_symbols_parsing
      @ext_registry = ExtensionRegistry::Unpacker.new
      @frozen = false  # Custom frozen flag for pool

      @stack = []
      @last_object = nil
      @head_byte = nil
      @head_byte_consumed = false  # Track if we've already consumed the format byte
      @fed_data = false  # Track if any data has been fed

      # Partial read state for strings/binaries
      @partial_read = nil  # Stores {type: :str8/:str16/:etc, length: n, buffer: ""}
    end

    # Set the extension registry for this unpacker.
    # Used internally by Factory to inject custom type registrations.
    #
    # @param registry [ExtensionRegistry::Unpacker] The extension registry to use
    #
    def extension_registry=(registry)
      @ext_registry = registry
    end

    # Mark this unpacker as frozen for pool use.
    # Prevents type registration when used from a pool.
    #
    def freeze_for_pool
      @frozen = true
    end

    # Feed more data for streaming.
    def feed(data)
      @buffer.feed(data)
      @fed_data = true  # Mark that data has been fed
      self
    end

    alias << feed

    # Read one complete object.
    # Returns nil if not enough data is available.
    def read
      result = nil

      loop do
        # If we have a partial read in progress, try to complete it
        if @partial_read
          obj = complete_partial_read
          if obj.equal?(UNAVAILABLE)
            # Still need more data
            return nil
          else
            # Partial read complete, process and return
            @partial_read = nil
            obj = process_object(obj)
            next if obj.equal?(UNAVAILABLE)
            result = obj
            break
          end
        end

        # Read the format byte
        # For non-IO case, use peek_byte to avoid consuming before we know we have enough data
        # For IO case, use read_byte to trigger reading from the IO
        if @buffer.io
          # Always use read_byte for IO (it will trigger ensure_readable)
          @head_byte ||= @buffer.read_byte
          @head_byte_consumed = true
        else
          # Non-IO case: use peek_byte
          @head_byte ||= @buffer.peek_byte
          @head_byte_consumed = false
        end

        # If no format byte is available, handle EOF or IO case
        if @head_byte.nil?
          if @buffer.io
            # For IO case, check if we've consumed all data
            # If buffer is empty and we've read all bytes from IO, return nil (not an error)
            if @buffer.bytes_available == 0 && @buffer.instance_variable_get(:@position) >= @buffer.instance_variable_get(:@length)
              # IO is fully consumed, return nil
              return nil
            elsif !@fed_data
              # Couldn't read from IO on first attempt (empty IO)
              raise EOFError, "no data available"
            else
              # Already tried reading from IO, return nil
              return nil
            end
          else
            # No IO and no data
            if !@fed_data
              raise EOFError, "no data available"
            else
              return nil
            end
          end
        end

        format_byte = @head_byte

        # Check if we have enough bytes to parse this format
        # Note: For IO case, format byte is already consumed, so we need one less byte
        needed_bytes = needed_bytes_for_format(format_byte)
        if needed_bytes
          # Adjust for already-consumed format byte
          needed_bytes -= 1 if @head_byte_consumed
          unless @buffer.bytes_available >= needed_bytes
            return nil
          end
        else
          # needed_bytes_for_format returned false (error case)
          return nil
        end

        # Consume the format byte if we peeked at it
        unless @head_byte_consumed
          @buffer.read_byte
        end

        # Clear @head_byte before dispatching to avoid re-reading the same byte
        @head_byte = nil
        @head_byte_consumed = false

        obj = dispatch_read(format_byte)

        # If we couldn't read anything and have no stack, return nil
        if obj.equal?(UNAVAILABLE) && @stack.empty? && @partial_read.nil?
          return nil
        elsif obj.equal?(UNAVAILABLE)
          # We're in the middle of reading a container, continue loop
          next
        end

        # Process the object we just read (or completed nested container)
        obj = process_object(obj)

        # If process_object returned UNAVAILABLE (need more elements for container),
        # continue the loop to try reading more data from the buffer
        if obj.equal?(UNAVAILABLE)
          # Check if we have more data in the buffer to continue reading
          # For IO streams, peek_byte might return nil even if more data is available
          # (because peek_byte doesn't trigger ensure_readable), so also check for IO
          if @buffer.peek_byte || @buffer.io
            # Have more data in buffer, or have IO to try reading from
            next
          end
          # No more data and no IO, return nil to wait for more
          return nil
        end

        # If we got a result and stack is now empty, we're done
        if !obj.nil? && @stack.empty?
          result = obj
          break
        end
      end

      result
    end

    # Get the number of bytes needed to parse the given format byte
    # Returns nil if the format is unknown
    def needed_bytes_for_format(format_byte)
      available = @buffer.bytes_available

      # For each format type, determine the total bytes needed (format + data)
      needed_bytes = case format_byte
      when 0x00..0x7f  # positive fixnum
        1  # Format byte is the value
      when 0xe0..0xff  # negative fixnum
        1  # Format byte is the value
      when 0xa0..0xbf  # fixstr
        1 + (format_byte & 0x1f)  # Format byte + length in lower 5 bits
      when 0x90..0x9f  # fixarray
        1  # Format byte (elements are parsed separately)
      when 0x80..0x8f  # fixmap
        1  # Format byte (elements are parsed separately)
      when 0xc0  # nil
        1
      when 0xc2  # false
        1
      when 0xc3  # true
        1
      when 0xc4  # bin8
        # Need to peek at length byte (after format byte)
        return nil if available < 2
        buffer_data = @buffer.to_s
        length = buffer_data.getbyte(1)
        return nil if length.nil?
        1 + 1 + length  # format + length + data
      when 0xc5  # bin16
        return nil if available < 3
        buffer_data = @buffer.to_s
        length = buffer_data.byteslice(1, 2).unpack1('n') rescue 0
        1 + 2 + length
      when 0xc6  # bin32
        return nil if available < 5
        buffer_data = @buffer.to_s
        length = buffer_data.byteslice(1, 4).unpack1('N') rescue 0
        1 + 4 + length
      when 0xc7  # ext8
        return nil if available < 2
        buffer_data = @buffer.to_s
        length = buffer_data.getbyte(1)  # Length of payload
        return nil if length.nil?
        1 + 1 + 1 + length  # format + length + type + payload
      when 0xc8  # ext16
        return nil if available < 3
        buffer_data = @buffer.to_s
        length = buffer_data.byteslice(1, 2).unpack1('n') rescue 0
        1 + 2 + 1 + length
      when 0xc9  # ext32
        return nil if available < 5
        buffer_data = @buffer.to_s
        length = buffer_data.byteslice(1, 4).unpack1('N') rescue 0
        1 + 4 + 1 + length
      when 0xca  # float32
        1 + 4  # format + 4 data bytes
      when 0xcb  # float64
        1 + 8  # format + 8 data bytes
      when 0xcc  # uint8
        1 + 1  # format + 1 data byte
      when 0xcd  # uint16
        1 + 2  # format + 2 data bytes
      when 0xce  # uint32
        1 + 4  # format + 4 data bytes
      when 0xcf  # uint64
        1 + 8  # format + 8 data bytes
      when 0xd0  # int8
        1 + 1  # format + 1 data byte
      when 0xd1  # int16
        1 + 2  # format + 2 data bytes
      when 0xd2  # int32
        1 + 4  # format + 4 data bytes
      when 0xd3  # int64
        1 + 8  # format + 8 data bytes
      when 0xd4  # fixext1
        1 + 1  # format + 1 type + 1 data
      when 0xd5  # fixext2
        1 + 1 + 2
      when 0xd6  # fixext4
        1 + 1 + 4
      when 0xd7  # fixext8
        1 + 1 + 8
      when 0xd8  # fixext16
        1 + 1 + 16
      when 0xd9  # str8
        return nil if available < 2
        buffer_data = @buffer.to_s
        length = buffer_data.getbyte(1)
        return nil if length.nil?
        1 + 1 + length
      when 0xda  # str16
        return nil if available < 3
        buffer_data = @buffer.to_s
        length = buffer_data.byteslice(1, 2).unpack1('n') rescue 0
        1 + 2 + length
      when 0xdb  # str32
        return nil if available < 5
        buffer_data = @buffer.to_s
        length = buffer_data.byteslice(1, 4).unpack1('N') rescue 0
        1 + 4 + length
      when 0xdc  # array16
        1 + 2  # format + 2 bytes count
      when 0xdd  # array32
        1 + 4
      when 0xde  # map16
        1 + 2
      when 0xdf  # map32
        1 + 4
      else
        raise MalformedFormatError, "Unknown format byte: 0x#{format_byte.to_s(16)}"
      end
      # Returns the number of bytes needed for this format
    end

    # Complete a partial read (string/binary that spanned multiple feed calls)
    def complete_partial_read
      type = @partial_read[:type]
      length = @partial_read[:length]

      case type
      when :str8, :bin8
        data = @buffer.read_bytes(length)
        if data.nil?
          UNAVAILABLE
        else
          @partial_read = nil
          data.force_encoding(type == :str8 ? Encoding::UTF_8 : Encoding::BINARY)
        end
      when :str16, :bin16
        data = @buffer.read_bytes(length)
        if data.nil?
          UNAVAILABLE
        else
          @partial_read = nil
          data.force_encoding(type == :str16 ? Encoding::UTF_8 : Encoding::BINARY)
        end
      when :str32, :bin32
        data = @buffer.read_bytes(length)
        if data.nil?
          UNAVAILABLE
        else
          @partial_read = nil
          data.force_encoding(type == :str32 ? Encoding::UTF_8 : Encoding::BINARY)
        end
      when :fixstr
        data = @buffer.read_bytes(length)
        if data.nil?
          UNAVAILABLE
        else
          @partial_read = nil
          data.force_encoding(Encoding::UTF_8)
        end
      when :fixext1, :fixext2, :fixext4, :fixext8, :fixext16
        ext_size = { fixext1: 1, fixext2: 2, fixext4: 4, fixext8: 8, fixext16: 16 }[type]
        payload = @buffer.read_bytes(ext_size)
        if payload.nil?
          UNAVAILABLE
        else
          @partial_read = nil
          ExtensionValue.new(@partial_read[:ext_type], payload)
        end
      when :ext8, :ext16, :ext32
        payload = @buffer.read_bytes(length)
        if payload.nil?
          UNAVAILABLE
        else
          @partial_read = nil
          ExtensionValue.new(@partial_read[:ext_type], payload)
        end
      else
        UNAVAILABLE
      end
    end

    # Process an object that was just read or a completed nested container
    def process_object(obj)
      # Keep processing while we have nested context
      while !@stack.empty?
        frame = @stack.last

        case frame.type
        when :array
          frame.object << obj
          frame.count -= 1
          if frame.count == 0
            # Array complete, pop and return for parent processing
            obj = complete_array(@stack.pop.object)
            # Continue to add this to parent frame
            next
          else
            # Need more elements for this array
            return UNAVAILABLE
          end
        when :map_key
          # Convert string keys to symbols if symbolize_keys is enabled
          if @symbolize_keys && obj.is_a?(String)
            obj = obj.to_sym
          end
          frame.key = obj
          frame.type = :map_value
          return UNAVAILABLE  # Need to read the value
        when :map_value
          # obj is the value, frame.key is the key
          frame.object[frame.key] = obj
          frame.count -= 1
          if frame.count == 0
            # Map complete, pop and return for parent processing
            obj = complete_map(@stack.pop.object)
            # Continue to add this to parent frame
            next
          else
            frame.type = :map_key
            return UNAVAILABLE  # Need to read next key
          end
        end
      end

      # Stack is empty, this is the final result
      # Apply freeze option if enabled
      if @freeze_objects
        obj = freeze_object(obj)
      end

      obj
    end

    # Freeze an object and all its contents recursively.
    def freeze_object(obj)
      return obj if obj.frozen?

      case obj
      when String
        # Use -'' syntax to create frozen/deduped string
        -obj
      when Array
        obj.each_with_index do |item, i|
          obj[i] = freeze_object(item)
        end
        obj.freeze
      when Hash
        # First, recursively freeze all keys and values (before freezing the hash)
        new_hash = {}
        obj.each do |k, v|
          frozen_key = freeze_object(k)
          frozen_value = freeze_object(v)
          new_hash[frozen_key] = frozen_value
        end
        # Replace the hash contents with the frozen version
        obj.clear
        new_hash.each { |k, v| obj[k] = v }
        obj.freeze
      else
        obj
      end
    end

    # Read and return array header count.
    def read_array_header
      byte = @buffer.read_byte
      raise UnexpectedTypeError, "no data" if byte.nil?

      count = case
      when Format.fixarray?(byte)
        Format.fixarray_count(byte)
      when byte == Format::ARRAY16
        n = @buffer.read_big_endian_uint16
        raise UnexpectedTypeError, "unexpected EOF" if n.nil?
        n
      when byte == Format::ARRAY32
        n = @buffer.read_big_endian_uint32
        raise UnexpectedTypeError, "unexpected EOF" if n.nil?
        n
      else
        raise UnexpectedTypeError, "unexpected format (byte=0x#{byte.to_s(16)})"
      end

      count
    end

    # Read and return map header count.
    def read_map_header
      byte = @buffer.read_byte
      raise UnexpectedTypeError, "no data" if byte.nil?

      count = case
      when Format.fixmap?(byte)
        Format.fixmap_count(byte)
      when byte == Format::MAP16
        n = @buffer.read_big_endian_uint16
        raise UnexpectedTypeError, "unexpected EOF" if n.nil?
        n
      when byte == Format::MAP32
        n = @buffer.read_big_endian_uint32
        raise UnexpectedTypeError, "unexpected EOF" if n.nil?
        n
      else
        raise UnexpectedTypeError, "unexpected format (byte=0x#{byte.to_s(16)})"
      end

      count
    end

    # Iterate over all objects in the buffer.
    def each
      return enum_for(__method__) unless block_given?

      while obj = read
        yield obj
      end
    end

    # Read single object and reset.
    def full_unpack
      obj = read
      # Check for extra bytes after the deserialized object
      # Only check if not reading from an IO (which could have more data)
      if !@buffer.io && !@buffer.empty?
        raise MalformedFormatError, "#{@buffer.bytes_available} extra bytes after the deserialized object"
      end
      reset
      obj
    end

    alias unpack full_unpack

    # Reset unpacker state.
    def reset
      @buffer.reset
      @stack.clear
      @last_object = nil
      @head_byte = nil
      @head_byte_consumed = false
      @partial_read = nil
      @frozen = false
      self
    end

    # Feed data and iterate over all objects in the buffer.
    #
    # @param data [String] Binary data to feed
    # @yield [Object] Each unpacked object
    # @return [Enumerator] Enumerator if no block given
    #
    def feed_each(data)
      return enum_for(__method__, data) unless block_given?

      feed(data)
      each { |obj| yield obj }
    end

    # Skip one complete object without deserializing it.
    #
    # @return [self]
    # @raise [EOFError] if no data is available
    # @raise [StackError] if stack depth exceeds capacity
    # @raise [MalformedFormatError] if invalid format byte encountered
    #
    def skip
      # Check if we have data
      @head_byte ||= @buffer.read_byte
      raise EOFError, "no data available" if @head_byte.nil?

      # Use a temporary stack to track nesting during skip
      temp_stack = []
      byte = @head_byte

      loop do
        # Check stack depth
        if temp_stack.length > STACK_CAPACITY
          raise StackError, "stack depth too deep"
        end

        case byte
        when 0x00..0x7f # Positive fixint
          # Single byte, done if stack empty
          break if temp_stack.empty?
          # Otherwise, we're inside a container
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xe0..0xff # Negative fixint
          # Single byte, done if stack empty
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xc0 # nil
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xc2 # false
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xc3 # true
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xcc # uint8
          @buffer.skip_bytes(1)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xcd # uint16
          @buffer.skip_bytes(2)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xce # uint32
          @buffer.skip_bytes(4)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xcf # uint64
          @buffer.skip_bytes(8)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xd0 # int8
          @buffer.skip_bytes(1)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xd1 # int16
          @buffer.skip_bytes(2)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xd2 # int32
          @buffer.skip_bytes(4)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xd3 # int64
          @buffer.skip_bytes(8)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xca # float32
          @buffer.skip_bytes(4)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xcb # float64
          @buffer.skip_bytes(8)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xa0..0xbf # fixstr
          length = byte & 0x1f
          @buffer.skip_bytes(length)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xd9 # str8
          length = @buffer.read_byte
          raise EOFError, "unexpected end of data" if length.nil?
          @buffer.skip_bytes(length)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xda # str16
          length = @buffer.read_big_endian_uint16
          raise EOFError, "unexpected end of data" if length.nil?
          @buffer.skip_bytes(length)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xdb # str32
          length = @buffer.read_big_endian_uint32
          raise EOFError, "unexpected end of data" if length.nil?
          @buffer.skip_bytes(length)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xc4 # bin8
          length = @buffer.read_byte
          raise EOFError, "unexpected end of data" if length.nil?
          @buffer.skip_bytes(length)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xc5 # bin16
          length = @buffer.read_big_endian_uint16
          raise EOFError, "unexpected end of data" if length.nil?
          @buffer.skip_bytes(length)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xc6 # bin32
          length = @buffer.read_big_endian_uint32
          raise EOFError, "unexpected end of data" if length.nil?
          @buffer.skip_bytes(length)
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xd4..0xd8 # fixext
          sizes = { 0xd4 => 1, 0xd5 => 2, 0xd6 => 4, 0xd7 => 8, 0xd8 => 16 }
          length = sizes[byte]
          @buffer.skip_bytes(1 + length) # type + payload
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xc7 # ext8
          length = @buffer.read_byte
          raise EOFError, "unexpected end of data" if length.nil?
          @buffer.skip_bytes(1 + length) # type + payload
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xc8 # ext16
          length = @buffer.read_big_endian_uint16
          raise EOFError, "unexpected end of data" if length.nil?
          @buffer.skip_bytes(2 + length) # type + payload
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0xc9 # ext32
          length = @buffer.read_big_endian_uint32
          raise EOFError, "unexpected end of data" if length.nil?
          @buffer.skip_bytes(4 + length) # type + payload
          break if temp_stack.empty?
          temp_stack[-1] -= 1
          break if temp_stack[-1] == 0
          temp_stack.pop if temp_stack[-1] == 0

        when 0x90..0x9f # fixarray
          count = byte & 0x0f
          if count > 0
            temp_stack.push(count)
          else
            break if temp_stack.empty?
            temp_stack[-1] -= 1
            break if temp_stack[-1] == 0
            temp_stack.pop if temp_stack[-1] == 0
          end

        when 0xdc # array16
          count = @buffer.read_big_endian_uint16
          raise EOFError, "unexpected end of data" if count.nil?
          if count > 0
            temp_stack.push(count)
          else
            break if temp_stack.empty?
            temp_stack[-1] -= 1
            break if temp_stack[-1] == 0
            temp_stack.pop if temp_stack[-1] == 0
          end

        when 0xdd # array32
          count = @buffer.read_big_endian_uint32
          raise EOFError, "unexpected end of data" if count.nil?
          if count > 0
            temp_stack.push(count)
          else
            break if temp_stack.empty?
            temp_stack[-1] -= 1
            break if temp_stack[-1] == 0
            temp_stack.pop if temp_stack[-1] == 0
          end

        when 0x80..0x8f # fixmap
          count = byte & 0x0f
          if count > 0
            temp_stack.push(count * 2) # Map has key-value pairs
          else
            break if temp_stack.empty?
            temp_stack[-1] -= 1
            break if temp_stack[-1] == 0
            temp_stack.pop if temp_stack[-1] == 0
          end

        when 0xde # map16
          count = @buffer.read_big_endian_uint16
          raise EOFError, "unexpected end of data" if count.nil?
          if count > 0
            temp_stack.push(count * 2)
          else
            break if temp_stack.empty?
            temp_stack[-1] -= 1
            break if temp_stack[-1] == 0
            temp_stack.pop if temp_stack[-1] == 0
          end

        when 0xdf # map32
          count = @buffer.read_big_endian_uint32
          raise EOFError, "unexpected end of data" if count.nil?
          if count > 0
            temp_stack.push(count * 2)
          else
            break if temp_stack.empty?
            temp_stack[-1] -= 1
            break if temp_stack[-1] == 0
            temp_stack.pop if temp_stack[-1] == 0
          end

        else
          raise MalformedFormatError, "unknown format byte: 0x#{byte.to_s(16)}"
        end

        # Read next byte for next iteration
        byte = @buffer.read_byte
        break if byte.nil? && temp_stack.empty?
        raise EOFError, "unexpected end of data" if byte.nil?
      end

      # Clear the head byte since we've consumed it during skip
      @head_byte = nil
      self
    end

    # Skip nil value or return false if next object is not nil.
    #
    # @return [Boolean] true if skipped nil, false otherwise
    # @raise [EOFError] if no data is available
    #
    def skip_nil
      @head_byte ||= @buffer.read_byte
      raise EOFError, "no data available" if @head_byte.nil?

      if @head_byte == Format::NIL
        @head_byte = nil
        return true
      else
        # Not a nil, don't consume the byte (it will be used by next read)
        return false
      end
    end

    # Extension type registration

    def register_type(type_id, klass = nil, unpacker_proc = nil, &block)
      raise FrozenError, "can't modify frozen Messagepack::Unpacker" if @frozen

      # Handle multiple calling patterns:
      # register_type(type_id) { |data| ... }
      # register_type(type_id, klass) { |data| ... }
      # register_type(type_id, klass, :method_name)
      # register_type(type_id, klass, proc)

      if block_given?
        unpacker_proc = block
      elsif unpacker_proc.is_a?(Symbol)
        # Convert symbol to proc (use a local variable to avoid capture issues)
        method_name = unpacker_proc
        unpacker_proc = ->(data) { klass.send(method_name, data) }
      elsif klass.is_a?(Symbol)
        # register_type(type_id, :method_name) pattern
        unpacker_proc = ->(data) { Object.send(klass, data) }
        klass = nil
      elsif klass&.respond_to?(:call)
        # klass is actually a proc
        unpacker_proc = klass
        klass = nil
      end

      @ext_registry.register(type_id, klass, unpacker_proc)
    end

    def registered_types
      @ext_registry.registered_types
    end

    def type_registered?(klass_or_type)
      @ext_registry.type_registered?(klass_or_type)
    end

    private

    # StackFrame class for tracking nested structures
    class StackFrame
      attr_accessor :count, :type, :object, :key

      def initialize(type, count, object = nil)
        @type = type
        @count = count
        @object = object
        @key = nil
      end
    end

    # Type dispatch based on first byte
    def dispatch_read(byte)
      return UNAVAILABLE if byte.nil?

      case byte
      when 0x00..0x7f
        read_positive_fixnum(byte)
      when 0xe0..0xff
        read_negative_fixnum(byte)
      when 0xa0..0xbf
        read_fixstr(byte)
      when 0x90..0x9f
        read_fixarray(byte)
      when 0x80..0x8f
        read_fixmap(byte)
      when 0xc0
        read_nil
      when 0xc2
        read_false
      when 0xc3
        read_true
      when 0xc4
        read_bin8
      when 0xc5
        read_bin16
      when 0xc6
        read_bin32
      when 0xc7
        read_ext8
      when 0xc8
        read_ext16
      when 0xc9
        read_ext32
      when 0xca
        read_float32
      when 0xcb
        read_float64
      when 0xcc
        read_uint8
      when 0xcd
        read_uint16
      when 0xce
        read_uint32
      when 0xcf
        read_uint64
      when 0xd0
        read_int8
      when 0xd1
        read_int16
      when 0xd2
        read_int32
      when 0xd3
        read_int64
      when 0xd4
        read_fixext1
      when 0xd5
        read_fixext2
      when 0xd6
        read_fixext4
      when 0xd7
        read_fixext8
      when 0xd8
        read_fixext16
      when 0xd9
        read_str8
      when 0xda
        read_str16
      when 0xdb
        read_str32
      when 0xdc
        read_array16
      when 0xdd
        read_array32
      when 0xde
        read_map16
      when 0xdf
        read_map32
      else
        raise MalformedFormatError, "Unknown format byte: 0x#{byte.to_s(16)}"
      end
    end

    # Primitive type readers

    def read_nil
      nil
    end

    def read_false
      false
    end

    def read_true
      true
    end

    def read_positive_fixnum(byte)
      byte
    end

    def read_negative_fixnum(byte)
      Format.negative_fixnum_value(byte)
    end

    def read_uint8
      n = @buffer.read_byte
      return UNAVAILABLE if n.nil?
      n
    end

    def read_uint16
      @buffer.read_big_endian_uint16 || UNAVAILABLE
    end

    def read_uint32
      @buffer.read_big_endian_uint32 || UNAVAILABLE
    end

    def read_uint64
      @buffer.read_big_endian_uint64 || UNAVAILABLE
    end

    def read_int8
      n = @buffer.read_byte
      return UNAVAILABLE if n.nil?
      # Convert to signed 8-bit
      n >= 128 ? n - 256 : n
    end

    def read_int16
      n = @buffer.read_big_endian_uint16
      return UNAVAILABLE if n.nil?
      # Convert to signed 16-bit
      n >= 32768 ? n - 65536 : n
    end

    def read_int32
      n = @buffer.read_big_endian_uint32
      return UNAVAILABLE if n.nil?
      # Convert to signed 32-bit
      n >= 2**31 ? n - 2**32 : n
    end

    def read_int64
      @buffer.read_big_endian_int64 || UNAVAILABLE
    end

    def read_float32
      @buffer.read_float32 || UNAVAILABLE
    end

    def read_float64
      @buffer.read_float64 || UNAVAILABLE
    end

    # String and binary readers

    def read_fixstr(byte)
      length = Format.fixstr_length(byte)
      data = @buffer.read_bytes(length)
      if data.nil?
        # Store partial read state
        @partial_read = { type: :fixstr, length: length - 0, buffer: "" }
        UNAVAILABLE
      else
        data.force_encoding(Encoding::UTF_8)
      end
    end

    def read_str8
      length = @buffer.read_byte
      return UNAVAILABLE if length.nil?
      data = @buffer.read_bytes(length)
      if data.nil?
        # Store partial read state
        @partial_read = { type: :str8, length: length, buffer: "" }
        UNAVAILABLE
      else
        data.force_encoding(Encoding::UTF_8)
      end
    end

    def read_str16
      length = @buffer.read_big_endian_uint16
      return UNAVAILABLE if length.nil?
      data = @buffer.read_bytes(length)
      if data.nil?
        # Store partial read state
        @partial_read = { type: :str16, length: length, buffer: "" }
        UNAVAILABLE
      else
        data.force_encoding(Encoding::UTF_8)
      end
    end

    def read_str32
      length = @buffer.read_big_endian_uint32
      return UNAVAILABLE if length.nil?
      data = @buffer.read_bytes(length)
      if data.nil?
        # Store partial read state
        @partial_read = { type: :str32, length: length, buffer: "" }
        UNAVAILABLE
      else
        data.force_encoding(Encoding::UTF_8)
      end
    end

    def read_bin8
      length = @buffer.read_byte
      return UNAVAILABLE if length.nil?
      data = @buffer.read_bytes(length)
      if data.nil?
        # Store partial read state
        @partial_read = { type: :bin8, length: length, buffer: "" }
        UNAVAILABLE
      else
        data || UNAVAILABLE
      end
    end

    def read_bin16
      length = @buffer.read_big_endian_uint16
      return UNAVAILABLE if length.nil?
      data = @buffer.read_bytes(length)
      if data.nil?
        # Store partial read state
        @partial_read = { type: :bin16, length: length, buffer: "" }
        UNAVAILABLE
      else
        data || UNAVAILABLE
      end
    end

    def read_bin32
      length = @buffer.read_big_endian_uint32
      return UNAVAILABLE if length.nil?
      data = @buffer.read_bytes(length)
      if data.nil?
        # Store partial read state
        @partial_read = { type: :bin32, length: length, buffer: "" }
        UNAVAILABLE
      else
        data || UNAVAILABLE
      end
    end

    # Array readers

    def read_fixarray(byte)
      count = Format.fixarray_count(byte)
      start_array(count)
    end

    def read_array16
      count = @buffer.read_big_endian_uint16
      return UNAVAILABLE if count.nil?
      start_array(count)
    end

    def read_array32
      count = @buffer.read_big_endian_uint32
      return UNAVAILABLE if count.nil?
      start_array(count)
    end

    def start_array(count)
      if count == 0
        []
      else
        @stack.push(StackFrame.new(:array, count, []))
        UNAVAILABLE  # Signal that we started a container
      end
    end

    def complete_array(array)
      if @freeze_objects
        freeze_object(array)
      else
        array
      end
    end

    # Map readers

    def read_fixmap(byte)
      count = Format.fixmap_count(byte)
      start_map(count)
    end

    def read_map16
      count = @buffer.read_big_endian_uint16
      return UNAVAILABLE if count.nil?
      start_map(count)
    end

    def read_map32
      count = @buffer.read_big_endian_uint32
      return UNAVAILABLE if count.nil?
      start_map(count)
    end

    def start_map(count)
      if count == 0
        result = @symbolize_keys ? {} : {}
        result.freeze if @freeze_objects
        result
      else
        @stack.push(StackFrame.new(:map_key, count, @symbolize_keys ? {} : {}))
        UNAVAILABLE  # Signal that we started a container
      end
    end

    def complete_map(hash)
      if @freeze_objects
        freeze_object(hash)
      else
        hash
      end
    end

    # Extension readers

    def read_fixext1
      type = @buffer.read_byte
      return UNAVAILABLE if type.nil?
      type = type >= 128 ? type - 256 : type
      payload = @buffer.read_bytes(1)
      if payload.nil?
        # Store partial read state
        @partial_read = { type: :fixext1, ext_type: type, length: 1 }
        UNAVAILABLE
      else
        handle_extension(type, payload)
      end
    end

    def read_fixext2
      type = @buffer.read_byte
      return UNAVAILABLE if type.nil?
      type = type >= 128 ? type - 256 : type
      payload = @buffer.read_bytes(2)
      if payload.nil?
        # Store partial read state
        @partial_read = { type: :fixext2, ext_type: type, length: 2 }
        UNAVAILABLE
      else
        handle_extension(type, payload)
      end
    end

    def read_fixext4
      type = @buffer.read_byte
      return UNAVAILABLE if type.nil?
      type = type >= 128 ? type - 256 : type
      payload = @buffer.read_bytes(4)
      if payload.nil?
        # Store partial read state
        @partial_read = { type: :fixext4, ext_type: type, length: 4 }
        UNAVAILABLE
      else
        handle_extension(type, payload)
      end
    end

    def read_fixext8
      type = @buffer.read_byte
      return UNAVAILABLE if type.nil?
      type = type >= 128 ? type - 256 : type
      payload = @buffer.read_bytes(8)
      if payload.nil?
        # Store partial read state
        @partial_read = { type: :fixext8, ext_type: type, length: 8 }
        UNAVAILABLE
      else
        handle_extension(type, payload)
      end
    end

    def read_fixext16
      type = @buffer.read_byte
      return UNAVAILABLE if type.nil?
      type = type >= 128 ? type - 256 : type
      payload = @buffer.read_bytes(16)
      if payload.nil?
        # Store partial read state
        @partial_read = { type: :fixext16, ext_type: type, length: 16 }
        UNAVAILABLE
      else
        handle_extension(type, payload)
      end
    end

    def read_ext8
      length = @buffer.read_byte
      return UNAVAILABLE if length.nil?
      type = @buffer.read_byte
      return UNAVAILABLE if type.nil?
      type = type >= 128 ? type - 256 : type
      payload = @buffer.read_bytes(length)
      if payload.nil?
        # Store partial read state
        @partial_read = { type: :ext8, ext_type: type, length: length }
        UNAVAILABLE
      else
        handle_extension(type, payload)
      end
    end

    def read_ext16
      length = @buffer.read_big_endian_uint16
      return UNAVAILABLE if length.nil?
      type = @buffer.read_byte
      return UNAVAILABLE if type.nil?
      type = type >= 128 ? type - 256 : type
      payload = @buffer.read_bytes(length)
      if payload.nil?
        # Store partial read state
        @partial_read = { type: :ext16, ext_type: type, length: length }
        UNAVAILABLE
      else
        handle_extension(type, payload)
      end
    end

    def read_ext32
      length = @buffer.read_big_endian_uint32
      return UNAVAILABLE if length.nil?
      type = @buffer.read_byte
      return UNAVAILABLE if type.nil?
      type = type >= 128 ? type - 256 : type
      payload = @buffer.read_bytes(length)
      if payload.nil?
        # Store partial read state
        @partial_read = { type: :ext32, ext_type: type, length: length }
        UNAVAILABLE
      else
        handle_extension(type, payload)
      end
    end

    def handle_extension(type, payload)
      klass, unpacker_proc, flags = @ext_registry.lookup(type)

      if klass && unpacker_proc
        # Check if this is a recursive unpacker
        if flags && (flags & 0x01) != 0
          # Recursive unpacker - create a temporary unpacker with the payload
          temp_unpacker = Unpacker.new
          temp_unpacker.feed(payload)
          # Share the extension registry so nested extensions work
          temp_unpacker.instance_variable_set(:@ext_registry, @ext_registry)
          # Convert Symbol to method call if needed
          if unpacker_proc.is_a?(Symbol)
            klass.send(unpacker_proc, temp_unpacker)
          else
            unpacker_proc.call(temp_unpacker)
          end
        else
          # Non-recursive - pass the payload directly
          # Convert Symbol to method call if needed
          if unpacker_proc.is_a?(Symbol)
            klass.send(unpacker_proc, payload)
          else
            unpacker_proc.call(payload)
          end
        end
      elsif @allow_unknown_ext
        ExtensionValue.new(type, payload)
      else
        raise UnknownExtTypeError, "Unknown extension type: #{type}"
      end
    end
  end
end
