# frozen_string_literal: true

require "test_helper"

class TestCCtx < Minitest::Test
  # Basic construction and compression
  def test_new_and_compress
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

  # Parameter tests - Basic parameters
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

  # Parameter bounds
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

  # Prefix dictionaries
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

  # Memory estimation
  def test_memory_estimation
    # Test CCtx memory estimation
    cctx_mem = VibeZstd::CCtx.estimate_memory(3)
    assert(cctx_mem > 0)
    assert(cctx_mem > 10_000) # Should be at least 10KB

    # Higher levels should use more memory
    cctx_mem_high = VibeZstd::CCtx.estimate_memory(19)
    assert(cctx_mem_high > cctx_mem)
  end

  # Reset methods
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

  # Advanced parameters - Long Distance Matching
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

  # Experimental parameters
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

  # Boolean API and idiomatic Ruby features
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

  # Convenient aliases
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

  def test_all_aliases_together
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new

    # Use all aliases together
    cctx.level = 7
    cctx.workers = 2

    data = "Test all convenient aliases together " * 200

    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)

    assert_equal(data, decompressed)

    # Verify aliases still work for reading
    assert_equal(7, cctx.level)
    assert_equal(2, cctx.workers)
  end
end
