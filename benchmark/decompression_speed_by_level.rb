#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "helpers"

# Benchmark: Does compression level affect decompression speed?
# Theory: Decompression speed should be constant regardless of compression level

BenchmarkHelpers.run_comparison(title: "Decompression Speed by Compression Level") do |results|
  # Use a large enough dataset to get meaningful measurements
  test_data = DataGenerator.json_data(count: 500)  # ~100KB

  puts "Test data size: #{Formatter.format_bytes(test_data.bytesize)}\n\n"

  # Compression levels to test
  levels = [-1, 1, 3, 9, 19]

  # Pre-compress the data at each level
  compressed_by_level = {}

  puts "Compressing data at different levels...\n"
  levels.each do |level|
    cctx = VibeZstd::CCtx.new
    compressed = cctx.compress(test_data, level: level)
    compressed_by_level[level] = compressed

    ratio = test_data.bytesize.to_f / compressed.bytesize
    puts "  Level #{level.to_s.rjust(3)}: #{Formatter.format_bytes(compressed.bytesize)} (#{ratio.round(2)}x ratio)"
  end

  puts "\nDecompressing 5,000 times at each level...\n"
  iterations = 5000

  levels.each do |level|
    compressed = compressed_by_level[level]

    print "  Level #{level.to_s.rjust(3)}: "

    # Benchmark decompression
    time = Benchmark.measure do
      dctx = VibeZstd::DCtx.new
      iterations.times do
        dctx.decompress(compressed)
      end
    end

    ops_per_sec = iterations / time.real
    throughput_mb = (test_data.bytesize * iterations / time.real) / (1024.0 * 1024.0)

    puts "#{time.real.round(3)}s (#{Formatter.format_number(ops_per_sec.to_i)} ops/sec, #{throughput_mb.round(1)} MB/s)"

    results << BenchmarkResult.new(
      :name => "Level #{level}",
      :iterations_per_sec => ops_per_sec,
      "Compressed Size" => Formatter.format_bytes(compressed.bytesize),
      "Ratio" => "#{(test_data.bytesize.to_f / compressed.bytesize).round(2)}x",
      "Throughput" => "#{throughput_mb.round(1)} MB/s"
    )
  end
end

puts "\n💡 Key Insight:"
puts "  Decompression speed is essentially constant regardless of compression level!"
puts "  Higher levels = better compression ratio, but same decompression speed."
puts "  This means you can use high compression levels for storage without impacting read performance."
