# frozen_string_literal: true

module MessagePack
  module Extension
    # Base module for extension types.
    #
    # Extension types allow custom Ruby objects to be serialized
    # and deserialized with MessagePack.
    #
    # To create a custom extension:
    #
    #   class MyType
    #     include MessagePack::Extension::Base
    #
    #     attr_reader :data
    #
    #     def initialize(data)
    #       @data = data
    #     end
    #
    #     def to_msgpack_ext
    #       @data  # Return binary string representation
    #     end
    #
    #     def self.from_msgpack_ext(data)
    #       new(data)  # Reconstruct from binary string
    #     end
    #   end
    #
    #   # Register the extension
    #   MyType.register_as_extension(42)
    #
    module Base
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Register this class as an extension type.
        #
        # @param type_id [Integer] The extension type ID (-128 to 127)
        # @param recursive [Boolean] Whether packer/unpacker is passed to proc
        def register_as_extension(type_id, recursive: false)
          MessagePack::DefaultFactory.register_type(
            type_id,
            self,
            packer: ->(obj) { obj.to_msgpack_ext },
            unpacker: ->(data) { from_msgpack_ext(data) },
            recursive: recursive
          )
        end
      end
    end
  end
end
