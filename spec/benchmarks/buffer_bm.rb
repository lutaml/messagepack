# frozen_string_literal: true

require_relative 'benchmark_suite'

module Messagepack
  module Benchmarks
    # Buffer-specific benchmarks
    #
    # Tests the performance of BinaryBuffer operations to identify bottlenecks:
    # - Chunk coalescing impact
    # - Memory allocation patterns
    # - Read performance with different chunk configurations
    # - Write performance with different write patterns
    #
    module Buffer
      class << self
        def run_all
          run_write_patterns
          run_read_performance
          run_chunk_coalescing
          run_memory_patterns
        end

        def run_write_patterns
          suite = Suite.new('Buffer Write Patterns')

          # Many small writes vs one large write
          suite.benchmark('1000x write_byte') do
            buffer = Messagepack::BinaryBuffer.new
            1000.times { |i| buffer.write_byte(i & 0xFF) }
            buffer.to_s
          end

          suite.benchmark('1000x write_bytes (1 byte each)') do
            buffer = Messagepack::BinaryBuffer.new
            1000.times { |i| buffer.write_bytes((i & 0xFF).chr) }
            buffer.to_s
          end

          suite.benchmark('100x write_bytes (10 bytes each)') do
            buffer = Messagepack::BinaryBuffer.new
            100.times { |i| buffer.write_bytes([i].pack('L>') + 'a' * 6) }
            buffer.to_s
          end

          suite.benchmark('10x write_bytes (100 bytes each)') do
            buffer = Messagepack::BinaryBuffer.new
            10.times { |i| buffer.write_bytes([i].pack('L>') + 'a' * 96) }
            buffer.to_s
          end

          suite.benchmark('1x write_bytes (1000 bytes)') do
            buffer = Messagepack::BinaryBuffer.new
            buffer.write_bytes('a' * 1000)
            buffer.to_s
          end

          # Mixed write operations
          suite.benchmark('mixed write operations') do
            buffer = Messagepack::BinaryBuffer.new
            buffer.write_byte(0xFF)
            buffer.write_bytes('hello')
            buffer.write_big_endian_uint16(1000)
            buffer.write_bytes('world')
            buffer.write_big_endian_uint32(1_000_000)
            buffer.write_float64(3.14)
            buffer.to_s
          end

          suite.run
        end

        def run_read_performance
          suite = Suite.new('Buffer Read Performance')

          # Prepare test data
          small_buffer = Messagepack::BinaryBuffer.new
          10.times { |i| small_buffer.write_bytes("data#{i}") }
          small_data = small_buffer.to_s

          medium_buffer = Messagepack::BinaryBuffer.new
          100.times { |i| medium_buffer.write_bytes("data#{i}") }
          medium_data = medium_buffer.to_s

          large_buffer = Messagepack::BinaryBuffer.new
          1000.times { |i| large_buffer.write_bytes("data#{i}") }
          large_data = large_buffer.to_s

          # Single read_all
          suite.benchmark('read_all small buffer') do
            buf = Messagepack::BinaryBuffer.new
            buf.feed(small_data)
            buf.read_all
          end

          suite.benchmark('read_all medium buffer') do
            buf = Messagepack::BinaryBuffer.new
            buf.feed(medium_data)
            buf.read_all
          end

          suite.benchmark('read_all large buffer') do
            buf = Messagepack::BinaryBuffer.new
            buf.feed(large_data)
            buf.read_all
          end

          # Chunked reads
          suite.benchmark('10x read 4 bytes from small buffer') do
            buf = Messagepack::BinaryBuffer.new
            buf.feed(small_data)
            10.times { buf.read(4) }
          end

          suite.benchmark('100x read 4 bytes from medium buffer') do
            buf = Messagepack::BinaryBuffer.new
            buf.feed(medium_data)
            100.times { buf.read(4) }
          end

          # Byte-by-byte read
          suite.benchmark('read_byte small buffer') do
            buf = Messagepack::BinaryBuffer.new
            buf.feed(small_data)
            buf.read_byte while buf.bytes_available?
          end

          suite.run
        end

        def run_chunk_coalescing
          suite = Suite.new('Chunk Coalescing Impact')

          # Test impact of many small chunks on to_s performance
          small_chunks = Messagepack::BinaryBuffer.new
          1000.times { |i| small_chunks.write_byte(i & 0xFF) }

          single_chunk = Messagepack::BinaryBuffer.new
          single_chunk.write_bytes((0...1000).map { |i| i & 0xFF }.pack('C*'))

          suite.benchmark('to_s with 1000 small chunks') do
            buf = Messagepack::BinaryBuffer.new
            1000.times { |i| buf.write_byte(i & 0xFF) }
            buf.to_s
          end

          suite.benchmark('to_s with 1 large chunk') do
            buf = Messagepack::BinaryBuffer.new
            buf.write_bytes((0...1000).map { |i| i & 0xFF }.pack('C*'))
            buf.to_s
          end

          # Test with realistic data (packer usage)
          many_writes_result = nil
          single_write_result = nil

          suite.benchmark('packer: 1000 small writes') do
            pk = Messagepack::Packer.new
            1000.times { |i| pk.write(i) }
            pk.to_s
          end

          suite.benchmark('packer: 1 array write') do
            Messagepack.pack((0...1000).to_a)
          end

          suite.run
        end

        def run_memory_patterns
          memory_suite = MemorySuite.new('Buffer Memory Allocation')

          memory_suite.benchmark('1000x write_byte (allocations)') do
            buffer = Messagepack::BinaryBuffer.new
            1000.times { |i| buffer.write_byte(i & 0xFF) }
            buffer.to_s
          end

          memory_suite.benchmark('1000x write_bytes (allocations)') do
            buffer = Messagepack::BinaryBuffer.new
            1000.times { |i| buffer.write_bytes([i].pack('C')) }
            buffer.to_s
          end

          memory_suite.benchmark('1x write_bytes 1000 bytes (allocations)') do
            buffer = Messagepack::BinaryBuffer.new
            buffer.write_bytes((0...1000).map { |i| [i].pack('C') }.join)
            buffer.to_s
          end

          memory_suite.run
        end

        def run_buffer_vs_stringio
          suite = Suite.new('Buffer vs StringIO')

          require 'stringio'

          test_data = 'hello world ' * 100

          suite.benchmark('Buffer write and read') do
            buffer = Messagepack::BinaryBuffer.new
            buffer.write_bytes(test_data)
            buffer.read_all
          end

          suite.benchmark('StringIO write and read') do
            io = StringIO.new('wb+')
            io.write(test_data)
            io.rewind
            io.read
          end

          suite.run
        end

        def run_clear_and_reset
          suite = Suite.new('Buffer Clear/Reset Performance')

          suite.benchmark('clear with data') do
            buffer = Messagepack::BinaryBuffer.new
            100.times { |i| buffer.write_bytes("data#{i}") }
            buffer.clear
          end

          suite.benchmark('reset with data') do
            buffer = Messagepack::BinaryBuffer.new
            100.times { |i| buffer.write_bytes("data#{i}") }
            buffer.reset
          end

          # Reuse after reset
          suite.benchmark('write, reset, write again') do
            buffer = Messagepack::BinaryBuffer.new
            100.times { |i| buffer.write_bytes("data#{i}") }
            buffer.reset
            100.times { |i| buffer.write_bytes("data2#{i}") }
            buffer.to_s
          end

          suite.run
        end
      end
    end
  end
end

# Run benchmarks if executed directly
if __FILE__ == $PROGRAM_NAME
  Messagepack::Benchmarks::Buffer.run_all
end
