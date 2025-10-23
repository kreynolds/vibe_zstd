#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "helpers"

# Benchmark: Dictionary Usage Performance
# Demonstrates compression ratio and speed improvements when using trained dictionaries

BenchmarkHelpers.run_comparison(title: "Dictionary Usage Performance Comparison") do |results|
  # Load the trained dictionary
  dict_path = File.join(__dir__, "..", "test", "fixtures", "sample.dict")
  unless File.exist?(dict_path)
    puts "⚠️  Dictionary fixture not found. Run: ruby benchmark/generate_fixture.rb"
    exit 1
  end

  dict_data = File.binread(dict_path)
  cdict = VibeZstd::CDict.new(dict_data)
  ddict = VibeZstd::DDict.new(dict_data)

  puts "Dictionary size: #{Formatter.format_bytes(dict_data.bytesize)}"
  puts "Dictionary ID: #{VibeZstd.get_dict_id(dict_data)}\n\n"

  # Generate test data (similar to training data for best dictionary performance)
  test_samples = 100.times.map do |i|
    {
      id: i + 1000,
      name: "User #{i + 1000}",
      email: "user#{i + 1000}@example.com",
      created_at: Time.now.to_i,
      status: %w[active pending inactive verified][rand(4)],
      preferences: {
        theme: %w[light dark auto][rand(3)],
        notifications: rand(2) == 1,
        language: %w[en es fr de][rand(4)]
      },
      metadata: {
        login_count: rand(1000),
        last_ip: "10.0.#{rand(255)}.#{rand(255)}",
        session_duration: rand(3600)
      }
    }.to_json
  end

  # Benchmark without dictionary
  Formatter.section("Testing: Compression without dictionary")
  cctx = VibeZstd::CCtx.new
  dctx = VibeZstd::DCtx.new

  compressed_sizes_no_dict = []
  no_dict_time = Benchmark.measure do
    test_samples.each do |sample|
      compressed = cctx.compress(sample)
      compressed_sizes_no_dict << compressed.bytesize
      dctx.decompress(compressed)
    end
  end

  no_dict_ops_per_sec = test_samples.size / no_dict_time.real
  avg_compressed_no_dict = compressed_sizes_no_dict.sum / compressed_sizes_no_dict.size.to_f
  puts "Completed #{test_samples.size} operations in #{no_dict_time.real.round(3)}s"

  # Benchmark with dictionary
  Formatter.section("Testing: Compression with dictionary")

  compressed_sizes_with_dict = []
  with_dict_time = Benchmark.measure do
    test_samples.each do |sample|
      compressed = cctx.compress(sample, dict: cdict)
      compressed_sizes_with_dict << compressed.bytesize
      dctx.decompress(compressed, dict: ddict)
    end
  end

  with_dict_ops_per_sec = test_samples.size / with_dict_time.real
  avg_compressed_with_dict = compressed_sizes_with_dict.sum / compressed_sizes_with_dict.size.to_f
  puts "Completed #{test_samples.size} operations in #{with_dict_time.real.round(3)}s"

  # Calculate compression ratios
  avg_original_size = test_samples.map(&:bytesize).sum / test_samples.size.to_f
  compression_ratio_no_dict = avg_original_size / avg_compressed_no_dict
  compression_ratio_with_dict = avg_original_size / avg_compressed_with_dict

  # Memory estimates
  cdict_memory = Memory.estimate_cdict(dict_data.bytesize)
  ddict_memory = Memory.estimate_ddict(dict_data.bytesize)
  dict_memory_overhead = cdict_memory + ddict_memory

  # Collect results
  results << BenchmarkResult.new(
    :name => "Without dictionary",
    :iterations_per_sec => no_dict_ops_per_sec,
    :compression_ratio => compression_ratio_no_dict,
    :memory_bytes => Memory.estimate_cctx + Memory.estimate_dctx,
    "Avg compressed size" => Formatter.format_bytes(avg_compressed_no_dict.to_i)
  )

  results << BenchmarkResult.new(
    :name => "With dictionary",
    :iterations_per_sec => with_dict_ops_per_sec,
    :compression_ratio => compression_ratio_with_dict,
    :memory_bytes => Memory.estimate_cctx + Memory.estimate_dctx + dict_memory_overhead,
    "Avg compressed size" => Formatter.format_bytes(avg_compressed_with_dict.to_i)
  )

  puts "\n📊 Detailed Statistics:"
  puts "  Average original size: #{Formatter.format_bytes(avg_original_size.to_i)}"
  puts "  Average compressed (no dict): #{Formatter.format_bytes(avg_compressed_no_dict.to_i)}"
  puts "  Average compressed (with dict): #{Formatter.format_bytes(avg_compressed_with_dict.to_i)}"
  puts "  Compression improvement: #{((avg_compressed_no_dict - avg_compressed_with_dict) / avg_compressed_no_dict * 100).round(1)}% smaller"
  puts "\n💾 Memory Overhead:"
  puts "  Dictionary in memory: #{Formatter.format_bytes(dict_memory_overhead)}"
  puts "  Dictionary on disk: #{Formatter.format_bytes(dict_data.bytesize)}"
end

puts "\n💡 When to use dictionaries:"
puts "  ✓ Small, similar data (JSON, logs, etc.)"
puts "  ✓ Many small messages with repeated patterns"
puts "  ✓ When compression ratio is more important than speed"
puts "  ✗ Large files (> 1MB each)"
puts "  ✗ Highly variable data with no patterns"
