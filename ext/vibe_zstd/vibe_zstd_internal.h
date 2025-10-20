#ifndef VIBE_ZSTD_INTERNAL_H
#define VIBE_ZSTD_INTERNAL_H 1

#include "vibe_zstd.h"
#include <ruby/thread.h>
#define ZDICT_STATIC_LINKING_ONLY
#include <zdict.h>

// Function declarations for cross-file usage

// CCtx functions (cctx.c)
void vibe_zstd_cctx_init_class(VALUE rb_cVibeZstdCCtx);

// DCtx functions (dctx.c)
void vibe_zstd_dctx_init_class(VALUE rb_cVibeZstdDCtx);

// Dictionary functions (dict.c)
void vibe_zstd_dict_init_classes(VALUE rb_cVibeZstdCDict, VALUE rb_cVibeZstdDDict);
void vibe_zstd_dict_init_module_methods(VALUE rb_mVibeZstd);

// Streaming functions (streaming.c)
void vibe_zstd_streaming_init_classes(VALUE rb_cVibeZstdCompressWriter, VALUE rb_cVibeZstdDecompressReader);

// Frame utility functions (frames.c)
void vibe_zstd_frames_init_module_methods(VALUE rb_mVibeZstd);

#endif /* VIBE_ZSTD_INTERNAL_H */
