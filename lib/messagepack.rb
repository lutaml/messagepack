# frozen_string_literal: true

require_relative 'messagepack/version'
require_relative 'messagepack/error'
require_relative 'messagepack/format'
require_relative 'messagepack/buffer'
require_relative 'messagepack/packer'
require_relative 'messagepack/unpacker'
require_relative 'messagepack/factory'
require_relative 'messagepack/bigint'
require_relative 'messagepack/extensions/base'
require_relative 'messagepack/extensions/registry'
require_relative 'messagepack/extensions/value'
require_relative 'messagepack/extensions/timestamp'
require_relative 'messagepack/time'
require_relative 'messagepack/symbol'
require_relative 'messagepack/core_ext'

# MessagePack - Efficient binary serialization format
#
# This is a pure Ruby implementation of the MessagePack specification.
# See https://msgpack.org/ for more information.
#
module Messagepack
  # Buffer class alias for backward compatibility
  Buffer = BinaryBuffer

  DefaultFactory = Factory.new

  # Register built-in extension types

  # Timestamp extension (-1) for Time class
  DefaultFactory.register_type(-1, ::Time,
    packer: ->(time) { Timestamp.to_msgpack_ext(time.tv_sec, time.tv_nsec) },
    unpacker: ->(data) {
      tv = Timestamp.from_msgpack_ext(data)
      ::Time.at(tv.sec, tv.nsec, :nanosecond)
    }
  )

  # Timestamp extension (-1) for Timestamp class
  DefaultFactory.register_type(-1, Timestamp,
    packer: :to_msgpack_ext,
    unpacker: :from_msgpack_ext
  )

  # Module-level convenience methods

  # Serialize an object to MessagePack binary.
  #
  # @param object Object to serialize
  # @param io [IO] Optional IO to write to
  # @param options [Hash] Options to pass to Packer
  # @return [String, nil] Binary string if io is nil
  #
  def self.pack(object, *args)
    io = args.first if args.first.respond_to?(:write)
    options = args.last if args.last.is_a?(Hash)
    DefaultFactory.pack(object, io, **(options || {}))
  end

  # Deserialize MessagePack binary to Ruby object.
  #
  # @param data [String, IO] Binary data or IO to read from
  # @param options [Hash] Options to pass to Unpacker
  # @return [Object] Deserialized object
  #
  def self.unpack(data, options = nil)
    DefaultFactory.unpack(data, **(options || {}))
  end

  # Alias for pack.
  def self.dump(object, *args)
    pack(object, *args)
  end

  # Alias for unpack.
  def self.load(data, options = nil)
    unpack(data, options)
  end
end
