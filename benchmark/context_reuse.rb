#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "helpers"

# Benchmark: Context Reuse vs New Context Creation
# This demonstrates the performance benefit of reusing compression/decompression contexts

BenchmarkHelpers.run_comparison(title: "Context Reuse Performance Comparison") do |results|
  # Test with different data sizes to show consistent benefit
  test_cases = {
    "Small (1KB)" => DataGenerator.json_data(count: 5),
    "Medium (10KB)" => DataGenerator.json_data(count: 50),
    "Large (100KB)" => DataGenerator.json_data(count: 500)
  }

  test_cases.each do |size_label, test_data|
    Formatter.section("Data size: #{size_label} (#{Formatter.format_bytes(test_data.bytesize)})")

    # Determine iterations based on data size (more iterations for smaller data to reduce noise)
    iterations = case test_data.bytesize
    when 0..5000 then 10000
    when 5001..50000 then 5000
    else 2000
    end

    puts "Running #{Formatter.format_number(iterations)} iterations...\n"

    # Benchmark 1: Creating new contexts every time (inefficient)
    print "  New context per operation: "
    new_context_time = Benchmark.measure do
      iterations.times do
        cctx = VibeZstd::CCtx.new
        dctx = VibeZstd::DCtx.new
        compressed = cctx.compress(test_data)
        dctx.decompress(compressed)
      end
    end
    new_context_ops_per_sec = iterations / new_context_time.real
    puts "#{new_context_time.real.round(3)}s (#{Formatter.format_number(new_context_ops_per_sec.to_i)} ops/sec)"

    # Benchmark 2: Reusing contexts (efficient)
    print "  Reused context (no reset): "
    reused_context_time = Benchmark.measure do
      cctx = VibeZstd::CCtx.new
      dctx = VibeZstd::DCtx.new

      iterations.times do
        compressed = cctx.compress(test_data)
        dctx.decompress(compressed)
      end
    end
    reused_context_ops_per_sec = iterations / reused_context_time.real
    puts "#{reused_context_time.real.round(3)}s (#{Formatter.format_number(reused_context_ops_per_sec.to_i)} ops/sec)"

    speedup = reused_context_ops_per_sec / new_context_ops_per_sec
    puts "  → Speedup: #{Formatter.format_ratio(speedup)}"

    # Benchmark 3: Reusing contexts with reset(:session)
    print "  Reused + reset(:session): "
    reused_reset_session_time = Benchmark.measure do
      cctx = VibeZstd::CCtx.new
      dctx = VibeZstd::DCtx.new

      iterations.times do
        compressed = cctx.compress(test_data)
        dctx.decompress(compressed)
        cctx.reset(VibeZstd::ResetDirective::SESSION)
        dctx.reset(VibeZstd::ResetDirective::SESSION)
      end
    end
    reused_reset_session_ops_per_sec = iterations / reused_reset_session_time.real
    puts "#{reused_reset_session_time.real.round(3)}s (#{Formatter.format_number(reused_reset_session_ops_per_sec.to_i)} ops/sec)"

    session_speedup = reused_reset_session_ops_per_sec / new_context_ops_per_sec
    puts "  → Speedup: #{Formatter.format_ratio(session_speedup)}"

    # Benchmark 4: Reusing contexts with reset(:parameters)
    print "  Reused + reset(:parameters): "
    reused_reset_params_time = Benchmark.measure do
      cctx = VibeZstd::CCtx.new
      dctx = VibeZstd::DCtx.new

      iterations.times do
        compressed = cctx.compress(test_data)
        dctx.decompress(compressed)
        cctx.reset(VibeZstd::ResetDirective::PARAMETERS)
        dctx.reset(VibeZstd::ResetDirective::PARAMETERS)
      end
    end
    reused_reset_params_ops_per_sec = iterations / reused_reset_params_time.real
    puts "#{reused_reset_params_time.real.round(3)}s (#{Formatter.format_number(reused_reset_params_ops_per_sec.to_i)} ops/sec)"

    params_speedup = reused_reset_params_ops_per_sec / new_context_ops_per_sec
    puts "  → Speedup: #{Formatter.format_ratio(params_speedup)}"

    # Benchmark 5: Reusing contexts with reset(:both)
    print "  Reused + reset(:both): "
    reused_reset_both_time = Benchmark.measure do
      cctx = VibeZstd::CCtx.new
      dctx = VibeZstd::DCtx.new

      iterations.times do
        compressed = cctx.compress(test_data)
        dctx.decompress(compressed)
        cctx.reset(VibeZstd::ResetDirective::BOTH)
        dctx.reset(VibeZstd::ResetDirective::BOTH)
      end
    end
    reused_reset_both_ops_per_sec = iterations / reused_reset_both_time.real
    puts "#{reused_reset_both_time.real.round(3)}s (#{Formatter.format_number(reused_reset_both_ops_per_sec.to_i)} ops/sec)"

    both_speedup = reused_reset_both_ops_per_sec / new_context_ops_per_sec
    puts "  → Speedup: #{Formatter.format_ratio(both_speedup)}\n\n"

    # Collect results for this data size
    results << BenchmarkResult.new(
      :name => "#{size_label} - New ctx",
      :iterations_per_sec => new_context_ops_per_sec,
      "Data size" => Formatter.format_bytes(test_data.bytesize),
      "Time (#{iterations})" => "#{new_context_time.real.round(3)}s"
    )

    results << BenchmarkResult.new(
      :name => "#{size_label} - Reused (no reset)",
      :iterations_per_sec => reused_context_ops_per_sec,
      "Data size" => Formatter.format_bytes(test_data.bytesize),
      "Time (#{iterations})" => "#{reused_context_time.real.round(3)}s",
      "Speedup" => "#{speedup.round(2)}x"
    )

    results << BenchmarkResult.new(
      :name => "#{size_label} - Reused + reset(:session)",
      :iterations_per_sec => reused_reset_session_ops_per_sec,
      "Data size" => Formatter.format_bytes(test_data.bytesize),
      "Time (#{iterations})" => "#{reused_reset_session_time.real.round(3)}s",
      "Speedup" => "#{session_speedup.round(2)}x"
    )

    results << BenchmarkResult.new(
      :name => "#{size_label} - Reused + reset(:parameters)",
      :iterations_per_sec => reused_reset_params_ops_per_sec,
      "Data size" => Formatter.format_bytes(test_data.bytesize),
      "Time (#{iterations})" => "#{reused_reset_params_time.real.round(3)}s",
      "Speedup" => "#{params_speedup.round(2)}x"
    )

    results << BenchmarkResult.new(
      :name => "#{size_label} - Reused + reset(:both)",
      :iterations_per_sec => reused_reset_both_ops_per_sec,
      "Data size" => Formatter.format_bytes(test_data.bytesize),
      "Time (#{iterations})" => "#{reused_reset_both_time.real.round(3)}s",
      "Speedup" => "#{both_speedup.round(2)}x"
    )
  end

  # Memory estimates
  cctx_memory = Memory.estimate_cctx(3)
  dctx_memory = Memory.estimate_dctx
  total_context_memory = cctx_memory + dctx_memory

  puts "\n📊 Memory Usage Analysis:"
  puts "  CCtx (level 3): #{Formatter.format_bytes(cctx_memory)}"
  puts "  DCtx: #{Formatter.format_bytes(dctx_memory)}"
  puts "  Total per context pair: #{Formatter.format_bytes(total_context_memory)}"
  puts "\n  For 10,000 operations:"
  puts "    New contexts: #{Formatter.format_bytes(total_context_memory * 10000)} allocated"
  puts "    Reused contexts: #{Formatter.format_bytes(total_context_memory)} allocated"
  puts "    Memory saved: #{Formatter.format_bytes(total_context_memory * 9999)} (#{((9999.0 / 10000) * 100).round(1)}%)"
end

puts "\n💡 Recommendation:"
puts "  Always reuse CCtx/DCtx instances when performing multiple operations."
puts "  This provides #{((1000 * (Memory.estimate_cctx(3) + Memory.estimate_dctx) / 1024.0 / 1024)).round(1)}MB memory savings for 1000 operations!"
