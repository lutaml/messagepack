# frozen_string_literal: true

module Messagepack
  # Extension registries for packer and unpacker.
  #
  # The packer registry maps Ruby classes to extension type IDs and packing procs.
  # The unpacker registry maps extension type IDs to unpacking procs.
  #
  module ExtensionRegistry
    # Packer registry for serializing custom types.
    #
    # Uses hash-based lookup with ancestor chain caching.
    #
    class Packer
      def initialize
        @registry = {}  # klass => [type_id, proc, flags]
        @cache = {}     # klass => [type_id, proc, flags] (ancestor cache)
      end

      def dup
        copy = self.class.new
        copy.instance_variable_set(:@registry, @registry.dup)
        copy.instance_variable_set(:@cache, {})
        copy
      end

      alias clone dup

      def register(type_id, klass, proc, flags: 0)
        @registry[klass] = [type_id, proc, flags]
        @cache.clear
      end

      def lookup(value)
        klass = value.class
        return @registry[klass] if @registry.key?(klass)

        # Check cache
        return @cache[klass] if @cache.key?(klass)

        # Search ancestors and modules
        @registry.each do |registered_class, data|
          # Check for inheritance (klass <= registered_class)
          if klass <= registered_class
            @cache[klass] = data
            return data
          end

          # Check if registered_class is a module (but not a class) and klass includes it
          # In Ruby, Class is not a subclass of Module, so we need to check the class
          if registered_class.is_a?(Class)
            # registered_class is a Class, already handled by inheritance check above
            next
          end

          # registered_class is a Module
          # Check if klass includes the module
          if klass.include?(registered_class)
            @cache[klass] = data
            return data
          end

          # Check if the object's singleton class includes the module
          # This handles cases like: obj.extend(Mod)
          # Some values don't support singleton_class:
          # - Immediate values: nil, true, false, integers, floats, symbols
          # - Frozen values (frozen_string_literal: true makes string literals frozen)
          unless value.nil? || value == true || value == false ||
                 value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(Symbol) ||
                 value.frozen?
            if value.singleton_class.include?(registered_class)
              @cache[klass] = data
              return data
            end
          end
        end

        nil
      end

      def registered_types
        @registry.map { |klass, (type_id, proc, flags)|
          { type: type_id, class: klass, packer: proc }
        }
      end

      def type_registered?(klass_or_type)
        if klass_or_type.is_a?(Integer)
          @registry.any? { |_, (type_id, _, _)| type_id == klass_or_type }
        else
          @registry.key?(klass_or_type)
        end
      end

      def clear
        @registry.clear
        @cache.clear
      end
    end

    # Unpacker registry for deserializing custom types.
    #
    # Uses direct array for O(1) type ID lookup.
    #
    class Unpacker
      ARRAY_SIZE = 256  # Signed byte range: -128 to 127

      def initialize
        @array = ::Array.new(ARRAY_SIZE)  # [klass, proc, flags]
      end

      def dup
        copy = self.class.new
        copy.instance_variable_set(:@array, @array.dup)
        copy
      end

      alias clone dup

      def register(type_id, klass, proc, flags: 0)
        index = type_id + 128  # Offset for signed byte
        raise IndexError, "type_id out of range: #{type_id}" unless (0...ARRAY_SIZE).cover?(index)
        @array[index] = [klass, proc, flags]
      end

      def lookup(type_id)
        index = type_id + 128
        return nil unless (0...ARRAY_SIZE).cover?(index)
        @array[index]
      end

      def registered_types
        @array.each_with_index.map { |(klass, proc, flags), index|
          next unless proc  # Include entries that have a proc, even if klass is nil
          { type: index - 128, class: klass, unpacker: proc }
        }.compact
      end

      def type_registered?(klass_or_type)
        if klass_or_type.is_a?(Integer)
          index = klass_or_type + 128
          # Check if any data (klass, proc, or flags) exists at this type ID index
          (0...ARRAY_SIZE).cover?(index) && @array[index]&.at(1)
        else
          @array.any? { |(klass, _, _)| klass == klass_or_type }
        end
      end

      def clear
        @array.fill(nil)
      end
    end
  end
end
