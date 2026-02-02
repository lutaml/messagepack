# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'messagepack'

# Define constants for easier test writing
Packer = MessagePack::Packer
Unpacker = MessagePack::Unpacker
Buffer = MessagePack::BinaryBuffer  # Alias for compatibility
Factory = MessagePack::Factory
ExtensionValue = MessagePack::ExtensionValue

# Platform constants
IS_JRUBY = RUBY_ENGINE == 'jruby'
IS_TRUFFLERUBY = RUBY_ENGINE == 'truffleruby'

# Helper methods for spec tests

# checking if Hash#[]= (rb_hash_aset) dedupes string keys
def automatic_string_keys_deduplication?
  h = {}
  x = {}
  r = rand.to_s
  h[%W(#{r}).join('')] = :foo
  x[%W(#{r}).join('')] = :foo

  x.keys[0].equal?(h.keys[0])
end

def string_deduplication?
  r1 = rand.to_s
  r2 = r1.dup
  (-r1).equal?(-r2)
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Note: We don't disable monkey patching to maintain compatibility with
  # spec files from the original msgpack-ruby that use global `describe`

  # Allow both `should` and `expect` syntaxes for compatibility
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end

  config.filter_run_when_matching :focus
  config.run_all_when_everything_filtered = true
  config.order = :random
  Kernel.srand config.seed
end
