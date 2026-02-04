# frozen_string_literal: true

require_relative 'value'

module Messagepack
  # Timestamp extension type (type -1).
  #
  # Represents a high-resolution timestamp with second and nanosecond precision.
  # Implements the MessagePack timestamp specification:
  # https://github.com/msgpack/msgpack/blob/master/spec.md#timestamp-extension-type
  #
  class Timestamp
    TYPE = -1

    TIMESTAMP32_MAX_SEC = (1 << 32) - 1
    TIMESTAMP64_MAX_SEC = (1 << 34) - 1

    attr_reader :sec, :nsec

    def initialize(sec, nsec)
      @sec = sec
      @nsec = nsec
    end

    # Deserialize from binary payload.
    #
    # @param data [String] Binary payload from MessagePack
    # @return [Timestamp] Deserialized timestamp
    #
    def self.from_msgpack_ext(data)
      case data.bytesize
      when 4
        # timestamp32 (sec: uint32be)
        sec = data.unpack1('L>')
        new(sec, 0)
      when 8
        # timestamp64 (nsec: uint30be, sec: uint34be)
        n, s = data.unpack('L>2')
        sec = ((n & 0b11) << 32) | s
        nsec = n >> 2
        new(sec, nsec)
      when 12
        # timestamp96 (nsec: uint32be, sec: int64be)
        nsec, sec = data.unpack('L>q>')
        new(sec, nsec)
      else
        raise MalformedFormatError, "Invalid timestamp data size: #{data.bytesize}"
      end
    end

    # Serialize to binary payload.
    #
    # @return [String] Binary payload for MessagePack extension
    #
    def to_msgpack_ext
      self.class.to_msgpack_ext(@sec, @nsec)
    end

    # Class helper for serialization.
    #
    # @param sec [Integer] Seconds since epoch
    # @param nsec [Integer] Nanoseconds within second (0-999999999)
    # @return [String] Binary payload
    #
    def self.to_msgpack_ext(sec, nsec)
      if sec >= 0 && nsec >= 0 && sec <= TIMESTAMP64_MAX_SEC
        if nsec == 0 && sec <= TIMESTAMP32_MAX_SEC
          # timestamp32: 4 bytes
          [sec].pack('L>')
        else
          # timestamp64: 8 bytes
          nsec30 = nsec << 2
          sec_high2 = sec >> 32
          sec_low32 = sec & 0xffffffff
          [nsec30 | sec_high2, sec_low32].pack('L>2')
        end
      else
        # timestamp96: 12 bytes
        [nsec, sec].pack('L>q>')
      end
    end

    # Convert to Time object
    def to_time
      Time.at(@sec, @nsec, :nanosecond)
    end

    # Create from Time object
    def self.from_time(time)
      new(time.tv_sec, time.tv_nsec)
    end

    def ==(other)
      other.class == self.class && @sec == other.sec && @nsec == other.nsec
    end

    alias eql? ==

    def hash
      [@sec, @nsec].hash
    end

    # String representation
    def to_s
      "Timestamp(#{@sec}, #{@nsec})"
    end

    alias inspect to_s
  end
end
