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
    cctx.set_parameter(:checksumFlag, 1)

    data = "Hello, world! This is a test with checksum."
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
  end

  def test_set_parameter_content_size
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Enable content size in frame
    cctx.set_parameter(:contentSizeFlag, 1)

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
    cctx.set_parameter(:windowLog, 10)

    data = "Small data for small window"
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
  end

  def test_set_parameter_compression_level
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set compression level via set_parameter
    cctx.set_parameter(:compressionLevel, 9)

    data = "Test data for compression level parameter"
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
  end

  def test_set_parameter_method_chaining
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Test method chaining
    cctx
      .set_parameter(:checksumFlag, 1)
      .set_parameter(:contentSizeFlag, 1)

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
    cctx.set_parameter(:contentSizeFlag, 1)
    compressed = cctx.compress(data, nil, nil, pledged_size: data.bytesize)

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
    dctx.set_parameter(:windowLogMax, 10)

    # Compress with matching window
    cctx.set_parameter(:windowLog, 10)
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
    compressed_neg1 = cctx.compress(data, -1)
    decompressed = dctx.decompress(compressed_neg1)
    assert_equal(data, decompressed)

    # Test level -5 (very fast)
    compressed_neg5 = cctx.compress(data, -5)
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
    cctx.set_parameter(:compression_level, 9)
    level = cctx.get_parameter(:compression_level)
    assert_equal(9, level)

    # Test window_log
    cctx.set_parameter(:window_log, 20)
    window_log = cctx.get_parameter(:window_log)
    assert_equal(20, window_log)

    # Test checksum_flag
    cctx.set_parameter(:checksum_flag, 1)
    checksum = cctx.get_parameter(:checksum_flag)
    assert_equal(1, checksum)
  end

  def test_dctx_get_parameter
    dctx = VibeZstd::DCtx.new

    # Set window_log_max and verify we can read it back
    dctx.set_parameter(:window_log_max, 20)
    window_log_max = dctx.get_parameter(:window_log_max)
    assert_equal(20, window_log_max)
  end

  # Tests for new compression parameters

  def test_search_log_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Set searchLog and verify
    cctx.set_parameter(:searchLog, 5)
    assert_equal(5, cctx.get_parameter(:searchLog))

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
    cctx.set_parameter(:minMatch, 4)
    assert_equal(4, cctx.get_parameter(:minMatch))

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
    cctx.set_parameter(:targetLength, 16)
    assert_equal(16, cctx.get_parameter(:targetLength))

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
    cctx.set_parameter(:targetCBlockSize, 2048)
    value = cctx.get_parameter(:targetCBlockSize)
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
    cctx.set_parameter(:enableLongDistanceMatching, 1)
    assert_equal(1, cctx.get_parameter(:enableLongDistanceMatching))

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
    cctx.set_parameter(:enableLongDistanceMatching, 1)

    # Set ldmHashLog and verify
    cctx.set_parameter(:ldmHashLog, 20)
    assert_equal(20, cctx.get_parameter(:ldmHashLog))

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
    cctx.set_parameter(:enableLongDistanceMatching, 1)

    # Set ldmMinMatch and verify
    cctx.set_parameter(:ldmMinMatch, 64)
    assert_equal(64, cctx.get_parameter(:ldmMinMatch))

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
    cctx.set_parameter(:enableLongDistanceMatching, 1)

    # Set ldmBucketSizeLog and verify
    cctx.set_parameter(:ldmBucketSizeLog, 3)
    assert_equal(3, cctx.get_parameter(:ldmBucketSizeLog))

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
    cctx.set_parameter(:enableLongDistanceMatching, 1)

    # Set ldmHashRateLog and verify
    cctx.set_parameter(:ldmHashRateLog, 5)
    assert_equal(5, cctx.get_parameter(:ldmHashRateLog))

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
    cctx.set_parameter(:nbWorkers, 2)

    # Set jobSize and verify
    cctx.set_parameter(:jobSize, 1048576) # 1MB
    assert_equal(1048576, cctx.get_parameter(:jobSize))

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
    cctx.set_parameter(:nbWorkers, 2)

    # Set overlapLog and verify
    cctx.set_parameter(:overlapLog, 5)
    assert_equal(5, cctx.get_parameter(:overlapLog))

    # Test compression with multi-threading and overlap
    data = "Test data for multi-threaded compression with overlap " * 1000
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_parameter_name_variants
    cctx = VibeZstd::CCtx.new

    # Test both snake_case and camelCase work for new parameters
    cctx.set_parameter(:search_log, 4)
    assert_equal(4, cctx.get_parameter(:searchLog))

    cctx.set_parameter(:minMatch, 5)
    assert_equal(5, cctx.get_parameter(:min_match))

    cctx.set_parameter(:target_length, 32)
    assert_equal(32, cctx.get_parameter(:targetLength))

    cctx.set_parameter(:enableLongDistanceMatching, 1)
    assert_equal(1, cctx.get_parameter(:enable_long_distance_matching))
  end

  def test_ldm_comprehensive
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Configure full LDM setup
    cctx.set_parameter(:enableLongDistanceMatching, 1)
    cctx.set_parameter(:ldmHashLog, 20)
    cctx.set_parameter(:ldmMinMatch, 64)
    cctx.set_parameter(:ldmBucketSizeLog, 3)
    cctx.set_parameter(:ldmHashRateLog, 6)

    # Create data with long-distance repetition
    base_pattern = "This is a base pattern that will repeat. " * 100
    middle_content = "Unique middle content. " * 200
    data = base_pattern + middle_content + base_pattern

    compressed = cctx.compress(data, 9) # High compression level
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)
    # LDM should provide good compression for this pattern
    compression_ratio = data.bytesize.to_f / compressed.bytesize
    assert(compression_ratio > 2.0, "Expected compression ratio > 2.0, got #{compression_ratio}")
  end

  # Tests for parameter bounds API

  def test_cctx_parameter_bounds_compression_level
    bounds = VibeZstd::CCtx.parameter_bounds(:compressionLevel)

    assert_instance_of(Hash, bounds)
    assert(bounds.key?(:min))
    assert(bounds.key?(:max))
    # Compression level should support negative levels
    assert(bounds[:min] < 0, "Min compression level should be negative")
    assert(bounds[:max] >= 22, "Max compression level should be at least 22")
  end

  def test_cctx_parameter_bounds_window_log
    bounds = VibeZstd::CCtx.parameter_bounds(:windowLog)

    assert_instance_of(Hash, bounds)
    assert_equal(2, bounds.size)
    # Window log typically ranges from 10 to 31
    assert(bounds[:min] >= 10)
    assert(bounds[:max] <= 31)
  end

  def test_cctx_parameter_bounds_all_parameters
    # Test that bounds work for all parameters
    parameters = [
      :compressionLevel, :windowLog, :hashLog, :chainLog, :searchLog,
      :minMatch, :targetLength, :strategy, :targetCBlockSize,
      :enableLongDistanceMatching, :ldmHashLog, :ldmMinMatch,
      :ldmBucketSizeLog, :ldmHashRateLog,
      :contentSizeFlag, :checksumFlag, :dictIDFlag,
      :nbWorkers, :jobSize, :overlapLog
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
    bounds2 = VibeZstd::CCtx.parameter_bounds(:compressionLevel)

    assert_equal(bounds1[:min], bounds2[:min])
    assert_equal(bounds1[:max], bounds2[:max])
  end

  def test_cctx_parameter_bounds_invalid_parameter
    assert_raises(ArgumentError) do
      VibeZstd::CCtx.parameter_bounds(:invalidParameter)
    end
  end

  def test_dctx_parameter_bounds_window_log_max
    bounds = VibeZstd::DCtx.parameter_bounds(:windowLogMax)

    assert_instance_of(Hash, bounds)
    assert(bounds.key?(:min))
    assert(bounds.key?(:max))
    assert(bounds[:min] >= 10)
    assert(bounds[:max] <= 31)
  end

  def test_dctx_parameter_bounds_snake_case
    # Test that snake_case works
    bounds1 = VibeZstd::DCtx.parameter_bounds(:window_log_max)
    bounds2 = VibeZstd::DCtx.parameter_bounds(:windowLogMax)

    assert_equal(bounds1[:min], bounds2[:min])
    assert_equal(bounds1[:max], bounds2[:max])
  end

  def test_parameter_bounds_practical_usage
    # Test practical use case: validating parameter before setting
    cctx = VibeZstd::CCtx.new

    bounds = VibeZstd::CCtx.parameter_bounds(:windowLog)

    # Set to min and max bounds
    cctx.set_parameter(:windowLog, bounds[:min])
    assert_equal(bounds[:min], cctx.get_parameter(:windowLog))

    cctx.set_parameter(:windowLog, bounds[:max])
    assert_equal(bounds[:max], cctx.get_parameter(:windowLog))
  end

  # Tests for experimental parameters
  def test_rsyncable_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    cctx.set_parameter(:rsyncable, 1)
    assert_equal(1, cctx.get_parameter(:rsyncable))

    data = "Test data for rsyncable parameter " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_format_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Test magicless format (ZSTD_f_zstd1_magicless = 1)
    cctx.set_parameter(:format, 1)
    assert_equal(1, cctx.get_parameter(:format))

    data = "Test data for format parameter " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_force_max_window_parameter
    cctx = VibeZstd::CCtx.new

    cctx.set_parameter(:forceMaxWindow, 1)
    assert_equal(1, cctx.get_parameter(:forceMaxWindow))
  end

  def test_force_attach_dict_parameter
    cctx = VibeZstd::CCtx.new

    # ZSTD_dictDefaultAttach = 0, ZSTD_dictForceAttach = 1, ZSTD_dictForceCopy = 2
    cctx.set_parameter(:forceAttachDict, 0)
    assert_equal(0, cctx.get_parameter(:forceAttachDict))
  end

  def test_literal_compression_mode_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # ZSTD_ps_auto = 0, ZSTD_ps_enable = 1, ZSTD_ps_disable = 2
    cctx.set_parameter(:literalCompressionMode, 1)
    assert_equal(1, cctx.get_parameter(:literalCompressionMode))

    data = "Test data for literal compression mode " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_src_size_hint_parameter
    cctx = VibeZstd::CCtx.new

    # Provide hint about source size
    cctx.set_parameter(:srcSizeHint, 10000)
    assert_equal(10000, cctx.get_parameter(:srcSizeHint))
  end

  def test_enable_dedicated_dict_search_parameter
    cctx = VibeZstd::CCtx.new

    cctx.set_parameter(:enableDedicatedDictSearch, 1)
    assert_equal(1, cctx.get_parameter(:enableDedicatedDictSearch))
  end

  def test_stable_in_buffer_parameter
    cctx = VibeZstd::CCtx.new

    cctx.set_parameter(:stableInBuffer, 1)
    assert_equal(1, cctx.get_parameter(:stableInBuffer))
  end

  def test_stable_out_buffer_parameter
    cctx = VibeZstd::CCtx.new

    cctx.set_parameter(:stableOutBuffer, 1)
    assert_equal(1, cctx.get_parameter(:stableOutBuffer))
  end

  def test_block_delimiters_parameter
    cctx = VibeZstd::CCtx.new

    cctx.set_parameter(:blockDelimiters, 1)
    assert_equal(1, cctx.get_parameter(:blockDelimiters))
  end

  def test_validate_sequences_parameter
    cctx = VibeZstd::CCtx.new

    cctx.set_parameter(:validateSequences, 1)
    assert_equal(1, cctx.get_parameter(:validateSequences))
  end

  def test_use_row_match_finder_parameter
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # ZSTD_urm_auto = 0, ZSTD_urm_disableRowMatchFinder = 1, ZSTD_urm_enableRowMatchFinder = 2
    cctx.set_parameter(:useRowMatchFinder, 2)
    assert_equal(2, cctx.get_parameter(:useRowMatchFinder))

    data = "Test data for row match finder " * 50
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)
  end

  def test_deterministic_ref_prefix_parameter
    cctx = VibeZstd::CCtx.new

    cctx.set_parameter(:deterministicRefPrefix, 1)
    assert_equal(1, cctx.get_parameter(:deterministicRefPrefix))
  end

  def test_prefetch_cdict_tables_parameter
    cctx = VibeZstd::CCtx.new

    # ZSTD_ps_auto = 0, ZSTD_ps_enable = 1, ZSTD_ps_disable = 2
    cctx.set_parameter(:prefetchCDictTables, 1)
    assert_equal(1, cctx.get_parameter(:prefetchCDictTables))
  end

  def test_enable_seq_producer_fallback_parameter
    cctx = VibeZstd::CCtx.new

    cctx.set_parameter(:enableSeqProducerFallback, 1)
    assert_equal(1, cctx.get_parameter(:enableSeqProducerFallback))
  end

  def test_max_block_size_parameter
    cctx = VibeZstd::CCtx.new

    cctx.set_parameter(:maxBlockSize, 131072)
    assert_equal(131072, cctx.get_parameter(:maxBlockSize))
  end

  def test_search_for_external_repcodes_parameter
    cctx = VibeZstd::CCtx.new

    # ZSTD_ps_auto = 0, ZSTD_ps_enable = 1, ZSTD_ps_disable = 2
    cctx.set_parameter(:searchForExternalRepcodes, 1)
    assert_equal(1, cctx.get_parameter(:searchForExternalRepcodes))
  end

  def test_experimental_parameter_name_variants
    cctx = VibeZstd::CCtx.new

    # Test both snake_case and camelCase work for experimental parameters
    cctx.set_parameter(:force_max_window, 1)
    assert_equal(1, cctx.get_parameter(:forceMaxWindow))

    cctx.set_parameter(:src_size_hint, 5000)
    assert_equal(5000, cctx.get_parameter(:srcSizeHint))

    cctx.set_parameter(:literal_compression_mode, 2)
    assert_equal(2, cctx.get_parameter(:literalCompressionMode))
  end

  def test_experimental_parameter_bounds
    # Test that bounds work for experimental parameters
    bounds = VibeZstd::CCtx.parameter_bounds(:rsyncable)
    assert_kind_of(Hash, bounds)
    assert(bounds.key?(:min))
    assert(bounds.key?(:max))

    bounds = VibeZstd::CCtx.parameter_bounds(:format)
    assert_kind_of(Hash, bounds)

    bounds = VibeZstd::CCtx.parameter_bounds(:literalCompressionMode)
    assert_kind_of(Hash, bounds)
  end
end
