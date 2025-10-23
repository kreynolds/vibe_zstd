#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to generate a trained dictionary fixture for testing and benchmarking

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "vibe_zstd"
require "json"
require "fileutils"

# Create fixtures directory
FIXTURES_DIR = File.join(__dir__, "..", "test", "fixtures")
FileUtils.mkdir_p(FIXTURES_DIR)

# Generate training samples (JSON-like data similar to web application data)
puts "Generating training samples..."
samples = 200.times.map do |i|
  {
    id: i,
    name: "User #{i}",
    email: "user#{i}@example.com",
    created_at: Time.now.to_i - rand(100000),
    status: %w[active pending inactive verified][rand(4)],
    preferences: {
      theme: %w[light dark auto][rand(3)],
      notifications: rand(2) == 1,
      language: %w[en es fr de][rand(4)]
    },
    metadata: {
      login_count: rand(1000),
      last_ip: "192.168.#{rand(255)}.#{rand(255)}",
      user_agent: "Mozilla/5.0 (compatible; Bot/1.0)",
      session_duration: rand(3600)
    },
    tags: rand(5).times.map { |t| "tag#{t}" }
  }.to_json
end

puts "Training dictionary with #{samples.size} samples..."
dict_data = VibeZstd.train_dict(samples, max_dict_size: 16 * 1024) # 16KB dictionary

# Save the dictionary
dict_path = File.join(FIXTURES_DIR, "sample.dict")
File.binwrite(dict_path, dict_data)

puts "\nDictionary saved to: #{dict_path}"
puts "Dictionary size: #{dict_data.bytesize} bytes"
puts "Dictionary ID: #{VibeZstd.get_dict_id(dict_data)}"

# Test the dictionary
puts "\nTesting dictionary effectiveness..."
test_data = {
  id: 999,
  name: "Test User",
  email: "test@example.com",
  status: "active",
  preferences: {theme: "dark", notifications: true, language: "en"},
  metadata: {login_count: 42, last_ip: "192.168.1.1"}
}.to_json

# Compress without dictionary
compressed_no_dict = VibeZstd.compress(test_data)

# Compress with dictionary
cdict = VibeZstd::CDict.new(dict_data)
compressed_with_dict = VibeZstd.compress(test_data, dict: cdict)

puts "\nCompression comparison:"
puts "  Original size: #{test_data.bytesize} bytes"
puts "  Without dictionary: #{compressed_no_dict.bytesize} bytes (#{(test_data.bytesize.to_f / compressed_no_dict.bytesize).round(2)}x)"
puts "  With dictionary: #{compressed_with_dict.bytesize} bytes (#{(test_data.bytesize.to_f / compressed_with_dict.bytesize).round(2)}x)"
puts "  Dictionary improvement: #{((compressed_no_dict.bytesize - compressed_with_dict.bytesize).to_f / compressed_no_dict.bytesize * 100).round(1)}% smaller"

# Verify decompression works
ddict = VibeZstd::DDict.new(dict_data)
decompressed = VibeZstd.decompress(compressed_with_dict, dict: ddict)
if decompressed == test_data
  puts "\n✓ Dictionary verification successful!"
else
  puts "\n✗ Dictionary verification FAILED!"
  exit 1
end
