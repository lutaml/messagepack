# frozen_string_literal: true

module Messagepack
  # Base exception class for all MessagePack errors
  class Error < StandardError; end

  # Exception raised during unpacking/deserialization
  class UnpackError < Error; end
end

# Malformed MessagePack format data
class Messagepack::MalformedFormatError < Messagepack::UnpackError; end

# Stack overflow or underflow during unpacking
class Messagepack::StackError < Messagepack::UnpackError; end

# Type mismatch during unpacking
class Messagepack::TypeError < Messagepack::UnpackError; end

# Unexpected type during unpacking
class Messagepack::UnexpectedTypeError < Messagepack::TypeError; end

# Unknown extension type during unpacking
class Messagepack::UnknownExtTypeError < Messagepack::UnpackError; end
