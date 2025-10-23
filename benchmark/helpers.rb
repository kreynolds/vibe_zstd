# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "vibe_zstd"
require "json"
require "benchmark" # Built-in Ruby module

# Try to load optional dependencies (gracefully handle missing gems)
HAS_BENCHMARK_DEPS = begin
  # Don't use bundler/setup - it's too strict. Just try to require the gems.
  require "benchmark/ips"
  require "terminal-table"
  true
rescue LoadError
  puts "⚠️  Optional benchmark dependencies not installed."
  puts "    Run: bundle install"
  puts "    Continuing with basic benchmark output...\n\n"
  false
end

module BenchmarkHelpers
  # Data generators for realistic test scenarios
  module DataGenerator
    # Generate JSON-like data (common in web apps)
    def self.json_data(count: 100)
      records = count.times.map do |i|
        {
          id: i,
          name: "User #{i}",
          email: "user#{i}@example.com",
          created_at: Time.now.to_i - rand(100000),
          status: %w[active pending inactive][rand(3)],
          metadata: {
            login_count: rand(1000),
            last_ip: "192.168.1.#{rand(255)}"
          }
        }
      end
      records.map(&:to_json).join("\n")
    end

    # Generate log-like data (common in logging scenarios)
    def self.log_data(count: 100)
      levels = %w[INFO WARN ERROR DEBUG]
      messages = [
        "Request processed successfully",
        "Database query took %dms",
        "Cache miss for key: user_%d",
        "Connection established to %s",
        "Background job completed"
      ]

      count.times.map do |i|
        level = levels[rand(levels.length)]
        message = messages[rand(messages.length)]
        message = format(message, rand(1000)) if message.include?("%")
        timestamp = Time.now.to_i - rand(100000)
        "[#{timestamp}] #{level}: #{message}"
      end.join("\n")
    end

    # Generate data with repeated patterns (good for LDM testing)
    def self.repeated_pattern_data(pattern_size: 1000, repetitions: 10, unique_middle: 500)
      pattern = "A" * pattern_size
      middle = "B" * unique_middle
      (pattern * repetitions) + middle + (pattern * repetitions)
    end

    # Generate random data (worst case for compression)
    def self.random_data(size: 10_000)
      size.times.map { rand(256).chr }.join
    end

    # Generate highly compressible data
    def self.compressible_data(size: 10_000)
      "a" * size
    end

    # Mixed realistic data
    def self.mixed_data(size: 10_000)
      json_data(count: size / 100) + "\n" + log_data(count: size / 100)
    end
  end

  # Formatting helpers for nice output
  module Formatter
    def self.header(title)
      puts "\n#{"=" * 80}"
      puts title.center(80)
      puts "#{"=" * 80}\n\n"
    end

    def self.section(title)
      puts "\n#{title}"
      puts "-" * title.length
    end

    def self.table(data, title: nil)
      puts "\n## #{title}\n" if title

      # Create markdown table
      if data.is_a?(Array) && data.first.is_a?(Hash)
        headers = data.first.keys
        rows = data.map(&:values)

        if defined?(Terminal::Table)
          table = Terminal::Table.new(headings: headers, rows: rows)
          puts table
          puts
        end

        # Print markdown version (always, for README)
        puts "Markdown table (for README):" if defined?(Terminal::Table)
        puts "| #{headers.join(" | ")} |"
        puts "| #{headers.map { "---" }.join(" | ")} |"
        rows.each do |row|
          puts "| #{row.join(" | ")} |"
        end
      end
      puts
    end

    def self.markdown_table(data, title: nil)
      puts "\n## #{title}\n" if title

      if data.is_a?(Array) && data.first.is_a?(Hash)
        headers = data.first.keys
        rows = data.map(&:values)

        puts "| #{headers.join(" | ")} |"
        puts "| #{headers.map { "---" }.join(" | ")} |"
        rows.each do |row|
          puts "| #{row.join(" | ")} |"
        end
      end
      puts
    end

    def self.format_bytes(bytes)
      if bytes < 1024
        "#{bytes}B"
      elsif bytes < 1024 * 1024
        "#{(bytes / 1024.0).round(1)}KB"
      else
        "#{(bytes / (1024.0 * 1024)).round(2)}MB"
      end
    end

    def self.format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    def self.format_ratio(ratio)
      "#{ratio.round(2)}x"
    end
  end

  # Memory tracking utilities
  module Memory
    def self.estimate_cctx(level = 3)
      VibeZstd::CCtx.estimate_memory(level)
    end

    def self.estimate_dctx
      VibeZstd::DCtx.estimate_memory
    end

    def self.estimate_cdict(dict_size, level = 3)
      VibeZstd::CDict.estimate_memory(dict_size, level)
    end

    def self.estimate_ddict(dict_size)
      VibeZstd::DDict.estimate_memory(dict_size)
    end

    def self.current_memory_usage
      # Try to get actual memory usage (platform-specific)
      if RUBY_PLATFORM.match?(/darwin/)
        # macOS
        `ps -o rss= -p #{Process.pid}`.to_i * 1024
      elsif RUBY_PLATFORM.match?(/linux/)
        # Linux
        File.read("/proc/#{Process.pid}/statm").split[1].to_i * 4096
      else
        # Fallback
        0
      end
    end
  end

  # Benchmark result tracking
  class BenchmarkResult
    attr_reader :name, :iterations_per_sec, :memory_bytes, :compression_ratio, :extra_data

    def initialize(name:, iterations_per_sec: nil, memory_bytes: nil, compression_ratio: nil, **extra_data)
      @name = name
      @iterations_per_sec = iterations_per_sec
      @memory_bytes = memory_bytes
      @compression_ratio = compression_ratio
      @extra_data = extra_data
    end

    def to_h
      h = {"Method" => name}
      h["Speed"] = "#{Formatter.format_number(iterations_per_sec.to_i)} ops/sec" if iterations_per_sec
      h["Memory"] = Formatter.format_bytes(memory_bytes) if memory_bytes
      h["Ratio"] = Formatter.format_ratio(compression_ratio) if compression_ratio
      h.merge!(extra_data.transform_values { |v| v.is_a?(Numeric) ? Formatter.format_number(v.to_i) : v.to_s })
      h
    end
  end

  # Helper to run a benchmark and collect results
  def self.run_comparison(title:, &block)
    Formatter.header(title)
    results = []

    yield results

    # Display results
    if results.any?
      Formatter.table(results.map(&:to_h), title: "Results")

      # Calculate speedups if we have iterations_per_sec
      if results.all? { |r| r.iterations_per_sec }
        baseline = results.first.iterations_per_sec
        puts "\nRelative Performance:"
        results.each do |result|
          speedup = result.iterations_per_sec / baseline
          puts "  #{result.name}: #{Formatter.format_ratio(speedup)}"
        end
      end
    end

    results
  end
end
