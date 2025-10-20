# frozen_string_literal: true

require "test_helper"

class TestVibeZstd < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::VibeZstd::VERSION
  end

  # Basic convenience methods
  def test_convenience_compress_decompress
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

  # Dictionary training methods
  def test_train_dict
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

  def test_train_dict_with_default_size
    # Test training with default max_dict_size
    samples = Array.new(50) { |i| "pattern #{i} " * 20 }

    dict_data = VibeZstd.train_dict(samples)

    refute_nil(dict_data)
    assert(dict_data.bytesize > 0)
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

  def test_finalize_dictionary_basic
    samples = [
      "common words and patterns appear frequently",
      "common words in this sample too",
      "common words are everywhere here",
      "common patterns repeat often",
      "common data structures used"
    ] * 10

    raw_content = "common words and patterns " * 20

    dict = VibeZstd.finalize_dictionary(
      content: raw_content,
      samples: samples,
      max_size: 2048
    )

    assert_kind_of String, dict
    assert dict.bytesize > 0
    assert dict.bytesize <= 2048

    # Should be a valid dictionary
    dict_id = VibeZstd.get_dict_id(dict)
    refute_equal 0, dict_id
  end

  def test_finalize_dictionary_with_compression_level
    samples = [
      "common words and patterns appear frequently",
      "common words in this sample too"
    ] * 25

    raw_content = "test content " * 30

    dict = VibeZstd.finalize_dictionary(
      content: raw_content,
      samples: samples,
      max_size: 2048,
      compression_level: 5
    )

    assert_kind_of String, dict
    assert dict.bytesize > 0

    # Can use for compression
    cdict = VibeZstd::CDict.new(dict, 5)
    compressed = VibeZstd.compress("common words test", dict: cdict)

    ddict = VibeZstd::DDict.new(dict)
    decompressed = VibeZstd.decompress(compressed, dict: ddict)
    assert_equal "common words test", decompressed
  end

  def test_finalize_dictionary_with_dict_id
    samples = ["common words"] * 50
    raw_content = "custom content " * 25
    custom_dict_id = 12345

    dict = VibeZstd.finalize_dictionary(
      content: raw_content,
      samples: samples,
      max_size: 2048,
      dict_id: custom_dict_id
    )

    # Verify the custom dict_id was used
    dict_id = VibeZstd.get_dict_id(dict)
    assert_equal custom_dict_id, dict_id
  end

  def test_finalize_dictionary_requires_content
    assert_raises(ArgumentError) do
      VibeZstd.finalize_dictionary(
        samples: ["test"],
        max_size: 2048
      )
    end
  end

  def test_finalize_dictionary_requires_samples
    assert_raises(ArgumentError) do
      VibeZstd.finalize_dictionary(
        content: "test",
        max_size: 2048
      )
    end
  end

  def test_finalize_dictionary_requires_max_size
    assert_raises(ArgumentError) do
      VibeZstd.finalize_dictionary(
        content: "test",
        samples: ["test"]
      )
    end
  end

  def test_finalize_dictionary_empty_samples
    assert_raises(ArgumentError) do
      VibeZstd.finalize_dictionary(
        content: "test",
        samples: [],
        max_size: 2048
      )
    end
  end

  def test_finalize_dictionary_end_to_end
    # Create a raw dictionary based on domain knowledge
    raw_content = "JSON field names: name, email, address, phone, city, state, zip " * 10

    # Sample JSON-like data
    json_samples = [
      '{"name":"John","email":"john@example.com"}',
      '{"name":"Jane","email":"jane@example.com"}',
      '{"name":"Bob","address":"123 Main St"}',
      '{"name":"Alice","phone":"555-1234"}',
      '{"email":"test@test.com","city":"NYC"}'
    ] * 15

    # Finalize into proper zstd dictionary
    dict = VibeZstd.finalize_dictionary(
      content: raw_content,
      samples: json_samples,
      max_size: 4096,
      compression_level: 5
    )

    # Use it for compression
    cdict = VibeZstd::CDict.new(dict, 5)
    test_data = '{"name":"Test","email":"test@example.com","address":"123 Test St"}'
    compressed = VibeZstd.compress(test_data, dict: cdict)

    # Decompress with same dictionary
    ddict = VibeZstd::DDict.new(dict)
    decompressed = VibeZstd.decompress(compressed, dict: ddict)

    assert_equal test_data, decompressed
  end

  # Dictionary ID methods
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

  def test_dict_header_size_basic
    # Train a dictionary
    samples = ["common words"] * 50
    dict = VibeZstd.train_dict(samples, max_dict_size: 2048)

    header_size = VibeZstd.dict_header_size(dict)

    assert_kind_of Integer, header_size
    assert header_size > 0
    assert header_size < dict.bytesize
  end

  def test_dict_header_size_finalized
    samples = ["common words"] * 50
    raw_content = "content " * 40
    dict = VibeZstd.finalize_dictionary(
      content: raw_content,
      samples: samples,
      max_size: 2048
    )

    header_size = VibeZstd.dict_header_size(dict)

    assert_kind_of Integer, header_size
    assert header_size > 0
    # Header should be reasonable size (typically 100-300 bytes)
    assert header_size < 1024
  end

  def test_dict_header_size_invalid_data
    assert_raises(RuntimeError) do
      VibeZstd.dict_header_size("not a dictionary")
    end
  end

  # Frame methods
  def test_frame_content_size
    cctx = VibeZstd::CCtx.new
    cctx.content_size_flag = 1

    data = "Hello, world! This is a test with content size."
    compressed = cctx.compress(data)

    # Verify we can read the content size from the frame
    size = VibeZstd.frame_content_size(compressed)
    assert_equal(data.bytesize, size)
  end

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
    metadata = {timestamp: Time.now.to_i, version: "1.0"}.to_json
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

    archive = String.new(encoding: "BINARY")

    files.each do |path, content|
      metadata = {path: path, size: content.bytesize}.to_json
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

  # Version information methods
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
end
