# frozen_string_literal: true

module VibeZstd
  # Frame format constants for compression and decompression
  module Format
    # Standard zstd frame format with magic number (default)
    STANDARD = 0

    # Zstd frame format without initial 4-byte magic number
    # Useful to save 4 bytes per frame, but decoder must be explicitly configured
    MAGICLESS = 1
  end

  # Compression strategy constants, listed from fastest to strongest
  module Strategy
    FAST = 1
    DFAST = 2
    GREEDY = 3
    LAZY = 4
    LAZY2 = 5
    BTLAZY2 = 6
    BTOPT = 7
    BTULTRA = 8
    BTULTRA2 = 9
  end

  # Literal compression mode constants
  module LiteralCompressionMode
    # Automatically determine based on compression level
    # Negative levels = uncompressed, positive levels = compressed
    AUTO = 0

    # Always attempt Huffman compression
    # Uncompressed literals still emitted if not profitable
    HUFFMAN = 1

    # Always emit uncompressed literals
    UNCOMPRESSED = 2
  end

  # Dictionary attachment preference constants
  module DictAttachPref
    # Automatically choose attachment method (default)
    AUTO = 0

    # Force dictionary to be attached by reference
    FORCE_ATTACH = 1

    # Force dictionary to be copied into working context
    FORCE_COPY = 2

    # Force dictionary to be reloaded
    FORCE_LOAD = 3
  end

  # Context reset modes
  module ResetDirective
    # Reset session only, keep parameters
    SESSION = 1

    # Reset parameters to defaults, keep session state
    PARAMETERS = 2

    # Reset both session and parameters (full reset)
    BOTH = 3
  end
end
