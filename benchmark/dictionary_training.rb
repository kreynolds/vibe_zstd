#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "helpers"

# Benchmark: Dictionary Training Algorithms
# Compares train_dict, train_dict_cover, and train_dict_fast_cover

BenchmarkHelpers.run_comparison(title: "Dictionary Training Algorithm Comparison") do |results|
  # Generate training samples
  puts "Generating training samples..."
  samples = 200.times.map do |i|
    {
      id: i,
      name: "User #{i}",
      email: "user#{i}@example.com",
      created_at: Time.now.to_i - rand(100000),
      status: %w[active pending inactive verified][rand(4)],
      preferences: {
        theme: %w[light dark auto][rand(3)],
        notifications: rand(2) == 1
      }
    }.to_json
  end

  puts "Training samples: #{samples.size}"
  puts "Average sample size: #{Formatter.format_bytes(samples.map(&:bytesize).sum / samples.size)}"
  puts "Total training data: #{Formatter.format_bytes(samples.map(&:bytesize).sum)}\n\n"

  dict_size = 16 * 1024 # 16KB

  # Benchmark 1: train_dict (default algorithm - fast)
  Formatter.section("Testing: train_dict (default/fast algorithm)")
  dict_fast = nil
  fast_time = Benchmark.measure do
    dict_fast = VibeZstd.train_dict(samples, max_dict_size: dict_size)
  end

  puts "Training time: #{fast_time.real.round(3)}s"
  puts "Dictionary size: #{Formatter.format_bytes(dict_fast.bytesize)}"
  puts "Dictionary ID: #{VibeZstd.get_dict_id(dict_fast)}"

  # Test compression effectiveness
  test_sample = samples[100]
  cdict_fast = VibeZstd::CDict.new(dict_fast)
  compressed_fast = VibeZstd.compress(test_sample, dict: cdict_fast)
  ratio_fast = test_sample.bytesize.to_f / compressed_fast.bytesize

  results << BenchmarkResult.new(
    :name => "train_dict",
    :compression_ratio => ratio_fast,
    :memory_bytes => dict_fast.bytesize,
    "Training time" => "#{fast_time.real.round(3)}s",
    "Compressed" => Formatter.format_bytes(compressed_fast.bytesize)
  )

  # Benchmark 2: train_dict_cover (COVER algorithm - better quality)
  Formatter.section("Testing: train_dict_cover (COVER algorithm)")
  dict_cover = nil
  cover_time = Benchmark.measure do
    dict_cover = VibeZstd.train_dict_cover(
      samples,
      max_dict_size: dict_size,
      k: 200,  # Segment size
      d: 6     # Dmer size
    )
  end

  puts "Training time: #{cover_time.real.round(3)}s"
  puts "Dictionary size: #{Formatter.format_bytes(dict_cover.bytesize)}"
  puts "Dictionary ID: #{VibeZstd.get_dict_id(dict_cover)}"

  cdict_cover = VibeZstd::CDict.new(dict_cover)
  compressed_cover = VibeZstd.compress(test_sample, dict: cdict_cover)
  ratio_cover = test_sample.bytesize.to_f / compressed_cover.bytesize

  results << BenchmarkResult.new(
    :name => "train_dict_cover",
    :compression_ratio => ratio_cover,
    :memory_bytes => dict_cover.bytesize,
    "Training time" => "#{cover_time.real.round(3)}s",
    "Compressed" => Formatter.format_bytes(compressed_cover.bytesize)
  )

  # Benchmark 3: train_dict_fast_cover (fast COVER - balanced)
  Formatter.section("Testing: train_dict_fast_cover (fast COVER)")
  dict_fast_cover = nil
  fast_cover_time = Benchmark.measure do
    dict_fast_cover = VibeZstd.train_dict_fast_cover(
      samples,
      max_dict_size: dict_size,
      k: 200,
      d: 6,
      f: 20,   # Frequency array size
      accel: 5 # Acceleration (1-10, higher = faster)
    )
  end

  puts "Training time: #{fast_cover_time.real.round(3)}s"
  puts "Dictionary size: #{Formatter.format_bytes(dict_fast_cover.bytesize)}"
  puts "Dictionary ID: #{VibeZstd.get_dict_id(dict_fast_cover)}"

  cdict_fast_cover = VibeZstd::CDict.new(dict_fast_cover)
  compressed_fast_cover = VibeZstd.compress(test_sample, dict: cdict_fast_cover)
  ratio_fast_cover = test_sample.bytesize.to_f / compressed_fast_cover.bytesize

  results << BenchmarkResult.new(
    :name => "train_dict_fast_cover",
    :compression_ratio => ratio_fast_cover,
    :memory_bytes => dict_fast_cover.bytesize,
    "Training time" => "#{fast_cover_time.real.round(3)}s",
    "Compressed" => Formatter.format_bytes(compressed_fast_cover.bytesize)
  )

  # Compare compression across multiple samples
  puts "\n"
  Formatter.section("Compression effectiveness across test samples")

  test_samples = (101..110).map { |i| samples[i] }

  [:fast, :cover, :fast_cover].each do |dict_type|
    dict_data = case dict_type
    when :fast then dict_fast
    when :cover then dict_cover
    when :fast_cover then dict_fast_cover
    end

    cdict = VibeZstd::CDict.new(dict_data)
    total_original = 0
    total_compressed = 0

    test_samples.each do |sample|
      total_original += sample.bytesize
      compressed = VibeZstd.compress(sample, dict: cdict)
      total_compressed += compressed.bytesize
    end

    avg_ratio = total_original.to_f / total_compressed
    puts "  #{dict_type}: #{Formatter.format_ratio(avg_ratio)} average ratio"
  end

  # Test dictionary sizes
  puts "\n"
  Formatter.section("Dictionary size impact")

  sizes = [4096, 8192, 16384, 32768]
  size_results = []

  sizes.each do |size|
    dict = VibeZstd.train_dict(samples, max_dict_size: size)
    cdict = VibeZstd::CDict.new(dict)
    compressed = VibeZstd.compress(test_sample, dict: cdict)
    ratio = test_sample.bytesize.to_f / compressed.bytesize

    size_results << {
      "Dict Size" => Formatter.format_bytes(size),
      "Actual Size" => Formatter.format_bytes(dict.bytesize),
      "Ratio" => Formatter.format_ratio(ratio),
      "Compressed" => Formatter.format_bytes(compressed.bytesize)
    }
  end

  Formatter.table(size_results)
end

puts "\n💡 Dictionary Training Recommendations:"
puts "  train_dict (default):"
puts "    ✓ Fastest training"
puts "    ✓ Good enough for most use cases"
puts "    ✓ Use when training time matters"
puts "\n  train_dict_cover:"
puts "    ✓ Best compression ratios"
puts "    ✓ Slower training (2-10x slower)"
puts "    ✓ Use for production dictionaries"
puts "\n  train_dict_fast_cover:"
puts "    ✓ Balanced speed/quality"
puts "    ✓ Configurable with accel parameter"
puts "    ✓ Good default for most users"
puts "\n  Dictionary size:"
puts "    - Larger = better compression (diminishing returns > 64KB)"
puts "    - Typical: 16KB-64KB for small messages"
puts "    - Memory overhead: ~2x dictionary size in memory"
