# frozen_string_literal: true

module Messagepack
  # ExtensionValue represents a raw MessagePack extension type.
  #
  # This is used when unpacking extension types that don't have a
  # registered handler, or for manual extension construction.
  #
  class ExtensionValue
    attr_accessor :type, :payload

    def initialize(type, payload)
      @type = type
      @payload = payload
    end

    def ==(other)
      return false unless other.is_a?(ExtensionValue)
      @type == other.type && @payload == other.payload
    end

    alias eql? ==

    def hash
      [@type, @payload].hash
    end

    # Convert back to MessagePack format
    def to_msgpack(packer = nil)
      if packer.is_a?(Messagepack::Packer)
        packer.write_extension(@type, @payload)
        packer
      else
        Messagepack::Packer.new.write_extension(@type, @payload).full_pack
      end
    end
  end
end
