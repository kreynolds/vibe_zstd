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
    writer = VibeZstd::Compress::Writer.new(output, level: 5, pledged_size: data.bytesize)
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
    VibeZstd::Compress::Writer.open(output, level: 5) do |writer|
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
    writer = VibeZstd::Compress::Writer.open(output, level: 5)
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
      VibeZstd::Compress::Writer.open(output, level: 5) do |writer|
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
    VibeZstd::Decompress::Reader.open(input) do |reader|
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
    reader = VibeZstd::Decompress::Reader.open(input)
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
    VibeZstd::Compress::Writer.open(output, level: 5, dict: cdict) do |writer|
      writer.write(data)
    end

    compressed = output.string

    # Verify decompression with dictionary using Reader
    input = StringIO.new(compressed)
    reader = VibeZstd::Decompress::Reader.new(input, dict: ddict)
    decompressed = reader.read
    assert_equal(data, decompressed)
  end
end
