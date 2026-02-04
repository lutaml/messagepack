# frozen_string_literal: true

require_relative 'benchmark_suite'
require 'stringio'

module Messagepack
  module Benchmarks
    # Streaming benchmarks
    #
    # Tests the performance of streaming MessagePack operations:
    # - Small chunks vs large chunks
    # - Multiple feed operations
    # - IO streaming (StringIO, File)
    # - Partial unpacking
    #
    module Streaming
      class << self
        def run_all
          run_chunk_size_benchmarks
          run_feed_benchmarks
          run_io_streaming_benchmarks
          run_partial_unpack_benchmarks
        end

        def run_chunk_size_benchmarks
          suite = Suite.new('Chunk Size Impact')

          # Small object
          small_obj = { key: 'value' }
          small_packed = Messagepack.pack(small_obj)

          suite.benchmark('pack small object (single write)') do
            pk = Messagepack::Packer.new
            pk.write(small_obj)
            pk.full_pack
          end

          # Medium object
          medium_obj = Hash[(0...100).map { |i| ["key#{i}", "value#{i}"] }]
          suite.benchmark('pack medium object (single write)') do
            pk = Messagepack::Packer.new
            pk.write(medium_obj)
            pk.full_pack
          end

          # Large object
          large_obj = Hash[(0...1000).map { |i| ["key#{i}", "value#{i}"] }]
          suite.benchmark('pack large object (single write)') do
            pk = Messagepack::Packer.new
            pk.write(large_obj)
            pk.full_pack
          end

          # Multiple small writes vs one large write
          suite.benchmark('100 small writes (separate packers)') do
            100.times { |i| Messagepack.pack(i) }
          end

          suite.benchmark('100 small writes (single packer)') do
            pk = Messagepack::Packer.new
            100.times { |i| pk.write(i) }
            pk.full_pack
          end

          suite.run
        end

        def run_feed_benchmarks
          suite = Suite.new('Feed Performance')

          # Feed in chunks vs all at once
          large_data = Array.new(1000) { |i| { id: i, name: "Item #{i}" } }
          packed = Messagepack.pack(large_data)

          # Unpack with feed
          suite.benchmark('unpack with single feed') do
            unpacker = Messagepack::Unpacker.new
            unpacker.feed(packed)
            unpacker.read
          end

          # Feed in chunks
          chunk_size = packed.bytesize / 10
          suite.benchmark('unpack with 10 feeds') do
            unpacker = Messagepack::Unpacker.new
            0.step(packed.bytesize - 1, chunk_size) do |i|
              chunk = packed.byteslice(i, chunk_size)
              unpacker.feed(chunk)
            end
            unpacker.read
          end

          # Many small feeds
          suite.benchmark('unpack with 100 small feeds') do
            unpacker = Messagepack::Unpacker.new
            chunk_size = [packed.bytesize / 100, 1].max
            0.step(packed.bytesize - 1, chunk_size) do |i|
              chunk = packed.byteslice(i, chunk_size)
              unpacker.feed(chunk)
            end
            unpacker.read
          end

          suite.run
        end

        def run_io_streaming_benchmarks
          suite = Suite.new('IO Streaming Performance')

          # StringIO packing
          obj = { data: Array.new(100) { |i| "item#{i}" } }

          suite.benchmark('pack to StringIO') do
            io = StringIO.new
            packer = Messagepack::Packer.new(io)
            packer.write(obj)
            packer.to_s
          end

          # StringIO unpacking
          packed = Messagepack.pack(obj)

          suite.benchmark('unpack from StringIO') do
            io = StringIO.new(packed)
            unpacker = Messagepack::Unpacker.new(io)
            unpacker.read
          end

          # Buffer to_s vs StringIO
          suite.benchmark('pack to buffer (to_s)') do
            packer = Messagepack::Packer.new
            packer.write(obj)
            packer.to_s
          end

          suite.run
        end

        def run_partial_unpack_benchmarks
          suite = Suite.new('Partial Unpacking Performance')

          # Array with multiple objects
          multi_obj = Array.new(100) { |i| { id: i, value: "data#{i}" } }
          packed = Messagepack.pack(multi_obj)

          # Unpack all at once
          suite.benchmark('unpack all (100 objects)') do
            Messagepack.unpack(packed)
          end

          # Unpack one at a time using streaming
          suite.benchmark('stream unpack 100 objects') do
            unpacker = Messagepack::Unpacker.new
            unpacker.feed(packed)
            results = []
            results << unpacker.read while unpacker.buffer.bytes_available?
            results
          end

          # Unpack partial data
          suite.benchmark('unpack first 10 objects (streaming)') do
            unpacker = Messagepack::Unpacker.new
            unpacker.feed(packed)
            results = []
            10.times { results << unpacker.read }
            results
          end

          suite.run
        end

        def run_buffer_operations_benchmarks
          suite = Suite.new('Buffer Operations')

          # Test buffer write operations
          suite.benchmark('buffer write_byte (1000x)') do
            buffer = Messagepack::BinaryBuffer.new
            1000.times { |i| buffer.write_byte(i & 0xFF) }
            buffer.to_s
          end

          suite.benchmark('buffer write_bytes (small chunks 1000x)') do
            buffer = Messagepack::BinaryBuffer.new
            1000.times { |i| buffer.write_bytes([i].pack('C')) }
            buffer.to_s
          end

          suite.benchmark('buffer write_bytes (large chunk)') do
            buffer = Messagepack::BinaryBuffer.new
            data = (0...1000).map { |i| [i].pack('C') }.join
            buffer.write_bytes(data)
            buffer.to_s
          end

          # Test buffer read operations
          buffer = Messagepack::BinaryBuffer.new
          1000.times { |i| buffer.write_bytes([i].pack('C')) }
          buffer_data = buffer.to_s

          suite.benchmark('buffer read_byte (1000x)') do
            buf = Messagepack::BinaryBuffer.new
            buf.feed(buffer_data)
            1000.times { buf.read_byte }
          end

          suite.benchmark('buffer read_bytes (all at once)') do
            buf = Messagepack::BinaryBuffer.new
            buf.feed(buffer_data)
            buf.read(1000)
          end

          suite.run
        end
      end
    end
  end
end

# Run benchmarks if executed directly
if __FILE__ == $PROGRAM_NAME
  Messagepack::Benchmarks::Streaming.run_all
end
