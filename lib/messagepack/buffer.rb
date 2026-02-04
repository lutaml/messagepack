# frozen_string_literal: true

require_relative 'format'

module Messagepack
  # BinaryBuffer manages binary data for reading and writing MessagePack data.
  #
  # This class provides:
  # - Chunk-based storage for efficient write operations
  # - Streaming support via IO integration
  # - Big-endian binary primitives for MessagePack format
  #
  class BinaryBuffer
    DEFAULT_IO_BUFFER_SIZE = 32 * 1024
    # Coalescing threshold: chunks smaller than this will be merged with the previous chunk
    # This reduces the number of chunks and improves to_s performance
    COALESCE_THRESHOLD = 512

    attr_reader :io

    # Disable dup and clone as they have weird semantics
    undef_method :dup
    undef_method :clone

    def initialize(io = nil, io_buffer_size: DEFAULT_IO_BUFFER_SIZE)
      @io = io
      @io_buffer_size = io_buffer_size
      @io_buffer = nil
      @chunks = []
      @position = 0
      @length = 0
      @saved_position = nil  # For save/restore position
    end

    # Write a single byte
    def write_byte(byte)
      append_to_last_chunk((byte & 0xFF).chr.force_encoding(Encoding::BINARY))
    end

    # Write multiple bytes
    def write_bytes(bytes)
      return self if bytes.nil? || bytes.empty?

      append_to_last_chunk(bytes.dup.force_encoding(Encoding::BINARY))
    end

    # Append data to the last chunk if it's small enough, otherwise create a new chunk
    # This coalesces small chunks to reduce the total number of chunks
    def append_to_last_chunk(data)
      data_bytesize = data.bytesize
      data.force_encoding(Encoding::BINARY)

      # Check if we should coalesce with the last chunk
      if !@chunks.empty? && should_coalesce?(data_bytesize)
        # Append to the last chunk instead of creating a new one
        @chunks[-1] << data
        @length += data_bytesize
      else
        # Create a new chunk
        @chunks << data
        @length += data_bytesize
      end

      self
    end

    # Check if we should coalesce new data with the last chunk
    # Coalesce if: both the new data AND the last chunk are below the threshold
    def should_coalesce?(new_data_bytesize)
      last_chunk_bytesize = @chunks.last.bytesize

      # Coalesce if both are below the threshold
      last_chunk_bytesize < COALESCE_THRESHOLD && new_data_bytesize < COALESCE_THRESHOLD
    end

    # Write 16-bit unsigned big-endian integer
    def write_big_endian_uint16(value)
      append_to_last_chunk([value].pack('n'))
    end

    # Write 32-bit unsigned big-endian integer
    def write_big_endian_uint32(value)
      append_to_last_chunk([value].pack('N'))
    end

    # Write 64-bit unsigned big-endian integer
    def write_big_endian_uint64(value)
      append_to_last_chunk([value].pack('Q>'))
    end

    # Write 64-bit signed big-endian integer
    def write_big_endian_int64(value)
      append_to_last_chunk([value].pack('q>'))
    end

    # Write 32-bit float (IEEE 754 binary32, big-endian)
    def write_float32(value)
      append_to_last_chunk([value].pack('g'))
    end

    # Write 64-bit float (IEEE 754 binary64, big-endian)
    def write_float64(value)
      append_to_last_chunk([value].pack('G'))
    end

    # Write data to buffer and return bytes written
    def write(data)
      return 0 if data.nil? || data.empty?

      append_to_last_chunk(data.dup.force_encoding(Encoding::BINARY))
      data.bytesize
    end

    # Read n bytes as a string
    # Returns nil if buffer is empty
    # Returns all available data if requested more than available
    def read(n = nil)
      return "" if n == 0  # Special case: read(0) returns empty string

      if n.nil?
        # Read all available data
        # Try to read from IO if buffer is empty
        if @chunks.empty? && @io
          # Read all data from IO when called with no arguments
          while @io
            data = @io.read(@io_buffer_size)
            break unless data  # EOF
            feed(data)
          end
        elsif @io
          # Continue reading from IO until all data is consumed
          # (when called with no arguments, read all data from IO)
          while @io
            data = @io.read(@io_buffer_size)
            break unless data  # EOF
            feed(data)
          end
        end

        # Return empty string (not nil) for empty buffers
        return "" if @chunks.empty? || @position >= @length

        result = String.new(capacity: @length - @position)
        while @position < @length
          chunk_index, offset = chunk_and_offset(@position)
          chunk = @chunks[chunk_index]
          bytes_to_read = chunk.bytesize - offset
          result << chunk.byteslice(offset, bytes_to_read)
          @position += bytes_to_read
        end
        return result.empty? ? nil : result
      end

      return nil if @position >= @length && !@io
      ensure_readable(n)
      available = @length - @position

      if available == 0
        return nil
      elsif n > available
        # Return all available data if more than available requested
        read_bytes_internal(available)
      else
        read_bytes_internal(n)
      end
    end

    # Read n bytes as a string
    # Raises EOFError if not enough data available
    def read_all(n = nil)
      return "" if n == 0  # Special case: read_all(0) returns empty string

      if n.nil?
        # Read all available data
        # Try to read from IO if buffer is empty
        if @chunks.empty? && @io
          # Read all data from IO when called with no arguments
          while @io
            data = @io.read(@io_buffer_size)
            break unless data  # EOF
            feed(data)
          end
        elsif @io
          # Continue reading from IO until all data is consumed
          # (when called with no arguments, read all data from IO)
          while @io
            data = @io.read(@io_buffer_size)
            break unless data  # EOF
            feed(data)
          end
        end

        # Return empty string if buffer is empty (not nil)
        return "" if @chunks.empty? || @position >= @length

        result = String.new(capacity: @length - @position)
        while @position < @length
          chunk_index, offset = chunk_and_offset(@position)
          chunk = @chunks[chunk_index]
          bytes_to_read = chunk.bytesize - offset
          result << chunk.byteslice(offset, bytes_to_read)
          @position += bytes_to_read
        end
        return result
      end

      ensure_readable(n)
      available = @length - @position

      if n > available
        raise EOFError, "not enough data: requested #{n} but only #{available} available"
      end

      read_bytes_internal(n)
    end

    # Read a single byte, or nil if no data available
    def read_byte
      ensure_readable(1)
      return nil if @position >= @length

      chunk_index, offset = chunk_and_offset(@position)
      chunk = @chunks[chunk_index]
      byte = chunk.getbyte(offset)
      @position += 1
      byte
    end

    # Read n bytes as a string (internal method)
    def read_bytes_internal(n)
      ensure_readable(n)
      return nil if n > @length - @position

      result = String.new(capacity: n)
      remaining = n

      while remaining > 0
        chunk_index, offset = chunk_and_offset(@position)
        chunk = @chunks[chunk_index]
        available = chunk.bytesize - offset
        to_read = [remaining, available].min

        result << chunk.byteslice(offset, to_read)
        @position += to_read
        remaining -= to_read
      end

      result
    end

    # Read n bytes as a string (backward compatibility alias)
    def read_bytes(n)
      read_bytes_internal(n)
    end

    # Read 16-bit unsigned big-endian integer
    def read_big_endian_uint16
      data = read_bytes(2)
      return nil if data.nil?

      data.unpack1('n')
    end

    # Read 32-bit unsigned big-endian integer
    def read_big_endian_uint32
      data = read_bytes(4)
      return nil if data.nil?

      data.unpack1('N')
    end

    # Read 64-bit unsigned big-endian integer
    def read_big_endian_uint64
      data = read_bytes(8)
      return nil if data.nil?

      data.unpack1('Q>')
    end

    # Read 64-bit signed big-endian integer
    def read_big_endian_int64
      data = read_bytes(8)
      return nil if data.nil?

      data.unpack1('q>')
    end

    # Read 32-bit float (IEEE 754 binary32, big-endian)
    def read_float32
      data = read_bytes(4)
      return nil if data.nil?

      data.unpack1('g')
    end

    # Read 64-bit float (IEEE 754 binary64, big-endian)
    def read_float64
      data = read_bytes(8)
      return nil if data.nil?

      data.unpack1('G')
    end

    # Look at next byte without consuming it
    def peek_byte
      return nil if @position >= @length

      chunk_index, offset = chunk_and_offset(@position)
      @chunks[chunk_index].getbyte(offset)
    end

    # Skip n bytes, returns bytes actually skipped
    # If more bytes requested than available, skips all available
    def skip(n)
      return 0 if n == 0  # Special case: skip(0) returns 0
      ensure_readable(n)
      available = @length - @position

      actual = [n, available].min
      @position += actual
      actual
    end

    # Skip n bytes, raises EOFError if not enough data
    def skip_all(n)
      return self if n == 0  # Special case: skip_all(0) returns self
      ensure_readable(n)
      available = @length - @position

      if n > available
        raise EOFError, "not enough data: requested #{n} but only #{available} available"
      end

      @position += n
      self
    end

    # Skip n bytes (internal method, returns self)
    def skip_bytes(n)
      @position += n
      self
    end

    # Check if bytes are available for reading
    def bytes_available?
      @position < @length
    end

    # Get the number of bytes available for reading
    def bytes_available
      @length - @position
    end

    # Check if buffer is empty
    def empty?
      @length - @position == 0
    end

    # Check if at EOF (no more data and no IO to read from)
    def eof?
      @position >= @length && !@io
    end

    # Convert all buffer data to a single string (does not consume data)
    def to_s
      # Fast-path: if position is 0, we can join all chunks directly
      if @position == 0
        result = @chunks.empty? ? String.new : @chunks.join
        result.force_encoding(Encoding::BINARY)
        return result
      end

      # General case: skip bytes before @position
      result = String.new(capacity: @length)
      offset = 0
      @chunks.each do |chunk|
        chunk_bytes = chunk.bytesize
        next if offset + chunk_bytes <= @position

        start_offset = [@position - offset, 0].max
        result << chunk.byteslice(start_offset, chunk_bytes - start_offset)
        offset += chunk_bytes
        break if offset >= @length
      end
      result.force_encoding(Encoding::BINARY)
    end

    # Convert to array of chunks
    def to_a
      @chunks.dup
    end

    # Clear buffer to empty state
    def clear
      @chunks.clear
      @position = 0
      @length = 0
      @io_buffer = nil
      self
    end

    # Reset buffer to empty state
    def reset
      @chunks.clear
      @position = 0
      @length = 0
      @io_buffer = nil
      @saved_position = nil
      self
    end

    # Get current size of buffer (available bytes)
    def size
      @length - @position
    end

    # Write buffer contents to an IO object
    def write_to(io)
      return 0 if @length - @position == 0  # Nothing to write

      bytes_written = 0
      remaining = @length - @position

      chunk_index, offset = chunk_and_offset(@position)

      # Write each chunk from current position
      (chunk_index...@chunks.length).each do |idx|
        start_offset = (idx == chunk_index) ? offset : 0
        chunk = @chunks[idx]
        data = chunk.byteslice(start_offset, chunk.bytesize - start_offset)
        next if data.empty?

        io.write(data)
        bytes_written += data.bytesize
      end

      @position = @length
      bytes_written
    end

    # Flush buffer contents to the internal IO (if present)
    def flush
      return self unless @io

      data = to_s
      @io.write(data)
      reset
      self
    end

    # Feed more data for streaming (typically from IO)
    def feed(data)
      return self if data.nil? || data.empty?

      @chunks << data.dup.force_encoding(Encoding::BINARY)
      @length += data.bytesize
      self
    end

    alias << feed

    # Close the IO if present
    def close
      @io.close if @io && !@io.closed?
      @io = nil
      self
    end

    # Save the current read position for later restoration
    # This is useful for peek-ahead operations where we might need to roll back
    def save_position
      @saved_position = @position
      self
    end

    # Restore a previously saved position
    # Returns true if position was restored, false if no position was saved
    def restore_position
      return false if @saved_position.nil?
      @position = @saved_position
      @saved_position = nil
      true
    end

    # Discard a saved position without restoring
    def discard_saved_position
      @saved_position = nil
      self
    end

    # Check if a position is currently saved
    def position_saved?
      !@saved_position.nil?
    end

    private

    # Ensure n bytes are available for reading
    def ensure_readable(n)
      return unless @io

      while @length - @position < n
        break unless feed_from_io
      end
    end

    # Read from @io and add to buffer
    def feed_from_io
      @io_buffer ||= String.new(capacity: @io_buffer_size)
      @io_buffer.clear

      data = @io.read(@io_buffer_size)
      return false if data.nil?

      feed(data)
      true
    end

    # Find chunk index and offset for a given position
    def chunk_and_offset(pos)
      offset = 0
      @chunks.each_with_index do |chunk, index|
        chunk_size = chunk.bytesize
        if pos < offset + chunk_size
          return [index, pos - offset]
        end
        offset += chunk_size
      end

      # Position is beyond all chunks (should not happen with proper ensure_readable)
      [@chunks.length - 1, @chunks.last.bytesize - 1]
    end
  end
end
