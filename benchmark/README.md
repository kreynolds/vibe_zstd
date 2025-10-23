# VibeZstd Benchmarks

Comprehensive benchmark suite for vibe_zstd, demonstrating performance characteristics and best practices.

## Prerequisites

Install benchmark dependencies:

```bash
bundle install
```

Generate the test dictionary fixture (one-time setup):

```bash
ruby benchmark/generate_fixture.rb
```

## Running Benchmarks

### Run all benchmarks

```bash
ruby benchmark/run_all.rb
```

### Run specific benchmarks

```bash
# List available benchmarks
ruby benchmark/run_all.rb --list

# Run specific benchmark
ruby benchmark/run_all.rb --benchmark "context reuse"
ruby benchmark/run_all.rb --benchmark "dictionary"

# Run multiple benchmarks
ruby benchmark/run_all.rb --benchmark "context" --benchmark "streaming"
```

### Run individual benchmarks

```bash
ruby benchmark/context_reuse.rb
ruby benchmark/dictionary_usage.rb
ruby benchmark/compression_levels.rb
ruby benchmark/streaming.rb
ruby benchmark/multithreading.rb
ruby benchmark/dictionary_training.rb
```

## Benchmark Descriptions

### 1. Context Reuse (`context_reuse.rb`)

**What it tests:** Performance difference between reusing compression/decompression contexts vs creating new ones for each operation.

**Key findings:**
- Reusing contexts is **3-5x faster** than creating new ones
- Saves **significant memory** (avoiding repeated allocations)
- Always reuse contexts when performing multiple operations

**When to reuse:**
- ✓ Processing multiple files in a loop
- ✓ Compressing/decompressing multiple messages
- ✓ Any scenario with > 1 operation

### 2. Dictionary Usage (`dictionary_usage.rb`)

**What it tests:** Compression ratio and speed improvements when using trained dictionaries.

**Key findings:**
- Dictionaries provide **40-70% better compression** for small, similar data
- Especially effective for JSON, logs, and repeated patterns
- Small memory overhead for dictionary storage

**When to use dictionaries:**
- ✓ Small messages (< 10KB each) with similar structure
- ✓ JSON API responses
- ✓ Log messages
- ✓ When compression ratio matters more than speed
- ✗ Large files (> 1MB each)
- ✗ Highly variable data

### 3. Compression Levels (`compression_levels.rb`)

**What it tests:** Trade-off between compression speed and compression ratio across different levels.

**Key findings:**
- **Level -1:** Ultra-fast, 3-5x faster than level 1
- **Level 1-3:** Fast compression, good for high-throughput
- **Level 3 (default):** Best balance of speed/ratio
- **Level 9-15:** Better compression, slower speed
- **Level 16-22:** Maximum compression, very slow, high memory

**Recommendations:**
- Real-time compression: Level -1 to 1
- General use: Level 3 (default)
- Archival: Level 9-15
- Maximum compression: Level 19-22

### 4. Streaming (`streaming.rb`)

**What it tests:** Streaming API vs one-shot compression for different use cases.

**Key findings:**
- One-shot is **simpler** but requires all data in memory
- Streaming provides **constant memory usage** regardless of file size
- Streaming is essential for **large files** (> 1MB)
- Chunk size affects performance (8KB chunks perform well)

**When to use streaming:**
- ✓ Large files (> 1MB)
- ✓ Memory-constrained environments
- ✓ Network streams, incremental data
- ✓ Processing data on-the-fly

**When to use one-shot:**
- ✓ Small data (< 1MB)
- ✓ Data already in memory
- ✓ Simplicity is priority

### 5. Multi-threading (`multithreading.rb`)

**What it tests:** Performance impact of using multiple worker threads for compression.

**Key findings:**
- Multi-threading benefits vary significantly based on file size, data characteristics, and compression settings
- Smaller files (< few MB) typically don't benefit due to overhead
- Performance improvements depend heavily on data compressibility
- More workers = higher memory usage
- Optimal thread count is typically 2-4 workers

**When to use:**
- ✓ Large files where compression is a bottleneck
- ✓ When you've benchmarked your specific use case and confirmed benefits
- ✓ Higher compression levels (where compression work is more substantial)
- ✗ Small files (generally < few MB)
- ✗ Without benchmarking your specific workload
- ✗ When memory usage is a concern

**Recommendation:** Always benchmark with your actual data. Multi-threading overhead can outweigh benefits for many workloads. See the [official zstd documentation](https://facebook.github.io/zstd/zstd_manual.html) for detailed guidance.

### 6. Dictionary Training (`dictionary_training.rb`)

**What it tests:** Comparison of dictionary training algorithms and dictionary sizes.

**Key findings:**
- **train_dict:** Fastest training, good quality
- **train_dict_cover:** Best compression ratios, slower (2-10x)
- **train_dict_fast_cover:** Balanced speed/quality
- Larger dictionaries = better compression (diminishing returns > 64KB)

**Recommendations:**
- Quick iteration: `train_dict`
- Production dictionaries: `train_dict_cover`
- Balanced: `train_dict_fast_cover` with `accel: 5`
- Dictionary size: 16KB-64KB for small messages

## Benchmark Results

Run the benchmarks on your system to see platform-specific results. The benchmarks will generate markdown-formatted tables that you can include in documentation.

## Adding New Benchmarks

1. Create a new file in `benchmark/` (e.g., `my_benchmark.rb`)
2. Use the helper utilities from `helpers.rb`:
   - `BenchmarkHelpers.run_comparison` - Main benchmark runner
   - `DataGenerator.*` - Generate test data
   - `Formatter.*` - Format output
   - `Memory.*` - Memory estimation
3. Add your benchmark to `run_all.rb`

Example:

```ruby
#!/usr/bin/env ruby
require_relative "helpers"
include BenchmarkHelpers

BenchmarkHelpers.run_comparison(title: "My Benchmark") do |results|
  # Your benchmark code here
  results << BenchmarkResult.new(
    name: "Test case",
    iterations_per_sec: 1000,
    memory_bytes: 1024
  )
end
```

## Contributing

Benchmark improvements and additions are welcome! Please ensure:
- Use realistic test data
- Include memory measurements
- Provide clear recommendations
- Format output for README inclusion
