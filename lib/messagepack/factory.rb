# frozen_string_literal: true

require_relative 'packer'
require_relative 'unpacker'
require_relative 'extensions/registry'

module MessagePack
  # Factory for creating packer/unpacker instances with custom type registration.
  #
  # Usage:
  #   factory = MessagePack::Factory.new
  #   factory.register_type(0x01, MyClass, packer: :to_msgpack, unpacker: :from_msgpack)
  #   packer = factory.packer
  #   unpacker = factory.unpacker
  #
  class Factory
    attr_reader :packer_registry, :unpacker_registry

    def initialize
      @packer_registry = ExtensionRegistry::Packer.new
      @unpacker_registry = ExtensionRegistry::Unpacker.new
      @frozen = false
    end

    def freeze
      @frozen = true
      @packer_registry.freeze
      @unpacker_registry.freeze
      super
    end

    # Ensure that when the factory is duplicated (for pool), the registries are also duplicated
    def initialize_copy(other)
      super
      @packer_registry = @packer_registry.dup
      @unpacker_registry = @unpacker_registry.dup
      @frozen = false
    end

    # Register a custom type for packing and unpacking.
    #
    # @param type_id [Integer] Extension type ID (-128 to 127)
    # @param klass [Class] Ruby class to register
    # @param options [Hash] Registration options
    # @option options [Proc, Method, Symbol, String] :packer Serialization proc/method
    # @option options [Proc, Method, Symbol, String] :unpacker Deserialization proc/method
    # @option options [Boolean] :recursive Whether packer/unpacker is passed to proc
    #
    def register_type(type_id, klass, options = {})
      raise FrozenError, "can't modify frozen MessagePack::Factory" if frozen?

      packer = normalize_packer(options[:packer], klass)
      unpacker = normalize_unpacker(options[:unpacker], klass)

      register_type_internal(type_id, klass, packer, unpacker, options)
    end

    # Get list of registered types.
    #
    # @param selector [Symbol] :packer, :unpacker, or :both
    # @return [Array<Hash>] List of registered types
    #
    def registered_types(selector = :both)
      case selector
      when :packer
        @packer_registry.registered_types
      when :unpacker
        @unpacker_registry.registered_types
      when :both
        packer_types = @packer_registry.registered_types
        unpacker_types = @unpacker_registry.registered_types

        # Merge by type_id
        all_types = {}
        packer_types.each { |t| all_types[t[:type]] = t.merge(unpacker: nil) }
        unpacker_types.each do |t|
          if all_types.key?(t[:type])
            all_types[t[:type]][:unpacker] = t[:unpacker]
          else
            all_types[t[:type]] = t.merge(packer: nil)
          end
        end

        all_types.values
      else
        raise ArgumentError, "Invalid selector: #{selector}"
      end
    end

    # Check if a type is registered.
    #
    # @param klass_or_type [Class, Integer] Class or type ID to check
    # @param selector [Symbol] :packer, :unpacker, or :both
    # @return [Boolean]
    #
    def type_registered?(klass_or_type, selector = :both)
      case selector
      when :packer
        @packer_registry.type_registered?(klass_or_type)
      when :unpacker
        @unpacker_registry.type_registered?(klass_or_type)
      when :both
        @packer_registry.type_registered?(klass_or_type) ||
          @unpacker_registry.type_registered?(klass_or_type)
      else
        raise ArgumentError, "Invalid selector: #{selector}"
      end
    end

    # Create a new packer instance.
    #
    # @param io [IO] Optional IO object for streaming output
    # @param options [Hash] Options to pass to Packer
    # @return [Packer] New packer with registered types
    #
    def packer(io = nil, options = nil)
      Packer.new(io, options).tap do |pk|
        pk.instance_variable_set(:@ext_registry, @packer_registry.dup)
      end
    end

    # Create a new unpacker instance.
    #
    # @param io [IO] Optional IO object for streaming input
    # @param options [Hash] Options to pass to Unpacker
    # @return [Unpacker] New unpacker with registered types
    #
    def unpacker(io = nil, **options)
      Unpacker.new(io, **options).tap do |uk|
        uk.instance_variable_set(:@ext_registry, @unpacker_registry.dup)
      end
    end

    # Serialize an object to MessagePack binary.
    #
    # @param object Object to serialize
    # @param io [IO] Optional IO to write to
    # @param options [Hash] Options to pass to Packer
    # @return [String, nil] Binary string if io is nil
    #
    def dump(object, *args)
      io = args.first if args.first.respond_to?(:write)
      options = args.last if args.last.is_a?(Hash)
      packer(io, **(options || {})).tap { |pk| pk.write(object); pk.flush }.full_pack
    end

    # Deserialize MessagePack binary to Ruby object.
    #
    # @param data [String, IO] Binary data or IO to read from
    # @param options [Hash] Options to pass to Unpacker
    # @return [Object] Deserialized object
    #
    def load(data, options = nil)
      # Check if data is an IO-like object
      if data.respond_to?(:read)
        unpacker(data, **(options || {})).full_unpack
      else
        unpacker(nil, **(options || {})).tap { |uk| uk.feed(data) }.full_unpack
      end
    end

    alias :pack :dump
    alias :unpack :load

    # Create a pool of packers/unpackers for thread-safe reuse.
    #
    # @param size [Integer] Number of packers/unpackers in the pool
    # @param options [Hash] Options for packer/unpacker creation
    # @return [Pool] New pool instance
    #
    def pool(size = 1, **options)
      Pool.new(frozen? ? self : dup.freeze, size, options)
    end

    private

    def normalize_packer(packer, klass)
      case packer
      when nil
        packer
      when Proc
        packer
      when String, Symbol
        # Create a proc that calls the method on the object being packed
        ->(obj) { obj.send(packer) }
      when Method
        packer.to_proc
      else
        if packer.respond_to?(:call)
          packer.method(:call).to_proc
        else
          raise ::TypeError, "invalid packer: #{packer.inspect}"
        end
      end
    end

    def normalize_unpacker(unpacker, klass)
      case unpacker
      when nil, Proc
        unpacker
      when String, Symbol
        klass.method(unpacker).to_proc
      when Method
        unpacker.to_proc
      else
        if unpacker.respond_to?(:call)
          unpacker.method(:call).to_proc
        else
          raise ::TypeError, "invalid unpacker: #{unpacker.inspect}"
        end
      end
    end

    def register_type_internal(type_id, klass, packer, unpacker, options)
      # Validate oversized_integer_extension option
      if options[:oversized_integer_extension]
        unless klass == Integer
          raise ArgumentError, "oversized_integer_extension can only be used with Integer class"
        end
      end

      # Only use default methods when packer/unpacker are not specified at all
      # (i.e., the keys don't exist in options)
      has_packer = options.key?(:packer)
      has_unpacker = options.key?(:unpacker)

      if !has_packer && !has_unpacker && packer.nil?
        packer = :to_msgpack_ext if klass.method_defined?(:to_msgpack_ext)
      end

      if !has_packer && !has_unpacker && unpacker.nil?
        unpacker = :from_msgpack_ext if klass.respond_to?(:from_msgpack_ext)
      end

      # Normalize packer/unpacker (convert symbols to procs)
      if packer.is_a?(Symbol)
        method_name = packer
        packer = ->(obj) { obj.send(method_name) }
      end

      if unpacker.is_a?(Symbol)
        unpacker = klass.method(unpacker).to_proc
      end

      flags = 0
      flags |= 0x01 if options[:recursive]
      flags |= 0x02 if options[:oversized_integer_extension]

      @packer_registry.register(type_id, klass, packer, flags: flags) if packer
      @unpacker_registry.register(type_id, klass, unpacker, flags: flags) if unpacker
    end

    # Pool for thread-safe packer/unpacker reuse.
    #
    class Pool
      def initialize(factory, size, options)
        @factory = factory
        @size = size
        @options = options.empty? ? nil : options
        @packers = []
        @unpackers = []
        @mutex = Mutex.new
      end

      # Deserialize data.
      #
      # @param data [String] Binary data
      # @return [Object] Deserialized object
      #
      def load(data)
        with_unpacker { |uk| uk.feed(data); uk.full_unpack }
      end

      # Serialize object.
      #
      # @param object Object to serialize
      # @return [String] Binary data
      #
      def dump(object)
        with_packer { |pk| pk.write(object); pk.full_pack }
      end

      alias :pack :dump
      alias :unpack :load

      # Execute block with a packer from the pool.
      #
      def with_packer
        packer = nil
        @mutex.synchronize do
          packer = @packers.pop || @factory.packer(**(@options || {}))
        end

        yield packer
      ensure
        @mutex.synchronize { @packers << packer.reset } if packer
      end

      # Execute block with an unpacker from the pool.
      #
      def with_unpacker
        unpacker = nil
        @mutex.synchronize do
          unpacker = @unpackers.pop || @factory.unpacker(**(@options || {}))
        end

        yield unpacker
      ensure
        @mutex.synchronize { @unpackers << unpacker.reset } if unpacker
      end

      # Get a packer from the pool and yield it to the block.
      #
      # @return [Object] Result of the block
      #
      def packer
        packer = nil
        @mutex.synchronize do
          packer = @packers.pop || @factory.packer(**(@options || {}))
        end

        # Set frozen flag to prevent type registration
        packer.instance_variable_set(:@frozen, true)

        yield packer
      ensure
        @mutex.synchronize { @packers << packer.reset } if packer
      end

      # Get an unpacker from the pool and yield it to the block.
      #
      # @return [Object] Result of the block
      #
      def unpacker
        unpacker = nil
        @mutex.synchronize do
          unpacker = @unpackers.pop || @factory.unpacker(**(@options || {}))
        end

        # Set frozen flag to prevent type registration
        unpacker.instance_variable_set(:@frozen, true)

        yield unpacker
      ensure
        @mutex.synchronize { @unpackers << unpacker.reset } if unpacker
      end
    end
  end
end
