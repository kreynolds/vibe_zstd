#ifndef VIBE_ZSTD_H
#define VIBE_ZSTD_H 1

#include "ruby.h"
#define ZSTD_STATIC_LINKING_ONLY
#include <zstd.h>

// TypedData structs
typedef struct {
    ZSTD_CCtx* cctx;
} vibe_zstd_cctx;

typedef struct {
    ZSTD_DCtx* dctx;
    size_t initial_capacity;  // Initial capacity for unknown-size decompression (0 = use class default)
} vibe_zstd_dctx;

typedef struct {
    ZSTD_CDict* cdict;
} vibe_zstd_cdict;

typedef struct {
    ZSTD_DDict* ddict;
} vibe_zstd_ddict;

typedef struct {
    ZSTD_CStream* cstream;
    VALUE io;
} vibe_zstd_cstream;

typedef struct {
    ZSTD_DStream* dstream;
    VALUE io;
    ZSTD_inBuffer input;  // Zstandard manages the buffer state
    VALUE input_data;      // Ruby string holding input data
    int eof;               // Flag to track if we've reached end of stream
    size_t initial_chunk_size;  // Initial chunk size for unbounded reads (0 = use default)
} vibe_zstd_dstream;

// TypedData types
extern rb_data_type_t vibe_zstd_cctx_type;
extern rb_data_type_t vibe_zstd_dctx_type;
extern rb_data_type_t vibe_zstd_cdict_type;
extern rb_data_type_t vibe_zstd_ddict_type;
extern rb_data_type_t vibe_zstd_cstream_type;
extern rb_data_type_t vibe_zstd_dstream_type;

// Ruby classes and modules
extern VALUE rb_cVibeZstdCCtx;
extern VALUE rb_cVibeZstdDCtx;
extern VALUE rb_cVibeZstdCDict;
extern VALUE rb_cVibeZstdDDict;
extern VALUE rb_cVibeZstdCompressWriter;
extern VALUE rb_cVibeZstdDecompressReader;

#endif /* VIBE_ZSTD_H */
