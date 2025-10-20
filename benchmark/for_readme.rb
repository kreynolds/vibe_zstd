#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick benchmark script to generate results for README

require_relative "helpers"
include BenchmarkHelpers

puts "# Performance Benchmarks\n\n"
puts "Results from Ruby #{RUBY_VERSION} on #{RUBY_PLATFORM}, Zstd #{VibeZstd.version_string}\n\n"

# 1. Context Reuse
puts "## Context Reuse Performance\n\n"
puts "Reusing compression/decompression contexts vs creating new ones (5000 iterations each):\n\n"

# Test with different data sizes
test_cases = {
  "1KB" => DataGenerator.json_data(count: 5),
  "10KB" => DataGenerator.json_data(count: 50),
  "100KB" => DataGenerator.json_data(count: 500)
}

puts "| Data Size | New Context | Reused Context | Speedup |"
puts "|-----------|-------------|----------------|---------|"

test_cases.each do |size_label, test_data|
  iterations = 5000

  new_ctx_time = Benchmark.measure do
    iterations.times do
      cctx = VibeZstd::CCtx.new
      dctx = VibeZstd::DCtx.new
      compressed = cctx.compress(test_data)
      dctx.decompress(compressed)
    end
  end

  reused_time = Benchmark.measure do
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new
    iterations.times do
      compressed = cctx.compress(test_data)
      dctx.decompress(compressed)
    end
  end

  new_ops = iterations / new_ctx_time.real
  reused_ops = iterations / reused_time.real
  speedup = reused_ops / new_ops

  puts "| #{size_label} | #{Formatter.format_number(new_ops.to_i)} ops/s | #{Formatter.format_number(reused_ops.to_i)} ops/s | #{speedup.round(2)}x |"
end

cctx_mem = Memory.estimate_cctx(3)
dctx_mem = Memory.estimate_dctx
total_mem = cctx_mem + dctx_mem

puts "\n**Memory savings:** Reusing contexts saves #{Formatter.format_bytes(total_mem * 4999)} for 5000 operations (99.98% reduction)\n"
puts "**Recommendation:** Always reuse CCtx/DCtx instances for multiple operations.\n\n"

# 2. Dictionary Performance
puts "## Dictionary Compression\n\n"
puts "Compression with vs without trained dictionaries (100 JSON samples):\n\n"

dict_path = File.join(__dir__, "..", "test", "fixtures", "sample.dict")
dict_data = File.binread(dict_path)
cdict = VibeZstd::CDict.new(dict_data)
ddict = VibeZstd::DDict.new(dict_data)

test_sample = {
  id: 999,
  name: "Test User",
  email: "test@example.com",
  status: "active",
  preferences: { theme: "dark", notifications: true }
}.to_json

compressed_no_dict = VibeZstd.compress(test_sample)
compressed_with_dict = VibeZstd.compress(test_sample, dict: cdict)

ratio_no_dict = test_sample.bytesize.to_f / compressed_no_dict.bytesize
ratio_with_dict = test_sample.bytesize.to_f / compressed_with_dict.bytesize

puts "| Method | Compressed Size | Ratio | Improvement |"
puts "|--------|----------------|-------|-------------|"
puts "| Without dictionary | #{compressed_no_dict.bytesize}B | #{ratio_no_dict.round(2)}x | - |"
puts "| With dictionary (16KB) | #{compressed_with_dict.bytesize}B | #{ratio_with_dict.round(2)}x | #{((compressed_no_dict.bytesize - compressed_with_dict.bytesize).to_f / compressed_no_dict.bytesize * 100).round(1)}% smaller |"
puts "\nOriginal size: #{test_sample.bytesize} bytes\n\n"

# 3. Compression Levels
puts "## Compression Levels\n\n"
puts "Speed vs compression ratio trade-offs:\n\n"

large_data = DataGenerator.mixed_data(size: 50_000)
levels = [-1, 1, 3, 9, 19]

puts "| Level | Ratio | Speed (ops/sec) | Memory | Use Case |"
puts "|-------|-------|-----------------|--------|----------|"

levels.each do |level|
  cctx = VibeZstd::CCtx.new

  compressed = nil
  time = Benchmark.measure do
    10.times { compressed = cctx.compress(large_data, level: level) }
  end

  ops_per_sec = 10 / time.real
  ratio = large_data.bytesize.to_f / compressed.bytesize
  memory = Memory.estimate_cctx(level)

  use_case = case level
  when -1 then "Ultra-fast, real-time"
  when 1 then "Fast, high-throughput"
  when 3 then "Balanced (default)"
  when 9 then "Better compression"
  when 19 then "Maximum compression"
  end

  puts "| #{level} | #{ratio.round(2)}x | #{Formatter.format_number(ops_per_sec.to_i)} | #{Formatter.format_bytes(memory)} | #{use_case} |"
end

puts "\n"

# 4. Multi-threading
puts "## Multi-threading Performance\n\n"
puts "Compression speedup with multiple workers (500KB data):\n\n"

mt_data = DataGenerator.mixed_data(size: 500_000)

puts "| Workers | Throughput | Speedup | Efficiency |"
puts "|---------|------------|---------|------------|"

baseline_throughput = nil

[0, 2, 4].each do |workers|
  cctx = VibeZstd::CCtx.new
  cctx.nb_workers = workers if workers > 0

  cctx.compress(mt_data) # warmup

  time = Benchmark.measure do
    5.times { cctx.compress(mt_data) }
  end

  throughput = (mt_data.bytesize * 5 / time.real)

  if workers == 0
    baseline_throughput = throughput
    puts "| #{workers} (single) | #{Formatter.format_bytes(throughput.to_i)}/s | 1.0x | 100% |"
  else
    speedup = throughput / baseline_throughput
    efficiency = (speedup / workers * 100).round(0)
    puts "| #{workers} | #{Formatter.format_bytes(throughput.to_i)}/s | #{speedup.round(2)}x | #{efficiency}% |"
  end
end

puts "\n**Note:** Multi-threading is most effective for data > 256KB. Diminishing returns after 4 workers.\n"
