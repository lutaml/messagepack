# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'messagepack'

describe Messagepack do
  it 'to_msgpack returns String' do
    expect(nil.to_msgpack.class).to eq(String)
    expect(true.to_msgpack.class).to eq(String)
    expect(false.to_msgpack.class).to eq(String)
    expect(1.to_msgpack.class).to eq(String)
    expect(1.0.to_msgpack.class).to eq(String)
    expect("".to_msgpack.class).to eq(String)
    expect(Hash.new.to_msgpack.class).to eq(String)
    expect(Array.new.to_msgpack.class).to eq(String)
  end

  class CustomPack01
    def to_msgpack(pk = nil)
      return Messagepack.pack(self, pk) unless pk.class == Messagepack::Packer
      pk.write_array_header(2)
      pk.write(1)
      pk.write(2)
      return pk
    end
  end

  class CustomPack02
    def to_msgpack(pk = nil)
      [1, 2].to_msgpack(pk)
    end
  end

  it 'calls custom to_msgpack method' do
    expect(Messagepack.pack(CustomPack01.new)).to eq([1, 2].to_msgpack)
    expect(Messagepack.pack(CustomPack02.new)).to eq([1, 2].to_msgpack)
    expect(CustomPack01.new.to_msgpack).to eq([1, 2].to_msgpack)
    expect(CustomPack02.new.to_msgpack).to eq([1, 2].to_msgpack)
  end

  it 'calls custom to_msgpack method with io' do
    require 'stringio'
    s01 = StringIO.new
    Messagepack.pack(CustomPack01.new, s01)
    expect(s01.string.b).to eq([1, 2].to_msgpack)

    s02 = StringIO.new
    Messagepack.pack(CustomPack02.new, s02)
    expect(s02.string.b).to eq([1, 2].to_msgpack)

    s03 = StringIO.new
    CustomPack01.new.to_msgpack(s03)
    expect(s03.string.b).to eq([1, 2].to_msgpack)

    s04 = StringIO.new
    CustomPack02.new.to_msgpack(s04)
    expect(s04.string.b).to eq([1, 2].to_msgpack)
  end
end
