# VibeZstd

A Ruby C extension that wraps the Zstandard (Zstd) compression library, providing fast, high-ratio compression and decompression capabilities.

## Installation

### Prerequisites

This gem requires the Zstandard library to be installed on your system:

- **macOS**: `brew install zstd`
- **Ubuntu/Debian**: `sudo apt-get install libzstd-dev`
- **CentOS/RHEL**: `sudo yum install libzstd-devel`
- **Windows**: Install via vcpkg or similar.

### Gem Installation

Add this line to your application's Gemfile:

```ruby
gem 'vibe_zstd'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install vibe_zstd
```

## Usage

### Basic Compression and Decompression

```ruby
require 'vibe_zstd'

# Create compression and decompression contexts
cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

# Compress data
data = "Hello, world! This is a test string for compression."
compressed = cctx.compress(data)
puts "Original size: #{data.bytesize}, Compressed size: #{compressed.bytesize}"

# Decompress data
decompressed = dctx.decompress(compressed)
puts "Decompressed: #{decompressed}"
```

### Compression with Custom Level

```ruby
# Compress with level 5 (lower levels are faster but compress less)
compressed = cctx.compress(data, 5)
```

### Advanced Compression Parameters

```ruby
require 'vibe_zstd'

cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

# Enable checksum for data integrity
cctx.set_parameter(:checksumFlag, 1)

# Include content size in frame header
cctx.set_parameter(:contentSizeFlag, 1)

# Use multi-threaded compression (4 threads)
cctx.set_parameter(:nbWorkers, 4)

# Parameters can be chained
cctx
  .set_parameter(:checksumFlag, 1)
  .set_parameter(:windowLog, 20)

data = "Your data here"
compressed = cctx.compress(data)
decompressed = dctx.decompress(compressed)
```

### Convenience Methods

For one-off compression/decompression operations, you can use the module-level convenience methods:

```ruby
# Simple compression/decompression
compressed = VibeZstd.compress(data)
decompressed = VibeZstd.decompress(compressed)

# With custom compression level
compressed = VibeZstd.compress(data, level: 5)

# With dictionary
compressed = VibeZstd.compress(data, dict: cdict)
decompressed = VibeZstd.decompress(compressed, dict: ddict)
```

### Using Dictionaries

Dictionaries can significantly improve compression ratios for small data with similar patterns.

#### Training a Dictionary

```ruby
# Train a dictionary from sample data
samples = [
  "sample data 1",
  "sample data 2",
  "sample data 3"
]

# Train with default algorithm (fast, good for most use cases)
dict_data = VibeZstd.train_dict(samples)

# Or specify custom max dictionary size
dict_data = VibeZstd.train_dict(samples, max_dict_size: 2048)

# For better dictionaries, use COVER algorithm (k and d are required)
# k: segment size (constraint: 0 < k, reasonable range: 16-2048+)
# d: dmer size (constraint: 0 < d <= k, reasonable range: 6-16)
dict_data = VibeZstd.train_dict_cover(
  samples,
  max_dict_size: 2048,
  k: 200,  # Segment size
  d: 6     # Dmer size
)

# For fastest training, use fast COVER algorithm
# f: log of frequency array size (constraint: 0 < f <= 31, default: 20)
# accel: acceleration level (constraint: 0 < accel <= 10, higher = faster but less accurate)
dict_data = VibeZstd.train_dict_fast_cover(
  samples,
  max_dict_size: 2048,
  k: 200,
  d: 6,
  f: 20,     # Frequency array size
  accel: 1   # Acceleration (1 = default)
)

# Get dictionary ID
dict_id = VibeZstd.get_dict_id(dict_data)
puts "Dictionary ID: #{dict_id}"
```

#### Using Pre-made Dictionaries

```ruby
# Create compression and decompression dictionaries
dict_data = "dictionary"
cdict = VibeZstd::CDict.new(dict_data)
ddict = VibeZstd::DDict.new(dict_data)

# Check dictionary properties
puts "Dictionary size: #{cdict.size} bytes"
puts "Dictionary ID: #{cdict.dict_id}"

# Compress and decompress with dictionaries
compressed = cctx.compress(data, nil, cdict)
decompressed = dctx.decompress(compressed, ddict)

# Or use convenience methods
compressed = VibeZstd.compress(data, dict: cdict)
decompressed = VibeZstd.decompress(compressed, dict: ddict)
```

