# frozen_string_literal: true

require_relative 'benchmark_suite'

module Messagepack
  module Benchmarks
    # Container type benchmarks
    #
    # Tests the performance of packing/unpacking container MessagePack types:
    # - Empty arrays and hashes
    # - Small arrays (2-10 elements)
    # - Large arrays (100-1000 elements)
    # - Nested arrays
    # - Small hashes (2-10 key-value pairs)
    # - Large hashes (100-1000 key-value pairs)
    # - Nested hashes
    # - Mixed nested structures
    #
    module Containers
      class << self
        def run_all
          run_array_benchmarks
          run_hash_benchmarks
          run_nested_benchmarks
        end

        def run_array_benchmarks
          run_empty_array_benchmarks
          run_small_array_benchmarks
          run_large_array_benchmarks
        end

        def run_empty_array_benchmarks
          suite = Suite.new('Empty Array Packing')
          suite.benchmark('pack []') { Messagepack.pack([]) }
          suite.benchmark('unpack []') { Messagepack.unpack(Messagepack.pack([])) }
          suite.run
        end

        def run_small_array_benchmarks
          suite = Suite.new('Small Array Packing (2-10 elements)')

          suite.benchmark('pack [1, 2]') { Messagepack.pack([1, 2]) }
          suite.benchmark('pack [1, 2, 3, 4, 5]') { Messagepack.pack([1, 2, 3, 4, 5]) }
          suite.benchmark('pack [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]') do
            Messagepack.pack([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
          end

          # String array
          suite.benchmark('pack ["a", "b", "c", "d", "e"]') do
            Messagepack.pack(%w[a b c d e])
          end

          suite.run
        end

        def run_large_array_benchmarks
          suite = Suite.new('Large Array Packing (100-1000 elements)')

          # 100 elements
          arr_100 = (0...100).to_a
          suite.benchmark('pack 100 integers') { Messagepack.pack(arr_100) }

          # 1000 elements
          arr_1000 = (0...1000).to_a
          suite.benchmark('pack 1000 integers') { Messagepack.pack(arr_1000) }

          # String array
          str_100 = Array.new(100) { |i| "item#{i}" }
          suite.benchmark('pack 100 strings') { Messagepack.pack(str_100) }

          suite.run
        end

        def run_hash_benchmarks
          run_empty_hash_benchmarks
          run_small_hash_benchmarks
          run_large_hash_benchmarks
        end

        def run_empty_hash_benchmarks
          suite = Suite.new('Empty Hash Packing')
          suite.benchmark('pack {}') { Messagepack.pack({}) }
          suite.benchmark('unpack {}') { Messagepack.unpack(Messagepack.pack({})) }
          suite.run
        end

        def run_small_hash_benchmarks
          suite = Suite.new('Small Hash Packing (2-10 key-value pairs)')

          suite.benchmark('pack {a: 1, b: 2}') { Messagepack.pack({ a: 1, b: 2 }) }
          suite.benchmark('pack {a: 1, b: 2, c: 3, d: 4, e: 5}') do
            Messagepack.pack({ a: 1, b: 2, c: 3, d: 4, e: 5 })
          end
          suite.benchmark('pack {k1: "v1", k2: "v2", k3: "v3", k4: "v4", k5: "v5", k6: "v6", k7: "v7", k8: "v8", k9: "v9", k10: "v10"}') do
            h = {}
            (1..10).each { |i| h[:"k#{i}"] = "v#{i}" }
            Messagepack.pack(h)
          end

          suite.run
        end

        def run_large_hash_benchmarks
          suite = Suite.new('Large Hash Packing (100-1000 key-value pairs)')

          # 100 key-value pairs
          hash_100 = Hash[(0...100).map { |i| ["key#{i}", i] }]
          suite.benchmark('pack 100 KV pairs') { Messagepack.pack(hash_100) }

          # 1000 key-value pairs
          hash_1000 = Hash[(0...1000).map { |i| ["key#{i}", i] }]
          suite.benchmark('pack 1000 KV pairs') { Messagepack.pack(hash_1000) }

          suite.run
        end

        def run_nested_benchmarks
          run_nested_array_benchmarks
          run_nested_hash_benchmarks
          run_mixed_nested_benchmarks
        end

        def run_nested_array_benchmarks
          suite = Suite.new('Nested Array Packing')

          suite.benchmark('pack [[1, 2], [3, 4]]') { Messagepack.pack([[1, 2], [3, 4]]) }
          suite.benchmark('pack [[1, 2], [3, 4], [5, 6], [7, 8]]') do
            Messagepack.pack([[1, 2], [3, 4], [5, 6], [7, 8]])
          end

          # Deep nesting
          deep_array = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
          suite.benchmark('pack deeply nested arrays') { Messagepack.pack(deep_array) }

          suite.run
        end

        def run_nested_hash_benchmarks
          suite = Suite.new('Nested Hash Packing')

          suite.benchmark('pack {a: {b: 1}}') { Messagepack.pack({ a: { b: 1 } }) }
          suite.benchmark('pack {a: {b: {c: 1}}}') { Messagepack.pack({ a: { b: { c: 1 } } }) }

          # Deep nesting
          deep_hash = { a: { b: { c: { d: { e: 1 } } } } }
          suite.benchmark('pack deeply nested hash') { Messagepack.pack(deep_hash) }

          suite.run
        end

        def run_mixed_nested_benchmarks
          suite = Suite.new('Mixed Nested Structures')

          # Array of hashes
          suite.benchmark('pack [{a: 1}, {b: 2}, {c: 3}]') do
            Messagepack.pack([{ a: 1 }, { b: 2 }, { c: 3 }])
          end

          # Hash with array values
          suite.benchmark('pack {a: [1, 2], b: [3, 4], c: [5, 6]}') do
            Messagepack.pack({ a: [1, 2], b: [3, 4], c: [5, 6] })
          end

          # Complex nested structure
          complex = {
            users: [
              { name: 'Alice', age: 30, emails: ['alice@example.com'] },
              { name: 'Bob', age: 25, emails: ['bob@example.com'] }
            ],
            settings: {
              theme: 'dark',
              notifications: true
            }
          }
          suite.benchmark('pack complex nested structure') { Messagepack.pack(complex) }

          # Very deep nesting - build programmatically
          very_deep = { a: 1 }
          9.times { very_deep = { a: very_deep } }
          suite.benchmark('pack 10-level deep hash') { Messagepack.pack(very_deep) }

          suite.run
        end
      end
    end
  end
end

# Run benchmarks if executed directly
if __FILE__ == $PROGRAM_NAME
  Messagepack::Benchmarks::Containers.run_all
end
