# frozen_string_literal: true

require "test_helper"

class TestDCtx < Minitest::Test
  # Basic construction and decompression
  def test_new_and_decompress
    cctx = VibeZstd::CCtx.new
    dctx = VibeZstd::DCtx.new
    data = "Hello, world! This is a test string for compression."
    compressed = cctx.compress(data)
    decompressed = dctx.decompress(compressed)
    assert_equal data, decompressed
  end

  # Parameter tests
  def test_dctx_get_parameter
    dctx = VibeZstd::DCtx.new

    # Set window_log_max and verify we can read it back
    dctx.window_log_max = 20
    window_log_max = dctx.window_log_max
    assert_equal(20, window_log_max)
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

  # Parameter bounds
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

  # Memory estimation
  def test_memory_estimation
    # Test DCtx memory estimation
    dctx_mem = VibeZstd::DCtx.estimate_memory
    assert(dctx_mem > 0)
    assert(dctx_mem > 10_000) # Should be at least 10KB
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

  # Reset methods
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

  # Idiomatic Ruby aliases
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

  # Initial capacity configuration tests
  def test_default_initial_capacity_returns_zstd_default
    # Should return ZSTD_DStreamOutSize() by default
    default_capacity = VibeZstd::DCtx.default_initial_capacity
    assert(default_capacity > 0)
    assert(default_capacity > 100_000) # Should be ~128KB
  end

  def test_class_level_default_initial_capacity
    original_default = VibeZstd::DCtx.default_initial_capacity

    begin
      # Set class-level default
      VibeZstd::DCtx.default_initial_capacity = 50_000

      # New instances should use the class default
      dctx = VibeZstd::DCtx.new
      assert_equal(50_000, dctx.initial_capacity)
    ensure
      # Reset to original default
      VibeZstd::DCtx.default_initial_capacity = nil
    end

    # Verify reset worked
    assert_equal(original_default, VibeZstd::DCtx.default_initial_capacity)
  end

  def test_instance_initial_capacity
    # Instance-level configuration
    dctx = VibeZstd::DCtx.new(initial_capacity: 10_000)
    assert_equal(10_000, dctx.initial_capacity)

    # Can be changed after creation
    dctx.initial_capacity = 20_000
    assert_equal(20_000, dctx.initial_capacity)

    # Reset to class default
    dctx.initial_capacity = nil
    assert_equal(VibeZstd::DCtx.default_initial_capacity, dctx.initial_capacity)
  end

  def test_initial_capacity_fallback_chain
    # Set class-level default
    VibeZstd::DCtx.default_initial_capacity = 30_000

    # Instance with override
    dctx = VibeZstd::DCtx.new(initial_capacity: 40_000)
    assert_equal(40_000, dctx.initial_capacity)

    # Create instance without override - should use class default
    dctx2 = VibeZstd::DCtx.new
    assert_equal(30_000, dctx2.initial_capacity)
  ensure
    VibeZstd::DCtx.default_initial_capacity = nil
  end

  def test_decompression_with_unknown_size_frame_small
    # Create a frame without content size (streaming compression)
    output = StringIO.new
    cstream = VibeZstd::CompressWriter.new(output, content_size: false)
    data = "Small data for unknown-size decompression test"
    cstream.write(data)
    cstream.finish
    compressed = output.string

    # Decompress with small initial capacity
    dctx = VibeZstd::DCtx.new
    decompressed = dctx.decompress(compressed, initial_capacity: 100)
    assert_equal(data, decompressed)
  end

  def test_decompression_with_unknown_size_frame_large
    # Create a large frame without content size
    large_data = "X" * 500_000  # 500KB
    output = StringIO.new
    cstream = VibeZstd::CompressWriter.new(output, content_size: false)
    cstream.write(large_data)
    cstream.finish
    compressed = output.string

    # Decompress with small initial capacity (will need exponential growth)
    dctx = VibeZstd::DCtx.new
    decompressed = dctx.decompress(compressed, initial_capacity: 4096)
    assert_equal(large_data, decompressed)
  end

  def test_per_call_initial_capacity_override
    # Instance with specific capacity
    dctx = VibeZstd::DCtx.new(initial_capacity: 50_000)

    # Create unknown-size frame
    output = StringIO.new
    cstream = VibeZstd::CompressWriter.new(output, content_size: false)
    data = "Test data for per-call override"
    cstream.write(data)
    cstream.finish
    compressed = output.string

    # Per-call override should take precedence
    decompressed = dctx.decompress(compressed, initial_capacity: 100)
    assert_equal(data, decompressed)
  end

  def test_initial_capacity_validation
    # Zero should raise error
    assert_raises(ArgumentError) do
      VibeZstd::DCtx.default_initial_capacity = 0
    end

    # Zero for instance should raise error
    assert_raises(ArgumentError) do
      VibeZstd::DCtx.new(initial_capacity: 0)
    end

    # Zero for per-call should raise error
    dctx = VibeZstd::DCtx.new
    output = StringIO.new
    cstream = VibeZstd::CompressWriter.new(output, content_size: false)
    cstream.write("test")
    cstream.finish
    compressed = output.string

    assert_raises(ArgumentError) do
      dctx.decompress(compressed, initial_capacity: 0)
    end
  end

  def test_known_size_frame_ignores_initial_capacity
    # For known-size frames, initial_capacity should be ignored
    # (the frame already specifies the exact size)
    data = "Test data with known size"
    compressed = VibeZstd.compress(data)

    dctx = VibeZstd::DCtx.new(initial_capacity: 100)
    decompressed = dctx.decompress(compressed)
    assert_equal(data, decompressed)

    # Per-call capacity should also be ignored for known-size frames
    decompressed2 = dctx.decompress(compressed, initial_capacity: 100)
    assert_equal(data, decompressed2)
  end

  def test_decompress_missing_required_dictionary
    samples = 10.times.map { |i| {id: i, name: "User #{i}", email: "user#{i}@example.com"}.to_json }
    dict_data = VibeZstd.train_dict(samples, max_dict_size: 2048)
    cdict = VibeZstd::CDict.new(dict_data)

    data = samples.first
    compressed = VibeZstd.compress(data, dict: cdict)

    # Try to decompress without providing required dictionary
    dctx = VibeZstd::DCtx.new
    error = assert_raises(ArgumentError) do
      dctx.decompress(compressed)
    end
    assert_match(/requires dictionary/i, error.message)
    assert_match(/#{cdict.dict_id}/, error.message)
  end

  def test_decompress_wrong_dictionary
    samples1 = 10.times.map { |i| {id: i, type: "user", name: "User #{i}"}.to_json }
    samples2 = 10.times.map { |i| {id: i, type: "product", sku: "SKU#{i}"}.to_json }

    dict_data1 = VibeZstd.train_dict(samples1, max_dict_size: 2048)
    dict_data2 = VibeZstd.train_dict(samples2, max_dict_size: 2048)

    cdict1 = VibeZstd::CDict.new(dict_data1)
    ddict1 = VibeZstd::DDict.new(dict_data1)
    ddict2 = VibeZstd::DDict.new(dict_data2)

    data = samples1.first
    compressed = VibeZstd.compress(data, dict: cdict1)

    # Try to decompress with wrong dictionary
    dctx = VibeZstd::DCtx.new
    error = assert_raises(ArgumentError) do
      dctx.decompress(compressed, dict: ddict2)
    end
    assert_match(/dictionary mismatch/i, error.message)
    assert_match(/#{cdict1.dict_id}/, error.message)
    assert_match(/#{ddict2.dict_id}/, error.message)

    # Correct dictionary should work
    result = dctx.decompress(compressed, dict: ddict1)
    assert_equal(data, result)
  end

  def test_decompress_with_dict_when_none_required
    data = "Test data without dictionary"
    compressed = VibeZstd.compress(data)

    # Create a dictionary (won't be used)
    samples = 10.times.map { |i| {id: i, data: "sample #{i}"}.to_json }
    dict_data = VibeZstd.train_dict(samples, max_dict_size: 2048)
    ddict = VibeZstd::DDict.new(dict_data)

    # Decompress with dictionary when none required - should ignore dict and work
    dctx = VibeZstd::DCtx.new
    result = dctx.decompress(compressed, dict: ddict)
    assert_equal(data, result)
  end
end