### Streaming API

The streaming API allows you to compress or decompress data incrementally, which is useful for large files or when working with IO streams.

#### Streaming Compression

```ruby
require 'vibe_zstd'

# Compress to a file
File.open('output.zst', 'wb') do |file|
  writer = VibeZstd::Compress::Writer.new(file, level: 5)

  # Write data in chunks
  writer.write("Hello, ")
  writer.write("world!")

  # Optionally flush to ensure data is written
  writer.flush

  # Finish compression (writes final frame)
  writer.finish
end

# With a dictionary
File.open('output.zst', 'wb') do |file|
  cdict = VibeZstd::CDict.new(dict_data)
  writer = VibeZstd::Compress::Writer.new(file, level: 5, dict: cdict)
  writer.write(data)
  writer.finish
end
```

#### Streaming Decompression

```ruby
require 'vibe_zstd'

# Decompress from a file - chunked streaming (memory-safe for large files)
File.open('input.zst', 'rb') do |file|
  reader = VibeZstd::Decompress::Reader.new(file)

  # Read in chunks (~128KB each) - recommended for large files
  while chunk = reader.read
    process(chunk)
  end
end

# Configure initial chunk size for unbounded reads
# Good for optimizing memory usage based on your workload
File.open('input.zst', 'rb') do |file|
  # Use 1MB chunks for large data streams
  reader = VibeZstd::Decompress::Reader.new(file, initial_chunk_size: 1_048_576)

  # Unbounded reads will now return up to 1MB per call
  while chunk = reader.read
    process(chunk)
  end
end

# Or specify custom chunk size per read
File.open('input.zst', 'rb') do |file|
  reader = VibeZstd::Decompress::Reader.new(file)

  # Read in 64KB chunks (overrides initial_chunk_size if set)
  while chunk = reader.read(64 * 1024)
    process(chunk)
  end
end

# Stream from HTTP to disk (true streaming - constant memory usage)
require 'net/http'
uri = URI('https://example.com/large_file.zst')
File.open('output.txt', 'wb') do |output|
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request_get(uri.path) do |response|
      reader = VibeZstd::Decompress::Reader.new(response.body)

      # Streams in chunks - only ~128KB in memory at a time
      while chunk = reader.read
        output.write(chunk)
      end
    end
  end
end

# With a dictionary
File.open('input.zst', 'rb') do |file|
  ddict = VibeZstd::DDict.new(dict_data)
  reader = VibeZstd::Decompress::Reader.new(file, dict: ddict)

  while chunk = reader.read
    process(chunk)
  end
end
```

#### Configuring Chunk Sizes

The `Reader#read` method uses chunked streaming for memory safety. You can configure the chunk size in two ways:

```ruby
# Method 1: Set initial_chunk_size when creating the reader
# This affects ALL unbounded reads on this reader
reader = VibeZstd::Decompress::Reader.new(io, initial_chunk_size: 1_048_576)  # 1MB chunks
chunk = reader.read()  # Returns up to 1MB

# Method 2: Specify size per read call
# This overrides initial_chunk_size for that specific call
reader = VibeZstd::Decompress::Reader.new(io)
chunk = reader.read(64 * 1024)  # Returns up to 64KB

# Default behavior (no configuration)
reader = VibeZstd::Decompress::Reader.new(io)
chunk = reader.read()  # Returns up to ~128KB (ZSTD_DStreamOutSize)
```

**Configuration options:**

