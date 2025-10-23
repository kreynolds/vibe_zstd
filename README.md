# VibeZstd

Fast, high-ratio compression for Ruby using the Zstandard (Zstd) library. VibeZstd provides a native Ruby C extension with an idiomatic API for compressing and decompressing data.

## Quick Start

```ruby
require 'vibe_zstd'

# One-line compression/decompression
compressed = VibeZstd.compress("Hello, world!")
original = VibeZstd.decompress(compressed)

# With custom compression level (1-22, or negative for ultra-fast)
compressed = VibeZstd.compress(data, level: 9)

# Reusable contexts (recommended for multiple operations - 2.2x faster!)
cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

# Reuse the same contexts for multiple operations
files.each do |file_data|
  compressed = cctx.compress(file_data)
  decompressed = dctx.decompress(compressed)
  # ... process data
end
```

## Installation

Add to your Gemfile:

```ruby
gem 'vibe_zstd'
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install vibe_zstd
```

## Performance & Best Practices

VibeZstd leverages Zstandard's excellent compression performance:

- **Compression ratios** comparable to or better than gzip/bzip2 at similar speeds
- **Extremely fast decompression**
- **Compression levels** from -7 (ultra-fast) to 22 (maximum compression)

### Context Reuse (Important!)

**Always reuse contexts for multiple operations** - it's 2-3x faster:

| Data Size | New Context | Reused Context | Speedup |
|-----------|-------------|----------------|---------|
| 1KB | 72,610 ops/s | 159,454 ops/s | **2.2x** |
| 10KB | 34,941 ops/s | 61,171 ops/s | **1.75x** |
| 100KB | 7,675 ops/s | 9,491 ops/s | **1.24x** |

```ruby
# ❌ Don't do this (creates new context each time)
1000.times do
  compressed = VibeZstd.compress(data)
end

# ✅ Do this instead (reuse context)
cctx = VibeZstd::CCtx.new
1000.times do
  compressed = cctx.compress(data)
end
```

**Memory savings:** Reusing contexts saves ~6.7GB for 5000 operations:
- Creating new contexts: 5000 × 1.34MB = 6.70GB
- Reusing contexts: 1 × 1.34MB = 1.34MB
- **Savings: 6.69GB (99.98% reduction)**

*Note: 1.34MB = CCtx memory (~1.24MB at level 3) + DCtx memory (~128KB)*

### Compression Level Trade-offs

Choose the right level for your use case:

| Level | Ratio | Speed (ops/sec) | Memory | Use Case |
|-------|-------|-----------------|--------|----------|
| -1 | 6.03x | 11,507 | 537KB | Ultra-fast, real-time |
| 1 | 8.2x | 10,752 | 569KB | Fast, high-throughput |
| 3 | 7.93x | 9,191 | 1.24MB | **Balanced (default)** |
| 9 | 9.17x | 987 | 12.49MB | Better compression |
| 19 | 10.3x | 35 | 81.25MB | Maximum compression |

```ruby
cctx = VibeZstd::CCtx.new

# Ultra-fast for real-time processing
compressed = cctx.compress(data, level: -1)

# Maximum compression for archival
compressed = cctx.compress(data, level: 19)
```

### Dictionary Compression

For small, similar data (JSON, logs, API responses), dictionaries provide dramatic improvements:

| Method | Compressed Size | Ratio | Improvement |
|--------|----------------|-------|-------------|
| Without dictionary | 110B | 1.15x | - |
| With dictionary (16KB) | 54B | 2.33x | **50.9% smaller** |

