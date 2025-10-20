# frozen_string_literal: true

require "mkmf"

# Check for Zstandard library
abort "zstd library is missing. Please install libzstd." if !pkg_config("libzstd") && !have_library("zstd")

# Makes all symbols private by default to avoid unintended conflict
# with other gems. To explicitly export symbols you can use RUBY_FUNC_EXPORTED
# selectively, or entirely remove this flag.
append_cflags("-fvisibility=hidden")

# Only compile the main vibe_zstd.c file - it includes the split files via #include
$srcs = ["vibe_zstd.c"] # standard:disable Style/GlobalVars

create_makefile("vibe_zstd/vibe_zstd")