```ruby
# Small chunks (4KB) - memory-constrained environments
reader = VibeZstd::Decompress::Reader.new(io, initial_chunk_size: 4096)
while chunk = reader.read
  process(chunk)  # Each chunk ≤ 4KB
end

# Default chunks (~128KB) - good for most use cases
reader = VibeZstd::Decompress::Reader.new(io)
while chunk = reader.read
  process(chunk)  # Each chunk ≤ 128KB
end

# Large chunks (10MB) - high-throughput scenarios
reader = VibeZstd::Decompress::Reader.new(io, initial_chunk_size: 10_485_760)
while chunk = reader.read
  process(chunk)  # Each chunk ≤ 10MB
end

# Per-read override (overrides initial_chunk_size)
reader = VibeZstd::Decompress::Reader.new(io, initial_chunk_size: 1_048_576)
chunk = reader.read(8192)  # Returns up to 8KB, ignoring 1MB setting
```

**Best practices:**
- **Small frames (< 10KB)**: Set `initial_chunk_size: 4096` to avoid over-allocation
- **Medium files (10KB - 1MB)**: Use default (~128KB) for balanced performance
- **Large files/streams (> 1MB)**: Set `initial_chunk_size: 1_048_576` (1MB) or higher to reduce read() calls
- **Memory-constrained**: Use smaller chunks (4KB-8KB) to minimize memory footprint
- **High throughput**: Use larger chunks (1MB-10MB) to reduce loop overhead
- **Mixed workloads**: Configure per-reader based on expected data size

### Prefix Dictionaries (Lightweight Alternative)

For cases where you want dictionary-like compression without the overhead of training or pre-digesting a dictionary:

```ruby
cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

# Use a shared prefix (must be the same for compression and decompression)
prefix = "Common prefix data that appears in your data"

cctx.use_prefix(prefix)
dctx.use_prefix(prefix)

compressed = cctx.compress("Common prefix data that we want to compress")
decompressed = dctx.decompress(compressed)
```

### Memory Estimation

Estimate memory usage before creating compression/decompression contexts:

```ruby
# Estimate memory for compression context at level 5
cctx_bytes = VibeZstd::CCtx.estimate_memory(5)
puts "CCtx will use approximately #{cctx_bytes} bytes"

# Estimate memory for decompression context
dctx_bytes = VibeZstd::DCtx.estimate_memory
puts "DCtx will use approximately #{dctx_bytes} bytes"

# Estimate memory for dictionaries
dict_size = 112 * 1024  # 112KB dictionary
cdict_bytes = VibeZstd::CDict.estimate_memory(dict_size, 5)
ddict_bytes = VibeZstd::DDict.estimate_memory(dict_size)
puts "CDict: #{cdict_bytes} bytes, DDict: #{ddict_bytes} bytes"
```

### Parameter Validation with Bounds

Query valid parameter ranges for validation and better error messages:

```ruby
# Get bounds for a compression parameter
bounds = VibeZstd::CCtx.parameter_bounds(:compressionLevel)
puts "Compression level: #{bounds[:min]} to #{bounds[:max]}"
# => Compression level: -131072 to 22

# Validate before setting
def set_safe_compression_level(cctx, level)
  bounds = VibeZstd::CCtx.parameter_bounds(:compressionLevel)
  if level < bounds[:min] || level > bounds[:max]
    raise ArgumentError, "Level must be between #{bounds[:min]} and #{bounds[:max]}"
  end
  cctx.set_parameter(:compressionLevel, level)
end

# Check bounds for window size
window_bounds = VibeZstd::CCtx.parameter_bounds(:windowLog)
puts "Window log: #{window_bounds[:min]} to #{window_bounds[:max]}"
# => Window log: 10 to 31

# Query all parameter bounds for documentation
[:compressionLevel, :windowLog, :nbWorkers].each do |param|
  bounds = VibeZstd::CCtx.parameter_bounds(param)
  puts "#{param}: #{bounds[:min]}..#{bounds[:max]}"
end

# Decompression parameter bounds
dctx_bounds = VibeZstd::DCtx.parameter_bounds(:windowLogMax)
puts "Max window log: #{dctx_bounds[:min]} to #{dctx_bounds[:max]}"
```

### Decompression Parameters

Control decompression behavior to prevent memory exhaustion:

```ruby
dctx = VibeZstd::DCtx.new

# Limit maximum window size during decompression (prevents memory attacks)
dctx.set_parameter(:windowLogMax, 20)  # Max 1MB window

compressed = File.read('data.zst')
decompressed = dctx.decompress(compressed)
```

