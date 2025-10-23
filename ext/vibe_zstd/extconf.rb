# frozen_string_literal: true

require "mkmf"

# Use vendored zstd library
LIBZSTD_DIR = File.expand_path("libzstd", __dir__)

# Add include paths for vendored zstd headers
# standard:disable Style/GlobalVars
$INCFLAGS << " -I#{LIBZSTD_DIR}"
$INCFLAGS << " -I#{LIBZSTD_DIR}/common"
$INCFLAGS << " -I#{LIBZSTD_DIR}/compress"
$INCFLAGS << " -I#{LIBZSTD_DIR}/decompress"
$INCFLAGS << " -I#{LIBZSTD_DIR}/dictBuilder"
# standard:enable Style/GlobalVars

# Add preprocessor definitions
append_cflags("-DXXH_NAMESPACE=ZSTD_")
append_cflags("-DZSTD_LEGACY_SUPPORT=0")  # Disable legacy support to reduce size
append_cflags("-DZSTD_MULTITHREAD")  # Enable multithreading support

# Link with pthread for multithreading
have_library("pthread") || abort("pthread library is required for multithreading support")

# Makes all symbols private by default to avoid unintended conflict
# with other gems. To explicitly export symbols you can use RUBY_FUNC_EXPORTED
# selectively, or entirely remove this flag.
append_cflags("-fvisibility=hidden")

# Gather all vendored zstd source files
zstd_sources = Dir[
  "#{LIBZSTD_DIR}/common/*.c",
  "#{LIBZSTD_DIR}/compress/*.c",
  "#{LIBZSTD_DIR}/decompress/*.c",
  "#{LIBZSTD_DIR}/dictBuilder/*.c",
  "#{LIBZSTD_DIR}/deprecated/*.c"
].map { |path| File.basename(path) }

# Add the main vibe_zstd.c file (which includes the split files via #include)
# standard:disable Style/GlobalVars
$srcs = ["vibe_zstd.c"] + zstd_sources

# Set vpath to find source files in subdirectories
$VPATH ||= []
$VPATH << "$(srcdir)/libzstd/common"
$VPATH << "$(srcdir)/libzstd/compress"
$VPATH << "$(srcdir)/libzstd/decompress"
$VPATH << "$(srcdir)/libzstd/dictBuilder"
$VPATH << "$(srcdir)/libzstd/deprecated"
# standard:enable Style/GlobalVars

create_makefile("vibe_zstd/vibe_zstd")
