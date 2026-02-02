# frozen_string_literal: true

# Compatibility shim for Random class (Ruby 1.8.7 support)
unless defined?(Random)
  class Random
    def initialize(seed = Time.now.to_i)
      Kernel.srand(seed)
      @seed = seed
    end

    attr_reader :seed

    def rand(arg)
      Kernel.rand(arg)
    end

    def bytes(n)
      array = []
      n.times do
        array << rand(256)
      end
      array.pack('C*')
    end
  end
end
