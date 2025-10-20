#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "helpers"

include BenchmarkHelpers

# Benchmark: Compression Levels Speed vs Ratio
# Demonstrates the trade-off between compression speed and compression ratio

BenchmarkHelpers.run_comparison(title: "Compression Levels: Speed vs Ratio") do |results|
  # Test with different data types
  test_data = {
    "JSON data" => DataGenerator.json_data(count: 100),
    "Log data" => DataGenerator.log_data(count: 100),
    "Mixed data" => DataGenerator.mixed_data(size: 10_000)
  }

  # Levels to test: negative (ultra-fast), low, default, medium, high, max
  levels_to_test = [-1, 1, 3, 9, 15, 19, 22]

  puts "Testing compression levels: #{levels_to_test.join(', ')}\n"
  puts "Min level: #{VibeZstd.min_compression_level}"
  puts "Max level: #{VibeZstd.max_compression_level}"
  puts "Default level: #{VibeZstd.default_compression_level}\n\n"

  test_data.each do |data_name, data|
    Formatter.section("Data type: #{data_name} (#{Formatter.format_bytes(data.bytesize)})")

    data_results = []

    levels_to_test.each do |level|
      cctx = VibeZstd::CCtx.new
      dctx = VibeZstd::DCtx.new

      # Benchmark compression
      compressed = nil
      compress_time = Benchmark.measure do
        100.times { compressed = cctx.compress(data, level: level) }
      end
      compress_ops_per_sec = 100 / compress_time.real

      # Benchmark decompression
      decompress_time = Benchmark.measure do
        100.times { dctx.decompress(compressed) }
      end
      decompress_ops_per_sec = 100 / decompress_time.real

      compression_ratio = data.bytesize.to_f / compressed.bytesize
      memory = Memory.estimate_cctx(level)

      data_results << {
        "Level" => level,
        "Compressed" => Formatter.format_bytes(compressed.bytesize),
        "Ratio" => Formatter.format_ratio(compression_ratio),
        "Compress" => "#{compress_ops_per_sec.round(0)} ops/s",
        "Decompress" => "#{decompress_ops_per_sec.round(0)} ops/s",
        "Memory" => Formatter.format_bytes(memory)
      }

      print "."
    end

    puts "\n"
    Formatter.table(data_results)
  end

  # Overall recommendations with a single data type for summary
  Formatter.section("Performance Summary (Mixed Data)")
  summary_data = DataGenerator.mixed_data(size: 50_000)

  levels_to_test.each do |level|
    cctx = VibeZstd::CCtx.new

    compressed = nil
    time = Benchmark.measure do
      10.times { compressed = cctx.compress(summary_data, level: level) }
    end

    ops_per_sec = 10 / time.real
    compression_ratio = summary_data.bytesize.to_f / compressed.bytesize
    memory = Memory.estimate_cctx(level)

    results << BenchmarkResult.new(
      name: "Level #{level}",
      iterations_per_sec: ops_per_sec,
      compression_ratio: compression_ratio,
      memory_bytes: memory,
      "Compressed" => Formatter.format_bytes(compressed.bytesize)
    )
  end
end

puts "\n💡 Level Recommendations:"
puts "  Level -1:  Ultra-fast, use for real-time compression (3-5x faster than level 1)"
puts "  Level 1-3: Fast compression, good for high-throughput scenarios"
puts "  Level 3:   Default, balanced speed/ratio (recommended for most use cases)"
puts "  Level 5-9: Better compression, moderate speed cost"
puts "  Level 10-15: High compression, slower (good for archival)"
puts "  Level 16-22: Maximum compression, very slow (archival, one-time compression)"
puts "\n  💾 Memory usage increases significantly at higher levels (15+)"
