# frozen_string_literal: true

require_relative "vibe_zstd/version"
require_relative "vibe_zstd/vibe_zstd"

module VibeZstd
  class Error < StandardError; end

  # Convenience method for one-off compression
  def self.compress(data, level: nil, dict: nil)
    cctx = CCtx.new
    cctx.compress(data, level, dict)
  end

  # Convenience method for one-off decompression
  def self.decompress(data, dict: nil)
    dctx = DCtx.new
    dctx.decompress(data, dict)
  end

  # Get the decompressed content size from a compressed frame
  # Returns nil if size is unknown or data is invalid
  def self.frame_content_size(data)
    DCtx.frame_content_size(data)
  end
end