### Optimizing Decompression for Unknown-Size Frames

When decompressing frames without a known content size (e.g., streaming compression with `content_size: false`), VibeZstd uses an exponential growth buffer strategy. You can configure the initial buffer capacity to optimize for your data size:

```ruby
# Configure globally for all new DCtx instances
VibeZstd::DCtx.default_initial_capacity = 1_048_576  # 1MB for large data
VibeZstd::DCtx.default_initial_capacity = 4_096      # 4KB for tiny data

# Configure per-instance
dctx = VibeZstd::DCtx.new(initial_capacity: 512_000)  # 512KB

# Or configure per-call (overrides instance setting)
dctx.decompress(compressed_data, initial_capacity: 16_384)  # 16KB

# Reset to default (ZSTD_DStreamOutSize, ~128KB)
VibeZstd::DCtx.default_initial_capacity = nil
dctx.initial_capacity = nil
```

**Configuration levels (priority order):**
1. **Per-call**: `decompress(data, initial_capacity: N)` - highest priority
2. **Instance**: `DCtx.new(initial_capacity: N)` or `dctx.initial_capacity = N`
3. **Global**: `DCtx.default_initial_capacity = N`
4. **Default**: `ZSTD_DStreamOutSize()` (~128KB) - if nothing configured

**When to configure:**
- **Small data (< 10KB)**: Set to `4096` or `8192` to avoid over-allocation
- **Large data (> 1MB)**: Set to `1_048_576` or higher to reduce reallocations
- **Mixed workloads**: Use per-call overrides for edge cases
- **Known-size frames**: Not applicable - size is known from frame header

**Note:** This only affects frames with unknown content size. Frames with known sizes (the common case) allocate exactly what's needed regardless of this setting.

### Ultra-Fast Compression with Negative Levels

For situations requiring maximum speed with acceptable compression loss:

```ruby
cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

data = "Large data that needs ultra-fast compression"

# Use negative level for fastest compression
# Levels range from -131072 (fastest) to -1
compressed = cctx.compress(data, -1)
decompressed = dctx.decompress(compressed)
```

### Long Distance Matching (LDM) for Large Files

For compressing large files with repeated patterns at long distances:

```ruby
cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

# Enable LDM for better compression of large files
cctx.set_parameter(:enableLongDistanceMatching, 1)

# Optionally tune LDM parameters
cctx.set_parameter(:ldmHashLog, 20)      # Hash table size (default: windowLog - 7)
cctx.set_parameter(:ldmMinMatch, 64)     # Minimum match size (default: 64)
cctx.set_parameter(:ldmBucketSizeLog, 3) # Bucket size for collision resolution
cctx.set_parameter(:ldmHashRateLog, 6)   # Hash insertion frequency

# Compress large file
large_data = File.read('large_file.txt')
compressed = cctx.compress(large_data, 9) # Use high compression level with LDM
decompressed = dctx.decompress(compressed)
```

**When to use LDM:**
- Large files (> 64KB) with repeated patterns
- Log files with recurring messages
- Database dumps
- Source code repositories
- Note: LDM increases memory usage and is auto-enabled at level 16+ with large windows

### Low-Latency Streaming with Target Block Size

For streaming applications that need to minimize latency (e.g., web browsers):

```ruby
require 'vibe_zstd'

File.open('output.zst', 'wb') do |file|
  writer = VibeZstd::Compress::Writer.new(file, level: 5)

  # Set target compressed block size for better streaming behavior
  # This helps browsers/clients process partial documents
  writer.instance_variable_get(:@cstream).tap do |cstream|
    cctx_ptr = cstream.instance_variable_get(:@cstream)
    # Note: This is for illustration - you would set this via CCtx if available before streaming
  end

  # Or set on CCtx before compression
  cctx = VibeZstd::CCtx.new
  cctx.set_parameter(:targetCBlockSize, 2048) # Target ~2KB compressed blocks

  data.each_slice(4096) do |chunk|
    writer.write(chunk.join)
  end

  writer.finish
end
```

### Multi-threading Tuning

For optimal multi-threaded compression performance:

