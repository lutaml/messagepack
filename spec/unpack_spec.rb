# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'messagepack'

describe MessagePack do
  it 'MessagePack.unpack symbolize_keys' do
    symbolized_hash = { a: 'b', c: 'd' }
    expect(MessagePack.load(MessagePack.pack(symbolized_hash), symbolize_keys: true)).to eq(symbolized_hash)
    expect(MessagePack.unpack(MessagePack.pack(symbolized_hash), symbolize_keys: true)).to eq(symbolized_hash)
  end

  it 'Unpacker#read symbolize_keys' do
    unpacker = MessagePack::Unpacker.new(symbolize_keys: true)
    symbolized_hash = { a: 'b', c: 'd' }
    expect(unpacker.feed(MessagePack.pack(symbolized_hash)).read).to eq(symbolized_hash)
  end

  it "msgpack str 8 type" do
    expect(MessagePack.unpack([0xd9, 0x00].pack('C*'))).to eq("")
    expect(MessagePack.unpack([0xd9, 0x01].pack('C*') + 'a')).to eq("a")
    expect(MessagePack.unpack([0xd9, 0x02].pack('C*') + 'aa')).to eq("aa")
  end

  it "msgpack str 16 type" do
    expect(MessagePack.unpack([0xda, 0x00, 0x00].pack('C*'))).to eq("")
    expect(MessagePack.unpack([0xda, 0x00, 0x01].pack('C*') + 'a')).to eq("a")
    expect(MessagePack.unpack([0xda, 0x00, 0x02].pack('C*') + 'aa')).to eq("aa")
  end

  it "msgpack str 32 type" do
    expect(MessagePack.unpack([0xdb, 0x00, 0x00, 0x00, 0x00].pack('C*'))).to eq("")
    expect(MessagePack.unpack([0xdb, 0x00, 0x00, 0x00, 0x01].pack('C*') + 'a')).to eq("a")
    expect(MessagePack.unpack([0xdb, 0x00, 0x00, 0x00, 0x02].pack('C*') + 'aa')).to eq("aa")
  end

  it "msgpack bin 8 type" do
    expect(MessagePack.unpack([0xc4, 0x00].pack('C*'))).to eq("".b)
    expect(MessagePack.unpack([0xc4, 0x01].pack('C*') + 'a')).to eq("a".b)
    expect(MessagePack.unpack([0xc4, 0x02].pack('C*') + 'aa')).to eq("aa".b)
  end

  it "msgpack bin 16 type" do
    expect(MessagePack.unpack([0xc5, 0x00, 0x00].pack('C*'))).to eq("".b)
    expect(MessagePack.unpack([0xc5, 0x00, 0x01].pack('C*') + 'a')).to eq("a".b)
    expect(MessagePack.unpack([0xc5, 0x00, 0x02].pack('C*') + 'aa')).to eq("aa".b)
  end

  it "msgpack bin 32 type" do
    expect(MessagePack.unpack([0xc6, 0x00, 0x00, 0x00, 0x00].pack('C*'))).to eq("".b)
    expect(MessagePack.unpack([0xc6, 0x00, 0x00, 0x00, 0x01].pack('C*') + 'a')).to eq("a".b)
    expect(MessagePack.unpack([0xc6, 0x00, 0x00, 0x00, 0x02].pack('C*') + 'aa')).to eq("aa".b)
  end
end
