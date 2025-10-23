#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestThreadLocalDictMismatch < Minitest::Test
  def setup
    VibeZstd::ThreadLocal.clear_thread_cache!

    # Create two different dictionaries
    samples1 = 10.times.map { |i| {id: i, type: "user", name: "User #{i}"}.to_json }
    samples2 = 10.times.map { |i| {id: i, type: "product", sku: "SKU#{i}"}.to_json }

    dict_data1 = VibeZstd.train_dict(samples1, max_dict_size: 2048)
    dict_data2 = VibeZstd.train_dict(samples2, max_dict_size: 2048)

    @cdict1 = VibeZstd::CDict.new(dict_data1)
    @ddict1 = VibeZstd::DDict.new(dict_data1)

    @cdict2 = VibeZstd::CDict.new(dict_data2)
    @ddict2 = VibeZstd::DDict.new(dict_data2)

    @test_data = samples1.first
  end

  def test_thread_local_with_wrong_dictionary
    # Compress with dict1
    compressed = VibeZstd::ThreadLocal.compress(@test_data, dict: @cdict1)

    # Try to decompress with wrong dictionary
    error = assert_raises(ArgumentError) do
      VibeZstd::ThreadLocal.decompress(compressed, dict: @ddict2)
    end
    assert_match(/dictionary mismatch/i, error.message)

    stats = VibeZstd::ThreadLocal.thread_cache_stats
    assert_includes(stats[:decompression_keys], @ddict2.dict_id)
  end

  def test_thread_local_pool_behavior_with_mismatches
    # Compress with dict1
    compressed1 = VibeZstd::ThreadLocal.compress(@test_data, dict: @cdict1)

    # Successfully decompress with correct dict1
    result1 = VibeZstd::ThreadLocal.decompress(compressed1, dict: @ddict1)
    assert_equal(@test_data, result1)

    # Try to decompress dict1 data with dict2 - should fail
    assert_raises(ArgumentError) do
      VibeZstd::ThreadLocal.decompress(compressed1, dict: @ddict2)
    end

    stats = VibeZstd::ThreadLocal.thread_cache_stats
    assert_equal(2, stats[:decompression_contexts])
    assert_includes(stats[:decompression_keys], @ddict1.dict_id)
    assert_includes(stats[:decompression_keys], @ddict2.dict_id)
  end

  def test_thread_local_missing_required_dictionary
    # Compress with dict1
    compressed = VibeZstd::ThreadLocal.compress(@test_data, dict: @cdict1)

    # Try to decompress without providing dictionary
    error = assert_raises(ArgumentError) do
      VibeZstd::ThreadLocal.decompress(compressed)
    end
    assert_match(/requires dictionary/i, error.message)
    assert_match(/#{@cdict1.dict_id}/, error.message)
  end
end
