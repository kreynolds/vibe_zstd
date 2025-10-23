#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "helpers"

# Benchmark: Multi-threaded Compression Performance
# Demonstrates the performance impact of using multiple worker threads

BenchmarkHelpers.run_comparison(title: "Multi-threaded Compression Performance") do |results|
  # Generate large test data (multi-threading only helps with larger data)
  large_data = DataGenerator.mixed_data(size: 5_000_000)
  puts "Test data size: #{Formatter.format_bytes(large_data.bytesize)}"
  puts "CPU cores available: #{begin
    `sysctl -n hw.ncpu`.strip
  rescue
    "unknown"
  end}\n\n"

  # Test with different worker counts
  worker_counts = [0, 1, 2, 4, 8]

  worker_counts.each do |workers|
    Formatter.section("Testing: #{workers} worker#{(workers == 1) ? "" : "s"} #{(workers == 0) ? "(single-threaded)" : ""}")

    cctx = VibeZstd::CCtx.new
    cctx.workers = workers if workers > 0

    # Warm up
    cctx.compress(large_data)

    # Benchmark compression
    compressed = nil
    time = Benchmark.measure do
      10.times { compressed = cctx.compress(large_data) }
    end

    ops_per_sec = 10 / time.real
    compression_ratio = large_data.bytesize.to_f / compressed.bytesize
    memory = Memory.estimate_cctx(3)

    puts "Completed 10 iterations in #{time.real.round(3)}s"
    puts "Throughput: #{Formatter.format_bytes((large_data.bytesize * 10 / time.real).to_i)}/sec"

    results << BenchmarkResult.new(
      :name => "#{workers} worker#{"s" unless workers == 1}",
      :iterations_per_sec => ops_per_sec,
      :compression_ratio => compression_ratio,
      :memory_bytes => memory,
      "Throughput" => "#{Formatter.format_bytes((large_data.bytesize * 10 / time.real).to_i)}/s"
    )
  end

  puts "\n📊 Multi-threading Analysis:"

  # Calculate speedup vs single-threaded
  baseline = results[0].iterations_per_sec
  results.each do |result|
    speedup = result.iterations_per_sec / baseline
    efficiency = begin
      (speedup / result.name.split.first.to_i * 100).round(1)
    rescue
      100.0
    end
    puts "  #{result.name}: #{Formatter.format_ratio(speedup)} speedup" +
      ((result.name != "0 workers") ? " (#{efficiency}% efficient)" : "")
  end

  # Test with job_size parameter
  puts "\n"
  Formatter.section("Testing: Multi-threading with different job sizes")

  job_sizes = [256 * 1024, 512 * 1024, 1024 * 1024] # 256KB, 512KB, 1MB
  job_results = []

  job_sizes.each do |job_size|
    cctx = VibeZstd::CCtx.new
    cctx.workers = 4
    cctx.job_size = job_size

    time = Benchmark.measure do
      5.times { cctx.compress(large_data) }
    end

    ops_per_sec = 5 / time.real
    puts "  Job size #{Formatter.format_bytes(job_size)}: #{time.real.round(3)}s for 5 iterations"

    job_results << {
      "Job Size" => Formatter.format_bytes(job_size),
      "Time (5 ops)" => "#{time.real.round(3)}s",
      "Ops/sec" => ops_per_sec.round(1)
    }
  end

  Formatter.table(job_results)
end

puts "\n💡 Multi-threading Recommendations:"
puts "  ✓ Generally only beneficial for large files (multiple MB or larger)"
puts "  ✓ Start with 2-4 workers and benchmark your specific use case"
puts "  ✓ Performance benefits vary greatly by data type and compression level"
puts "  ✓ More workers = higher memory usage"
puts "  ✗ May show no improvement or even slowdown for many workloads"
puts "\n  Always benchmark with your actual data before enabling in production."
puts "  See: https://facebook.github.io/zstd/zstd_manual.html"
