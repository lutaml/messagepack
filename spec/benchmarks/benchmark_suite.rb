# frozen_string_literal: true

require 'benchmark/ips'
begin
  require 'benchmark/memory'
rescue LoadError
  # benchmark-memory is optional
end
require_relative '../../lib/messagepack'

module Messagepack
  module Benchmarks
    # Unified benchmark runner using benchmark-ips
    #
    # Provides a consistent interface for running benchmarks and collecting
    # performance metrics.
    #
    class Suite
      attr_reader :name, :tests, :results

      def initialize(name)
        @name = name
        @tests = []
        @results = {}
      end

      # Define a benchmark test
      #
      # @param label [String] The label for this benchmark
      # @yield The block to benchmark
      def benchmark(label, &block)
        @tests << [label, block]
      end

      # Define multiple benchmarks from a hash
      #
      # @param benchmarks [Hash] Hash of label => block pairs
      def benchmarks(benchmarks)
        benchmarks.each { |label, block| @tests << [label, block] }
      end

      # Run all benchmarks and display results
      #
      # @param quiet [Boolean] If true, suppress output
      # @return [Hash] Results hash with label => ips (iterations per second)
      def run(quiet: false)
        return runquiet(quiet) if quiet

        puts "\n"
        puts '=' * 80
        puts "  #{@name}"
        puts '=' * 80

        Benchmark.ips do |x|
          @tests.each do |label, block|
            x.report(label, &block)
          end
          x.compare!
        end

        @results
      end

      # Run benchmarks quietly and return results
      #
      # @param silent [Boolean] If true, completely suppress output
      # @return [Hash] Results hash with label => ips (iterations per second)
      def runquiet(silent = false)
        @results.clear

        @tests.each do |label, block|
          ips = nil
          Benchmark.ips(quiet: !silent) do |x|
            x.report(label, &block)
            ips = lambda do
              # Capture IPS after the benchmark completes
              x.send(:calc, x.send(:data))
            end
          end
          # Store the result
          capture_result(label)
        end

        @results
      end

      # Run and return results as a hash
      #
      # @return [Hash] Results hash with label => ips (iterations per second)
      def measure
        runquiet(true)

        @tests.each do |label, _block|
          @results[label] = measure_single(label)
        end

        @results
      end

      # Measure a single benchmark and return IPS
      #
      # @param label [String] The benchmark label
      # @return [Float, nil] Iterations per second
      def measure_single(label)
        test = @tests.find { |l, _| l == label }
        return nil unless test

        _, block = test
        ips = nil

        Benchmark.ips(quiet: true) do |x|
          x.report(label, &block)
        end

        ips
      end

      # Compare results with a baseline
      #
      # @param baseline [Hash] Baseline results from previous run
      # @return [Hash] Comparison results
      def compare(baseline)
        comparison = {}

        @results.each do |label, current_ips|
          baseline_ips = baseline[label]
          next unless baseline_ips

          ratio = current_ips / baseline_ips.to_f
          comparison[label] = {
            current: current_ips,
            baseline: baseline_ips,
            ratio: ratio,
            improvement: ratio >= 1.0 ? ((ratio - 1.0) * 100).round(2) : -((1.0 - ratio) * 100).round(2)
          }
        end

        comparison
      end

      # Print comparison report
      #
      # @param baseline [Hash] Baseline results
      def print_comparison(baseline)
        comparison = compare(baseline)

        puts "\n"
        puts '=' * 80
        puts "  Comparison Report: #{@name}"
        puts '=' * 80
        puts

        comparison.each do |label, data|
          if data[:ratio] >= 1.0
            puts "  ✓ #{label}:"
            puts "      #{data[:current].round(2)} i/s vs #{data[:baseline].round(2)} i/s"
            puts "      +#{data[:improvement]}% improvement"
          else
            puts "  ✗ #{label}:"
            puts "      #{data[:current].round(2)} i/s vs #{data[:baseline].round(2)} i/s"
            puts "      #{data[:improvement]}% regression"
          end
          puts
        end
      end

      private

      # Capture result from benchmark-ips
      #
      # This is a placeholder - benchmark-ips doesn't provide a clean API
      # for capturing results. In practice, we'll need to parse output or
      # use a different approach.
      def capture_result(label)
        # benchmark-ips doesn't provide a clean way to capture results
        # We'll need to extend it or parse the output
        nil
      end
    end

    # Memory benchmark runner using benchmark-memory
    #
    class MemorySuite
      attr_reader :name, :tests

      def initialize(name)
        @name = name
        @tests = []
      end

      def benchmark(label, &block)
        @tests << [label, block]
      end

      def run
        return run_fallback unless defined?(Benchmark.memory)

        puts "\n"
        puts '=' * 80
        puts "  Memory Benchmark: #{@name}"
        puts '=' * 80
        puts

        Benchmark.memory do |x|
          @tests.each do |label, block|
            x.report(label, &block)
          end
          x.compare!
        end
      end

      def run_fallback
        puts "\n"
        puts '=' * 80
        puts "  Memory Benchmark: #{@name} (skipped - benchmark-memory not available)"
        puts '=' * 80
        puts
        puts "Install benchmark-memory gem for memory profiling:"
        puts "  gem install benchmark-memory"
      end
    end
  end
end
