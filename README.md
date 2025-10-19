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

# Train with default size (112KB)
dict_data = VibeZstd.train_dict(samples)

# Or specify custom max dictionary size
dict_data = VibeZstd.train_dict(samples, max_dict_size: 2048)

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

# Decompress from a file
File.open('input.zst', 'rb') do |file|
  reader = VibeZstd::Decompress::Reader.new(file)

  # Read all at once
  decompressed = reader.read

  # Or read in chunks
  while chunk = reader.read(1024)
    process(chunk)
  end
end

# With a dictionary
File.open('input.zst', 'rb') do |file|
  ddict = VibeZstd::DDict.new(dict_data)
  reader = VibeZstd::Decompress::Reader.new(file, dict: ddict)
  decompressed = reader.read
end
```

## API Reference

### VibeZstd::CCtx (Compression Context)

A reusable context for compressing data.

#### Methods

- `new()` - Creates a new compression context.
- `compress(data, level = nil, dict = nil)` - Compresses the given data string. `level` defaults to Zstd's default compression level if not specified. `dict` is an optional CDict for dictionary-based compression.

### VibeZstd::DCtx (Decompression Context)

A reusable context for decompressing data.

#### Methods

- `new()` - Creates a new decompression context.
- `decompress(data, dict = nil)` - Decompresses the given compressed data string. `dict` is an optional DDict for dictionary-based decompression.
- `DCtx.frame_content_size(data)` - Class method that returns the decompressed size of a compressed frame, or nil if unknown or invalid.

### VibeZstd::CDict (Compression Dictionary)

A pre-digested dictionary for compression.

#### Methods

- `new(dict_data, level = nil)` - Creates a compression dictionary from the given data. `level` defaults to Zstd's default if not specified.
- `size()` - Returns the size of the dictionary in memory (in bytes).
- `dict_id()` - Returns the dictionary ID. Returns 0 if the dictionary is raw content.

### VibeZstd::DDict (Decompression Dictionary)

A pre-digested dictionary for decompression.

#### Methods

- `new(dict_data)` - Creates a decompression dictionary from the given data.
- `size()` - Returns the size of the dictionary in memory (in bytes).
- `dict_id()` - Returns the dictionary ID. Returns 0 if the dictionary is raw content.

### VibeZstd::Compress::Writer (Streaming Compression)

A streaming writer for compressing data incrementally.

#### Methods

- `new(io, level: 3, dict: nil)` - Creates a new compression writer that writes to the given IO object. `level` specifies the compression level (1-22). `dict` is an optional CDict for dictionary-based compression.
- `write(data)` - Compresses and writes the given data. Returns self for method chaining.
- `flush()` - Flushes any buffered compressed data to the IO. Returns self for method chaining.
- `finish()` / `close()` - Finalizes the compression and writes the end frame. Must be called to produce valid compressed data. Returns self.

### VibeZstd::Decompress::Reader (Streaming Decompression)

A streaming reader for decompressing data incrementally.

#### Methods

- `new(io, dict: nil)` - Creates a new decompression reader that reads from the given IO object. `dict` is an optional DDict for dictionary-based decompression.
- `read(size = nil)` - Reads and decompresses data. If `size` is nil, reads until end of stream. If `size` is specified, reads up to that many bytes of decompressed data. Returns nil at end of stream.

### VibeZstd Module Methods

#### Methods

- `compress(data, level: nil, dict: nil)` - Convenience method for one-off compression. Returns compressed data.
- `decompress(data, dict: nil)` - Convenience method for one-off decompression. Returns decompressed data.
- `frame_content_size(data)` - Returns the decompressed size of a compressed frame, or nil if unknown or invalid. Useful for pre-allocating buffers.
- `train_dict(samples, max_dict_size: 112640)` - Trains a dictionary from an array of sample strings. Returns the trained dictionary data as a string. The `max_dict_size` parameter specifies the maximum dictionary size in bytes (default is 112KB).
- `get_dict_id(dict_data)` - Returns the dictionary ID from raw dictionary data. Returns 0 for raw content dictionaries, non-zero for trained dictionaries.

## Thread Safety and Ractors

VibeZstd is designed to be thread-safe and compatible with Ruby's Ractors:

- Each context/dictionary object encapsulates its own Zstd state, ensuring no shared mutable state between threads or Ractors.
- CPU-intensive operations release the Global VM Lock (GVL) to allow concurrent execution.
- Create separate instances for each thread/Ractor as needed.

## Performance

VibeZstd leverages the high-performance Zstandard library:

- Compression ratios comparable to or better than gzip/bzip2 at similar speeds.
- Extremely fast decompression.
- Supports compression levels from 1 (fastest) to 22 (best compression).

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
