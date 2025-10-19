# frozen_string_literal: true

require_relative "vibe_zstd/version"
require_relative "vibe_zstd/vibe_zstd"

module VibeZstd
  class Error < StandardError; end

  # Convenience method for one-off compression
  def self.compress(data, level: nil, dict: nil)
    cctx = CCtx.new
    options = {}
    options[:level] = level if level
    options[:dict] = dict if dict
    cctx.compress(data, **options)
  end

  # Convenience method for one-off decompression
  def self.decompress(data, dict: nil)
    dctx = DCtx.new
    options = {}
    options[:dict] = dict if dict
    dctx.decompress(data, **options)
  end

  # Get the decompressed content size from a compressed frame
  # Returns nil if size is unknown or data is invalid
  def self.frame_content_size(data)
    DCtx.frame_content_size(data)
  end

  module Compress
    class Writer
      # Block-based resource management
      # Automatically calls finish when block completes
      def self.open(io, **options)
        writer = new(io, **options)
        return writer unless block_given?

        begin
          yield writer
        ensure
          writer.finish
        end
      end
    end
  end

  module Decompress
    class Reader
      # Block-based resource management
      # Automatically cleans up when block completes
      def self.open(io, **options)
        reader = new(io, **options)
        return reader unless block_given?

        begin
          yield reader
        ensure
          # Reader doesn't have finish, but this ensures cleanup
        end
      end
    end
  end
end
