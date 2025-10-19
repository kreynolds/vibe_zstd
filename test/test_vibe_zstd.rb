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
    compressed = cctx.compress(data, level: 5)
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
    compressed = cctx.compress(data, dict: cdict)
    decompressed = dctx.decompress(compressed, dict: ddict)
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

  def test_streaming_decompression
    require "stringio"

    data = "hello world! " * 1000
    compressed = VibeZstd.compress(data, level: 5)

    input = StringIO.new(compressed)
    reader = VibeZstd::DecompressReader.new(input)

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

  def test_streaming_read_in_chunks
    require "stringio"

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

  def test_set_parameter_checksum
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Enable checksum
    cctx.checksum_flag = 1

    data = "Hello, world! This is a test with checksum."
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
  end

  def test_set_parameter_content_size
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Enable content size in frame
    cctx.content_size_flag = 1

    data = "Hello, world! This is a test with content size."
    compressed = cctx.compress(data)

    # Verify we can read the content size from the frame
    size = VibeZstd.frame_content_size(compressed)
    assert_equal(data.bytesize, size)

    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_set_parameter_window_log
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set window log to 10 (1KB window)
    cctx.window_log = 10

    data = "Small data for small window"
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
  end

  def test_set_parameter_compression_level
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set compression level via setter
    cctx.compression_level = 9

    data = "Test data for compression level parameter"
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
  end

  def test_set_parameter_method_chaining
    # Test keyword argument initialization
    cctx = VibeZstd::CCtx.new(checksum_flag: 1, content_size_flag: 1)
    dctx = VibeZstd::DCtx.new

    data = "Test data for method chaining"
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
  end

  def test_pledged_source_size
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    data = "Test data for pledged source size"

    # Compress with pledged source size
    cctx.content_size_flag = 1
    compressed = cctx.compress(data, pledged_size: data.bytesize)

    # Verify content size was set
    size = VibeZstd.frame_content_size(compressed)
    assert_equal(data.bytesize, size)

    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_streaming_with_pledged_size
    require "stringio"

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

  def test_compress_bound
    # Test that compress_bound returns reasonable values
    data_size = 1000
    bound = VibeZstd.compress_bound(data_size)

    # Bound should be at least as large as the data
    assert(bound >= data_size)

    # Bound should be reasonable (not absurdly large)
    assert(bound < data_size * 2)

    # Test with actual compression
    data = "x" * data_size
    compressed = VibeZstd.compress(data)

    # Compressed size should be within bound
    assert(compressed.bytesize <= bound)
  end

  def test_get_dict_id_from_frame
    # Create a trained dictionary
    samples = Array.new(50) { |i| "sample #{i} " * 10 }
    trained_dict = VibeZstd.train_dict(samples, max_dict_size: 1024)

    # Get the dictionary ID
    expected_dict_id = VibeZstd.get_dict_id(trained_dict)
    assert(expected_dict_id > 0)

    # Compress data with this dictionary
    cdict = VibeZstd::CDict.new(trained_dict)
    data = "sample 42 " * 10
    compressed = VibeZstd.compress(data, dict: cdict)

    # Get dict ID from the compressed frame
    frame_dict_id = VibeZstd.get_dict_id_from_frame(compressed)
    assert_equal(expected_dict_id, frame_dict_id)
  end

  def test_get_dict_id_from_frame_without_dict
    # Compress without dictionary
    data = "test data without dictionary"
    compressed = VibeZstd.compress(data)

    # Should return 0 for no dictionary
    dict_id = VibeZstd.get_dict_id_from_frame(compressed)
    assert_equal(0, dict_id)
  end

  def test_prefix_dictionaries
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Use a shared prefix for compression and decompression
    prefix = "This is a shared prefix that contains common patterns " * 10

    # Set prefix on both contexts
    cctx.use_prefix(prefix)
    dctx.use_prefix(prefix)

    # Compress and decompress data that shares patterns with the prefix
    data = "This is a shared prefix that we want to compress efficiently"
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
  end

  def test_memory_estimation
    # Test CCtx memory estimation
    cctx_mem = VibeZstd::CCtx.estimate_memory(3)
    assert(cctx_mem > 0)
    assert(cctx_mem > 10_000) # Should be at least 10KB

    # Higher levels should use more memory
    cctx_mem_high = VibeZstd::CCtx.estimate_memory(19)
    assert(cctx_mem_high > cctx_mem)

    # Test DCtx memory estimation
    dctx_mem = VibeZstd::DCtx.estimate_memory
    assert(dctx_mem > 0)
    assert(dctx_mem > 10_000) # Should be at least 10KB

    # Test CDict memory estimation
    dict_size = 1024
    cdict_mem = VibeZstd::CDict.estimate_memory(dict_size, 3)
    assert(cdict_mem > dict_size) # Should be larger than just the dict size

    # Test DDict memory estimation
    ddict_mem = VibeZstd::DDict.estimate_memory(dict_size)
    assert(ddict_mem > dict_size) # Should be larger than just the dict size
  end

  def test_dctx_set_parameter_window_log_max
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set a small window on decompression context
    dctx.window_log_max = 10

    # Compress with matching window
    cctx.window_log = 10
    data = "Small data for small window"
    compressed = cctx.compress(data)

    # Should decompress successfully
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_negative_compression_levels
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Test ultra-fast compression with negative level
    data = "Test data for negative compression level " * 100

    # Test level -1 (fastest)
    compressed_neg1 = cctx.compress(data, level: -1)
    decompressed = dctx.decompress(compressed_neg1)
    assert_equal(data, decompressed)

    # Test level -5 (very fast)
    compressed_neg5 = cctx.compress(data, level: -5)
    decompressed = dctx.decompress(compressed_neg5)
    assert_equal(data, decompressed)

    # Verify negative levels produce valid compressed data
    assert(compressed_neg1.bytesize > 0)
    assert(compressed_neg5.bytesize > 0)
  end

  def test_train_dict_cover
    # Create training samples
    samples = []
    100.times do |i|
      samples << ("sample data number #{i} with repeated patterns " * 3)
    end

    # Train dictionary with COVER algorithm (k and d are required)
    dict_data = VibeZstd.train_dict_cover(samples, max_dict_size: 2048, k: 200, d: 6)

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

  def test_train_dict_fast_cover
    # Create training samples
    samples = []
    50.times do |i|
      samples << ("fast sample #{i} with patterns " * 5)
    end

    # Train dictionary with fast COVER algorithm
    dict_data = VibeZstd.train_dict_fast_cover(samples, max_dict_size: 1024, k: 200, d: 6)

    # Verify dictionary was created
    refute_nil(dict_data)
    assert(dict_data.bytesize > 0)
    assert(dict_data.bytesize <= 1024)

    # Verify dictionary can be used
    cdict = VibeZstd::CDict.new(dict_data)
    ddict = VibeZstd::DDict.new(dict_data)

    test_data = "fast sample 10 with patterns " * 20
    compressed = VibeZstd.compress(test_data, dict: cdict)
    decompressed = VibeZstd.decompress(compressed, dict: ddict)

    assert_equal(test_data, decompressed)
  end

  def test_cctx_get_parameter
    cctx = VibeZstd::CCtx.new

    # Set a parameter and verify we can read it back
    cctx.compression_level = 9
    level = cctx.compression_level
    assert_equal(9, level)

    # Test window_log
    cctx.window_log = 20
    window_log = cctx.window_log
    assert_equal(20, window_log)

    # Test checksum_flag (returns boolean)
    cctx.checksum_flag = 1
    checksum = cctx.checksum_flag
    assert_equal(true, checksum)
  end

  def test_dctx_get_parameter
    dctx = VibeZstd::DCtx.new

    # Set window_log_max and verify we can read it back
    dctx.window_log_max = 20
    window_log_max = dctx.window_log_max
    assert_equal(20, window_log_max)
  end

  # Tests for new compression parameters

  def test_search_log_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set searchLog and verify
    cctx.search_log = 5
    assert_equal(5, cctx.search_log)

    # Test compression with search_log
    data = "Test data for searchLog parameter " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_min_match_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set minMatch and verify
    cctx.min_match = 4
    assert_equal(4, cctx.min_match)

    # Test compression with min_match
    data = "Test data for minMatch parameter " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_target_length_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set targetLength and verify
    cctx.target_length = 16
    assert_equal(16, cctx.target_length)

    # Test compression with target_length
    data = "Test data for targetLength parameter " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_target_cblock_size_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set targetCBlockSize and verify (important for low-latency streaming)
    # Note: zstd may clamp this value to a minimum bound (ZSTD_TARGETCBLOCKSIZE_MIN)
    cctx.target_cblock_size = 2048
    value = cctx.target_cblock_size
    # Value should be at least what we set or the minimum bound
    assert(value >= 1024, "targetCBlockSize should be >= 1024, got #{value}")

    # Test compression with targetCBlockSize
    data = "Test data for targetCBlockSize parameter " * 100
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_long_distance_matching
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Enable LDM and verify
    cctx.enable_long_distance_matching = 1
    assert_equal(true, cctx.enable_long_distance_matching)

    # Test with large data to benefit from LDM
    pattern = "This is a repeating pattern that appears multiple times. " * 20
    data = (pattern * 100) + ("Some unique data in the middle. " * 50) + (pattern * 100)

    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)

    # LDM should improve compression ratio for this type of data
    assert(compressed.bytesize < data.bytesize)
  end

  def test_ldm_hash_log_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Enable LDM first
    cctx.enable_long_distance_matching = 1

    # Set ldmHashLog and verify
    cctx.ldm_hash_log = 20
    assert_equal(20, cctx.ldm_hash_log)

    # Test compression
    data = ("Repeating pattern for LDM " * 50) * 20
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_ldm_min_match_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Enable LDM first
    cctx.enable_long_distance_matching = 1

    # Set ldmMinMatch and verify
    cctx.ldm_min_match = 64
    assert_equal(64, cctx.ldm_min_match)

    # Test compression
    data = ("Repeating pattern for LDM min match " * 50) * 20
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_ldm_bucket_size_log_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Enable LDM first
    cctx.enable_long_distance_matching = 1

    # Set ldmBucketSizeLog and verify
    cctx.ldm_bucket_size_log = 3
    assert_equal(3, cctx.ldm_bucket_size_log)

    # Test compression
    data = "Test data for LDM bucket size " * 200
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_ldm_hash_rate_log_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Enable LDM first
    cctx.enable_long_distance_matching = 1

    # Set ldmHashRateLog and verify
    cctx.ldm_hash_rate_log = 5
    assert_equal(5, cctx.ldm_hash_rate_log)

    # Test compression
    data = "Test data for LDM hash rate " * 200
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_job_size_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set nbWorkers first (required for jobSize to have effect)
    cctx.nb_workers = 2

    # Set jobSize and verify
    cctx.job_size = 1048576 # 1MB
    assert_equal(1048576, cctx.job_size)

    # Test compression with multi-threading
    data = "Test data for multi-threaded compression with job size " * 1000
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_overlap_log_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set nbWorkers first (required for overlapLog to have effect)
    cctx.nb_workers = 2

    # Set overlapLog and verify
    cctx.overlap_log = 5
    assert_equal(5, cctx.overlap_log)

    # Test compression with multi-threading and overlap
    data = "Test data for multi-threaded compression with overlap " * 1000
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_parameter_name_variants
    cctx = VibeZstd::CCtx.new

    # Test both snake_case and camelCase work for new parameters
    cctx.search_log = 4
    assert_equal(4, cctx.search_log)

    cctx.min_match = 5
    assert_equal(5, cctx.min_match)

    cctx.target_length = 32
    assert_equal(32, cctx.target_length)

    cctx.enable_long_distance_matching = 1
    assert_equal(true, cctx.enable_long_distance_matching)
  end

  def test_ldm_comprehensive
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Configure full LDM setup
    cctx.enable_long_distance_matching = 1
    cctx.ldm_hash_log = 20
    cctx.ldm_min_match = 64
    cctx.ldm_bucket_size_log = 3
    cctx.ldm_hash_rate_log = 6

    # Create data with long-distance repetition
    base_pattern = "This is a base pattern that will repeat. " * 100
    middle_content = "Unique middle content. " * 200
    data = base_pattern + middle_content + base_pattern

    compressed = cctx.compress(data, level: 9) # High compression level
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
    # LDM should provide good compression for this pattern
    compression_ratio = data.bytesize.to_f / compressed.bytesize
    assert(compression_ratio > 2.0, "Expected compression ratio > 2.0, got #{compression_ratio}")
  end

  # Tests for parameter bounds API

  def test_cctx_parameter_bounds_compression_level
    bounds = VibeZstd::CCtx.parameter_bounds(:compression_level)

    assert_instance_of(Hash, bounds)
    assert(bounds.key?(:min))
    assert(bounds.key?(:max))
    # Compression level should support negative levels
    assert(bounds[:min] < 0, "Min compression level should be negative")
    assert(bounds[:max] >= 22, "Max compression level should be at least 22")
  end

  def test_cctx_parameter_bounds_window_log
    bounds = VibeZstd::CCtx.parameter_bounds(:window_log)

    assert_instance_of(Hash, bounds)
    assert_equal(2, bounds.size)
    # Window log typically ranges from 10 to 31
    assert(bounds[:min] >= 10)
    assert(bounds[:max] <= 31)
  end

  def test_cctx_parameter_bounds_all_parameters
    # Test that bounds work for all parameters
    parameters = [
      :compression_level, :window_log, :hash_log, :chain_log, :search_log,
      :min_match, :target_length, :strategy, :target_cblock_size,
      :enable_long_distance_matching, :ldm_hash_log, :ldm_min_match,
      :ldm_bucket_size_log, :ldm_hash_rate_log,
      :content_size_flag, :checksum_flag, :dict_id_flag,
      :nb_workers, :job_size, :overlap_log
    ]

    parameters.each do |param|
      bounds = VibeZstd::CCtx.parameter_bounds(param)
      assert_instance_of(Hash, bounds, "Failed for parameter #{param}")
      assert(bounds.key?(:min), "Missing :min for #{param}")
      assert(bounds.key?(:max), "Missing :max for #{param}")
      assert_instance_of(Integer, bounds[:min], "Non-integer :min for #{param}")
      assert_instance_of(Integer, bounds[:max], "Non-integer :max for #{param}")
      assert(bounds[:min] <= bounds[:max], "Invalid bounds for #{param}")
    end
  end

  def test_cctx_parameter_bounds_snake_case
    # Test that snake_case works
    bounds1 = VibeZstd::CCtx.parameter_bounds(:compression_level)
    bounds2 = VibeZstd::CCtx.parameter_bounds(:compression_level)

    assert_equal(bounds1[:min], bounds2[:min])
    assert_equal(bounds1[:max], bounds2[:max])
  end

  def test_cctx_parameter_bounds_invalid_parameter
    assert_raises(ArgumentError) do
      VibeZstd::CCtx.parameter_bounds(:invalidParameter)
    end
  end

  def test_dctx_parameter_bounds_window_log_max
    bounds = VibeZstd::DCtx.parameter_bounds(:window_log_max)

    assert_instance_of(Hash, bounds)
    assert(bounds.key?(:min))
    assert(bounds.key?(:max))
    assert(bounds[:min] >= 10)
    assert(bounds[:max] <= 31)
  end

  def test_dctx_parameter_bounds_snake_case
    # Test that snake_case works
    bounds1 = VibeZstd::DCtx.parameter_bounds(:window_log_max)
    bounds2 = VibeZstd::DCtx.parameter_bounds(:window_log_max)

    assert_equal(bounds1[:min], bounds2[:min])
    assert_equal(bounds1[:max], bounds2[:max])
  end

  def test_parameter_bounds_practical_usage
    # Test practical use case: validating parameter before setting
    cctx = VibeZstd::CCtx.new

    bounds = VibeZstd::CCtx.parameter_bounds(:window_log)

    # Set to min and max bounds
    cctx.window_log = bounds[:min]
    assert_equal(bounds[:min], cctx.window_log)

    cctx.window_log = bounds[:max]
    assert_equal(bounds[:max], cctx.window_log)
  end

  # Tests for experimental parameters
  def test_rsyncable_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    cctx.rsyncable = 1
    assert_equal(true, cctx.rsyncable)

    data = "Test data for rsyncable parameter " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_format_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Test magicless format (ZSTD_f_zstd1_magicless = 1)
    cctx.format = 1
    assert_equal(1, cctx.format)

    data = "Test data for format parameter " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_force_max_window_parameter
    cctx = VibeZstd::CCtx.new

    cctx.force_max_window = 1
    assert_equal(true, cctx.force_max_window)
  end

  def test_force_attach_dict_parameter
    cctx = VibeZstd::CCtx.new

    # ZSTD_dictDefaultAttach = 0, ZSTD_dictForceAttach = 1, ZSTD_dictForceCopy = 2
    cctx.force_attach_dict = 0
    assert_equal(0, cctx.force_attach_dict)
  end

  def test_literal_compression_mode_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # ZSTD_ps_auto = 0, ZSTD_ps_enable = 1, ZSTD_ps_disable = 2
    cctx.literal_compression_mode = 1
    assert_equal(1, cctx.literal_compression_mode)

    data = "Test data for literal compression mode " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_src_size_hint_parameter
    cctx = VibeZstd::CCtx.new

    # Provide hint about source size
    cctx.src_size_hint = 10000
    assert_equal(10000, cctx.src_size_hint)
  end

  def test_enable_dedicated_dict_search_parameter
    cctx = VibeZstd::CCtx.new

    cctx.enable_dedicated_dict_search = 1
    assert_equal(true, cctx.enable_dedicated_dict_search)
  end

  def test_stable_in_buffer_parameter
    cctx = VibeZstd::CCtx.new

    cctx.stable_in_buffer = 1
    assert_equal(true, cctx.stable_in_buffer)
  end

  def test_stable_out_buffer_parameter
    cctx = VibeZstd::CCtx.new

    cctx.stable_out_buffer = 1
    assert_equal(true, cctx.stable_out_buffer)
  end

  def test_block_delimiters_parameter
    cctx = VibeZstd::CCtx.new

    cctx.block_delimiters = 1
    assert_equal(true, cctx.block_delimiters)
  end

  def test_validate_sequences_parameter
    cctx = VibeZstd::CCtx.new

    cctx.validate_sequences = 1
    assert_equal(true, cctx.validate_sequences)
  end

  def test_use_row_match_finder_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # ZSTD_urm_auto = 0, ZSTD_urm_disableRowMatchFinder = 1, ZSTD_urm_enableRowMatchFinder = 2
    cctx.use_row_match_finder = 2
    assert_equal(2, cctx.use_row_match_finder)

    data = "Test data for row match finder " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_deterministic_ref_prefix_parameter
    cctx = VibeZstd::CCtx.new

    cctx.deterministic_ref_prefix = 1
    assert_equal(true, cctx.deterministic_ref_prefix)
  end

  def test_prefetch_cdict_tables_parameter
    cctx = VibeZstd::CCtx.new

    # ZSTD_ps_auto = 0, ZSTD_ps_enable = 1, ZSTD_ps_disable = 2
    cctx.prefetch_cdict_tables = 1
    assert_equal(1, cctx.prefetch_cdict_tables)
  end

  def test_enable_seq_producer_fallback_parameter
    cctx = VibeZstd::CCtx.new

    cctx.enable_seq_producer_fallback = 1
    assert_equal(true, cctx.enable_seq_producer_fallback)
  end

  def test_max_block_size_parameter
    cctx = VibeZstd::CCtx.new

    cctx.max_block_size = 131072
    assert_equal(131072, cctx.max_block_size)
  end

  def test_search_for_external_repcodes_parameter
    cctx = VibeZstd::CCtx.new

    # ZSTD_ps_auto = 0, ZSTD_ps_enable = 1, ZSTD_ps_disable = 2
    cctx.search_for_external_repcodes = 1
    assert_equal(1, cctx.search_for_external_repcodes)
  end

  def test_experimental_parameter_name_variants
    cctx = VibeZstd::CCtx.new

    # Test both snake_case and camelCase work for experimental parameters
    cctx.force_max_window = 1
    assert_equal(true, cctx.force_max_window)

    cctx.src_size_hint = 5000
    assert_equal(5000, cctx.src_size_hint)

    cctx.literal_compression_mode = 2
    assert_equal(2, cctx.literal_compression_mode)
  end

  def test_experimental_parameter_bounds
    # Test that bounds work for experimental parameters
    bounds = VibeZstd::CCtx.parameter_bounds(:rsyncable)
    assert_kind_of(Hash, bounds)
    assert(bounds.key?(:min))
    assert(bounds.key?(:max))

    bounds = VibeZstd::CCtx.parameter_bounds(:format)
    assert_kind_of(Hash, bounds)

    bounds = VibeZstd::CCtx.parameter_bounds(:literal_compression_mode)
    assert_kind_of(Hash, bounds)
  end

  # Tests for idiomatic Ruby boolean API (items #1 and #9 from PLAN.md)
  def test_boolean_api_with_ruby_booleans
    cctx = VibeZstd::CCtx.new

    # Test setting with Ruby true/false
    cctx.checksum = true
    assert_equal(true, cctx.checksum)
    assert_equal(true, cctx.checksum?)

    cctx.checksum = false
    assert_equal(false, cctx.checksum)
    assert_equal(false, cctx.checksum?)

    # Test content_size alias
    cctx.content_size = true
    assert_equal(true, cctx.content_size)
    assert_equal(true, cctx.content_size?)
    assert_equal(true, cctx.content_size_flag)

    # Test dict_id alias
    cctx.dict_id = false
    assert_equal(false, cctx.dict_id)
    assert_equal(false, cctx.dict_id?)
    assert_equal(false, cctx.dict_id_flag)
  end

  def test_boolean_api_predicate_methods
    cctx = VibeZstd::CCtx.new

    # Test predicate methods for various boolean parameters
    cctx.rsyncable = true
    assert(cctx.rsyncable?)

    cctx.force_max_window = true
    assert(cctx.force_max_window?)

    cctx.stable_in_buffer = false
    refute(cctx.stable_in_buffer?)

    cctx.long_distance_matching = true
    assert(cctx.long_distance_matching?)
    assert(cctx.enable_long_distance_matching)
  end

  def test_boolean_api_backward_compatibility
    cctx = VibeZstd::CCtx.new

    # Old integer API still works
    cctx.checksum_flag = 1
    assert_equal(true, cctx.checksum_flag)
    assert_equal(true, cctx.checksum)

    cctx.checksum_flag = 0
    assert_equal(false, cctx.checksum_flag)
    assert_equal(false, cctx.checksum)

    # Can still use integers with new names
    cctx.checksum = 1
    assert_equal(true, cctx.checksum)

    cctx.checksum = 0
    assert_equal(false, cctx.checksum)
  end

  def test_boolean_api_in_compression
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Use boolean API in actual compression
    cctx.checksum = true
    cctx.content_size = true

    data = "Test data with idiomatic Ruby boolean API"
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)

    # Verify content size was set
    size = VibeZstd.frame_content_size(compressed)
    assert_equal(data.bytesize, size)
  end

  # Tests for convenient aliases (item #6 from PLAN.md)
  def test_level_alias
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Test short form
    cctx.level = 9
    assert_equal(9, cctx.level)
    assert_equal(9, cctx.compression_level)

    # Test compression works with alias
    data = "Test data for level alias " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_workers_alias
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Test natural English alias
    cctx.workers = 4
    assert_equal(4, cctx.workers)
    assert_equal(4, cctx.nb_workers)

    # Test compression works with alias
    data = "Test data for workers alias " * 100
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_max_window_log_alias
    dctx = VibeZstd::DCtx.new
    cctx = VibeZstd::CCtx.new

    # Test more natural ordering
    dctx.max_window_log = 20
    assert_equal(20, dctx.max_window_log)
    assert_equal(20, dctx.window_log_max)

    # Test decompression works with alias
    cctx.window_log = 20
    data = "Test data for max_window_log alias"
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_all_aliases_together
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Use all aliases together
    cctx.level = 7
    cctx.workers = 2
    dctx.max_window_log = 25

    data = "Test all convenient aliases together " * 200

    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)

    # Verify aliases still work for reading
    assert_equal(7, cctx.level)
    assert_equal(2, cctx.workers)
    assert_equal(25, dctx.max_window_log)
  end

  # Tests for block-based resource management (item #5 from PLAN.md)
  def test_writer_open_with_block
    require "stringio"

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
    require "stringio"

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
    require "stringio"

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
    require "stringio"

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
    require "stringio"

    data = "Test data for non-block Reader.open"
    compressed = VibeZstd.compress(data)
    input = StringIO.new(compressed)

    # Without block, returns reader
    reader = VibeZstd::DecompressReader.open(input)
    decompressed = reader.read

    assert_equal(data, decompressed)
  end

  def test_writer_open_with_dictionary
    require "stringio"

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

  # Tests for library version information (item 1 from PLAN.md)
  def test_version_number
    version = VibeZstd.version_number
    assert_kind_of(Integer, version)
    assert(version > 0, "Version number should be positive")
    # Version number format: MMmmpp (major, minor, patch)
    # Example: 10507 for version 1.5.7
    assert(version >= 10000, "Version should be at least 1.0.0")
  end

  def test_version_string
    version_string = VibeZstd.version_string
    assert_kind_of(String, version_string)
    refute_empty(version_string)
    # Should match format like "1.5.7"
    assert_match(/\d+\.\d+\.\d+/, version_string)
  end

  def test_version_consistency
    # Version number and string should be consistent
    version_num = VibeZstd.version_number
    version_str = VibeZstd.version_string

    # Parse version string to check consistency
    parts = version_str.split(".").map(&:to_i)
    expected_num = parts[0] * 10000 + parts[1] * 100 + parts[2]

    assert_equal(expected_num, version_num,
      "Version number #{version_num} should match version string #{version_str}")
  end

  def test_min_compression_level
    min_level = VibeZstd.min_compression_level
    assert_kind_of(Integer, min_level)
    # Should support negative levels (ultra-fast)
    assert(min_level < 0, "Min compression level should be negative")
    # Typically around -131072 or similar
    assert(min_level < -1, "Min compression level should be significantly negative")
  end

  def test_max_compression_level
    max_level = VibeZstd.max_compression_level
    assert_kind_of(Integer, max_level)
    # Should be at least 22
    assert(max_level >= 22, "Max compression level should be at least 22")
  end

  def test_default_compression_level
    default_level = VibeZstd.default_compression_level
    assert_kind_of(Integer, default_level)
    # Default is typically 3
    assert(default_level >= 1, "Default level should be at least 1")
    assert(default_level <= 10, "Default level should be reasonable (<=10)")
  end

  def test_compression_level_bounds
    min_level = VibeZstd.min_compression_level
    max_level = VibeZstd.max_compression_level
    default_level = VibeZstd.default_compression_level

    # Verify bounds make sense
    assert(min_level < default_level, "Min should be less than default")
    assert(default_level < max_level, "Default should be less than max")
  end

  def test_compression_level_aliases
    # Test short-form aliases
    assert_equal(VibeZstd.min_compression_level, VibeZstd.min_level)
    assert_equal(VibeZstd.max_compression_level, VibeZstd.max_level)
    assert_equal(VibeZstd.default_compression_level, VibeZstd.default_level)
  end

  def test_use_version_info_for_validation
    # Practical use case: validate compression levels
    min_level = VibeZstd.min_level
    max_level = VibeZstd.max_level

    cctx = VibeZstd::CCtx.new
    data = "Test data for level validation"

    # Test with min level
    compressed_min = cctx.compress(data, level: min_level)
    assert(compressed_min.bytesize > 0)

    # Test with max level
    compressed_max = cctx.compress(data, level: max_level)
    assert(compressed_max.bytesize > 0)

    # Verify both decompress correctly
    dctx = VibeZstd::DCtx.new
    assert_equal(data, dctx.decompress(compressed_min))
    assert_equal(data, dctx.decompress(compressed_max))
  end

  def test_use_version_info_for_feature_detection
    # Practical use case: feature detection based on version
    version = VibeZstd.version_number

    # All versions >= 1.3.0 should support basic features
    if version >= 10300
      # Test that basic compression works
      data = "Test feature detection"
      compressed = VibeZstd.compress(data)
      decompressed = VibeZstd.decompress(compressed)
      assert_equal(data, decompressed)
    end
  end

  def test_version_info_in_error_messages
    # Practical use case: include version in error/debug info
    version_info = "zstd #{VibeZstd.version_string} (#{VibeZstd.version_number})"

    assert_match(/zstd \d+\.\d+\.\d+ \(\d+\)/, version_info)
  end

  def test_cctx_reset_session_only
    cctx = VibeZstd::CCtx.new
    cctx.compression_level = 9
    cctx.checksum_flag = true

    data1 = "First compression with level 9 and checksum"
    compressed1 = cctx.compress(data1)

    # Reset session only - should keep parameters (level=9, checksum=true)
    cctx.reset(VibeZstd::ResetDirective::SESSION)

    data2 = "Second compression should keep level 9 and checksum"
    compressed2 = cctx.compress(data2)

    # Verify both decompress correctly
    dctx = VibeZstd::DCtx.new
    assert_equal(data1, dctx.decompress(compressed1))
    assert_equal(data2, dctx.decompress(compressed2))

    # Verify parameters were retained
    assert_equal(9, cctx.compression_level)
    assert_equal(true, cctx.checksum_flag)
  end

  def test_cctx_reset_parameters
    cctx = VibeZstd::CCtx.new
    cctx.compression_level = 9
    cctx.checksum_flag = true

    # Reset parameters to defaults
    cctx.reset(VibeZstd::ResetDirective::PARAMETERS)

    # Verify parameters were reset to defaults
    assert_equal(VibeZstd.default_compression_level, cctx.compression_level)
    assert_equal(false, cctx.checksum_flag)
  end

  def test_cctx_reset_both
    cctx = VibeZstd::CCtx.new
    cctx.compression_level = 9
    cctx.checksum_flag = true

    data1 = "First compression"
    compressed1 = cctx.compress(data1)

    # Reset both session and parameters
    cctx.reset(VibeZstd::ResetDirective::BOTH)

    # Verify parameters were reset
    assert_equal(VibeZstd.default_compression_level, cctx.compression_level)
    assert_equal(false, cctx.checksum_flag)

    # Verify can still compress
    data2 = "Second compression"
    compressed2 = cctx.compress(data2)

    dctx = VibeZstd::DCtx.new
    assert_equal(data1, dctx.decompress(compressed1))
    assert_equal(data2, dctx.decompress(compressed2))
  end

  def test_cctx_reset_default_is_both
    cctx = VibeZstd::CCtx.new
    cctx.compression_level = 9
    cctx.checksum_flag = true

    # Reset with no argument should default to BOTH
    cctx.reset

    # Verify parameters were reset
    assert_equal(VibeZstd.default_compression_level, cctx.compression_level)
    assert_equal(false, cctx.checksum_flag)
  end

  def test_cctx_reset_allows_reuse
    # Test that reset allows efficient context reuse
    cctx = VibeZstd::CCtx.new(level: 5)
    dctx = VibeZstd::DCtx.new

    # Compress multiple different datasets
    results = []
    10.times do |i|
      data = "Dataset #{i}: " + ("x" * 100)
      compressed = cctx.compress(data)
      results << [data, compressed]

      # Reset session for next compression
      cctx.reset(VibeZstd::ResetDirective::SESSION)
    end

    # Verify all compressions
    results.each do |original, compressed|
      assert_equal(original, dctx.decompress(compressed))
    end
  end

  def test_dctx_reset_session_only
    dctx = VibeZstd::DCtx.new
    dctx.window_log_max = 20

    data = "Test data for decompression"
    compressed = VibeZstd.compress(data)

    # Decompress once
    decompressed1 = dctx.decompress(compressed)
    assert_equal(data, decompressed1)

    # Reset session only - should keep parameters
    dctx.reset(VibeZstd::ResetDirective::SESSION)

    # Decompress again
    decompressed2 = dctx.decompress(compressed)
    assert_equal(data, decompressed2)

    # Verify parameters were retained
    assert_equal(20, dctx.window_log_max)
  end

  def test_dctx_reset_parameters
    dctx = VibeZstd::DCtx.new
    dctx.window_log_max = 20

    # Reset parameters to defaults
    dctx.reset(VibeZstd::ResetDirective::PARAMETERS)

    # Verify parameters were reset
    # window_log_max default is 27
    assert_equal(27, dctx.window_log_max)
  end

  def test_dctx_reset_both
    dctx = VibeZstd::DCtx.new
    dctx.window_log_max = 20

    data = "Test data"
    compressed = VibeZstd.compress(data)

    # Decompress once
    decompressed1 = dctx.decompress(compressed)
    assert_equal(data, decompressed1)

    # Reset both
    dctx.reset(VibeZstd::ResetDirective::BOTH)

    # Verify parameters were reset
    assert_equal(27, dctx.window_log_max)

    # Verify can still decompress
    decompressed2 = dctx.decompress(compressed)
    assert_equal(data, decompressed2)
  end

  def test_dctx_reset_default_is_both
    dctx = VibeZstd::DCtx.new
    dctx.window_log_max = 20

    # Reset with no argument should default to BOTH
    dctx.reset

    # Verify parameters were reset
    assert_equal(27, dctx.window_log_max)
  end

  def test_dctx_reset_allows_reuse
    # Test that reset allows efficient context reuse
    dctx = VibeZstd::DCtx.new

    # Decompress multiple different datasets
    10.times do |i|
      data = "Dataset #{i}: " + ("y" * 100)
      compressed = VibeZstd.compress(data)

      decompressed = dctx.decompress(compressed)
      assert_equal(data, decompressed)

      # Reset session for next decompression
      dctx.reset(VibeZstd::ResetDirective::SESSION)
    end
  end

  def test_reset_invalid_mode
    cctx = VibeZstd::CCtx.new

    # Test invalid reset mode
    assert_raises(ArgumentError) do
      cctx.reset(999)
    end
  end

  def test_reset_constants_defined
    # Verify reset constants are defined
    assert_equal(1, VibeZstd::ResetDirective::SESSION)
    assert_equal(2, VibeZstd::ResetDirective::PARAMETERS)
    assert_equal(3, VibeZstd::ResetDirective::BOTH)
  end

  # Tests for skippable frames

  def test_write_skippable_frame
    data = "test metadata"
    frame = VibeZstd.write_skippable_frame(data)

    # Frame should be 8 bytes header + data
    assert_equal(8 + data.bytesize, frame.bytesize)

    # Should be identified as skippable
    assert(VibeZstd.skippable_frame?(frame))
  end

  def test_write_skippable_frame_with_magic_variant
    data = "test data"

    # Test different magic variants (0-15)
    [0, 5, 15].each do |variant|
      frame = VibeZstd.write_skippable_frame(data, magic_number: variant)
      assert(VibeZstd.skippable_frame?(frame))
    end
  end

  def test_write_skippable_frame_invalid_magic_number
    assert_raises(ArgumentError) do
      VibeZstd.write_skippable_frame("data", magic_number: 16)
    end

    assert_raises(ArgumentError) do
      VibeZstd.write_skippable_frame("data", magic_number: 100)
    end
  end

  def test_read_skippable_frame
    original_data = "test metadata content"
    frame = VibeZstd.write_skippable_frame(original_data, magic_number: 3)

    content, magic_variant = VibeZstd.read_skippable_frame(frame)

    assert_equal(original_data, content)
    assert_equal(3, magic_variant)
  end

  def test_read_skippable_frame_not_skippable
    # Try to read a regular compressed frame as skippable
    compressed = VibeZstd.compress("test data")

    assert_raises(ArgumentError) do
      VibeZstd.read_skippable_frame(compressed)
    end
  end

  def test_skippable_frame_predicate
    skippable = VibeZstd.write_skippable_frame("metadata")
    compressed = VibeZstd.compress("data")

    assert(VibeZstd.skippable_frame?(skippable))
    refute(VibeZstd.skippable_frame?(compressed))
  end

  def test_find_frame_compressed_size_regular_frame
    data = "test data"
    compressed = VibeZstd.compress(data)

    size = VibeZstd.find_frame_compressed_size(compressed)
    assert_equal(compressed.bytesize, size)
  end

  def test_find_frame_compressed_size_skippable_frame
    data = "metadata"
    skippable = VibeZstd.write_skippable_frame(data)

    size = VibeZstd.find_frame_compressed_size(skippable)
    assert_equal(skippable.bytesize, size)
  end

  def test_find_frame_compressed_size_multi_frame
    data1 = "first frame"
    data2 = "second frame"

    frame1 = VibeZstd.compress(data1)
    frame2 = VibeZstd.compress(data2)
    combined = frame1 + frame2

    # Should return size of first frame only
    size = VibeZstd.find_frame_compressed_size(combined)
    assert_equal(frame1.bytesize, size)
  end

  def test_skippable_frame_with_compressed_data
    # Create metadata + compressed data
    metadata = { timestamp: Time.now.to_i, version: "1.0" }.to_json
    data = "actual compressed data"

    skippable = VibeZstd.write_skippable_frame(metadata, magic_number: 0)
    compressed = VibeZstd.compress(data)
    combined = skippable + compressed

    # Decompressor should automatically skip the metadata frame
    decompressed = VibeZstd.decompress(combined)
    assert_equal(data, decompressed)
  end

  def test_skippable_frame_multiple_leading_frames
    # Test multiple skippable frames before compressed data
    metadata1 = "first metadata"
    metadata2 = "second metadata"
    data = "actual data"

    skippable1 = VibeZstd.write_skippable_frame(metadata1, magic_number: 0)
    skippable2 = VibeZstd.write_skippable_frame(metadata2, magic_number: 1)
    compressed = VibeZstd.compress(data)
    combined = skippable1 + skippable2 + compressed

    # Should automatically skip both skippable frames
    decompressed = VibeZstd.decompress(combined)
    assert_equal(data, decompressed)
  end

  def test_only_skippable_frames_error
    # Test that trying to decompress only skippable frames raises an error
    skippable = VibeZstd.write_skippable_frame("metadata")

    assert_raises(RuntimeError) do
      VibeZstd.decompress(skippable)
    end
  end

  def test_each_skippable_frame_single_frame
    metadata = "test metadata"
    frame = VibeZstd.write_skippable_frame(metadata, magic_number: 5)

    results = []
    VibeZstd.each_skippable_frame(frame) do |content, magic, offset|
      results << [content, magic, offset]
    end

    assert_equal(1, results.size)
    assert_equal(metadata, results[0][0])
    assert_equal(5, results[0][1])
    assert_equal(0, results[0][2])
  end

  def test_each_skippable_frame_multiple_frames
    metadata1 = "first metadata"
    metadata2 = "second metadata"
    metadata3 = "third metadata"

    frame1 = VibeZstd.write_skippable_frame(metadata1, magic_number: 0)
    frame2 = VibeZstd.write_skippable_frame(metadata2, magic_number: 1)
    frame3 = VibeZstd.write_skippable_frame(metadata3, magic_number: 2)

    combined = frame1 + frame2 + frame3

    results = []
    VibeZstd.each_skippable_frame(combined) do |content, magic, offset|
      results << [content, magic, offset]
    end

    assert_equal(3, results.size)

    assert_equal(metadata1, results[0][0])
    assert_equal(0, results[0][1])
    assert_equal(0, results[0][2])

    assert_equal(metadata2, results[1][0])
    assert_equal(1, results[1][1])
    assert_equal(frame1.bytesize, results[1][2])

    assert_equal(metadata3, results[2][0])
    assert_equal(2, results[2][1])
    assert_equal(frame1.bytesize + frame2.bytesize, results[2][2])
  end

  def test_each_skippable_frame_mixed_with_compressed
    metadata1 = "before compression"
    metadata2 = "after compression"
    data = "compressed data"

    skippable1 = VibeZstd.write_skippable_frame(metadata1, magic_number: 0)
    compressed = VibeZstd.compress(data)
    skippable2 = VibeZstd.write_skippable_frame(metadata2, magic_number: 1)

    combined = skippable1 + compressed + skippable2

    results = []
    VibeZstd.each_skippable_frame(combined) do |content, magic, offset|
      results << [content, magic, offset]
    end

    # Should only yield the skippable frames, not the compressed frame
    assert_equal(2, results.size)

    assert_equal(metadata1, results[0][0])
    assert_equal(0, results[0][1])

    assert_equal(metadata2, results[1][0])
    assert_equal(1, results[1][1])
  end

  def test_each_skippable_frame_returns_enumerator
    metadata = "test"
    frame = VibeZstd.write_skippable_frame(metadata)

    enum = VibeZstd.each_skippable_frame(frame)
    assert_instance_of(Enumerator, enum)

    results = enum.to_a
    assert_equal(1, results.size)
    assert_equal(metadata, results[0][0])
  end

  def test_skippable_frame_archive_pattern
    # Simulate a simple archive format
    files = {
      "file1.txt" => "content of file 1",
      "file2.txt" => "content of file 2"
    }

    archive = String.new(encoding: 'BINARY')

    files.each do |path, content|
      metadata = { path: path, size: content.bytesize }.to_json
      archive << VibeZstd.write_skippable_frame(metadata, magic_number: 0)
      archive << VibeZstd.compress(content)
    end

    # Extract archive
    extracted = {}
    offset = 0

    while offset < archive.bytesize
      frame_data = archive.byteslice(offset..-1)
      frame_size = VibeZstd.find_frame_compressed_size(frame_data)

      if VibeZstd.skippable_frame?(frame_data)
        content, _magic = VibeZstd.read_skippable_frame(frame_data)
        metadata = JSON.parse(content)
        offset += frame_size

        # Next frame should be the compressed file
        compressed_data = archive.byteslice(offset..-1)
        compressed_size = VibeZstd.find_frame_compressed_size(compressed_data)
        file_content = VibeZstd.decompress(compressed_data.byteslice(0, compressed_size))

        extracted[metadata["path"]] = file_content
        offset += compressed_size
      else
        offset += frame_size
      end
    end

    assert_equal(files, extracted)
  end
end
