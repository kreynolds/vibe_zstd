# frozen_string_literal: true

require_relative "vibe_zstd/version"
require_relative "vibe_zstd/vibe_zstd"
require_relative "vibe_zstd/constants"

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

  # Iterate over all skippable frames in the data
  # Yields [content, magic_variant, offset] for each skippable frame
  def self.each_skippable_frame(data)
    return enum_for(:each_skippable_frame, data) unless block_given?

    offset = 0
    while offset < data.bytesize
      frame_data = data.byteslice(offset..-1)
      frame_size = find_frame_compressed_size(frame_data)

      if skippable_frame?(frame_data)
        content, magic_variant = read_skippable_frame(frame_data)
        yield content, magic_variant, offset
      end

      offset += frame_size
    end
  end

  # Convenient aliases for version/level methods
  class << self
    alias_method :min_level, :min_compression_level
    alias_method :max_level, :max_compression_level
    alias_method :default_level, :default_compression_level
  end

  class CompressWriter
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

  class DecompressReader
    include Enumerable

    # Block-based resource management
    # Automatically cleans up when block completes
    def self.open(io, **options)
      reader = new(io, **options)
      return reader unless block_given?

      yield reader

      # Reader doesn't have finish, but this ensures cleanup
    end

    # Read all remaining data
    def read_all
      chunks = []
      while (chunk = read)
        chunks << chunk
      end
      chunks.join
    end

    # Alias for eof?
    def eof
      eof?
    end

    # Iterate over chunks (required for Enumerable)
    def each(chunk_size = nil)
      return enum_for(:each, chunk_size) unless block_given?

      until eof?
        chunk = read(chunk_size)
        yield chunk if chunk
      end
    end

    # Read a single line (up to newline or EOF)
    def gets(sep = $/)
      return nil if eof?

      line = +""
      until eof?
        chunk = read(1)
        break unless chunk

        line << chunk
        break if chunk.end_with?(sep)
      end

      line.empty? ? nil : line
    end

    # Iterate over lines
    def each_line(sep = $/)
      return enum_for(:each_line, sep) unless block_given?

      while (line = gets(sep))
        yield line
      end
    end

    # Alias for gets
    alias_method :readline, :gets

    # Read exactly n bytes, or raise EOFError
    def readpartial(maxlen)
      raise EOFError, "end of file reached" if eof?

      data = read(maxlen)
      raise EOFError, "end of file reached" if data.nil?

      data
    end
  end
end
