# frozen_string_literal: true

require_relative 'benchmark_suite'

module Messagepack
  module Benchmarks
    # Primitive type benchmarks
    #
    # Tests the performance of packing/unpacking primitive MessagePack types:
    # - Nil, True, False
    # - Fixnums (positive/negative)
    # - Integers (uint8, uint16, uint32, uint64, int8, int16, int32, int64)
    # - Floats (float32, float64)
    # - Strings (fixstr, str8, str16, str32)
    # - Binary data
    # - Symbols
    #
    module Primitives
      class << self
        def run_all
          run_nil_benchmarks
          run_boolean_benchmarks
          run_integer_benchmarks
          run_float_benchmarks
          run_string_benchmarks
          run_binary_benchmarks
          run_symbol_benchmarks
        end

        def run_nil_benchmarks
          suite = Suite.new('Nil Packing')
          suite.benchmark('pack nil') { Messagepack.pack(nil) }
          suite.benchmark('unpack nil') { Messagepack.unpack(Messagepack.pack(nil)) }
          suite.run
        end

        def run_boolean_benchmarks
          suite = Suite.new('Boolean Packing')
          suite.benchmark('pack true') { Messagepack.pack(true) }
          suite.benchmark('pack false') { Messagepack.pack(false) }
          suite.benchmark('unpack true') { Messagepack.unpack(Messagepack.pack(true)) }
          suite.benchmark('unpack false') { Messagepack.unpack(Messagepack.pack(false)) }
          suite.run
        end

        def run_integer_benchmarks
          run_fixnum_benchmarks
          run_uint_benchmarks
          run_int_benchmarks
        end

        def run_fixnum_benchmarks
          suite = Suite.new('Fixnum Packing')

          # Positive fixnums (0-127)
          suite.benchmark('pack 0') { Messagepack.pack(0) }
          suite.benchmark('pack 1') { Messagepack.pack(1) }
          suite.benchmark('pack 42') { Messagepack.pack(42) }
          suite.benchmark('pack 127') { Messagepack.pack(127) }

          # Negative fixnums (-32 to -1)
          suite.benchmark('pack -1') { Messagepack.pack(-1) }
          suite.benchmark('pack -32') { Messagepack.pack(-32) }

          suite.run
        end

        def run_uint_benchmarks
          suite = Suite.new('Unsigned Integer Packing')

          # uint8
          suite.benchmark('pack 128 (uint8)') { Messagepack.pack(128) }
          suite.benchmark('pack 255 (uint8)') { Messagepack.pack(255) }

          # uint16
          suite.benchmark('pack 256 (uint16)') { Messagepack.pack(256) }
          suite.benchmark('pack 65535 (uint16)') { Messagepack.pack(65_535) }

          # uint32
          suite.benchmark('pack 65536 (uint32)') { Messagepack.pack(65_536) }
          suite.benchmark('pack 4294967295 (uint32)') { Messagepack.pack(4_294_967_295) }

          # uint64
          suite.benchmark('pack 4294967296 (uint64)') { Messagepack.pack(4_294_967_296) }

          suite.run
        end

        def run_int_benchmarks
          suite = Suite.new('Signed Integer Packing')

          # int8
          suite.benchmark('pack -33 (int8)') { Messagepack.pack(-33) }
          suite.benchmark('pack -128 (int8)') { Messagepack.pack(-128) }

          # int16
          suite.benchmark('pack -129 (int16)') { Messagepack.pack(-129) }
          suite.benchmark('pack -32768 (int16)') { Messagepack.pack(-32_768) }

          # int32
          suite.benchmark('pack -32769 (int32)') { Messagepack.pack(-32_769) }
          suite.benchmark('pack -2147483648 (int32)') { Messagepack.pack(-2_147_483_648) }

          # int64
          suite.benchmark('pack -2147483649 (int64)') { Messagepack.pack(-2_147_483_649) }

          suite.run
        end

        def run_float_benchmarks
          suite = Suite.new('Float Packing')

          # float64 (default)
          suite.benchmark('pack 3.14') { Messagepack.pack(3.14) }
          suite.benchmark('pack -3.14') { Messagepack.pack(-3.14) }
          suite.benchmark('pack 1e100') { Messagepack.pack(1e100) }
          suite.benchmark('pack -1e100') { Messagepack.pack(-1e100) }

          # Manual float32 packing
          packer = Messagepack::Packer.new
          suite.benchmark('pack float32 3.14') do
            pk = Messagepack::Packer.new
            pk.write_float32(3.14)
            pk.full_pack
          end

          suite.run
        end

        def run_string_benchmarks
          run_fixstr_benchmarks
          run_str_benchmarks
        end

        def run_fixstr_benchmarks
          suite = Suite.new('FixStr Packing')

          suite.benchmark('pack "" (empty)') { Messagepack.pack('') }
          suite.benchmark('pack "a"') { Messagepack.pack('a') }
          suite.benchmark('pack "hello"') { Messagepack.pack('hello') }
          suite.benchmark('pack "a" * 31') { Messagepack.pack('a' * 31) }

          suite.run
        end

        def run_str_benchmarks
          suite = Suite.new('Str8/16/32 Packing')

          # str8
          suite.benchmark('pack "a" * 32 (str8)') { Messagepack.pack('a' * 32) }
          suite.benchmark('pack "a" * 255 (str8)') { Messagepack.pack('a' * 255) }

          # str16
          suite.benchmark('pack "a" * 256 (str16)') { Messagepack.pack('a' * 256) }
          suite.benchmark('pack "a" * 65535 (str16)') { Messagepack.pack('a' * 65_535) }

          # str32
          suite.benchmark('pack "a" * 65536 (str32)') { Messagepack.pack('a' * 65_536) }

          suite.run
        end

        def run_binary_benchmarks
          suite = Suite.new('Binary Packing')

          # bin8
          suite.benchmark('pack binary 32 bytes') { Messagepack.pack('a' * 32.encode('BINARY')) }
          suite.benchmark('pack binary 255 bytes') { Messagepack.pack('a' * 255.encode('BINARY')) }

          # bin16
          suite.benchmark('pack binary 256 bytes') { Messagepack.pack('a' * 256.encode('BINARY')) }

          suite.run
        end

        def run_symbol_benchmarks
          suite = Suite.new('Symbol Packing')

          suite.benchmark('pack :foo') { Messagepack.pack(:foo) }
          suite.benchmark('pack :hello_world') { Messagepack.pack(:hello_world) }
          suite.benchmark('pack :"a" * 31') { Messagepack.pack(('a' * 31).to_sym) }

          suite.run
        end
      end
    end
  end
end

# Run benchmarks if executed directly
if __FILE__ == $PROGRAM_NAME
  Messagepack::Benchmarks::Primitives.run_all
end