```ruby
cctx = VibeZstd::CCtx.new
dctx = VibeZstd::DCtx.new

# Enable multi-threaded compression
cctx.set_parameter(:nbWorkers, 4) # Use 4 threads

# Tune job size (default: auto-determined)
# Larger jobs = better compression ratio but higher latency
# Smaller jobs = lower latency but may reduce ratio
cctx.set_parameter(:jobSize, 1048576) # 1MB per job

# Tune overlap between jobs (0-9 scale)
# Higher overlap = better ratio but slower
# 0 = default (auto, usually 6-9 depending on strategy)
# 1 = no overlap (fastest)
# 9 = full window overlap (best ratio)
cctx.set_parameter(:overlapLog, 6)

# Compress large data with multi-threading
large_data = File.read('large_dataset.txt')
compressed = cctx.compress(large_data, 5)
decompressed = dctx.decompress(compressed)
```

**Multi-threading tips:**
- More workers ≠ always faster (diminishing returns after 4-8 threads)
- Multi-threading adds overhead for small data (< 256KB)
- Best for data > 1MB
- jobSize and overlapLog only affect performance when nbWorkers >= 1

## API Reference

### VibeZstd::CCtx (Compression Context)

A reusable context for compressing data.

#### Methods

- `new()` - Creates a new compression context.
- `compress(data, level = nil, dict = nil, pledged_size: nil)` - Compresses the given data string.
  - `level` defaults to Zstd's default compression level if not specified. Supports levels from -131072 to 22 (negative levels provide ultra-fast compression)
  - `dict` is an optional CDict for dictionary-based compression
  - `pledged_size` hints the decompressed size for improved compression ratio (optional)
- `set_parameter(param, value)` - Sets advanced compression parameters. Returns self for method chaining. Available parameters:
  - **Frame parameters:**
    - `:checksumFlag` (0/1) - Enable 32-bit checksum for integrity verification
    - `:contentSizeFlag` (0/1) - Include decompressed size in frame header
    - `:dictIDFlag` (0/1) - Include dictionary ID in frame header
  - **Core compression parameters:**
    - `:compressionLevel` (1-22 or negative) - Compression level (negative for ultra-fast)
    - `:windowLog` (10-31) - Window size as power of 2 (affects memory usage)
    - `:hashLog` (6-26) - Hash table size as power of 2
    - `:chainLog` (6-28) - Search chain length as power of 2
    - `:searchLog` (1-26) - Number of search attempts as power of 2
    - `:minMatch` (3-7) - Minimum match size
    - `:targetLength` (0-128) - Target match length (strategy-dependent)
    - `:strategy` (1-9) - Compression strategy (1=fast, 9=btultra2)
    - `:targetCBlockSize` (0-131072+) - Target compressed block size for low-latency streaming
  - **Long Distance Matching (LDM) parameters:**
    - `:enableLongDistanceMatching` (0/1) - Enable LDM mode (critical for large files)
    - `:ldmHashLog` (6-30) - LDM hash table size as power of 2
    - `:ldmMinMatch` (4-4096) - LDM minimum match size (default: 64)
    - `:ldmBucketSizeLog` (0-8) - LDM bucket size for collision resolution
    - `:ldmHashRateLog` (0-28) - LDM hash insertion frequency
  - **Multi-threading parameters:**
    - `:nbWorkers` (0-200) - Number of threads for parallel compression (0 = single-threaded)
    - `:jobSize` (0-1GB) - Compression job size (only when nbWorkers >= 1)
    - `:overlapLog` (0-9) - Overlap size as fraction of window (only when nbWorkers >= 1)
  - **Experimental parameters** (advanced use cases, may change between zstd versions):
    - `:rsyncable` (0/1) - Generate rsync-friendly compressed data
    - `:format` (0/1/2) - Frame format (0=zstd, 1=magicless, 2=skippable)
    - `:forceMaxWindow` (0/1) - Force back-reference distance to remain < windowSize
    - `:forceAttachDict` (0/1/2) - Force dictionary attachment mode (0=default, 1=attach, 2=copy)
    - `:literalCompressionMode` (0/1/2) - Literal compression mode (0=auto, 1=enable, 2=disable)
    - `:srcSizeHint` (0-INT_MAX) - Hint about source size for optimization
    - `:enableDedicatedDictSearch` (0/1) - Enable dedicated dictionary search
    - `:stableInBuffer` (0/1) - Input buffer will remain valid between calls
    - `:stableOutBuffer` (0/1) - Output buffer will remain valid between calls
    - `:blockDelimiters` (0/1) - Emit block boundary delimiters
    - `:validateSequences` (0/1) - Validate generated sequences
    - `:useRowMatchFinder` (0/1/2) - Use row-based match finder (0=auto, 1=disable, 2=enable)
    - `:deterministicRefPrefix` (0/1) - Make reference prefix deterministic
    - `:prefetchCDictTables` (0/1/2) - Prefetch dictionary tables (0=auto, 1=enable, 2=disable)
    - `:enableSeqProducerFallback` (0/1) - Enable fallback for external sequence producer
    - `:maxBlockSize` (0-131072+) - Maximum uncompressed block size
    - `:searchForExternalRepcodes` (0/1/2) - Search for external repeat codes (0=auto, 1=enable, 2=disable)
