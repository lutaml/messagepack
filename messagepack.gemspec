# frozen_string_literal: true

require_relative "lib/messagepack/version"

Gem::Specification.new do |spec|
  spec.name = "messagepack"
  spec.version = Messagepack::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary       = "Pure Ruby implementation of the MessagePack binary serialization format"
  spec.description   = "MessagePack Ruby is a pure Ruby implementation of the MessagePack binary
serialization format. MessagePack is an efficient binary serialization format that
enables exchange of data among multiple languages like JSON, but is faster and smaller."
  spec.homepage      = "https://github.com/lutaml/messagepack"
  spec.license       = "MIT"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__,
                                             err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github
                          Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage
end
