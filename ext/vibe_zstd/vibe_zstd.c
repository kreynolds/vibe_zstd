#include "vibe_zstd.h"

VALUE rb_mVibeZstd;

RUBY_FUNC_EXPORTED void
Init_vibe_zstd(void)
{
  rb_mVibeZstd = rb_define_module("VibeZstd");
}