- `get_parameter(param)` - Gets current value of a compression parameter. Returns the integer value. Accepts the same parameter symbols as `set_parameter`
- `use_prefix(prefix_data)` - Uses raw data as a compression prefix (lightweight dictionary alternative). The prefix must be set before each compression operation. Returns self for method chaining.
- `CCtx.parameter_bounds(param)` - Class method that returns the valid range for a compression parameter. Returns a hash with `:min` and `:max` keys. Useful for parameter validation.
- `CCtx.estimate_memory(level)` - Class method that estimates memory usage in bytes for a compression context at the given level. Useful for memory planning in constrained environments.

### VibeZstd::DCtx (Decompression Context)

A reusable context for decompressing data.

#### Methods

- `new(initial_capacity: nil)` - Creates a new decompression context.
  - `initial_capacity` - Optional initial buffer capacity (in bytes) for unknown-size frames. If nil, uses the class default.
- `decompress(data, dict: nil, initial_capacity: nil)` - Decompresses the given compressed data string.
  - `dict` - Optional DDict for dictionary-based decompression.
  - `initial_capacity` - Optional per-call override for initial buffer capacity (in bytes) for unknown-size frames.
- `set_parameter(param, value)` - Sets advanced decompression parameters. Returns self for method chaining. Available parameters:
  - `:windowLogMax` (10-31) - Maximum window size as power of 2. Prevents memory exhaustion attacks.
- `get_parameter(param)` - Gets current value of a decompression parameter. Returns the integer value. Currently supports `:windowLogMax`.
- `initial_capacity` - Gets the instance's initial capacity setting for unknown-size frames. Returns the configured value, or the class default if not set.
- `initial_capacity=(value)` - Sets the instance's initial capacity for unknown-size frames. Set to nil to use the class default. Value must be positive.
- `use_prefix(prefix_data)` - Uses raw data as a decompression prefix (must match the prefix used during compression). Returns self for method chaining.
- `DCtx.default_initial_capacity` - Class method that gets the global default initial capacity for all new DCtx instances. Returns `ZSTD_DStreamOutSize()` (~128KB) if not configured.
- `DCtx.default_initial_capacity=(value)` - Class method that sets the global default initial capacity for all new DCtx instances. Set to nil to reset to ZSTD default. Value must be positive.
- `DCtx.parameter_bounds(param)` - Class method that returns the valid range for a decompression parameter. Returns a hash with `:min` and `:max` keys. Useful for parameter validation.
- `DCtx.frame_content_size(data)` - Class method that returns the decompressed size of a compressed frame, or nil if unknown or invalid.
- `DCtx.estimate_memory()` - Class method that estimates memory usage in bytes for a decompression context. Useful for memory planning in constrained environments.

### VibeZstd::CDict (Compression Dictionary)

A pre-digested dictionary for compression.

#### Methods

