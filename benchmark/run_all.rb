#!/usr/bin/env ruby
# frozen_string_literal: true

# Run all benchmarks and generate a comprehensive report

require_relative "helpers"

include BenchmarkHelpers

Formatter.header("VibeZstd Comprehensive Benchmark Suite")

puts "Ruby version: #{RUBY_VERSION}"
puts "Platform: #{RUBY_PLATFORM}"
puts "Zstd version: #{VibeZstd.version_string}"
puts "Date: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
puts

# Check for fixture
fixture_path = File.join(__dir__, "..", "test", "fixtures", "sample.dict")
unless File.exist?(fixture_path)
  puts "⚠️  Dictionary fixture not found. Generating..."
  require_relative "generate_fixture"
  puts
end

# List of benchmarks to run
benchmarks = [
  {
    name: "Context Reuse",
    file: "context_reuse.rb",
    description: "Compare reusing contexts vs creating new ones"
  },
  {
    name: "Dictionary Usage",
    file: "dictionary_usage.rb",
    description: "Compare compression with and without dictionaries"
  },
  {
    name: "Compression Levels",
    file: "compression_levels.rb",
    description: "Speed vs compression ratio across levels"
  },
  {
    name: "Streaming",
    file: "streaming.rb",
    description: "Streaming API vs one-shot compression"
  },
  {
    name: "Multi-threading",
    file: "multithreading.rb",
    description: "Performance with different worker counts"
  },
  {
    name: "Dictionary Training",
    file: "dictionary_training.rb",
    description: "Compare dictionary training algorithms"
  }
]

# Option parsing
require 'optparse'

options = {
  list: false,
  benchmarks: []
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby run_all.rb [options]"

  opts.on("-l", "--list", "List available benchmarks") do
    options[:list] = true
  end

  opts.on("-b", "--benchmark NAME", "Run specific benchmark (can specify multiple times)") do |name|
    options[:benchmarks] << name
  end

  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end.parse!

# List benchmarks if requested
if options[:list]
  puts "Available benchmarks:\n\n"
  benchmarks.each_with_index do |bench, i|
    puts "#{i + 1}. #{bench[:name]}"
    puts "   File: #{bench[:file]}"
    puts "   Description: #{bench[:description]}"
    puts
  end
  exit
end

# Filter benchmarks if specific ones requested
benchmarks_to_run = if options[:benchmarks].any?
  benchmarks.select do |bench|
    options[:benchmarks].any? { |name| bench[:name].downcase.include?(name.downcase) }
  end
else
  benchmarks
end

if benchmarks_to_run.empty?
  puts "No benchmarks match your criteria. Use --list to see available benchmarks."
  exit 1
end

# Run benchmarks
puts "Running #{benchmarks_to_run.size} benchmark(s)...\n\n"

results = []
start_time = Time.now

benchmarks_to_run.each_with_index do |bench, i|
  puts "\n" + "=" * 80
  puts "Benchmark #{i + 1}/#{benchmarks_to_run.size}: #{bench[:name]}"
  puts "=" * 80
  puts

  begin
    load File.join(__dir__, bench[:file])
    results << { name: bench[:name], status: "✓ Completed" }
  rescue => e
    puts "\n❌ Error running #{bench[:name]}: #{e.message}"
    puts e.backtrace.first(5)
    results << { name: bench[:name], status: "✗ Failed: #{e.message}" }
  end

  # Add separator between benchmarks
  puts "\n" + "-" * 80 + "\n" if i < benchmarks_to_run.size - 1
end

end_time = Time.now
duration = end_time - start_time

# Summary
puts "\n\n"
Formatter.header("Benchmark Suite Summary")

puts "Total time: #{duration.round(2)}s\n\n"

results.each do |result|
  puts "  #{result[:status].ljust(20)} #{result[:name]}"
end

puts "\n"
puts "=" * 80
puts "Benchmark suite completed!"
puts "=" * 80
