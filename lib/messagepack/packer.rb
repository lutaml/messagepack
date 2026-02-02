# frozen_string_literal: true

require_relative 'buffer'
require_relative 'format'

module MessagePack
  # Packer serializes Ruby objects into MessagePack binary format.
  #
  # Usage:
  #   packer = MessagePack::Packer.new
  #   packer.write("hello")
  #   packer.write([1, 2, 3])
  #   data = packer.full_pack
  #
  class Packer
    # Disable dup and clone as they have weird semantics
    undef_method :dup
    undef_method :clone

    attr_reader :buffer, :compatibility_mode, :frozen

    # Predicate method for compatibility_mode
    def compatibility_mode?
      @compatibility_mode
    end

    def initialize(io = nil, options = nil)
      # Handle various initialization patterns:
      # Packer.new
      # Packer.new(io)
      # Packer.new(options_hash)
      # Packer.new(io, options_hash)

      compatibility_mode = false

      if io.is_a?(Hash)
        # Packer.new({}) or Packer.new(options_hash)
        options = io
        io = nil  # Reset io to nil since the first arg is options
        io = options[:io] if options.key?(:io)
        compatibility_mode = options[:compatibility_mode] if options.key?(:compatibility_mode)
      elsif options.is_a?(Hash)
        # Packer.new(io, options_hash) or Packer.new(StringIO.new, {})
        compatibility_mode = options[:compatibility_mode] if options.key?(:compatibility_mode)
      end

      @buffer = BinaryBuffer.new(io)
      @compatibility_mode = compatibility_mode
      @ext_registry = ExtensionRegistry::Packer.new
      @to_msgpack_method = :to_msgpack
      @to_msgpack_arg = self
      @frozen = false  # Custom frozen flag for pool
    end

    # Main API: Write any Ruby object
    def write(value)
      # First check if this type is registered as an extension
      data = @ext_registry.lookup(value)
      if data
        type_id, packer_proc, flags = data
        # Convert Symbol to Proc if needed
        proc = packer_proc.is_a?(Symbol) ? ->(obj) { obj.send(packer_proc) } : packer_proc

        # Handle oversized_integer_extension for Integer
        if value.is_a?(Integer) && flags & 0x02 != 0
          # Check if integer fits in int64 range
          int64_min = -2**63
          int64_max = 2**63 - 1
          if value >= int64_min && value <= int64_max
            # Fits in native int64 format, use native serialization
            # Fall through to standard serialization below
            data = nil
          else
            # Too large, use the extension packer
            payload = proc.call(value)
            write_extension_direct(type_id, payload)
            return self
          end
        elsif value.is_a?(Integer)
          # Integer type registered without oversized_integer_extension flag
          # Don't use the extension packer - fall through to native format
          # (which will raise RangeError for values that don't fit)
          data = nil
        end

        if data
          # For recursive packers, pass self as second argument
          if flags & 0x01 != 0
            # Recursive packer - create a temporary buffer to capture the output
            temp_buffer = BinaryBuffer.new
            temp_packer = Packer.new(io: nil).tap do |pk|
              pk.instance_variable_set(:@buffer, temp_buffer)
              pk.instance_variable_set(:@ext_registry, @ext_registry)
            end
            proc.call(value, temp_packer)
            payload = temp_buffer.to_s
            write_extension_direct(type_id, payload)
          else
            # Non-recursive - get the payload and write it as extension
            payload = proc.call(value)
            write_extension_direct(type_id, payload)
          end
          return self
        end
      end

      # Use standard serialization
      case value
      when NilClass then write_nil_internal
      when TrueClass then write_true_internal
      when FalseClass then write_false_internal
      when Integer then write_integer_internal(value)
      when Float then write_float_internal(value)
      when String
        # Check if string is binary (ASCII-8BIT) vs UTF-8 text
        if value.encoding == Encoding::ASCII_8BIT
          write_binary_internal(value)
        else
          write_string_internal(value)
        end
      when Symbol then write_symbol_internal(value)
      when Array then write_array_internal(value)
      when Hash then write_hash_internal(value)
      else
        write_extension_internal(value)
      end
      self
    end

    alias pack write

    # Flush buffer to IO if present
    def flush
      @buffer.flush
      self
    end

    # Return packed string and reset buffer
    def full_pack
      flush if @buffer.io
      result = @buffer.to_s
      reset
      @buffer.io ? nil : result
    end

    # Return current packed string without resetting buffer
    def to_s
      @buffer.io ? '' : @buffer.to_s
    end

    alias to_str to_s

    # Reset buffer state
    def reset
      @buffer.reset
      @frozen = false
      self
    end

    # Public API for custom to_msgpack implementations

    def write_nil
      write_nil_internal
      self
    end

    def write_true
      write_true_internal
      self
    end

    def write_false
      write_false_internal
      self
    end

    def write_integer(value)
      raise ::TypeError, "value must be an Integer" unless value.is_a?(Integer)
      write_integer_internal(value)
      self
    end

    def write_float(value)
      raise ::TypeError, "value must be numeric" unless value.is_a?(Numeric)
      write_float_internal(value)
      self
    end

    def write_float32(value)
      raise ArgumentError, "value must be numeric" unless value.is_a?(Numeric)
      @buffer.write_byte(Format::FLOAT32)
      @buffer.write_float32(value)
      self
    end

    def write_string(value)
      raise ::TypeError, "value must be a String" unless value.is_a?(String)
      write_string_internal(value)
      self
    end

    def write_binary(value)
      raise ::TypeError, "value must be a String" unless value.is_a?(String)
      write_binary_internal(value)
      self
    end

    def write_bin(value)
      write_binary(value)
      self
    end

    def write_bin_header(length)
      write_binary_header(length)
      self
    end

    def write_array_header(count)
      raise ::TypeError, "count must be an Integer" unless count.is_a?(Integer)
      write_array_header_internal(count)
      self
    end

    def write_map_header(count)
      raise ::TypeError, "count must be an Integer" unless count.is_a?(Integer)
      write_map_header_internal(count)
      self
    end

    def write_extension(type, payload = nil)
      # The test calls write_extension("hello") with one argument and expects TypeError
      # because the first argument should be an Integer type ID, not a String
      raise ::TypeError, "type must be an Integer" unless type.is_a?(Integer)

      # Validate type range (-128 to 127)
      unless type >= -128 && type <= 127
        raise RangeError, "type must be -128..127 but got #{type.inspect}"
      end

      if payload.nil?
        # Called with (type, payload) form where payload is yielded
        payload = yield if block_given?
        write_extension_direct(type, payload)
      else
        write_extension_direct(type, payload)
      end
      self
    end

    # Additional convenience methods not in the core API
    def write_array(value)
      raise ::TypeError, "value must be an Array" unless value.is_a?(Array)
      write_array_internal(value)
      self
    end

    def write_hash(value)
      raise ::TypeError, "value must be a Hash" unless value.is_a?(Hash)
      write_hash_internal(value)
      self
    end

    def write_symbol(value)
      raise ::TypeError, "value must be a Symbol" unless value.is_a?(Symbol)
      write_symbol_internal(value)
      self
    end

    def write_int(value)
      write_integer(value)
      self
    end

    # Extension type registration

    def register_type(type_id, klass, packer_proc = nil, &block)
      # Handle multiple calling patterns:
      # register_type(type_id, klass) { |obj| ... }
      # register_type(type_id, klass, :method_name)
      # register_type(type_id, klass, proc)
      # register_type(type_id, klass, &:method)

      raise FrozenError, "can't modify frozen MessagePack::Packer" if @frozen

      if block_given?
        packer_proc = block
      elsif packer_proc.is_a?(Symbol)
        # Convert symbol to proc (use a local variable to avoid capture issues)
        method_name = packer_proc
        packer_proc = ->(obj) { obj.send(method_name) }
      end

      @ext_registry.register(type_id, klass, packer_proc)
    end

    def registered_types
      @ext_registry.registered_types
    end

    def type_registered?(klass_or_type)
      @ext_registry.type_registered?(klass_or_type)
    end

    private

    # Internal type dispatch

    def write_nil_internal
      @buffer.write_byte(Format::NIL)
    end

    def write_true_internal
      @buffer.write_byte(Format::TRUE)
    end

    def write_false_internal
      @buffer.write_byte(Format::FALSE)
    end

    def write_integer_internal(value)
      if value >= 0
        write_positive_integer(value)
      else
        write_negative_integer(value)
      end
    end

    def write_positive_integer(value)
      if value <= Format::POSITIVE_FIXNUM_MAX
        write_fixint(value)
      elsif value <= 0xff
        write_uint8(value)
      elsif value <= 0xffff
        write_uint16(value)
      elsif value <= 0xffffffff
        write_uint32(value)
      elsif value <= 0xffffffffffffffff
        write_uint64(value)
      else
        raise RangeError, "integer too large for MessagePack: #{value}"
      end
    end

    def write_negative_integer(value)
      if value >= -32
        write_fixint(value)
      elsif value >= -0x80
        write_int8(value)
      elsif value >= -0x8000
        write_int16(value)
      elsif value >= -0x80000000
        write_int32(value)
      elsif value >= -0x8000000000000000
        write_int64(value)
      else
        raise RangeError, "integer too small for MessagePack: #{value}"
      end
    end

    def write_bignum_internal(value)
      # Handle big integers outside 64-bit range
      # Convert to binary representation
      num_bytes = (value.abs.bit_length + 7) / 8
      is_negative = value < 0

      if is_negative
        # For negative numbers, store as two's complement
        # We need to handle the sign properly
        abs_value = value.abs
        data = []
        remaining = abs_value
        while remaining > 0
          data << (remaining & 0xff)
          remaining >>= 8
        end
        # Two's complement: invert and add 1
        data = data.map { |b| (~b) & 0xff }
        i = 0
        while i < data.length && data[i] == 0
          i += 1
        end
        if i < data.length
          data[i] += 1
        else
          data << 1
        end
        payload = data.pack('C*')
      else
        # Positive number - big-endian bytes
        abs_value = value
        data = []
        while abs_value > 0
          data.unshift(abs_value & 0xff)
          abs_value >>= 8
        end
        payload = data.pack('C*')
      end

      # Use bin format for raw binary data
      write_binary_header(payload.bytesize)
      @buffer.write_bytes(payload)
    end

    def write_float_internal(value)
      @buffer.write_byte(Format::FLOAT64)
      @buffer.write_float64(value)
    end

    def write_string_internal(value)
      data = utf8_compatible?(value) ? value : transcode_to_utf8(value)
      write_string_header_internal(data.bytesize)
      @buffer.write_bytes(data)
    end

    def write_symbol_internal(value)
      # Symbols are encoded as strings
      # If the symbol was created from a binary string, encode as bin
      data = value.to_s
      if data.encoding == Encoding::ASCII_8BIT
        write_binary_internal(data)
      else
        write_string_internal(data)
      end
    end

    def write_array_internal(value)
      write_array_header_internal(value.size)
      value.each { |item| write(item) }
    end

    def write_hash_internal(value)
      write_map_header_internal(value.size)
      value.each { |k, v| write(k); write(v) }
    end

    def write_binary_internal(value)
      write_binary_header(value.bytesize)
      @buffer.write_bytes(value)
    end

    def write_extension_internal(value)
      if value.is_a?(Integer)
        # type, payload form
        type = value
        payload = yield if block_given?
        write_extension_direct(type, payload)
        return self
      end

      # Try extension registry
      type_id, packer_proc = @ext_registry.lookup(value)

      if type_id
        payload = packer_proc.call(value)
        write_extension_direct(type_id, payload)
      elsif value.respond_to?(@to_msgpack_method)
        # Use to_msgpack if available
        value.send(@to_msgpack_method, @to_msgpack_arg)
      else
        # Try to call to_msgpack and let NoMethodError propagate
        value.send(@to_msgpack_method, @to_msgpack_arg)
      end
    end

    def write_extension_direct(type, payload)
      length = payload.bytesize

      case length
      when 1
        @buffer.write_byte(Format::FIXEXT1)
        @buffer.write_byte(type)
        @buffer.write_bytes(payload)
      when 2
        @buffer.write_byte(Format::FIXEXT2)
        @buffer.write_byte(type)
        @buffer.write_bytes(payload)
      when 4
        @buffer.write_byte(Format::FIXEXT4)
        @buffer.write_byte(type)
        @buffer.write_bytes(payload)
      when 8
        @buffer.write_byte(Format::FIXEXT8)
        @buffer.write_byte(type)
        @buffer.write_bytes(payload)
      when 16
        @buffer.write_byte(Format::FIXEXT16)
        @buffer.write_byte(type)
        @buffer.write_bytes(payload)
      else
        if length <= 0xff
          @buffer.write_byte(Format::EXT8)
          @buffer.write_byte(length)
          @buffer.write_byte(type)
        elsif length <= 0xffff
          @buffer.write_byte(Format::EXT16)
          @buffer.write_big_endian_uint16(length)
          @buffer.write_byte(type)
        else
          @buffer.write_byte(Format::EXT32)
          @buffer.write_big_endian_uint32(length)
          @buffer.write_byte(type)
        end
        @buffer.write_bytes(payload)
      end
    end

    # Format helpers

    def write_fixint(value)
      # Convert to unsigned byte representation
      byte = value & 0xff
      @buffer.write_byte(byte)
    end

    def write_uint8(value)
      @buffer.write_byte(Format::UINT8)
      @buffer.write_byte(value)
    end

    def write_uint16(value)
      @buffer.write_byte(Format::UINT16)
      @buffer.write_big_endian_uint16(value)
    end

    def write_uint32(value)
      @buffer.write_byte(Format::UINT32)
      @buffer.write_big_endian_uint32(value)
    end

    def write_uint64(value)
      @buffer.write_byte(Format::UINT64)
      @buffer.write_big_endian_uint64(value)
    end

    def write_int8(value)
      @buffer.write_byte(Format::INT8)
      @buffer.write_byte(value & 0xff)
    end

    def write_int16(value)
      @buffer.write_byte(Format::INT16)
      @buffer.write_big_endian_uint16(value & 0xffff)
    end

    def write_int32(value)
      @buffer.write_byte(Format::INT32)
      @buffer.write_big_endian_uint32(value & 0xffffffff)
    end

    def write_int64(value)
      @buffer.write_byte(Format::INT64)
      @buffer.write_big_endian_int64(value)
    end

    def write_string_header_internal(length)
      case length
      when 0..31
        @buffer.write_byte(Format::FIXRAW_MIN | length)
      when 0..0xff
        # In compatibility mode, skip str8 and use str16 directly
        if @compatibility_mode
          @buffer.write_byte(Format::STR16)
          @buffer.write_big_endian_uint16(length)
        else
          @buffer.write_byte(Format::STR8)
          @buffer.write_byte(length)
        end
      when 0..0xffff
        @buffer.write_byte(Format::STR16)
        @buffer.write_big_endian_uint16(length)
      when 0..0xffffffff
        @buffer.write_byte(Format::STR32)
        @buffer.write_big_endian_uint32(length)
      else
        raise Error, "String too large: #{length} bytes"
      end
    end

    def write_binary_header(length)
      if @compatibility_mode
        # In compatibility mode, use str format instead of bin format
        write_string_header_internal(length)
      else
        case length
        when 0..0xff
          @buffer.write_byte(Format::BIN8)
          @buffer.write_byte(length)
        when 0..0xffff
          @buffer.write_byte(Format::BIN16)
          @buffer.write_big_endian_uint16(length)
        when 0..0xffffffff
          @buffer.write_byte(Format::BIN32)
          @buffer.write_big_endian_uint32(length)
        else
          raise Error, "Binary too large: #{length} bytes"
        end
      end
    end

    def write_array_header_internal(count)
      case count
      when 0..15
        @buffer.write_byte(Format::FIXARRAY_MIN | count)
      when 0..0xffff
        @buffer.write_byte(Format::ARRAY16)
        @buffer.write_big_endian_uint16(count)
      when 0..0xffffffff
        @buffer.write_byte(Format::ARRAY32)
        @buffer.write_big_endian_uint32(count)
      else
        raise Error, "Array too large: #{count} elements"
      end
    end

    def write_map_header_internal(count)
      case count
      when 0..15
        @buffer.write_byte(Format::FIXMAP_MIN | count)
      when 0..0xffff
        @buffer.write_byte(Format::MAP16)
        @buffer.write_big_endian_uint16(count)
      when 0..0xffffffff
        @buffer.write_byte(Format::MAP32)
        @buffer.write_big_endian_uint32(count)
      else
        raise Error, "Map too large: #{count} entries"
      end
    end

    # Encoding helpers

    def utf8_compatible?(string)
      string.encoding == Encoding::UTF_8 || string.ascii_only?
    end

    def binary?(string)
      string.encoding == Encoding::BINARY
    end

    def transcode_to_utf8(string)
      string.encode(Encoding::UTF_8)
    rescue EncodingError => e
      raise Error, "Failed to encode string to UTF-8: #{e.message}"
    end
  end
end
