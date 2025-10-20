# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestStreaming < Minitest::Test
  # CompressWriter tests
  def test_streaming_compression
    data = "hello world! " * 1000
    output = StringIO.new

    writer = VibeZstd::CompressWriter.new(output, level: 5)

    # Write in chunks
    data.chars.each_slice(100) do |chunk|
      writer.write(chunk.join)
    end

    writer.finish
    compressed = output.string

    # Verify we can decompress it
    decompressed = VibeZstd.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_compress_writer_with_dictionary
    dict_data = "hello world! "
    cdict = VibeZstd::CDict.new(dict_data, 3)
    ddict = VibeZstd::DDict.new(dict_data)

    data = "hello world! " * 1000
    output = StringIO.new

    # Compress with dictionary
    writer = VibeZstd::CompressWriter.new(output, level: 5, dict: cdict)
    writer.write(data)
    writer.finish

    compressed = output.string

    # Decompress with dictionary
    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input, dict: ddict)
    decompressed = reader.read

    assert_equal(data, decompressed)
  end

  def test_streaming_with_pledged_size
    data = "hello world! " * 100
    output = StringIO.new

    # Create writer with pledged source size
    writer = VibeZstd::CompressWriter.new(output, level: 5, pledged_size: data.bytesize)
    writer.write(data)
    writer.finish

    compressed = output.string

    # Verify we can decompress it
    decompressed = VibeZstd.decompress(compressed)
    assert_equal(data, decompressed)

    # Verify content size was set
    size = VibeZstd.frame_content_size(compressed)
    assert_equal(data.bytesize, size)
  end

  def test_compress_writer_multiple_writes
    output = StringIO.new
    writer = VibeZstd::CompressWriter.new(output, level: 3)

    # Write multiple chunks
    chunks = ["first ", "second ", "third ", "fourth"]
    chunks.each { |chunk| writer.write(chunk) }
    writer.finish

    compressed = output.string
    decompressed = VibeZstd.decompress(compressed)
    assert_equal(chunks.join, decompressed)
  end

  # DecompressReader tests
  def test_streaming_decompression
    data = "hello world! " * 1000
    compressed = VibeZstd.compress(data, level: 5)

    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input)

    # Read all at once
    decompressed = reader.read
    assert_equal(data, decompressed)
  end

  def test_decompress_reader_with_dictionary
    dict_data = "hello world! "
    cdict = VibeZstd::CDict.new(dict_data, 3)
    ddict = VibeZstd::DDict.new(dict_data)

    data = "hello world! " * 1000

    # Compress with dictionary
    compressed = VibeZstd.compress(data, dict: cdict)

    # Decompress with dictionary using reader
    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input, dict: ddict)
    decompressed = reader.read

    assert_equal(data, decompressed)
  end

  def test_streaming_read_in_chunks
    data = "hello world! " * 100
    compressed = VibeZstd.compress(data)

    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input)

    # Read in small chunks and collect
    chunks = []
    while (chunk = reader.read(50))
      chunks << chunk
      break if chunks.size > 100  # Safety limit to prevent infinite loop
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
  end

  def test_decompress_reader_read_all
    data = "test data for read all " * 50
    compressed = VibeZstd.compress(data)

    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input)

    # Read without size argument should read all
    decompressed = reader.read
    assert_equal(data, decompressed)

    # Second read should return nil (EOF)
    assert_nil(reader.read)
  end

  # Block-based resource management
  def test_writer_open_with_block
    data = "Test data for block-based Writer " * 100
    output = StringIO.new

    # Block form automatically calls finish
    VibeZstd::CompressWriter.open(output, level: 5) do |writer|
      writer.write(data)
      # finish called automatically on block exit
    end

    compressed = output.string

    # Verify compression worked
    decompressed = VibeZstd.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_writer_open_without_block
    data = "Test data for non-block Writer.open"
    output = StringIO.new

    # Without block, returns writer and doesn't call finish
    writer = VibeZstd::CompressWriter.open(output, level: 5)
    writer.write(data)
    writer.finish

    compressed = output.string
    decompressed = VibeZstd.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_writer_open_with_exception
    output = StringIO.new
    exception_raised = false

    begin
      VibeZstd::CompressWriter.open(output, level: 5) do |writer|
        writer.write("some data")
        raise "Test exception"
      end
    rescue
      exception_raised = true
    end

    assert(exception_raised, "Exception should have been raised")

    # Finish should have been called despite exception
    compressed = output.string
    assert(compressed.bytesize > 0, "Data should have been written")
  end

  def test_reader_open_with_block
    data = "Test data for block-based Reader " * 100
    compressed = VibeZstd.compress(data)
    input = StringIO.new(compressed)

    # Block form automatically handles cleanup
    decompressed = nil
    VibeZstd::DecompressReader.open(input) do |reader|
      decompressed = reader.read
      # Cleanup happens automatically on block exit
    end

    assert_equal(data, decompressed)
  end

  def test_reader_open_without_block
    data = "Test data for non-block Reader.open"
    compressed = VibeZstd.compress(data)
    input = StringIO.new(compressed)

    # Without block, returns reader
    reader = VibeZstd::DecompressReader.open(input)
    decompressed = reader.read

    assert_equal(data, decompressed)
  end

  def test_writer_open_with_dictionary
    dict_data = "hello world! "
    cdict = VibeZstd::CDict.new(dict_data, 3)
    ddict = VibeZstd::DDict.new(dict_data)

    data = "hello world! " * 100
    output = StringIO.new

    # Test block form with dictionary
    VibeZstd::CompressWriter.open(output, level: 5, dict: cdict) do |writer|
      writer.write(data)
    end

    compressed = output.string

    # Verify decompression with dictionary using Reader
    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input, dict: ddict)
    decompressed = reader.read
    assert_equal(data, decompressed)
  end

  def test_reader_open_with_dictionary
    dict_data = "hello world! "
    cdict = VibeZstd::CDict.new(dict_data, 3)
    ddict = VibeZstd::DDict.new(dict_data)

    data = "hello world! " * 100

    # Compress with dictionary
    compressed = VibeZstd.compress(data, dict: cdict)

    # Decompress using Reader.open with block
    input = StringIO.new(compressed)
    decompressed = nil
    VibeZstd::DecompressReader.open(input, dict: ddict) do |reader|
      decompressed = reader.read
    end

    assert_equal(data, decompressed)
  end

  # Combined streaming tests
  def test_streaming_roundtrip
    data = "Round trip streaming test " * 200
    output = StringIO.new

    # Compress with streaming
    VibeZstd::CompressWriter.open(output, level: 5) do |writer|
      # Write in chunks
      data.chars.each_slice(100) do |chunk|
        writer.write(chunk.join)
      end
    end

    compressed = output.string

    # Decompress with streaming
    input = StringIO.new(compressed)
    chunks = []
    VibeZstd::DecompressReader.open(input) do |reader|
      while (chunk = reader.read(100))
        chunks << chunk
      end
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
  end

  def test_streaming_with_contexts
    # Test streaming with reusable contexts
    data = "Streaming with context reuse " * 100
    output = StringIO.new

    # Use streaming writer
    writer = VibeZstd::CompressWriter.new(output, level: 5)
    writer.write(data)
    writer.finish

    compressed = output.string

    # Use streaming reader
    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input)
    decompressed = reader.read

    assert_equal(data, decompressed)
  end

  def test_writer_new_vs_open
    data = "Testing new vs open"
    output1 = StringIO.new
    output2 = StringIO.new

    # Test with new (manual finish)
    writer1 = VibeZstd::CompressWriter.new(output1, level: 3)
    writer1.write(data)
    writer1.finish

    # Test with open and block (auto finish)
    VibeZstd::CompressWriter.open(output2, level: 3) do |writer2|
      writer2.write(data)
    end

    # Both should produce valid compressed data
    decompressed1 = VibeZstd.decompress(output1.string)
    decompressed2 = VibeZstd.decompress(output2.string)

    assert_equal(data, decompressed1)
    assert_equal(data, decompressed2)
  end

  def test_reader_new_vs_open
    data = "Testing new vs open for reader"
    compressed = VibeZstd.compress(data)

    # Test with new
    input1 = StringIO.new(compressed)
    reader1 = VibeZstd::DecompressReader.new(input1)
    decompressed1 = reader1.read

    # Test with open and block
    input2 = StringIO.new(compressed)
    decompressed2 = nil
    VibeZstd::DecompressReader.open(input2) do |reader2|
      decompressed2 = reader2.read
    end

    assert_equal(data, decompressed1)
    assert_equal(data, decompressed2)
  end

  def test_streaming_empty_data
    # Test streaming with empty data
    output = StringIO.new

    VibeZstd::CompressWriter.open(output, level: 3) do |writer|
      writer.write("")
    end

    compressed = output.string
    assert(compressed.bytesize > 0, "Should produce a valid frame even for empty data")

    # Should decompress to empty string
    decompressed = VibeZstd.decompress(compressed)
    assert_equal("", decompressed)
  end

  def test_unbounded_read_returns_chunks
    # Test that unbounded read() returns chunks, not entire frame
    # Create data larger than ZSTD_DStreamOutSize (~128KB)
    large_data = "A" * 500_000  # 500KB
    compressed = VibeZstd.compress(large_data, level: 5)

    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input)

    # First unbounded read should return a chunk, not entire frame
    first_chunk = reader.read
    refute_nil(first_chunk)
    assert(first_chunk.bytesize > 0, "First chunk should have data")
    assert(first_chunk.bytesize <= 200_000, "First chunk should be reasonably sized, not entire frame")

    # Should be able to read more chunks
    chunks = [first_chunk]
    while (chunk = reader.read)
      chunks << chunk
    end

    # Verify all chunks combine to original data
    decompressed = chunks.join
    assert_equal(large_data, decompressed)
    assert(chunks.size >= 2, "Large data should require multiple chunks")
  end

  def test_bounded_read_respects_size_limit
    # Test that bounded reads respect the size parameter
    data = "B" * 100_000  # 100KB
    compressed = VibeZstd.compress(data, level: 5)

    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input)

    # Read in 10KB chunks
    chunk_size = 10_000
    chunks = []
    while (chunk = reader.read(chunk_size))
      chunks << chunk
      assert(chunk.bytesize <= chunk_size, "Chunk should not exceed requested size")
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
    assert(chunks.size >= 10, "Should read multiple chunks")
  end

  def test_chunked_streaming_memory_safety
    # Verify that streaming doesn't buffer entire frame in memory
    # This is a behavioral test - unbounded reads should not grow exponentially
    data = "C" * 300_000  # 300KB
    compressed = VibeZstd.compress(data, level: 5)

    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input)

    # Collect all chunks
    chunks = []
    while (chunk = reader.read)
      chunks << chunk
      # Each chunk should be reasonably sized (not growing exponentially)
      assert(chunk.bytesize <= 200_000, "Chunk size should be bounded")
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
  end

  # Tests for configurable initial_chunk_size
  def test_default_chunk_size_behavior
    # Without initial_chunk_size option, should use ZSTD_DStreamOutSize() default
    data = "D" * 500_000  # 500KB
    compressed = VibeZstd.compress(data, level: 5)

    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input)

    # First unbounded read should return default chunk (~128KB)
    first_chunk = reader.read
    refute_nil(first_chunk)
    assert(first_chunk.bytesize > 0, "Should return data")
    assert(first_chunk.bytesize <= 200_000, "Should use default chunk size")

    # Verify we can read the rest
    chunks = [first_chunk]
    while (chunk = reader.read)
      chunks << chunk
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
  end

  def test_custom_initial_chunk_size
    # Test with custom 1MB chunk size
    data = "E" * 2_000_000  # 2MB
    compressed = VibeZstd.compress(data, level: 5)

    chunk_size = 1_048_576  # 1MB
    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input, initial_chunk_size: chunk_size)

    # First unbounded read should respect custom chunk size
    first_chunk = reader.read
    refute_nil(first_chunk)
    assert(first_chunk.bytesize > 0, "Should return data")

    # Collect all chunks
    chunks = [first_chunk]
    while (chunk = reader.read)
      chunks << chunk
      # Verify chunks don't exceed configured size
      assert(chunk.bytesize <= chunk_size, "Chunk should not exceed configured size")
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
  end

  def test_small_custom_chunk_size
    # Test with very small chunk size (e.g., for memory-constrained environments)
    data = "F" * 100_000  # 100KB
    compressed = VibeZstd.compress(data, level: 5)

    small_chunk = 4096  # 4KB chunks
    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input, initial_chunk_size: small_chunk)

    chunks = []
    while (chunk = reader.read)
      chunks << chunk
      # Chunks should be small
      assert(chunk.bytesize <= small_chunk, "Chunk should respect small size limit")
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
    # With 100KB data and 4KB chunks, we expect multiple chunks
    assert(chunks.size >= 10, "Small chunks should require multiple reads")
  end

  def test_large_custom_chunk_size
    # Test with large chunk size (e.g., for high-throughput scenarios)
    data = "G" * 5_000_000  # 5MB
    compressed = VibeZstd.compress(data, level: 5)

    large_chunk = 10_485_760  # 10MB
    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input, initial_chunk_size: large_chunk)

    chunks = []
    while (chunk = reader.read)
      chunks << chunk
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
  end

  def test_initial_chunk_size_zero_error
    # Test that initial_chunk_size: 0 raises an error
    compressed = VibeZstd.compress("test")
    input = StringIO.new(compressed)

    error = assert_raises(ArgumentError) do
      VibeZstd::DecompressReader.new(input, initial_chunk_size: 0)
    end
    assert_match(/must be greater than 0/i, error.message)
  end

  def test_initial_chunk_size_with_bounded_reads
    # Verify that initial_chunk_size doesn't affect explicitly sized reads
    data = "H" * 100_000
    compressed = VibeZstd.compress(data, level: 5)

    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input, initial_chunk_size: 1_048_576)

    # Explicitly request 5KB chunks - should override initial_chunk_size
    requested_size = 5000
    chunks = []
    while (chunk = reader.read(requested_size))
      chunks << chunk
      assert(chunk.bytesize <= requested_size, "Should respect explicit size request")
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
  end
end
