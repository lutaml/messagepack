# frozen_string_literal: true

require_relative 'benchmark_suite'

module Messagepack
  module Benchmarks
    # Extension registry benchmarks
    #
    # Tests the performance of extension type registry operations:
    # - Lookup performance for native types
    # - Lookup performance with many registered types
    # - Ancestor search performance
    # - Cache hit vs miss performance
    #
    module Registry
      class << self
        def run_all
          run_native_type_lookup
          run_registry_size_impact
          run_ancestor_search
          run_cache_performance
        end

        def run_native_type_lookup
          suite = Suite.new('Native Type Lookup Performance')

          # Native types don't go through extension registry
          suite.benchmark('pack native string') { Messagepack.pack('hello world') }
          suite.benchmark('pack native array') { Messagepack.pack([1, 2, 3]) }
          suite.benchmark('pack native hash') { Messagepack.pack({ a: 1, b: 2 }) }
          suite.benchmark('pack native integer') { Messagepack.pack(42) }
          suite.benchmark('pack native float') { Messagepack.pack(3.14) }
          suite.benchmark('pack native symbol') { Messagepack.pack(:foo) }
          suite.benchmark('pack native nil') { Messagepack.pack(nil) }
          suite.benchmark('pack native bool') { Messagepack.pack(true) }

          suite.run
        end

        def run_registry_size_impact
          suite = Suite.new('Registry Size Impact')

          # Create custom types for testing
          custom_types = []

          # Base type for testing
          test_klass = Class.new do
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

          # Test with no registered types
          factory_empty = Messagepack::Factory.new
          obj = test_klass.new(42)

          suite.benchmark('pack custom type (0 registered)') do
            pk = factory_empty.packer
            pk.write(obj)
            pk.full_pack
          end

          # Test with 10 registered types
          factory_10 = Messagepack::Factory.new
          10.times do |i|
            klass = Class.new { attr_reader :i; def initialize(i); @i = i; end }
            factory_10.register_type(0x10 + i, klass, packer: ->(o) { Messagepack.pack(o.i) })
          end

          suite.benchmark('pack custom type (10 registered)') do
            pk = factory_10.packer
            pk.write(obj)
            pk.full_pack
          end

          # Test with 100 registered types
          factory_100 = Messagepack::Factory.new
          100.times do |i|
            klass = Class.new { attr_reader :i; def initialize(i); @i = i; end }
            factory_100.register_type(0x10 + i, klass, packer: ->(o) { Messagepack.pack(o.i) })
          end

          suite.benchmark('pack custom type (100 registered)') do
            pk = factory_100.packer
            pk.write(obj)
            pk.full_pack
          end

          # Test with registered type that matches
          factory_match = Messagepack::Factory.new
          factory_match.register_type(0x01, test_klass, packer: ->(o) { Messagepack.pack(o.value) })

          suite.benchmark('pack registered custom type (10 total)') do
            pk = factory_match.packer
            pk.write(obj)
            pk.full_pack
          end

          suite.run
        end

        def run_ancestor_search
          suite = Suite.new('Ancestor Search Performance')

          # Create inheritance hierarchy
          base_class = Class.new do
            attr_reader :value

            def initialize(value)
              @value = value
            end
          end

          middle_class = Class.new(base_class)
          leaf_class = Class.new(middle_class)

          # Register for base class
          factory = Messagepack::Factory.new
          factory.register_type(0x01, base_class, packer: ->(o) { Messagepack.pack(o.value) })

          leaf_obj = leaf_class.new(42)

          # First lookup (cache miss)
          suite.benchmark('pack leaf class (cache miss)') do
            pk = factory.packer
            pk.write(leaf_obj)
            pk.full_pack
          end

          # Subsequent lookups (cache hit) - need to test separately
          # This would be tested in cache_performance

          suite.run
        end

        def run_cache_performance
          suite = Suite.new('Extension Cache Performance')

          # Create inheritance hierarchy
          base_class = Class.new do
            attr_reader :value

            def initialize(value)
              @value = value
            end
          end

          child_class = Class.new(base_class)

          # Register for base class
          factory = Messagepack::Factory.new
          factory.register_type(0x01, base_class, packer: ->(o) { Messagepack.pack(o.value) })

          base_obj = base_class.new(42)
          child_obj = child_class.new(24)

          # Cache miss vs hit for base class
          suite.benchmark('pack base class (first time - cache miss)') do
            pk = factory.packer
            pk.write(base_obj)
            pk.full_pack
          end

          # Cache miss vs hit for child class
          suite.benchmark('pack child class (first time - cache miss)') do
            pk = factory.packer
            pk.write(child_obj)
            pk.full_pack
          end

          # For cache hits, we need to reuse the same packer
          # This tests the benefit of caching
          packer = factory.packer
          packer.write(base_obj)
          packer.reset

          suite.benchmark('pack base class (same packer - cache hit)') do
            pk = factory.packer
            pk.write(base_obj)
            pk.to_s
            pk.reset
          end

          suite.run
        end

        def run_module_inclusion
          suite = Suite.new('Module Inclusion Performance')

          # Define a module
          test_module = Module.new do
            attr_reader :value

            def value=(v)
              @value = v
            end
          end

          # Create classes with/without module
          class_with_module = Class.new do
            include test_module

            def initialize(value)
              @value = value
            end
          end

          class_without_module = Class.new do
            attr_reader :value

            def initialize(value)
              @value = value
            end
          end

          # Register module type
          factory = Messagepack::Factory.new
          factory.register_type(0x01, test_module, &:value)

          obj_with = class_with_module.new(42)
          obj_without = class_without_module.new(24)

          suite.benchmark('pack class with module (registered)') do
            pk = factory.packer
            pk.write(obj_with)
            pk.full_pack
          end

          suite.benchmark('pack class without module (native)') do
            pk = factory.packer
            pk.write(obj_without)
            pk.full_pack
          end

          suite.run
        end

        def run_packer_registry_lookup
          suite = Suite.new('Packer Registry Lookup Overhead')

          # Direct packing (no registry lookup)
          suite.benchmark('direct pack integer') { Messagepack.pack(42) }
          suite.benchmark('direct pack string') { Messagepack.pack('hello') }
          suite.benchmark('direct pack array') { Messagepack.pack([1, 2, 3]) }

          # Packer with empty registry
          suite.benchmark('packer pack integer (empty registry)') do
            pk = Messagepack::Packer.new
            pk.write(42)
            pk.full_pack
          end

          suite.benchmark('packer pack string (empty registry)') do
            pk = Messagepack::Packer.new
            pk.write('hello')
            pk.full_pack
          end

          suite.benchmark('packer pack array (empty registry)') do
            pk = Messagepack::Packer.new
            pk.write([1, 2, 3])
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
  Messagepack::Benchmarks::Registry.run_all
end
