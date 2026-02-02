# frozen_string_literal: true

module MessagePack
  # MessagePack format specification constants
  #
  # See: https://github.com/msgpack/msgpack/blob/master/spec.md
  #
  module Format
    # Format type markers (single-byte)
    NIL              = 0xc0
    FALSE            = 0xc2
    TRUE             = 0xc3
    BIN8             = 0xc4
    BIN16            = 0xc5
    BIN32            = 0xc6
    EXT8             = 0xc7
    EXT16            = 0xc8
    EXT32            = 0xc9
    FLOAT32          = 0xca
    FLOAT64          = 0xcb
    UINT8            = 0xcc
    UINT16           = 0xcd
    UINT32           = 0xce
    UINT64           = 0xcf
    INT8             = 0xd0
    INT16            = 0xd1
    INT32            = 0xd2
    INT64            = 0xd3
    FIXEXT1          = 0xd4
    FIXEXT2          = 0xd5
    FIXEXT4          = 0xd6
    FIXEXT8          = 0xd7
    FIXEXT16         = 0xd8
    STR8             = 0xd9
    STR16            = 0xda
    STR32            = 0xdb
    ARRAY16          = 0xdc
    ARRAY32          = 0xdd
    MAP16            = 0xde
    MAP32            = 0xdf

    # Range constants for fix formats
    POSITIVE_FIXNUM_MIN = 0x00
    POSITIVE_FIXNUM_MAX = 0x7f
    NEGATIVE_FIXNUM_MIN = 0xe0  # represents -32
    NEGATIVE_FIXNUM_MAX = 0xff  # represents -1
    FIXARRAY_MIN       = 0x90
    FIXARRAY_MAX       = 0x9f
    FIXMAP_MIN         = 0x80
    FIXMAP_MAX         = 0x8f
    FIXRAW_MIN         = 0xa0
    FIXRAW_MAX         = 0xbf

    # Helper methods to determine format type
    class << self
      def positive_fixnum?(byte)
        byte >= POSITIVE_FIXNUM_MIN && byte <= POSITIVE_FIXNUM_MAX
      end

      def negative_fixnum?(byte)
        byte >= NEGATIVE_FIXNUM_MIN && byte <= NEGATIVE_FIXNUM_MAX
      end

      def fixnum?(byte)
        positive_fixnum?(byte) || negative_fixnum?(byte)
      end

      def fixarray?(byte)
        byte >= FIXARRAY_MIN && byte <= FIXARRAY_MAX
      end

      def fixmap?(byte)
        byte >= FIXMAP_MIN && byte <= FIXMAP_MAX
      end

      def fixstr?(byte)
        byte >= FIXRAW_MIN && byte <= FIXRAW_MAX
      end

      # Extract count from fix format header
      def fixarray_count(byte)
        byte - FIXARRAY_MIN
      end

      def fixmap_count(byte)
        byte - FIXMAP_MIN
      end

      def fixstr_length(byte)
        byte - FIXRAW_MIN
      end

      # Convert negative fixnum byte to integer value
      def negative_fixnum_value(byte)
        byte - 256
      end
    end
  end
end
