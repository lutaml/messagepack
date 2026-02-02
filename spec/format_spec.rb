# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'messagepack'

describe MessagePack do
  it "nil" do
    check 1, nil
  end

  it "true" do
    check 1, true
  end

  it "false" do
    check 1, false
  end

  it "zero" do
    check 1, 0
  end

  it "positive fixnum" do
    check 1, 1
    check 1, (1 << 6)
    check 1, (1 << 7) - 1
  end

  it "positive int 8" do
    check 2, (1 << 7)
    check 2, (1 << 8) - 1
  end

  it "positive int 16" do
    check 3, (1 << 8)
    check 3, (1 << 16) - 1
  end

  it "positive int 32" do
    check 5, (1 << 16)
    check 5, (1 << 32) - 1
  end

  it "positive int 64" do
    check 9, (1 << 32)
  end

  it "negative fixnum" do
    check 1, -1
    check 1, -((1 << 5) - 1)
    check 1, -(1 << 5)
  end

  it "negative int 8" do
    check 2, -((1 << 5) + 1)
    check 2, -(1 << 7)
  end

  it "negative int 16" do
    check 3, -((1 << 7) + 1)
    check 3, -(1 << 15)
  end

  it "negative int 32" do
    check 5, -((1 << 15) + 1)
    check 5, -(1 << 31)
  end

  it "negative int 64" do
    check 9, -((1 << 31) + 1)
    check 9, -(1 << 63)
  end

  it "double" do
    check 9, 1.0
    check 9, 0.1
    check 9, -0.1
    check 9, -1.0
  end

  it "fixraw" do
    check_raw 1, 0
    check_raw 1, (1 << 5) - 1
  end

  it "raw 8" do
    check_raw 2, (1 << 5)
    check_raw 2, (1 << 8) - 1
  end

  it "raw 16" do
    check_raw 3, (1 << 8)
    check_raw 3, (1 << 16) - 1
  end

  it "raw 32" do
    check_raw 5, (1 << 16)
  end

  it "str encoding is UTF_8" do
    v = pack_unpack('string'.dup.force_encoding(Encoding::UTF_8))
    expect(v.encoding).to eq(Encoding::UTF_8)
  end

  it "str transcode US-ASCII" do
    v = pack_unpack('string'.dup.force_encoding(Encoding::US_ASCII))
    expect(v.encoding).to eq(Encoding::UTF_8)
  end

  it "str transcode UTF-16" do
    v = pack_unpack('string'.encode(Encoding::UTF_16))
    expect(v.encoding).to eq(Encoding::UTF_8)
    expect(v).to eq('string')
  end

  it "str transcode EUC-JP 7bit safe" do
    v = pack_unpack('string'.dup.force_encoding(Encoding::EUC_JP))
    expect(v.encoding).to eq(Encoding::UTF_8)
    expect(v).to eq('string')
  end

  it "str transcode EUC-JP 7bit unsafe" do
    v = pack_unpack([0xa4, 0xa2].pack('C*').force_encoding(Encoding::EUC_JP))
    expect(v.encoding).to eq(Encoding::UTF_8)
    expect(v).to eq("\xE3\x81\x82".dup.force_encoding('UTF-8'))
  end

  it "symbol to str" do
    v = pack_unpack(:a)
    expect(v).to eq('a'.dup.force_encoding('UTF-8'))
  end

  it "symbol to str with encoding" do
    a = "\xE3\x81\x82".dup.force_encoding('UTF-8')
    v = pack_unpack(a.encode('Shift_JIS').to_sym)
    expect(v.encoding).to eq(Encoding::UTF_8)
    expect(v).to eq(a)
  end

  it "symbol to bin" do
    a = "\xE3\x81\x82".dup.force_encoding('ASCII-8BIT')
    v = pack_unpack(a.to_sym)
    expect(v.encoding).to eq(Encoding::ASCII_8BIT)
    expect(v).to eq(a)
  end

  it "bin 8" do
    check_bin 2, (1 << 8) - 1
  end

  it "bin 16" do
    check_bin 3, (1 << 16) - 1
  end

  it "bin 32" do
    check_bin 5, (1 << 16)
  end

  it "bin encoding is ASCII_8BIT" do
    expect(pack_unpack('string'.dup.force_encoding(Encoding::ASCII_8BIT)).encoding).to eq(Encoding::ASCII_8BIT)
  end

  it "fixarray" do
    check_array 1, 0
    check_array 1, (1 << 4) - 1
  end

  it "array 16" do
    check_array 3, (1 << 4)
  end

  it "array 32" do
    check_array 5, (1 << 16)
  end

  it "nil" do
    match nil, "\xc0".b
  end

  it "false" do
    match false, "\xc2".b
  end

  it "true" do
    match true, "\xc3".b
  end

  it "0" do
    match 0, "\x00".b
  end

  it "127" do
    match 127, "\x7f".b
  end

  it "128" do
    match 128, "\xcc\x80".b
  end

  it "256" do
    match 256, "\xcd\x01\x00".b
  end

  it "-1" do
    match -1, "\xff".b
  end

  it "-33" do
    match -33, "\xd0\xdf".b
  end

  it "-129" do
    match -129, "\xd1\xff\x7f".b
  end

  it "{1=>1}" do
    obj = { 1 => 1 }
    match obj, "\x81\x01\x01".b
  end

  it "1.0" do
    match 1.0, "\xcb\x3f\xf0\x00\x00\x00\x00\x00\x00".b
  end

  it "[]" do
    match [], "\x90".b
  end

  it "[0, 1, ..., 14]" do
    obj = (0..14).to_a
    match obj, "\x9f\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e".b
  end

  it "[0, 1, ..., 15]" do
    obj = (0..15).to_a
    match obj, "\xdc\x00\x10\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f".b
  end

  it "{}" do
    obj = {}
    match obj, "\x80".b
  end

  def check(len, obj)
    raw = obj.to_msgpack.to_s
    expect(raw.length).to eq(len)
    expect(MessagePack.unpack(raw)).to eq(obj)
  end

  def check_raw(overhead, num)
    check num + overhead, (" " * num).force_encoding(Encoding::UTF_8)
  end

  def check_bin(overhead, num)
    check num + overhead, (" " * num).force_encoding(Encoding::ASCII_8BIT)
  end

  def check_array(overhead, num)
    check num + overhead, Array.new(num)
  end

  def match(obj, buf)
    raw = obj.to_msgpack.to_s
    expect(raw).to eq(buf)
  end

  def pack_unpack(obj)
    MessagePack.unpack(obj.to_msgpack)
  end
end
