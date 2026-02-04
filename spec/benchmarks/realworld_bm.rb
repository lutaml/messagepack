# frozen_string_literal: true

require_relative 'benchmark_suite'

module Messagepack
  module Benchmarks
    # Real-world scenario benchmarks
    #
    # Tests the performance of MessagePack on realistic data structures:
    # - API response structures
    # - Log entry structures
    # - Configuration data
    # - Large dataset serialization
    #
    module RealWorld
      class << self
        def run_all
          run_api_response_benchmarks
          run_log_entry_benchmarks
          run_configuration_benchmarks
          run_large_dataset_benchmarks
        end

        def run_api_response_benchmarks
          suite = Suite.new('API Response Structures')

          # Simple API response
          simple_response = {
            status: 'success',
            data: {
              id: 1,
              name: 'Test User',
              email: 'test@example.com'
            }
          }

          suite.benchmark('pack simple API response') { Messagepack.pack(simple_response) }

          # Paginated API response
          paginated_response = {
            status: 'success',
            data: Array.new(50) do |i|
              {
                id: i + 1,
                name: "User #{i}",
                email: "user#{i}@example.com",
                created_at_i: (::Time.now.to_i - (i * 86400))
              }
            end,
            pagination: {
              page: 1,
              per_page: 50,
              total: 1000,
              total_pages: 20
            }
          }

          suite.benchmark('pack paginated API response') { Messagepack.pack(paginated_response) }

          # Error response
          error_response = {
            status: 'error',
            error: {
              code: 'VALIDATION_ERROR',
              message: 'Invalid input data',
              details: {
                field: 'email',
                reason: 'Invalid format'
              }
            }
          }

          suite.benchmark('pack error response') { Messagepack.pack(error_response) }

          suite.run
        end

        def run_log_entry_benchmarks
          suite = Suite.new('Log Entry Structures')

          # Simple log entry
          simple_log = {
            timestamp_i: ::Time.now.to_i,
            level: 'INFO',
            message: 'Request processed successfully',
            context: {
              request_id: 'req-123',
              user_id: 1,
              duration_ms: 45
            }
          }

          suite.benchmark('pack simple log entry') { Messagepack.pack(simple_log) }

          # Detailed log entry with stack trace
          detailed_log = {
            timestamp_i: ::Time.now.to_i,
            level: 'ERROR',
            message: 'Database connection failed',
            context: {
              request_id: 'req-456',
              user_id: 1,
              error_class: 'ConnectionError',
              error_message: 'Could not connect to database',
              backtrace: [
                'app/models/user.rb:45:in `find\'',
                'app/controllers/users_controller.rb:23:in `show\''
              ]
            }
          }

          suite.benchmark('pack detailed log entry') { Messagepack.pack(detailed_log) }

          # Batch log entries
          batch_logs = Array.new(100) do |i|
            {
              timestamp: ::Time.now - i,
              level: i.even? ? 'INFO' : 'DEBUG',
              message: "Log entry #{i}",
              context: { index: i }
            }
          end

          suite.benchmark('pack 100 log entries') { Messagepack.pack(batch_logs) }

          suite.run
        end

        def run_configuration_benchmarks
          suite = Suite.new('Configuration Data Structures')

          # Application configuration
          app_config = {
            app_name: 'MyApp',
            version: '1.0.0',
            environment: 'production',
            server: {
              host: '0.0.0.0',
              port: 3000,
              workers: 4
            },
            database: {
              adapter: 'postgresql',
              host: 'localhost',
              port: 5432,
              database: 'myapp_production',
              pool: 10
            },
            cache: {
              adapter: 'redis',
              host: 'localhost',
              port: 6379,
              namespace: 'myapp'
            },
            features: {
              feature_a: true,
              feature_b: false,
              feature_c: true
            },
            limits: {
              max_requests_per_minute: 1000,
              max_file_size_mb: 10,
              max_upload_count: 5
            }
          }

          suite.benchmark('pack application config') { Messagepack.pack(app_config) }

          # User preferences
          user_preferences = {
            user_id: 1,
            theme: 'dark',
            language: 'en',
            notifications: {
              email: true,
              push: false,
              sms: true
            },
            privacy: {
              profile_visible: true,
              activity_visible: false
            },
            shortcuts: {
              'ctrl+s': 'save',
              'ctrl+f': 'find',
              'ctrl+n': 'new'
            }
          }

          suite.benchmark('pack user preferences') { Messagepack.pack(user_preferences) }

          suite.run
        end

        def run_large_dataset_benchmarks
          suite = Suite.new('Large Dataset Serialization')

          # Product catalog
          product_catalog = Array.new(1000) do |i|
            {
              id: i + 1,
              sku: "PROD-#{i.to_s.rjust(6, '0')}",
              name: "Product #{i}",
              description: "Description for product #{i}",
              price: (rand * 1000).round(2),
              category: ['Electronics', 'Clothing', 'Food', 'Books'].sample,
              in_stock: rand(100),
              created_at: ::Time.now - (rand * 365 * 86400),
              tags: Array.new(rand(5)) { |j| "tag#{j}" },
              attributes: {
                weight: rand(10),
                color: %w[red blue green yellow].sample,
                size: %w[S M L XL].sample
              }
            }
          end

          suite.benchmark('pack 1000 products') { Messagepack.pack(product_catalog) }

          # Time series data (metrics)
          metrics_data = Array.new(1000) do |i|
            {
              timestamp: ::Time.now - (i * 60),
              metric_name: 'request_duration',
              value: rand(1000),
              labels: {
                service: 'api',
                endpoint: '/users',
                method: 'GET'
              }
            }
          end

          suite.benchmark('pack 1000 metric points') { Messagepack.pack(metrics_data) }

          # Social network data
          social_data = {
            users: Array.new(100) do |i|
              {
                id: i + 1,
                username: "user#{i}",
                name: "User #{i}",
                followers: rand(1000),
                following: rand(500)
              }
            end,
            posts: Array.new(500) do |i|
              {
                id: i + 1,
                user_id: rand(100) + 1,
                content: "Post content #{i}",
                created_at: ::Time.now - (rand * 7 * 86400),
                likes: rand(100),
                comments: Array.new(rand(20)) do |j|
                  {
                    user_id: rand(100) + 1,
                    content: "Comment #{j}",
                    created_at: ::Time.now - (rand * 7 * 86400)
                  }
                end
              }
            end
          }

          suite.benchmark('pack social network data') { Messagepack.pack(social_data) }

          suite.run
        end

        def run_comparison_benchmarks
          suite = Suite.new('MessagePack vs JSON (Real World)')

          require 'json'

          # Test data
          test_data = {
            users: Array.new(100) do |i|
              {
                id: i + 1,
                name: "User #{i}",
                email: "user#{i}@example.com",
                active: i.even?,
                score: rand(1000),
                created_at: ::Time.now
              }
            end
          }

          suite.benchmark('MessagePack pack') { Messagepack.pack(test_data) }
          suite.benchmark('JSON generate') { JSON.generate(test_data) }

          msg_packed = Messagepack.pack(test_data)
          json_packed = JSON.generate(test_data)

          suite.benchmark('MessagePack unpack') { Messagepack.unpack(msg_packed) }
          suite.benchmark('JSON parse') { JSON.parse(json_packed) }

          suite.run
        end
      end
    end
  end
end

# Run benchmarks if executed directly
if __FILE__ == $PROGRAM_NAME
  Messagepack::Benchmarks::RealWorld.run_all
end