- `new(dict_data, level = nil)` - Creates a compression dictionary from the given data. `level` defaults to Zstd's default if not specified.
- `size()` - Returns the size of the dictionary in memory (in bytes).
- `dict_id()` - Returns the dictionary ID. Returns 0 if the dictionary is raw content.
- `CDict.estimate_memory(dict_size, level)` - Class method that estimates memory usage in bytes for a compression dictionary of the given size and compression level.

### VibeZstd::DDict (Decompression Dictionary)

A pre-digested dictionary for decompression.

#### Methods

- `new(dict_data)` - Creates a decompression dictionary from the given data.
- `size()` - Returns the size of the dictionary in memory (in bytes).
- `dict_id()` - Returns the dictionary ID. Returns 0 if the dictionary is raw content.
- `DDict.estimate_memory(dict_size)` - Class method that estimates memory usage in bytes for a decompression dictionary of the given size.

### VibeZstd::Compress::Writer (Streaming Compression)

A streaming writer for compressing data incrementally.

#### Methods

- `new(io, level: 3, dict: nil, pledged_size: nil)` - Creates a new compression writer that writes to the given IO object.
  - `level` specifies the compression level (1-22)
  - `dict` is an optional CDict for dictionary-based compression
  - `pledged_size` hints the total size to be compressed for improved compression ratio (optional)
- `write(data)` - Compresses and writes the given data. Returns self for method chaining.
- `flush()` - Flushes any buffered compressed data to the IO. Returns self for method chaining.
- `finish()` / `close()` - Finalizes the compression and writes the end frame. Must be called to produce valid compressed data. Returns self.

### VibeZstd::Decompress::Reader (Streaming Decompression)

A streaming reader for decompressing data incrementally with chunked reading for memory safety.

#### Methods

- `new(io, dict: nil, initial_chunk_size: nil)` - Creates a new decompression reader that reads from the given IO object.
  - `dict` - Optional DDict for dictionary-based decompression.
  - `initial_chunk_size` - Optional size (in bytes) for unbounded reads. If nil, defaults to `ZSTD_DStreamOutSize()` (~128KB). Must be greater than 0 if specified. This setting affects all unbounded `read()` calls on this reader instance.
- `read(size = nil)` - Reads and decompresses data in chunks.
  - If `size` is nil, reads up to `initial_chunk_size` bytes (or ~128KB if not configured) of decompressed data per call.
  - If `size` is specified, reads up to that many bytes of decompressed data (overrides `initial_chunk_size` for this call).
  - Returns nil at end of stream.
  - **Note:** This method uses true chunked streaming - it does NOT buffer entire frames in memory, making it safe for decompressing multi-GB files with constant memory usage.
- `eof?` - Returns true if the end of stream has been reached.

### VibeZstd Module Methods

#### Methods

- `compress(data, level: nil, dict: nil)` - Convenience method for one-off compression. Returns compressed data.
- `decompress(data, dict: nil)` - Convenience method for one-off decompression. Returns decompressed data.
- `frame_content_size(data)` - Returns the decompressed size of a compressed frame, or nil if unknown or invalid. Useful for pre-allocating buffers.
- `compress_bound(size)` - Returns the maximum compressed size for data of given uncompressed size. Useful for buffer pre-allocation.
- `train_dict(samples, max_dict_size: 112640)` - Trains a dictionary from an array of sample strings using the default algorithm. Returns the trained dictionary data as a string. The `max_dict_size` parameter specifies the maximum dictionary size in bytes (default is 112KB).
- `train_dict_cover(samples, max_dict_size: 112640, k:, d:, steps: 0, split_point: 1.0, shrink_dict: false, shrink_dict_max_regression: 0, nb_threads: 0)` - Trains a dictionary using the COVER algorithm for better compression. Parameters `k` (segment size) and `d` (dmer size) are required. Returns the trained dictionary data.
- `train_dict_fast_cover(samples, max_dict_size: 112640, k:, d:, f: 0, steps: 0, split_point: 0.75, accel: 0, shrink_dict: false, shrink_dict_max_regression: 0, nb_threads: 0)` - Trains a dictionary using the fast COVER algorithm for faster training with good quality. Parameters `k` and `d` are required. Optional `f` (log of frequency array size) and `accel` (acceleration level 1-10) control speed vs quality tradeoff.
- `get_dict_id(dict_data)` - Returns the dictionary ID from raw dictionary data. Returns 0 for raw content dictionaries, non-zero for trained dictionaries.
- `get_dict_id_from_frame(data)` - Returns the dictionary ID from a compressed frame. Returns 0 if no dictionary was used. Useful for determining which dictionary to use for decompression.

