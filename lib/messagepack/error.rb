# frozen_string_literal: true

module MessagePack
  # Base exception class for all MessagePack errors
  class Error < StandardError; end

  # Exception raised during unpacking/deserialization
  class UnpackError < Error; end
end

# Malformed MessagePack format data
class MessagePack::MalformedFormatError < MessagePack::UnpackError; end

# Stack overflow or underflow during unpacking
class MessagePack::StackError < MessagePack::UnpackError; end

# Type mismatch during unpacking
class MessagePack::TypeError < MessagePack::UnpackError; end

# Unexpected type during unpacking
class MessagePack::UnexpectedTypeError < MessagePack::TypeError; end

# Unknown extension type during unpacking
class MessagePack::UnknownExtTypeError < MessagePack::UnpackError; end
