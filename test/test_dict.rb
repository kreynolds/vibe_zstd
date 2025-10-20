# frozen_string_literal: true

require "test_helper"

class TestDict < Minitest::Test
  # CDict and DDict construction and basic usage
  def test_dictionary_construction_and_usage
    dict_data = "dictionary"
    cdict = VibeZstd::CDict.new(dict_data)
    ddict = VibeZstd::DDict.new(dict_data)
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Test compression and decompression with dictionary
    data = "Hello, world! This is dictionary compressed data."
    compressed = cctx.compress(data, dict: cdict)
    decompressed = dctx.decompress(compressed, dict: ddict)
    assert_equal data, decompressed
  end

  def test_cdict_with_compression_level
    dict_data = "test dictionary"
    cdict = VibeZstd::CDict.new(dict_data, 5)
    ddict = VibeZstd::DDict.new(dict_data)

    data = "Test data with dictionary and compression level"
    compressed = VibeZstd.compress(data, dict: cdict)
    decompressed = VibeZstd.decompress(compressed, dict: ddict)
    assert_equal(data, decompressed)
  end

  # Utility methods
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

  def test_dictionary_ids_with_trained_dictionary
    # Create a trained dictionary which should have a non-zero ID
    samples = Array.new(50) { |i| "sample #{i} " * 10 }
    trained_dict = VibeZstd.train_dict(samples, max_dict_size: 1024)

    cdict = VibeZstd::CDict.new(trained_dict)
    ddict = VibeZstd::DDict.new(trained_dict)

    # Both should have the same non-zero ID
    cdict_id = cdict.dict_id
    ddict_id = ddict.dict_id

    assert(cdict_id > 0, "Trained dictionary should have non-zero ID")
    assert_equal(cdict_id, ddict_id, "CDict and DDict should have same ID")
  end

  # Memory estimation
  def test_cdict_memory_estimation
    dict_size = 1024
    cdict_mem = VibeZstd::CDict.estimate_memory(dict_size, 3)
    assert(cdict_mem > dict_size) # Should be larger than just the dict size
  end

  def test_ddict_memory_estimation
    dict_size = 1024
    ddict_mem = VibeZstd::DDict.estimate_memory(dict_size)
    assert(ddict_mem > dict_size) # Should be larger than just the dict size
  end

  # End-to-end dictionary usage
  def test_dictionary_compression_efficiency
    # Dictionary should improve compression for similar data
    dict_data = "common repeated pattern in data " * 10

    # Create dictionaries
    cdict = VibeZstd::CDict.new(dict_data, 3)
    ddict = VibeZstd::DDict.new(dict_data)

    # Test data that shares patterns with dictionary
    data = "common repeated pattern in data " * 5 + "some unique content"

    # Compress with and without dictionary
    compressed_with_dict = VibeZstd.compress(data, dict: cdict)
    compressed_without_dict = VibeZstd.compress(data)

    # Dictionary compression should be better for this data
    assert(compressed_with_dict.bytesize <= compressed_without_dict.bytesize,
      "Dictionary compression should be at least as good as regular compression")

    # Verify decompression works
    decompressed = VibeZstd.decompress(compressed_with_dict, dict: ddict)
    assert_equal(data, decompressed)
  end

  def test_trained_dictionary_usage
    # Create training samples with common patterns
    samples = []
    100.times do |i|
      samples << "sample data number #{i} with repeated patterns " * 3
    end

    # Train dictionary
    trained_dict = VibeZstd.train_dict(samples, max_dict_size: 2048)

    # Create CDict and DDict from trained dictionary
    cdict = VibeZstd::CDict.new(trained_dict)
    ddict = VibeZstd::DDict.new(trained_dict)

    # Test compression/decompression
    test_data = "sample data number 42 with repeated patterns " * 10
    compressed = VibeZstd.compress(test_data, dict: cdict)
    decompressed = VibeZstd.decompress(compressed, dict: ddict)

    assert_equal(test_data, decompressed)

    # Verify dictionary ID is embedded in frame
    frame_dict_id = VibeZstd.get_dict_id_from_frame(compressed)
    assert_equal(cdict.dict_id, frame_dict_id)
  end

  def test_multiple_dictionaries
    # Test that different dictionaries work independently
    dict_data_1 = "first dictionary content"
    dict_data_2 = "second dictionary content"

    cdict1 = VibeZstd::CDict.new(dict_data_1)
    ddict1 = VibeZstd::DDict.new(dict_data_1)

    cdict2 = VibeZstd::CDict.new(dict_data_2)
    ddict2 = VibeZstd::DDict.new(dict_data_2)

    data1 = "Test data for first dictionary"
    data2 = "Test data for second dictionary"

    # Compress with different dictionaries
    compressed1 = VibeZstd.compress(data1, dict: cdict1)
    compressed2 = VibeZstd.compress(data2, dict: cdict2)

    # Decompress with matching dictionaries
    decompressed1 = VibeZstd.decompress(compressed1, dict: ddict1)
    decompressed2 = VibeZstd.decompress(compressed2, dict: ddict2)

    assert_equal(data1, decompressed1)
    assert_equal(data2, decompressed2)
  end

  def test_dictionary_with_contexts
    # Test using dictionaries with CCtx and DCtx
    dict_data = "context dictionary data"
    cdict = VibeZstd::CDict.new(dict_data, 5)
    ddict = VibeZstd::DDict.new(dict_data)

    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    data = "Test using dictionary with contexts"
    compressed = cctx.compress(data, dict: cdict)
    decompressed = dctx.decompress(compressed, dict: ddict)

    assert_equal(data, decompressed)
  end

  def test_dictionary_size_method
    # Test that size() returns reasonable values
    small_dict = "small"
    large_dict = "x" * 1000

    cdict_small = VibeZstd::CDict.new(small_dict)
    cdict_large = VibeZstd::CDict.new(large_dict)

    # Larger dictionaries should have larger sizes
    assert(cdict_large.size > cdict_small.size,
      "Larger dictionary should have larger size")

    # Same for DDict
    ddict_small = VibeZstd::DDict.new(small_dict)
    ddict_large = VibeZstd::DDict.new(large_dict)

    assert(ddict_large.size > ddict_small.size,
      "Larger dictionary should have larger size")
  end
end
