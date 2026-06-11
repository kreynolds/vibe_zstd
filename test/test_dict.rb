# frozen_string_literal: true

require "test_helper"
require "stringio"

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

  # Regression: a dictionary-compressed frame with unknown content size must be
  # decompressable via one-shot #decompress when the matching dict is supplied.
  # CompressWriter never pledges a size, so every frame it produces has unknown
  # content size and took the streaming decompress path, which previously failed
  # to reference the dictionary and raised "Dictionary mismatch".
  def test_decompress_dict_frame_with_unknown_content_size
    srand(7)
    samples = (1..600).map do |i|
      %({"user_id":#{i},"name":"user#{i}","active":#{i.even?},"role":"member"}).b
    end
    dict_raw = VibeZstd.train_dict(samples, max_dict_size: 16 * 1024)
    cdict = VibeZstd::CDict.new(dict_raw, 10)
    ddict = cdict.to_ddict

    payload = %({"user_id":999,"name":"user999","active":true,"role":"member"}).b

    io = StringIO.new(+"".b)
    VibeZstd::CompressWriter.open(io, level: 10, dict: cdict) { |w| w.write(payload) }
    compressed = io.string

    # Sanity: frame really does have unknown content size and requires the dict.
    assert_nil VibeZstd.frame_content_size(compressed)
    assert_equal cdict.dict_id, VibeZstd.get_dict_id_from_frame(compressed)

    out = VibeZstd::DCtx.new.decompress(compressed, dict: ddict)
    assert_equal payload, out
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

  # Regression: samples that respond to to_str (but are not Strings) must be
  # accepted and produce a valid dictionary.  Previously StringValue(sample)
  # updated only the C local, so copy_samples_to_buffer re-fetched the raw
  # non-String element and called RSTRING_PTR on it → memory corruption/segfault.
  def test_train_dict_with_to_str_samples
    # Build a custom object whose to_str returns a real String.
    to_str_obj = Object.new
    base = "sample data with repeated patterns for dictionary training " * 3
    to_str_obj.define_singleton_method(:to_str) { base.dup }

    # Mix it in with plain Strings so we have enough varied samples.
    samples = Array.new(50) { |i| "sample #{i} with common pattern " * 4 }
    samples[10] = to_str_obj

    # Must not crash; must return a String (the trained dictionary).
    result = VibeZstd.train_dict(samples, max_dict_size: 2048)
    assert_instance_of(String, result)
    assert(result.bytesize > 0)
  end

  # Regression: a malicious to_str that mutates another sample in the array
  # must not cause a heap overflow.  The fix records converted Strings in a
  # private array during validation, so later mutation of the caller's array
  # is invisible to copy_samples_to_buffer.  Any size mismatch detected at
  # copy time raises RuntimeError.  Either outcome (clean success on the
  # originally-converted data, or RuntimeError) is acceptable; a crash is not.
  def test_train_dict_with_mutating_to_str_samples
    samples = Array.new(50) { |i| "sample #{i} with common pattern " * 4 }

    # This object's to_str side-effects samples[0] by appending 1 MB to it,
    # making total_samples_size stale if copy_samples_to_buffer sees the
    # grown string.  With the fix, samples[0] in the private converted array
    # still holds the original (short) string captured during validation.
    mutator = Object.new
    mutator.define_singleton_method(:to_str) do
      samples[0] = samples[0] + ("x" * (1024 * 1024))
      "mutator sample with common pattern " * 4
    end
    samples[25] = mutator

    begin
      result = VibeZstd.train_dict(samples, max_dict_size: 2048)
      # If training succeeds it must return a String (trained on converted data).
      assert_instance_of(String, result)
    rescue RuntimeError, ArgumentError
      # A clean Ruby error is also acceptable (e.g. if ZDICT rejects the data).
      pass
    end
    # The key assertion is implicit: reaching this line without a crash means
    # no heap overflow occurred.
  end
end
