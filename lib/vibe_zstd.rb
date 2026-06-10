# frozen_string_literal: true

require_relative "vibe_zstd/version"
require "vibe_zstd/vibe_zstd"
require_relative "vibe_zstd/constants"

module VibeZstd
  class Error < StandardError; end

  # Keyword options handled per-operation by CCtx#compress / DCtx#decompress.
  # Any other keyword is treated as a context (sticky) parameter and applied via
  # the constructor, so e.g. VibeZstd.compress(data, checksum_flag: true) and
  # VibeZstd.decompress(data, format: 1) work through the convenience methods.
  # An unknown keyword raises NoMethodError from the corresponding setter.
  COMPRESS_CALL_OPTIONS = %i[level dict pledged_size].freeze
  DECOMPRESS_CALL_OPTIONS = %i[dict initial_capacity max_decompressed_size max_size].freeze
  private_constant :COMPRESS_CALL_OPTIONS, :DECOMPRESS_CALL_OPTIONS

  # Convenience method for one-off compression.
  # Per-call options (level, dict, pledged_size) are passed to #compress; any
  # other keyword is a context parameter (e.g. checksum_flag:, window_log:,
  # workers:, format:) applied to a fresh CCtx.
  def self.compress(data, **options)
    call_opts = options.slice(*COMPRESS_CALL_OPTIONS)
    ctx_opts = options.except(*COMPRESS_CALL_OPTIONS)
    CCtx.new(**ctx_opts).compress(data, **call_opts)
  end

  # Convenience method for one-off decompression.
  # Per-call options (dict, initial_capacity, max_decompressed_size/max_size) are
  # passed to #decompress; any other keyword is a context parameter (e.g.
  # format:, window_log_max:) applied to a fresh DCtx.
  def self.decompress(data, **options)
    call_opts = options.slice(*DECOMPRESS_CALL_OPTIONS)
    ctx_opts = options.except(*DECOMPRESS_CALL_OPTIONS)
    DCtx.new(**ctx_opts).decompress(data, **call_opts)
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

      # Defense: Prevent infinite loop on malformed data
      # A valid frame must have non-zero size (at minimum: frame header)
      raise Error, "Invalid frame: zero or negative size at offset #{offset}" if frame_size <= 0

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

  # Add helper method to CDict for creating matching DDict
  class CDict
    # Get or create a matching DDict from this CDict's dictionary data
    # The DDict is cached so it's only created once
    #
    # @return [DDict] Decompression dictionary matching this compression dictionary
    def to_ddict
      @ddict ||= DDict.new(@dict_data)
    end
    alias_method :ddict, :to_ddict
  end

  # Thread-local context pooling for high-performance reuse
  # Ideal for Rails/Puma applications where threads are reused across requests
  #
  # Example usage:
  #   # In Rails model with encrypted attributes
  #   class User < ApplicationRecord
  #     encrypts :email
  #     encrypts :preferences, dict: JSON_DICT
  #   end
  #
  #   # Instead of:
  #   VibeZstd.decompress(data, dict: dict)  # Creates new DCtx each time
  #
  #   # Use:
  #   VibeZstd::ThreadLocal.decompress(data, dict: dict)  # Reuses DCtx per thread
  #
  # Memory footprint: ~128KB per DCtx × unique dictionaries × threads
  # Example: 3 dicts × 5 Puma threads = 1.9MB total
  #
  # Note: Only supports per-operation parameters (level, dict, pledged_size, initial_capacity)
  # Does NOT support context-level settings (nb_workers, checksum_flag, etc.)
  module ThreadLocal
    # Compress data using thread-local context pool
    # Contexts are keyed by dictionary ID for automatic isolation
    #
    # @param data [String] Data to compress
    # @param level [Integer] Compression level (per-operation, can vary)
    # @param dict [CDict] Compression dictionary (optional)
    # @param pledged_size [Integer] Expected input size (optional)
    # @return [String] Compressed data
    def self.compress(data, level: nil, dict: nil, pledged_size: nil)
      # Key by dictionary ID, or :default if no dict
      key = dict ? dict.dict_id : :default

      # Get or create thread-local context pool
      Thread.current[:vibe_zstd_cctx_pool] ||= {}
      cctx = Thread.current[:vibe_zstd_cctx_pool][key] ||= VibeZstd::CCtx.new

      # Build options hash
      options = {}
      options[:level] = level if level
      options[:dict] = dict if dict
      options[:pledged_size] = pledged_size if pledged_size

      cctx.compress(data, **options)
    end

    # Decompress data using thread-local context pool
    # Contexts are keyed by dictionary ID for automatic isolation
    #
    # @param data [String] Data to decompress
    # @param dict [DDict] Decompression dictionary (optional)
    # @param initial_capacity [Integer] Initial buffer size for unknown-size frames (optional)
    # @param max_decompressed_size [Integer] Output-size limit; raises DecompressedSizeExceeded if exceeded (optional)
    # @return [String] Decompressed data
    def self.decompress(data, dict: nil, initial_capacity: nil, max_decompressed_size: nil)
      key = dict ? dict.dict_id : :default

      # Get or create thread-local context pool
      Thread.current[:vibe_zstd_dctx_pool] ||= {}
      dctx = Thread.current[:vibe_zstd_dctx_pool][key] ||= VibeZstd::DCtx.new

      # Build options hash
      options = {}
      options[:dict] = dict if dict
      options[:initial_capacity] = initial_capacity if initial_capacity
      options[:max_decompressed_size] = max_decompressed_size if max_decompressed_size

      # C code will validate dict matches frame requirements
      dctx.decompress(data, **options)
    end

    # Clear all thread-local context pools for the current thread
    # Useful for testing or explicit memory management
    def self.clear_thread_cache!
      Thread.current[:vibe_zstd_cctx_pool] = {}
      Thread.current[:vibe_zstd_dctx_pool] = {}
      nil
    end

    # Get statistics about the current thread's context pools
    # @return [Hash] Pool statistics
    def self.thread_cache_stats
      {
        compression_contexts: Thread.current[:vibe_zstd_cctx_pool]&.size || 0,
        decompression_contexts: Thread.current[:vibe_zstd_dctx_pool]&.size || 0,
        compression_keys: Thread.current[:vibe_zstd_cctx_pool]&.keys || [],
        decompression_keys: Thread.current[:vibe_zstd_dctx_pool]&.keys || []
      }
    end
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
    # Drains any buffered data from line_buffer first
    def read_all
      chunks = []
      # Drain line buffer first if present
      if @line_buffer && !@line_buffer.empty?
        chunks << @line_buffer
        @line_buffer = +""
      end
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

    # Read a single line (up to separator or EOF)
    # Uses buffered reads (8192 bytes) instead of byte-at-a-time for performance.
    # Orders of magnitude faster for line-oriented reading.
    def gets(sep = $/)
      return nil if eof? && (@line_buffer.nil? || @line_buffer.empty?)

      @line_buffer ||= +""

      loop do
        # Check buffer for separator
        if (idx = @line_buffer.index(sep))
          return @line_buffer.slice!(0, idx + sep.bytesize)
        end

        # Read more data in larger chunks
        chunk = read(8192)
        break unless chunk

        @line_buffer << chunk
      end

      # Return remaining buffer or nil
      @line_buffer.empty? ? nil : @line_buffer.slice!(0, @line_buffer.bytesize)
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
