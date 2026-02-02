# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'messagepack'
  spec.version       = '1.0.0'
  spec.authors       = ['MessagePack Ruby Community']
  spec.email         = ['msgpack@googlegroups.com']

  spec.summary       = 'MessagePack, a binary-based efficient object serialization library'
  spec.description   = 'MessagePack is a binary-based efficient object serialization library. ' \
                       'This is a pure Ruby implementation.'
  spec.homepage      = 'https://github.com/msgpack/msgpack-ruby'
  spec.license       = 'Apache-2.0'

  spec.required_ruby_version = '>= 2.7.0'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Development dependencies are in Gemfile
end
