# frozen_string_literal: true

# Symbol extension for MessagePack.
#
# This adds support for serializing Symbol objects directly.
# When registered, symbols are serialized as their string representation.
#
class Symbol
  # to_msgpack_ext is supposed to return a binary string.
  # The canonical way to do it for symbols would be:
  #  [to_s].pack('A*')
  # However in this instance we can take a shortcut
  if method_defined?(:name)
    alias_method :to_msgpack_ext, :name
  else
    alias_method :to_msgpack_ext, :to_s
  end

  # Reconstruct symbol from binary payload.
  #
  # @param data [String] Binary payload (symbol name as string)
  # @return [Symbol] The reconstructed symbol
  #
  def self.from_msgpack_ext(data)
    # from_msgpack_ext is supposed to parse a binary string.
    # The canonical way to do it for symbols would be:
    #  data.unpack1('A*').to_sym
    # However in this instance we can take a shortcut

    # We assume the string encoding is UTF-8, and let Ruby create either
    # an ASCII symbol or UTF-8 symbol.
    data.force_encoding(Encoding::UTF_8).to_sym
  rescue EncodingError
    # If somehow the string wasn't valid UTF-8 not valid ASCII, we fallback
    # to what has been the historical behavior of creating a binary symbol
    data.force_encoding(Encoding::BINARY).to_sym
  end
end
