# frozen_string_literal: true

require_relative 'extensions/value'

module MessagePack
  # Bigint extension type for arbitrary precision integers.
  #
  # This class handles integers that are too large for 64-bit representation.
  # Uses the same format as msgpack-ruby: 32-bit big-endian chunks.
  #
  class Bigint
    # Bigint extension type ID
    TYPE = 0

    # Number of bits per chunk
    CHUNK_BITLENGTH = 32

    # Ruby pack format: sign byte + 32-bit big-endian chunks
    FORMAT = 'CL>*'

    attr_reader :data

    def initialize(data)
      @data = data
    end

    # Serialize an integer to MessagePack bigint extension format.
    #
    # @param int [Integer] The integer to serialize
    # @return [String] Binary payload
    #
    def self.to_msgpack_ext(int)
      # Format: [sign(1 byte)][32-bit big-endian chunks...]
      # sign: 0 for positive, 1 for negative
      # chunks: absolute value split into 32-bit pieces, LSB first, each in big-endian byte order

      if int == 0
        return "\x00".b
      end

      members = []

      # Sign byte
      if int < 0
        int = -int
        members << 1
      else
        members << 0
      end

      # Split into 32-bit chunks (least significant chunk first)
      base = (2 ** CHUNK_BITLENGTH) - 1
      while int > 0
        members << (int & base)
        int >>= CHUNK_BITLENGTH
      end

      # Pack as sign byte + 32-bit big-endian chunks
      members.pack(FORMAT)
    end

    # Deserialize from binary payload.
    #
    # @param data [String] Binary payload
    # @return [Integer] The deserialized integer
    #
    def self.from_msgpack_ext(data)
      return 0 if data.nil? || data.empty?

      # Unpack as sign byte + 32-bit big-endian chunks
      parts = data.unpack(FORMAT)

      return 0 if parts.empty?

      sign = parts.shift

      return 0 if parts.empty?

      # Reconstruct integer from chunks (LSB first)
      sum = parts.pop.to_i
      parts.reverse_each do |part|
        sum = (sum << CHUNK_BITLENGTH) | part.to_i
      end

      sign == 0 ? sum : -sum
    end

    # Create a Bigint from an integer.
    #
    # @param int [Integer] The integer
    # @return [Bigint] A new Bigint instance
    #
    def self.from_int(int)
      new(to_msgpack_ext(int))
    end

    # Convert to integer.
    #
    # @return [Integer] The integer value
    #
    def to_int
      self.class.from_msgpack_ext(@data)
    end

    # Equality comparison.
    #
    # @param other [Object] Another object
    # @return [Boolean]
    #
    def ==(other)
      return false unless other.is_a?(Bigint)
      to_int == other.to_int
    end

    alias eql? ==

    def hash
      to_int.hash
    end

    # String representation.
    #
    # @return [String]
    #
    def to_s
      "Bigint(#{@data.bytes.map { |b| '0x%02x' % b }.join(' ')})"
    end

    alias inspect to_s
  end
end
