#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "helpers"
require "stringio"
require "tempfile"

# Benchmark: Streaming vs One-Shot Compression
# Compares streaming API vs convenience methods for different use cases

BenchmarkHelpers.run_comparison(title: "Streaming vs One-Shot Compression") do |results|
  # Generate test data
  large_data = DataGenerator.mixed_data(size: 100_000)
  puts "Test data size: #{Formatter.format_bytes(large_data.bytesize)}\n\n"

  # Benchmark 1: One-shot compression (simple, all-in-memory)
  Formatter.section("Testing: One-shot compression")
  oneshot_time = Benchmark.measure do
    10.times do
      compressed = VibeZstd.compress(large_data)
      VibeZstd.decompress(compressed)
    end
  end

  oneshot_ops_per_sec = 10 / oneshot_time.real
  oneshot_compressed = VibeZstd.compress(large_data)
  puts "Completed 10 iterations in #{oneshot_time.real.round(3)}s"
  puts "Compressed size: #{Formatter.format_bytes(oneshot_compressed.bytesize)}"

  # Benchmark 2: Streaming compression (more control, constant memory)
  Formatter.section("Testing: Streaming compression")
  streaming_time = Benchmark.measure do
    10.times do
      # Compress
      compressed_io = StringIO.new
      writer = VibeZstd::Compress::Writer.new(compressed_io, level: 3)

      # Write in chunks
      large_data.scan(/.{1,1000}/m).each { |chunk| writer.write(chunk) }
      writer.finish

      # Decompress
      compressed_io.rewind
      reader = VibeZstd::Decompress::Reader.new(compressed_io)
      decompressed = +""
      while (chunk = reader.read)
        decompressed << chunk
      end
    end
  end

  streaming_ops_per_sec = 10 / streaming_time.real
  puts "Completed 10 iterations in #{streaming_time.real.round(3)}s"

  # Benchmark 3: Streaming with larger chunks (optimization)
  Formatter.section("Testing: Streaming with optimized chunk size")
  optimized_streaming_time = Benchmark.measure do
    10.times do
      # Compress
      compressed_io = StringIO.new
      writer = VibeZstd::Compress::Writer.new(compressed_io, level: 3)

      # Write in larger chunks
      large_data.scan(/.{1,8192}/m).each { |chunk| writer.write(chunk) }
      writer.finish

      # Decompress with optimized chunk size
      compressed_io.rewind
      reader = VibeZstd::Decompress::Reader.new(compressed_io, initial_chunk_size: 8192)
      decompressed = +""
      while (chunk = reader.read)
        decompressed << chunk
      end
    end
  end

  optimized_streaming_ops_per_sec = 10 / optimized_streaming_time.real
  puts "Completed 10 iterations in #{optimized_streaming_time.real.round(3)}s"

  # File-based streaming benchmark
  Formatter.section("Testing: Streaming to file")
  file_streaming_time = Benchmark.measure do
    10.times do
      Tempfile.create(["benchmark", ".zst"]) do |tmpfile|
        # Compress to file
        writer = VibeZstd::Compress::Writer.new(tmpfile, level: 3)
        large_data.scan(/.{1,8192}/m).each { |chunk| writer.write(chunk) }
        writer.finish

        # Decompress from file
        tmpfile.rewind
        reader = VibeZstd::Decompress::Reader.new(tmpfile)
        decompressed = +""
        while (chunk = reader.read)
          decompressed << chunk
        end
      end
    end
  end

  file_streaming_ops_per_sec = 10 / file_streaming_time.real
  puts "Completed 10 iterations in #{file_streaming_time.real.round(3)}s"

  # Memory estimates (one-shot needs to buffer everything)
  cctx_memory = Memory.estimate_cctx(3)
  dctx_memory = Memory.estimate_dctx
  oneshot_memory = cctx_memory + dctx_memory + large_data.bytesize + oneshot_compressed.bytesize
  streaming_memory = cctx_memory + dctx_memory + 8192 # Only chunk size in memory

  # Collect results
  results << BenchmarkResult.new(
    :name => "One-shot",
    :iterations_per_sec => oneshot_ops_per_sec,
    :memory_bytes => oneshot_memory,
    "Use case" => "Small data, simplicity"
  )

  results << BenchmarkResult.new(
    :name => "Streaming (1KB chunks)",
    :iterations_per_sec => streaming_ops_per_sec,
    :memory_bytes => streaming_memory,
    "Use case" => "Large files, low memory"
  )

  results << BenchmarkResult.new(
    :name => "Streaming (8KB chunks)",
    :iterations_per_sec => optimized_streaming_ops_per_sec,
    :memory_bytes => streaming_memory,
    "Use case" => "Balanced performance"
  )

  results << BenchmarkResult.new(
    :name => "File streaming",
    :iterations_per_sec => file_streaming_ops_per_sec,
    :memory_bytes => streaming_memory,
    "Use case" => "Large files, disk I/O"
  )

  puts "\n💾 Memory Comparison:"
  puts "  One-shot: #{Formatter.format_bytes(oneshot_memory)} (entire data in memory)"
  puts "  Streaming: #{Formatter.format_bytes(streaming_memory)} (only chunks in memory)"
  puts "  Memory savings: #{Formatter.format_bytes(oneshot_memory - streaming_memory)} (#{((oneshot_memory - streaming_memory).to_f / oneshot_memory * 100).round(1)}%)"
end

puts "\n💡 When to use each approach:"
puts "  One-shot compression (VibeZstd.compress):"
puts "    ✓ Small data (< 1MB)"
puts "    ✓ Data already in memory"
puts "    ✓ Simplicity is priority"
puts "\n  Streaming compression (Writer/Reader):"
puts "    ✓ Large files (> 1MB)"
puts "    ✓ Memory-constrained environments"
puts "    ✓ Incremental data (network streams, logs)"
puts "    ✓ Need to process data on-the-fly"
