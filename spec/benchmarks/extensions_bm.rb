# frozen_string_literal: true

require_relative 'benchmark_suite'
require 'time'

module Messagepack
  module Benchmarks
    # Extension type benchmarks
    #
    # Tests the performance of packing/unpacking extension MessagePack types:
    # - Timestamp (32, 64, 96 bit)
    # - Symbol extension
    # - Custom extension types
    # - Recursive extension packing
    #
    module Extensions
      class << self
        def run_all
          run_timestamp_benchmarks
          run_symbol_extension_benchmarks
          run_custom_extension_benchmarks
          run_recursive_extension_benchmarks
        end

        def run_timestamp_benchmarks
          suite = Suite.new('Timestamp Extension Packing')

          # 32-bit timestamp (seconds since epoch)
          ts_32 = ::Time.at(1_700_000_000)
          suite.benchmark('pack 32-bit timestamp') { Messagepack.pack(ts_32) }

          # 64-bit timestamp (nanoseconds since epoch)
          ts_64 = ::Time.now
          suite.benchmark('pack 64-bit timestamp') { Messagepack.pack(ts_64) }

          # 96-bit timestamp (high precision)
          ts_96 = ::Time.at(1_700_000_000, 123_456_789, :nanosecond)
          suite.benchmark('pack 96-bit timestamp') { Messagepack.pack(ts_96) }

          # Unpack timestamps
          packed_ts = Messagepack.pack(ts_64)
          suite.benchmark('unpack timestamp') { Messagepack.unpack(packed_ts) }

          suite.run
        end

        def run_symbol_extension_benchmarks
          suite = Suite.new('Symbol Extension Packing')

          # Symbol extension vs string packing
          suite.benchmark('pack symbol with extension') { Messagepack.pack(:test_symbol) }
          suite.benchmark('pack string equivalent') { Messagepack.pack('test_symbol') }

          # Unpack symbol
          packed_symbol = Messagepack.pack(:test_symbol)
          suite.benchmark('unpack symbol') { Messagepack.unpack(packed_symbol) }

          # Multiple symbols
          symbols = [:foo, :bar, :baz, :qux, :quux]
          suite.benchmark('pack array of symbols') { Messagepack.pack(symbols) }

          suite.run
        end

        def run_custom_extension_benchmarks
          suite = Suite.new('Custom Extension Packing')

          # Create a custom type with extension
          custom_class = Class.new do
            attr_reader :x, :y

            def initialize(x, y)
              @x = x
              @y = y
            end

            def to_msgpack(packer = nil)
              if packer
                packer.write_array_header(2)
                packer.write(@x)
                packer.write(@y)
              else
                Messagepack.pack([@x, @y])
              end
            end
          end

          obj = custom_class.new(10, 20)

          suite.benchmark('pack custom object (to_msgpack)') { Messagepack.pack(obj) }

          # Register as extension type
          factory = Messagepack::Factory.new
          factory.register_type(0x01, custom_class) { |obj| [obj.x, obj.y].to_msgpack }

          packer = factory.packer
          suite.benchmark('pack custom object (registered extension)') do
            pk = factory.packer
            pk.write(obj)
            pk.full_pack
          end

          suite.run
        end

        def run_recursive_extension_benchmarks
          suite = Suite.new('Recursive Extension Packing')

          # Create a recursive custom type
          recursive_class = Class.new do
            attr_reader :name, :children

            def initialize(name, children = [])
              @name = name
              @children = children
            end

            def to_msgpack(packer = nil)
              if packer
                packer.write_array_header(2)
                packer.write(@name)
                packer.write(@children)
              else
                Messagepack.pack([@name, @children])
              end
            end
          end

          # Simple recursive structure
          simple = recursive_class.new('root', [
            recursive_class.new('child1'),
            recursive_class.new('child2')
          ])

          suite.benchmark('pack recursive object (2 children)') { Messagepack.pack(simple) }

          # Deeper recursive structure
          deep = recursive_class.new('root', [
            recursive_class.new('child1', [
              recursive_class.new('grandchild1'),
              recursive_class.new('grandchild2')
            ]),
            recursive_class.new('child2', [
              recursive_class.new('grandchild3')
            ])
          ])

          suite.benchmark('pack recursive object (deep)') { Messagepack.pack(deep) }

          # Very wide recursive structure
          wide_children = Array.new(100) { |i| recursive_class.new("child#{i}") }
          wide = recursive_class.new('root', wide_children)

          suite.benchmark('pack recursive object (100 children)') { Messagepack.pack(wide) }

          suite.run
        end

        def run_extension_lookup_benchmarks
          suite = Suite.new('Extension Registry Lookup Performance')

          # Test the overhead of extension registry lookups
          factory = Messagepack::Factory.new

          # Register many types
          100.times do |i|
            klass = Class.new
            factory.register_type(0x10 + i, klass) { |obj| "data" }
          end

          # Create an instance of a registered type
          registered_klass = Class.new do
            attr_reader :value

            def initialize(value)
              @value = value
            end

            def to_msgpack(packer = nil)
              if packer
                packer.write(@value)
              else
                Messagepack.pack(@value)
              end
            end
          end

          factory.register_type(0x01, registered_klass, &:value)

          obj = registered_klass.new(42)

          suite.benchmark('pack with 100 registered types') do
            pk = factory.packer
            pk.write(obj)
            pk.full_pack
          end

          suite.run
        end
      end
    end
  end
end

# Run benchmarks if executed directly
if __FILE__ == $PROGRAM_NAME
  Messagepack::Benchmarks::Extensions.run_all
end
