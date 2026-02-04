# frozen_string_literal: true

require_relative 'packer'

module Messagepack
  # Core extensions for to_msgpack method.
  #
  # This module is included in core Ruby classes to provide
  # a convenient to_msgpack method.
  #
  module CoreExt
    def to_msgpack(packer_or_io = nil)
      if packer_or_io.is_a?(Packer)
        to_msgpack_with_packer(packer_or_io)
      elsif packer_or_io
        Messagepack.pack(self, packer_or_io)
      else
        Messagepack.pack(self)
      end
    end

    private

    def to_msgpack_with_packer(packer)
      packer.write(self)
      packer
    end
  end
end

# Include in core classes
[NilClass, TrueClass, FalseClass, Integer, Float, String, Array, Hash, Symbol].each do |klass|
  klass.include(Messagepack::CoreExt) unless klass.include?(Messagepack::CoreExt)
end