## Thread Safety and Ractors

VibeZstd is designed to be thread-safe and compatible with Ruby's Ractors:

- Each context/dictionary object encapsulates its own Zstd state, ensuring no shared mutable state between threads or Ractors.
- CPU-intensive operations release the Global VM Lock (GVL) to allow concurrent execution.
- Create separate instances for each thread/Ractor as needed.

## Performance

VibeZstd leverages the high-performance Zstandard library for excellent compression performance:

- Compression ratios comparable to or better than gzip/bzip2 at similar speeds
- Extremely fast decompression
- Supports compression levels from -131072 (ultra-fast) to 22 (maximum compression)

### Benchmark Results

Results from Ruby 3.3.7 on arm64-darwin24, Zstd 1.5.7. Run `ruby benchmark/for_readme.rb` to generate results for your platform.

#### Context Reuse Performance

Reusing compression/decompression contexts vs creating new ones (5000 iterations each):

| Data Size | New Context | Reused Context | Speedup |
|-----------|-------------|----------------|---------|
| 1KB | 70,095 ops/s | 159,245 ops/s | 2.27x |
| 10KB | 38,839 ops/s | 62,467 ops/s | 1.61x |
| 100KB | 7,732 ops/s | 9,346 ops/s | 1.21x |

**Memory savings:** Reusing contexts saves ~6.7GB for 5000 operations (99.98% reduction)

**Recommendation:** Always reuse CCtx/DCtx instances for multiple operations.

#### Dictionary Compression

Compression with vs without trained dictionaries (JSON data):

| Method | Compressed Size | Ratio | Improvement |
|--------|----------------|-------|-------------|
| Without dictionary | 110B | 1.15x | - |
| With dictionary (16KB) | 54B | 2.33x | 50.9% smaller |

Original size: 126 bytes. Dictionaries are highly effective for small, similar data like JSON, logs, and API responses.

#### Compression Levels

Speed vs compression ratio trade-offs:

| Level | Ratio | Speed (ops/sec) | Memory | Use Case |
|-------|-------|-----------------|--------|----------|
| -1 | 5.99x | 11,086 | 537KB | Ultra-fast, real-time |
| 1 | 8.19x | 10,775 | 569KB | Fast, high-throughput |
| 3 | 7.92x | 8,896 | 1.24MB | Balanced (default) |
| 9 | 9.1x | 969 | 12.49MB | Better compression |
| 19 | 10.22x | 34 | 81.25MB | Maximum compression |

#### Multi-threading Performance

Compression speedup with multiple workers (500KB data):

| Workers | Throughput | Speedup | Efficiency |
|---------|------------|---------|------------|
| 0 (single) | 732MB/s | 1.0x | 100% |
| 2 | 734MB/s | 1.0x | 50% |
| 4 | 689MB/s | 0.94x | 24% |

**Note:** Multi-threading is most effective for larger data (> 1MB). Overhead may outweigh benefits for smaller payloads.

### Running Benchmarks

Comprehensive benchmarks are available in the `benchmark/` directory:

```bash
# Run all benchmarks
ruby benchmark/run_all.rb

# Run specific benchmarks
ruby benchmark/context_reuse.rb
ruby benchmark/dictionary_usage.rb
ruby benchmark/compression_levels.rb
ruby benchmark/streaming.rb
ruby benchmark/multithreading.rb
ruby benchmark/dictionary_training.rb
```

See `benchmark/README.md` for detailed benchmark documentation.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To build the C extension:

```bash
rake compile
```

To run tests:

```bash
rake test
```

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/vibe_zstd. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/vibe_zstd/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the VibeZstd project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/vibe_zstd/blob/main/CODE_OF_CONDUCT.md).
