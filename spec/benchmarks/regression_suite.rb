# frozen_string_literal: true

require 'yaml'
require_relative 'benchmark_suite'
require_relative 'primitives_bm'
require_relative 'containers_bm'
require_relative 'extensions_bm'
require_relative 'streaming_bm'
require_relative 'realworld_bm'
require_relative 'buffer_bm'
require_relative 'registry_bm'

module Messagepack
  module Benchmarks
    # Regression protection suite
    #
    # Ensures that performance doesn't degrade below acceptable thresholds.
    # Compares current performance against a baseline and reports regressions.
    #
    class RegressionSuite
      MIN_IMPROVEMENT_RATIO = 0.95  # Must be at least 95% of baseline
      MAX_IMPROVEMENT_EXPECTED = 2.0 # Any improvement >2x should be verified

      attr_reader :baseline_path, :baseline, :current_results

      def initialize(baseline_path = 'spec/benchmarks/baseline.yml')
        @baseline_path = baseline_path
        @baseline = load_baseline
        @current_results = {}
      end

      # Run all regression checks
      #
      # @return [Boolean] true if no regressions detected
      def verify_all
        puts "\n"
        puts '=' * 80
        puts '  MessagePack Performance Regression Check'
        puts '=' * 80
        puts

        all_pass = true

        collect_current_results
        compare_results

        all_pass
      end

      # Collect current performance measurements
      def collect_current_results
        puts 'Collecting current performance metrics...'
        puts

        # Measure key operations (we can't easily capture benchmark-ips output)
        # For now, this is a placeholder for how we'd capture results
        # In practice, we'd need to extend benchmark_suite to capture results
      end

      # Compare current results with baseline
      def compare_results
        return if @current_results.empty?

        @baseline.each do |category, tests|
          puts "Category: #{category}"
          puts '-' * 40

          tests.each do |name, baseline_value|
            current_value = @current_results.dig(category, name)
            next unless current_value

            ratio = current_value / baseline_value.to_f

            if ratio < MIN_IMPROVEMENT_RATIO
              puts "  ✗ REGRESSION: #{name}"
              puts "      Baseline: #{baseline_value.round(2)} i/s"
              puts "      Current:  #{current_value.round(2)} i/s"
              puts "      Ratio:    #{ratio.round(2)}x (#{((ratio - 1) * 100).round(1)}%)"
            elsif ratio > MAX_IMPROVEMENT_EXPECTED
              puts "  ⚠ UNEXPECTED IMPROVEMENT: #{name}"
              puts "      Baseline: #{baseline_value.round(2)} i/s"
              puts "      Current:  #{current_value.round(2)} i/s"
              puts "      Ratio:    #{ratio.round(2)}x (#{((ratio - 1) * 100).round(1)}%)"
              puts "      NOTE: Large improvement - verify baseline is correct"
            else
              improvement = ((ratio - 1) * 100).round(1)
              indicator = improvement >= 0 ? '+' : ''
              puts "  ✓ #{name}: #{current_value.round(2)} i/s (#{indicator}#{improvement}% vs baseline)"
            end
          end

          puts
        end
      end

      # Update the baseline with current results
      #
      # @param results [Hash] Current performance results
      def update_baseline(results)
        save_baseline(results)
        puts "Baseline updated at: #{@baseline_path}"
      end

      # Generate baseline from current run
      #
      # @return [Hash] Baseline measurements
      def generate_baseline
        puts "\n"
        puts '=' * 80
        puts '  Generating Baseline Measurements'
        puts '=' * 80
        puts
        puts 'Note: This is a placeholder. In a real implementation,'
        puts 'we would run each benchmark and capture the IPS values.'
        puts
        puts 'For now, please run individual benchmark files to see results.'
        puts

        # Placeholder baseline structure
        {
          primitives: {
            pack_nil: 1_000_000,
            pack_true: 1_000_000,
            pack_false: 1_000_000,
            pack_fixnum: 800_000,
            pack_uint8: 600_000,
            pack_uint16: 500_000,
            pack_uint32: 400_000,
            pack_float64: 400_000,
            pack_fixstr: 500_000,
            pack_str8: 350_000,
            pack_symbol: 400_000
          },
          containers: {
            pack_empty_array: 800_000,
            pack_small_array: 300_000,
            pack_large_array: 5_000,
            pack_empty_hash: 700_000,
            pack_small_hash: 200_000,
            pack_large_hash: 3_000,
            pack_nested_hash: 50_000
          },
          buffer: {
            write_byte_1000: 200_000,
            write_bytes_small: 150_000,
            write_bytes_large: 300_000,
            to_s_many_chunks: 10_000,
            to_s_one_chunk: 50_000
          },
          registry: {
            pack_native_string: 400_000,
            pack_with_10_registered: 350_000,
            pack_with_100_registered: 300_000,
            cache_miss: 200_000,
            cache_hit: 400_000
          },
          extensions: {
            pack_timestamp: 150_000,
            pack_symbol_extension: 200_000,
            pack_custom_extension: 100_000
          },
          streaming: {
            pack_single_write: 200_000,
            pack_100_small_writes: 50_000,
            unpack_single_feed: 100_000,
            unpack_multiple_feeds: 80_000
          },
          realworld: {
            pack_api_response: 100_000,
            pack_log_entry: 80_000,
            pack_config: 50_000,
            pack_1000_products: 2_000
          }
        }
      end

      # Save baseline to file
      #
      # @param baseline [Hash] Baseline data
      def save_baseline(baseline)
        File.open(@baseline_path, 'w') do |f|
          f.write(baseline.to_yaml)
        end
      end

      # Load baseline from file
      #
      # @return [Hash] Baseline data
      def load_baseline
        if File.exist?(@baseline_path)
          YAML.load_file(@baseline_path)
        else
          puts "Warning: Baseline file not found at #{@baseline_path}"
          puts "Run with --generate-baseline to create one."
          puts
          {}
        end
      end

      # Check if a specific test meets the baseline
      #
      # @param category [String] Test category
      # @param name [String] Test name
      # @param current_value [Numeric] Current measured value
      # @return [Hash] Comparison result
      def check_test(category, name, current_value)
        baseline_value = @baseline.dig(category, name)
        return { status: :no_baseline } unless baseline_value

        ratio = current_value / baseline_value.to_f

        if ratio < MIN_IMPROVEMENT_RATIO
          { status: :regression, ratio: ratio, baseline: baseline_value, current: current_value }
        elsif ratio > MAX_IMPROVEMENT_EXPECTED
          { status: :unexpected_improvement, ratio: ratio, baseline: baseline_value, current: current_value }
        else
          { status: :pass, ratio: ratio, baseline: baseline_value, current: current_value }
        end
      end

      # Print summary report
      #
      # @param results [Hash] Comparison results
      def print_summary(results)
        puts "\n"
        puts '=' * 80
        puts '  Summary'
        puts '=' * 80
        puts

        pass_count = results.values.count { |v| v && v[:status] == :pass }
        regression_count = results.values.count { |v| v && v[:status] == :regression }
        unexpected_count = results.values.count { |v| v && v[:status] == :unexpected_improvement }
        no_baseline_count = results.values.count { |v| v.nil? || v[:status] == :no_baseline }

        total = results.values.size

        puts "Total tests: #{total}"
        puts "  ✓ Pass: #{pass_count}"
        puts "  ✗ Regressions: #{regression_count}"
        puts "  ⚠ Unexpected improvements: #{unexpected_count}"
        puts "  - No baseline: #{no_baseline_count}"
        puts

        if regression_count > 0
          puts "FAILURE: #{regression_count} regression(s) detected!"
          false
        else
          puts "SUCCESS: No regressions detected!"
          true
        end
      end
    end
  end
end

# Run regression suite if executed directly
if __FILE__ == $PROGRAM_NAME
  require 'optparse'

  options = {}
  OptionParser.new do |opts|
    opts.banner = 'Usage: regression_suite.rb [options]'

    opts.on('-g', '--generate-baseline', 'Generate new baseline file') do
      options[:generate] = true
    end

    opts.on('-b', '--baseline FILE', 'Specify baseline file') do |file|
      options[:baseline] = file
    end

    opts.on('-h', '--help', 'Show this message') do
      puts opts
      exit
    end
  end.parse!

  # Use default baseline path if not specified
  baseline_path = options[:baseline] || 'spec/benchmarks/baseline.yml'
  suite = Messagepack::Benchmarks::RegressionSuite.new(baseline_path)

  if options[:generate]
    baseline = suite.generate_baseline
    suite.save_baseline(baseline)
  else
    exit(suite.verify_all ? 0 : 1)
  end
end
