#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "helpers"

include BenchmarkHelpers

# Benchmark: Multi-threaded Compression Performance
# Demonstrates the performance impact of using multiple worker threads

BenchmarkHelpers.run_comparison(title: "Multi-threaded Compression Performance") do |results|
  # Generate large test data (multi-threading only helps with larger data)
  large_data = DataGenerator.mixed_data(size: 500_000)
  puts "Test data size: #{Formatter.format_bytes(large_data.bytesize)}"
  puts "CPU cores available: #{`sysctl -n hw.ncpu`.strip rescue 'unknown'}\n\n"

  # Test with different worker counts
  worker_counts = [0, 1, 2, 4, 8]

  worker_counts.each do |workers|
    Formatter.section("Testing: #{workers} worker#{workers == 1 ? '' : 's'} #{workers == 0 ? '(single-threaded)' : ''}")

    cctx = VibeZstd::CCtx.new
    cctx.nb_workers = workers if workers > 0

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
      name: "#{workers} worker#{'s' unless workers == 1}",
      iterations_per_sec: ops_per_sec,
      compression_ratio: compression_ratio,
      memory_bytes: memory,
      "Throughput" => "#{Formatter.format_bytes((large_data.bytesize * 10 / time.real).to_i)}/s"
    )
  end

  puts "\n📊 Multi-threading Analysis:"

  # Calculate speedup vs single-threaded
  baseline = results[0].iterations_per_sec
  results.each do |result|
    speedup = result.iterations_per_sec / baseline
    efficiency = (speedup / result.name.split.first.to_i * 100).round(1) rescue 100.0
    puts "  #{result.name}: #{Formatter.format_ratio(speedup)} speedup" +
         (result.name != "0 workers" ? " (#{efficiency}% efficient)" : "")
  end

  # Test with job_size parameter
  puts "\n"
  Formatter.section("Testing: Multi-threading with different job sizes")

  job_sizes = [256 * 1024, 512 * 1024, 1024 * 1024] # 256KB, 512KB, 1MB
  job_results = []

  job_sizes.each do |job_size|
    cctx = VibeZstd::CCtx.new
    cctx.nb_workers = 4
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
puts "  ✓ Use for data > 256KB (overhead not worth it for smaller data)"
puts "  ✓ Optimal workers: 2-4 for most use cases (diminishing returns after)"
puts "  ✓ More workers = higher memory usage"
puts "  ✓ job_size affects compression ratio vs parallelism tradeoff"
puts "\n  Typical speedups:"
puts "    - 2 workers: 1.5-1.8x faster"
puts "    - 4 workers: 2.0-2.5x faster"
puts "    - 8 workers: 2.2-3.0x faster (diminishing returns)"
