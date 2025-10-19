# frozen_string_literal: true

require "test_helper"

class TestVibeZstd < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::VibeZstd::VERSION
  end

  def test_compress_decompress
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new
    data = "Hello, world! This is a test string for compression."
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal data, decompressed
  end

  def test_compress_with_level
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new
    data = "Hello, world! This is a test string for compression."
    compressed = cctx.compress(data, 5)
    decompressed = dctx.decompress(compressed)
    assert_equal data, decompressed
  end

  def test_dictionary
    dict_data = "dictionary"
    cdict = VibeZstd::CDict.new(dict_data)
    ddict = VibeZstd::DDict.new(dict_data)
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Test compression and decompression with dictionary
    data = "Hello, world! This is dictionary compressed data."
    compressed = cctx.compress(data, nil, cdict)
    decompressed = dctx.decompress(compressed, ddict)
    assert_equal data, decompressed
  end

  def test_convenience_methods
    data = "Hello, world! This is a test string for convenience methods."

    # Test basic compression/decompression
    compressed = VibeZstd.compress(data)
    decompressed = VibeZstd.decompress(compressed)
    assert_equal data, decompressed

    # Test with custom level
    compressed_level = VibeZstd.compress(data, level: 5)
    decompressed_level = VibeZstd.decompress(compressed_level)
    assert_equal data, decompressed_level

    # Test with dictionary
    dict_data = "dictionary"
    cdict = VibeZstd::CDict.new(dict_data)
    ddict = VibeZstd::DDict.new(dict_data)

    compressed_dict = VibeZstd.compress(data, dict: cdict)
    decompressed_dict = VibeZstd.decompress(compressed_dict, dict: ddict)
    assert_equal data, decompressed_dict
  end

  def test_streaming_compression
    require "stringio"

    data = "hello world! " * 1000
    output = StringIO.new

    writer = VibeZstd::Compress::Writer.new(output, level: 5)

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

  def test_streaming_decompression
    require "stringio"

    data = "hello world! " * 1000
    compressed = VibeZstd.compress(data, level: 5)

    input = StringIO.new(compressed)
    reader = VibeZstd::Decompress::Reader.new(input)

    # Read all at once
    decompressed = reader.read
    assert_equal(data, decompressed)
  end

  def test_streaming_with_dictionary
    require "stringio"

    dict_data = "hello world! "
    cdict = VibeZstd::CDict.new(dict_data, 3)
    ddict = VibeZstd::DDict.new(dict_data)

    data = "hello world! " * 1000
    output = StringIO.new

    # Compress with dictionary
    writer = VibeZstd::Compress::Writer.new(output, level: 5, dict: cdict)
    writer.write(data)
    writer.finish

    compressed = output.string

    # Decompress with dictionary
    input = StringIO.new(compressed)
    reader = VibeZstd::Decompress::Reader.new(input, dict: ddict)
    decompressed = reader.read

    assert_equal(data, decompressed)
  end

  def test_streaming_read_in_chunks
    require "stringio"

    data = "hello world! " * 100
    compressed = VibeZstd.compress(data)

    input = StringIO.new(compressed)
    reader = VibeZstd::Decompress::Reader.new(input)

    # Read in small chunks and collect
    chunks = []
    while chunk = reader.read(50)
      chunks << chunk
      break if chunks.size > 100  # Safety limit to prevent infinite loop
    end

    decompressed = chunks.join
    assert_equal(data, decompressed)
  end

  def test_dictionary_training
    # Create training samples
    samples = []
    100.times do |i|
      samples << ("sample data number #{i} with repeated patterns " * 3)
    end

    # Train dictionary
    dict_data = VibeZstd.train_dict(samples, max_dict_size: 2048)

    # Verify dictionary was created
    refute_nil(dict_data)
    assert(dict_data.bytesize > 0)
    assert(dict_data.bytesize <= 2048)

    # Verify dictionary can be used for compression/decompression
    cdict = VibeZstd::CDict.new(dict_data)
    ddict = VibeZstd::DDict.new(dict_data)

    test_data = "sample data number 42 with repeated patterns " * 10
    compressed = VibeZstd.compress(test_data, dict: cdict)
    decompressed = VibeZstd.decompress(compressed, dict: ddict)

    assert_equal(test_data, decompressed)
  end

  def test_dictionary_training_with_default_size
    # Test training with default max_dict_size
    samples = Array.new(50) { |i| "pattern #{i} " * 20 }

    dict_data = VibeZstd.train_dict(samples)

    refute_nil(dict_data)
    assert(dict_data.bytesize > 0)
  end

  def test_get_dict_id
    # Get ID from raw dictionary data (should be 0 for raw content)
    dict_data = "test dictionary content"
    dict_id = VibeZstd.get_dict_id(dict_data)
    assert_equal(0, dict_id)

    # Train a dictionary and get its ID
    samples = Array.new(50) { |i| "sample #{i} " * 10 }
    trained_dict = VibeZstd.train_dict(samples, max_dict_size: 1024)
    trained_id = VibeZstd.get_dict_id(trained_dict)

    # Trained dictionaries should have non-zero IDs
    refute_equal(0, trained_id)

    # Verify the ID matches what we get from CDict and DDict
    cdict_trained = VibeZstd::CDict.new(trained_dict)
    ddict_trained = VibeZstd::DDict.new(trained_dict)

    assert_equal(trained_id, cdict_trained.dict_id)
    assert_equal(trained_id, ddict_trained.dict_id)
  end

  def test_dictionary_utility_methods
    # Test CDict utility methods
    dict_data = "test dictionary"
    cdict = VibeZstd::CDict.new(dict_data, 3)

    size = cdict.size
    assert(size > 0)

    dict_id = cdict.dict_id
    assert_equal(0, dict_id) # Raw content has ID 0

    # Test DDict utility methods
    ddict = VibeZstd::DDict.new(dict_data)

    ddict_size = ddict.size
    assert(ddict_size > 0)

    ddict_id = ddict.dict_id
    assert_equal(0, ddict_id)
  end
end