See the [Dictionaries](#dictionaries) section below for usage examples.

## Basic Usage

### Simple Compression

```ruby
require 'vibe_zstd'

data = "Hello, world! This is a test string."

# One-off compression (creates context internally)
compressed = VibeZstd.compress(data)
decompressed = VibeZstd.decompress(compressed)

# With custom level
compressed = VibeZstd.compress(data, level: 5)
```

### Using Contexts (Recommended)

For multiple operations, create reusable contexts:

```ruby
# Create contexts once
cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

# Reuse for multiple operations
files.each do |file|
  data = File.read(file)
  compressed = cctx.compress(data)
  File.write("#{file}.zst", compressed)
end
```

### Compression Levels

```ruby
cctx = VibeZstd::CCtx.new

# Fast compression (level 1)
compressed = cctx.compress(data, level: 1)

# Default level (3)
compressed = cctx.compress(data)

# High compression (level 9)
compressed = cctx.compress(data, level: 9)

# Negative levels for ultra-fast compression
compressed = cctx.compress(data, level: -1)
```

### Frame Information

```ruby
# Check decompressed size before decompressing
size = VibeZstd.frame_content_size(compressed_data)
puts "Will decompress to #{size} bytes" if size

# Get compression bound (maximum compressed size)
max_size = VibeZstd.compress_bound(data.bytesize)
```

## Advanced Features

### Dictionaries

Dictionaries dramatically improve compression for small, similar data by pre-training on representative samples.

#### Training a Dictionary

```ruby
# Collect representative samples
samples = [
  {id: 1, name: "Alice", email: "alice@example.com"}.to_json,
  {id: 2, name: "Bob", email: "bob@example.com"}.to_json,
  {id: 3, name: "Charlie", email: "charlie@example.com"}.to_json
  # ... more samples
]

# Train dictionary with default algorithm (fast, good for most use cases)
dict_data = VibeZstd.train_dict(samples)

# Or specify custom size
dict_data = VibeZstd.train_dict(samples, max_dict_size: 16_384)

# Advanced: Use COVER algorithm for better dictionaries
# k: segment size (typical: 16-2048+)
# d: dmer size (typical: 6-16, must be ≤ k)
dict_data = VibeZstd.train_dict_cover(
  samples,
  max_dict_size: 16_384,
  k: 200,  # Segment size
  d: 6     # Dmer size
)

# Advanced: Fast COVER for quick training
dict_data = VibeZstd.train_dict_fast_cover(
  samples,
  max_dict_size: 16_384,
  k: 200,
  d: 6,
  accel: 1  # Higher = faster but less accurate (1-10)
)
```

#### Using Dictionaries

```ruby
# Create dictionary objects
dict_data = File.binread('my.dict')
cdict = VibeZstd::CDict.new(dict_data)
ddict = VibeZstd::DDict.new(dict_data)

# Use with contexts
cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

compressed = cctx.compress(data, dict: cdict)
decompressed = dctx.decompress(compressed, dict: ddict)

# Or use convenience methods
compressed = VibeZstd.compress(data, dict: cdict)
decompressed = VibeZstd.decompress(compressed, dict: ddict)

# Check dictionary properties
puts "Dictionary size: #{cdict.size} bytes"
puts "Dictionary ID: #{cdict.dict_id}"

# Get dictionary ID from compressed data
dict_id = VibeZstd.get_dict_id_from_frame(compressed)
```

#### Prefix Dictionaries (Lightweight Alternative)

For cases where training isn't practical:

```ruby
cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

# Use a common prefix (same for compression and decompression)
prefix = "Common data prefix that appears frequently"

compressed = cctx.use_prefix(prefix).compress(data)
decompressed = dctx.use_prefix(prefix).decompress(compressed)
```

### Streaming API

Process large files with constant memory usage.

#### Streaming Compression

```ruby
# Compress to file
File.open('output.zst', 'wb') do |file|
  writer = VibeZstd::CompressWriter.new(file, level: 5)

  writer.write("chunk 1")
  writer.write("chunk 2")
  writer.flush  # Optional: force output
  writer.finish # Required: finalize frame
end

# Or use block form (auto-finishes)
VibeZstd::CompressWriter.open(file, level: 5) do |writer|
  large_data.each_slice(65536) do |chunk|
    writer.write(chunk)
  end
end

# With dictionary
cdict = VibeZstd::CDict.new(dict_data)
writer = VibeZstd::CompressWriter.new(file, level: 5, dict: cdict)
```

#### Streaming Decompression

```ruby
# Decompress file in chunks (memory-safe for large files)
File.open('input.zst', 'rb') do |file|
  reader = VibeZstd::DecompressReader.new(file)

  # Read in ~128KB chunks by default
  while chunk = reader.read
    process(chunk)
  end
end

# Custom chunk sizes
reader = VibeZstd::DecompressReader.new(file, initial_chunk_size: 1_048_576)
while chunk = reader.read  # Returns up to 1MB per call
  process(chunk)
end

# Or specify per-read
while chunk = reader.read(65536)  # Read 64KB chunks
  process(chunk)
end

# Block form
VibeZstd::DecompressReader.open(file) do |reader|
  reader.each do |chunk|
    process(chunk)
  end
end

# HTTP streaming example
require 'net/http'
uri = URI('https://example.com/large_file.zst')
File.open('output.txt', 'wb') do |output|
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request_get(uri.path) do |response|
      reader = VibeZstd::DecompressReader.new(response.body)
      reader.each { |chunk| output.write(chunk) }
    end
  end
end
```

**Chunk size recommendations:**
- **Small data (< 10KB)**: `initial_chunk_size: 4096` to avoid over-allocation
- **Medium data (10KB-1MB)**: Default (~128KB) for balanced performance
- **Large data (> 1MB)**: `initial_chunk_size: 1_048_576` to reduce overhead
- **Memory-constrained**: Use smaller chunks (4-8KB)
- **High throughput**: Use larger chunks (1-10MB)

#### Line-by-Line Processing

`DecompressReader` provides IO-like methods for processing compressed text files line by line:

```ruby
# Process compressed log file line by line
File.open('app.log.zst', 'rb') do |file|
  reader = VibeZstd::DecompressReader.new(file)

  # Read lines one at a time
  while line = reader.gets
    # Process each log entry
    if line.include?('ERROR')
      alert_on_call(line)
    end
  end
end

# Or use each_line for cleaner iteration
VibeZstd::DecompressReader.open(file) do |reader|
  reader.each_line do |line|
    process_log_entry(line)
  end
end

# Read specific number of bytes
reader.readpartial(4096)  # Raises EOFError at end of stream

# Check for end of stream
reader.eof?  # => true/false
```

**Use cases:**
- **Log processing** - Parse compressed log files without decompressing the entire file
- **CSV/TSV parsing** - Read compressed data files line by line for memory-efficient ETL
- **Configuration files** - Load compressed config files with minimal memory footprint

### Multi-threaded Compression

Enable parallel compression for large data:

```ruby
cctx = VibeZstd::CCtx.new

# Enable 4 worker threads
cctx.workers = 4

# Or set during initialization
cctx = VibeZstd::CCtx.new(workers: 4)

large_data = File.read('big_file.txt')
compressed = cctx.compress(large_data)
```

**Multi-threading performance** (500KB data):

| Workers | Throughput | Speedup | Efficiency |
|---------|------------|---------|------------|
| 0 (single) | 795MB/s | 1.0x | 100% |
| 2 | 784MB/s | 0.99x | 49% |
| 4 | 748MB/s | 0.94x | 24% |

**Note:** Multi-threading works best for data > 1MB. Overhead may outweigh benefits for smaller payloads.

#### Multi-threading Tuning

```ruby
cctx = VibeZstd::CCtx.new(workers: 4)

# Tune job size (default: auto)
# Larger = better ratio but higher latency
cctx.job_size = 1_048_576  # 1MB per job

# Tune overlap (0-9)
# Higher = better ratio but slower
cctx.overlap_log = 6  # Default: auto (usually 6-9)
```

### Compression Parameters

Fine-tune compression behavior using property setters:

```ruby
# Set during initialization (recommended)
cctx = VibeZstd::CCtx.new(
  checksum_flag: 1,        # Add checksum for integrity
  content_size_flag: 1,    # Include size in frame header
  window_log: 20,          # 1MB window (2^20)
  workers: 4            # 4 threads
)

# Or set after creation
cctx = VibeZstd::CCtx.new
cctx.checksum_flag = 1
cctx.content_size_flag = 1
cctx.workers = 4

data = "Your data here"
compressed = cctx.compress(data)
```

#### Common Parameters

**Frame parameters:**
```ruby
cctx.checksum_flag = 1      # Enable 32-bit checksum
cctx.content_size_flag = 1  # Include decompressed size
cctx.dict_id_flag = 1       # Include dictionary ID
```

**Compression tuning:**
```ruby
cctx.compression_level = 9  # Same as level: argument
cctx.window_log = 20        # Window size (2^20 = 1MB)
```

**Long Distance Matching (for large files with repeated patterns):**
```ruby
cctx.enable_long_distance_matching = 1
cctx.ldm_hash_log = 20
cctx.ldm_min_match = 64
```

**Multi-threading:**
```ruby
cctx.workers = 4         # Number of threads
cctx.job_size = 1_048_576   # Size per job
cctx.overlap_log = 6        # Overlap between jobs
```

#### Query Parameter Bounds

```ruby
# Get valid range for a parameter
bounds = VibeZstd::CCtx.parameter_bounds(:compression_level)
puts "Level range: #{bounds[:min]} to #{bounds[:max]}"
# => Level range: -131072 to 22
# Note: Practical range is -7 to 22; -131072 is a technical limit, not a usable level

# Validate before setting
level = user_input.to_i
bounds = VibeZstd::CCtx.parameter_bounds(:compression_level)
if level >= bounds[:min] && level <= bounds[:max]
  cctx.compression_level = level
else
  raise "Invalid level"
end
```

#### Get Current Parameter Values

```ruby
cctx = VibeZstd::CCtx.new(compression_level: 9)

# Read current values
puts cctx.compression_level  # => 9
puts cctx.checksum_flag      # => 0
```

### Decompression Parameters

Control decompression behavior to prevent memory exhaustion:

```ruby
dctx = VibeZstd::DCtx.new

# Limit maximum window size (prevents memory attacks)
dctx.window_log_max = 20  # Max 1MB window (2^20)

# Or set during initialization
dctx = VibeZstd::DCtx.new(window_log_max: 20)

compressed = File.read('data.zst')
decompressed = dctx.decompress(compressed)
```

#### Optimize for Unknown-Size Frames

When decompressing frames without known content size:

```ruby
# Set globally for all new DCtx instances
VibeZstd::DCtx.default_initial_capacity = 1_048_576  # 1MB for large data

# Set per instance
dctx = VibeZstd::DCtx.new(initial_capacity: 512_000)

# Or per call (overrides instance setting)
dctx.decompress(compressed, initial_capacity: 16_384)

# Reset to default (~128KB)
VibeZstd::DCtx.default_initial_capacity = nil
```

**When to configure:**
- **Small data (< 10KB)**: Set to `4096-8192`
- **Large data (> 1MB)**: Set to `1_048_576` or higher
- **Known-size frames**: Not applicable (size read from frame header)

### Memory Estimation

Estimate memory usage before creating contexts:

```ruby
# Compression context memory at level 5
cctx_bytes = VibeZstd::CCtx.estimate_memory(5)
puts "CCtx will use ~#{cctx_bytes} bytes"

# Decompression context
dctx_bytes = VibeZstd::DCtx.estimate_memory
puts "DCtx will use ~#{dctx_bytes} bytes"

# Dictionary memory
dict_size = 16_384
cdict_bytes = VibeZstd::CDict.estimate_memory(dict_size, 5)
ddict_bytes = VibeZstd::DDict.estimate_memory(dict_size)
puts "CDict: #{cdict_bytes} bytes, DDict: #{ddict_bytes} bytes"
```

## Integration Examples

Real-world examples demonstrating VibeZstd in production scenarios.

### Rails Encrypted Columns with Thread-Local Contexts

Use VibeZstd with ActiveRecord::Encryption for high-performance compression of encrypted attributes.

#### Rails 7.1+ (Global Compressor Configuration)

```ruby
# config/initializers/vibe_zstd_encryption.rb
module VibeZstdCompressor
  # Compress using thread-local contexts (2-3x faster in multi-threaded environments)
  def self.deflate(data)
    VibeZstd::ThreadLocal.compress(data, level: 3)
  end

  def self.inflate(data)
    VibeZstd::ThreadLocal.decompress(data)
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Encryption.config.support_unencrypted_data = true
  ActiveRecord::Encryption.config.compressor = VibeZstdCompressor
end

# In your model - all encrypted attributes use VibeZstd
class User < ApplicationRecord
  encrypts :preferences
  encrypts :metadata
end
```

#### Rails 8.0+ (Per-Attribute Compressor)

Rails 8 introduces per-attribute `compressor:` option for fine-grained control:

```ruby
# config/initializers/vibe_zstd_encryption.rb
module VibeZstdCompressor
  def self.deflate(data)
    VibeZstd::ThreadLocal.compress(data, level: 3)
  end

  def self.inflate(data)
    VibeZstd::ThreadLocal.decompress(data)
  end
end

# In your model - specify compressor per attribute
class User < ApplicationRecord
  # Use VibeZstd for large JSON columns
  encrypts :preferences, compressor: VibeZstdCompressor
  encrypts :settings, compressor: VibeZstdCompressor

  # Use default Zlib for small text fields
  encrypts :api_key
end
```

#### Rails 8.0+ with Per-Attribute Dictionaries

Rails 8's per-attribute compressor enables custom dictionaries for individual fields—maximum compression for structured data:

```ruby
# config/initializers/vibe_zstd_encryption.rb

# Compressor for user preferences with custom dictionary
module UserPrefsCompressor
  DICT = VibeZstd::CDict.new(
    File.binread('config/dictionaries/user_preferences.dict')
  )

  def self.deflate(data)
    VibeZstd::ThreadLocal.compress(data, dict: DICT, level: 5)
  end

  def self.inflate(data)
    VibeZstd::ThreadLocal.decompress(data, dict: DICT.to_ddict)
  end
end

# Compressor for audit logs with different dictionary
module AuditLogCompressor
  DICT = VibeZstd::CDict.new(
    File.binread('config/dictionaries/audit_logs.dict')
  )

  def self.deflate(data)
    VibeZstd::ThreadLocal.compress(data, dict: DICT, level: 3)
  end

  def self.inflate(data)
    VibeZstd::ThreadLocal.decompress(data, dict: DICT.to_ddict)
  end
end

# In your models - each attribute gets optimized dictionary
class User < ApplicationRecord
  encrypts :preferences, compressor: UserPrefsCompressor    # 50%+ smaller with custom dict
  encrypts :settings, compressor: VibeZstdCompressor        # Standard VibeZstd (no dict)
  encrypts :api_key                                         # Default Zlib for small data
end

class AuditEvent < ApplicationRecord
  encrypts :event_data, compressor: AuditLogCompressor      # Custom dict for audit logs
end
```

**Why per-attribute dictionaries?**
- **50-70% size reduction** for small, similar data (JSON user preferences, API responses, logs)
- **Different dictionaries** trained on different data patterns (user prefs vs audit logs)
- **ThreadLocal pooling** keeps one context per dictionary per thread—minimal memory overhead

**Why ThreadLocal?** In Puma/multi-threaded Rails apps, `ThreadLocal` reuses contexts per thread (saves ~1.3MB per operation × requests). Each Puma worker thread maintains one CCtx and one DCtx, reducing memory and improving throughput.

**Rails 8 Advantage:** Per-attribute compressors let you optimize each field—use VibeZstd for large structured data (JSON, serialized objects) and default Zlib for small strings.

### Dictionary Training for Encrypted Columns

For small, structured data (JSON, serialized objects), dictionaries can reduce size by 50%+:

```ruby
# Step 1: Train dictionary from representative samples (one-time setup)
samples = User.limit(1000).pluck(:preferences).compact
dict_data = VibeZstd.train_dict(samples, max_dict_size: 16_384)
File.write('config/user_prefs.dict', dict_data)

# Step 2: Load dictionary at boot (config/initializers/vibe_zstd_encryption.rb)
module UserPrefsCompressor
  DICT = VibeZstd::CDict.new(File.binread('config/user_prefs.dict'))

  def self.deflate(data)
    VibeZstd::ThreadLocal.compress(data, dict: DICT)
  end

  def self.inflate(data)
    VibeZstd::ThreadLocal.decompress(data, dict: DICT.to_ddict)
  end
end

# Step 3: Configure in your model
# Rails 7.1+: Set as global compressor
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Encryption.config.compressor = UserPrefsCompressor
end

# Rails 8.0+: Set per-attribute
class User < ApplicationRecord
  encrypts :preferences, compressor: UserPrefsCompressor
end
```

**Dictionary guidelines:**
- **Samples:** 100+ representative samples, similar to production data
- **Algorithm:** `train_dict` (fast, good) or `train_dict_cover` (slower, better compression)
- **Size:** 16-64KB typical; larger doesn't always improve compression
- **Best for:** Small (< 10KB), similar data (JSON, logs, structured text)
- **Avoid for:** Large files, binary data, highly variable content

### Stream Decompressing a Remote File

Memory-efficient decompression of large remote `.zst` files:

```ruby
require 'net/http'
require 'vibe_zstd'

uri = URI('https://example.com/large_dataset.zst')
File.open('dataset.csv', 'wb') do |output|
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request_get(uri.path) do |response|
      reader = VibeZstd::DecompressReader.new(response.body)
      reader.each { |chunk| output.write(chunk) }
    end
  end
end
```

**Constant memory:** Processes files of any size with ~128KB RAM (configurable via `initial_chunk_size`).

### Stream Compressing Large Files

Compress large files without loading into memory:

```ruby
# Compress 10GB file in chunks
File.open('large_data.txt', 'rb') do |input|
  VibeZstd::CompressWriter.open('large_data.txt.zst', level: 5) do |writer|
    while chunk = input.read(1_048_576)  # 1MB chunks
      writer.write(chunk)
    end
  end
end
```

**When to stream:**
- Files > 100MB (avoids loading entire file into memory)
- Network streams, pipes, or IO objects
- Progressive compression (write data as it's generated)

### Skippable Frame Metadata

Add metadata (version, timestamp, checksums) without affecting decompression:

```ruby
# Write file with metadata
metadata = {version: "2.0", created_at: Time.now.to_i, schema: "users_v2"}.to_json
File.open('data.zst', 'wb') do |f|
  f.write VibeZstd.write_skippable_frame(metadata, magic_number: 0)
  f.write VibeZstd.compress(actual_data)
end

# Read decompresses normally (skips metadata automatically)
data = VibeZstd.decompress(File.binread('data.zst'))

# Extract metadata without decompressing payload
File.open('data.zst', 'rb') do |f|
  VibeZstd.each_skippable_frame(f.read) do |content, magic, offset|
    metadata = JSON.parse(content)
    puts "File version: #{metadata['version']}"
  end
end
```

**Use cases:**
- **Versioning:** Track data schema versions for migrations
- **Provenance:** Store creation timestamp, user, source system
- **Integrity:** Add checksums or signatures before compression
- **Archives:** Multi-file archives with per-file metadata (see test_skippable_frame_archive_pattern in tests)

**Note:** Skippable frames add 8 bytes + metadata size. For small files, consider alternatives (separate metadata file, database columns).

## API Reference

### Module Methods

```ruby
VibeZstd.compress(data, level: nil, dict: nil)
VibeZstd.decompress(data, dict: nil)
VibeZstd.frame_content_size(data)
VibeZstd.compress_bound(size)
VibeZstd.train_dict(samples, max_dict_size: 112640)
VibeZstd.train_dict_cover(samples, max_dict_size:, k:, d:, **opts)
VibeZstd.train_dict_fast_cover(samples, max_dict_size:, k:, d:, **opts)
VibeZstd.get_dict_id(dict_data)
VibeZstd.get_dict_id_from_frame(data)
VibeZstd.version_number  # e.g., 10507
VibeZstd.version_string  # e.g., "1.5.7"
VibeZstd.min_level       # Minimum compression level
VibeZstd.max_level       # Maximum compression level
VibeZstd.default_level   # Default compression level
```

### CCtx (Compression Context)

```ruby
cctx = VibeZstd::CCtx.new(**params)
cctx.compress(data, level: nil, dict: nil, pledged_size: nil)
cctx.use_prefix(prefix_data)

# Property setters (see parameters section)
cctx.checksum_flag = 1
cctx.content_size_flag = 1
cctx.compression_level = 9
cctx.window_log = 20
cctx.workers = 4
# ... and many more

# Class methods
VibeZstd::CCtx.parameter_bounds(param)
VibeZstd::CCtx.estimate_memory(level)
```

### DCtx (Decompression Context)

```ruby
dctx = VibeZstd::DCtx.new(**params)
dctx.decompress(data, dict: nil, initial_capacity: nil)
dctx.use_prefix(prefix_data)
dctx.initial_capacity = 1_048_576
dctx.window_log_max = 20

# Class methods
VibeZstd::DCtx.default_initial_capacity = value
VibeZstd::DCtx.parameter_bounds(param)
VibeZstd::DCtx.frame_content_size(data)
VibeZstd::DCtx.estimate_memory
```

### CDict / DDict (Dictionaries)

```ruby
cdict = VibeZstd::CDict.new(dict_data, level = nil)
cdict.size       # Dictionary size in bytes
cdict.dict_id    # Dictionary ID

ddict = VibeZstd::DDict.new(dict_data)
ddict.size
ddict.dict_id

# Class methods
VibeZstd::CDict.estimate_memory(dict_size, level)
VibeZstd::DDict.estimate_memory(dict_size)
```

### Streaming

```ruby
# Compression
writer = VibeZstd::CompressWriter.new(io, level: 3, dict: nil, pledged_size: nil)
VibeZstd::CompressWriter.open(io, **opts) { |w| ... }
writer.write(data)
writer.flush
writer.finish  # or writer.close

# Decompression
reader = VibeZstd::DecompressReader.new(io, dict: nil, initial_chunk_size: nil)
VibeZstd::DecompressReader.open(io, **opts) { |r| ... }
reader.read(size = nil)
reader.eof?
reader.each { |chunk| ... }
reader.each_line(separator = $/) { |line| ... }
reader.gets(separator = $/)
reader.readline(separator = $/)
reader.readpartial(maxlen)
reader.read_all
```

### ThreadLocal (Context Pooling)

```ruby
# Thread-local context reuse (ideal for Rails/Puma applications)
VibeZstd::ThreadLocal.compress(data, level: nil, dict: nil, pledged_size: nil)
VibeZstd::ThreadLocal.decompress(data, dict: nil, initial_capacity: nil)
VibeZstd::ThreadLocal.clear_thread_cache!
VibeZstd::ThreadLocal.thread_cache_stats
```

## Thread Safety and Ractors

VibeZstd is designed to be thread-safe and Ractor-compatible:

- Each context/dictionary object manages its own Zstd state
- CPU-intensive operations release the GVL for concurrent execution
- Create separate instances for each thread/Ractor as needed

```ruby
# Safe: Each thread has its own context
threads = 10.times.map do
  Thread.new do
    cctx = VibeZstd::CCtx.new
    # ... use cctx
  end
end
```

## Benchmarking

Run comprehensive benchmarks:

```bash
# All benchmarks
ruby benchmark/run_all.rb

# Specific benchmarks
ruby benchmark/context_reuse.rb
ruby benchmark/dictionary_usage.rb
ruby benchmark/compression_levels.rb
ruby benchmark/streaming.rb
ruby benchmark/multithreading.rb

# Generate README benchmark output
ruby benchmark/for_readme.rb
```

See `benchmark/README.md` for detailed documentation.

## Development

To set up the development environment:

```bash
bin/setup              # Install dependencies
rake compile           # Build C extension
rake test              # Run tests
bin/console            # Interactive console
bundle exec rake install  # Install locally
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kreynolds/vibe_zstd.

## Vendored Libraries

This gem vendors the Zstandard (zstd) compression library to provide consistent behavior across all platforms. The vendored zstd library is located in `ext/vibe_zstd/libzstd/` and is licensed under the BSD License.

**Zstandard License:**
- Copyright (c) Meta Platforms, Inc. and affiliates
- Licensed under the BSD License (see `ext/vibe_zstd/libzstd/LICENSE`)
- Project: https://github.com/facebook/zstd

For the complete zstd license text, see the LICENSE file in the vendored library directory.

## License

The VibeZstd gem itself is available as open source under the [MIT License](https://opensource.org/licenses/MIT).

This gem vendors the Zstandard library, which is separately licensed under the BSD License. See the [Vendored Libraries](#vendored-libraries) section above for details.
