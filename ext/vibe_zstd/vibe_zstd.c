#include "vibe_zstd_internal.h"
#include <ruby/thread.h>
#define ZDICT_STATIC_LINKING_ONLY
#include <zdict.h>

// Ruby module and class handles
VALUE rb_mVibeZstd;
VALUE rb_cVibeZstdCCtx;
VALUE rb_cVibeZstdDCtx;
VALUE rb_cVibeZstdCDict;
VALUE rb_cVibeZstdDDict;
VALUE rb_cVibeZstdCompressWriter;
VALUE rb_cVibeZstdDecompressReader;

// Forward declarations for free and mark functions
static void vibe_zstd_cctx_free(void* ptr);
static void vibe_zstd_dctx_free(void* ptr);
static void vibe_zstd_cdict_free(void* ptr);
static void vibe_zstd_ddict_free(void* ptr);
static void vibe_zstd_cstream_free(void* ptr);
static void vibe_zstd_cstream_mark(void* ptr);
static void vibe_zstd_dstream_free(void* ptr);
static void vibe_zstd_dstream_mark(void* ptr);

// TypedData type definitions (these are referenced by extern in the split files)
rb_data_type_t vibe_zstd_cctx_type = {
    .wrap_struct_name = "vibe_zstd_cctx",
    .function = {
        .dmark = NULL,
        .dfree = (RUBY_DATA_FUNC)vibe_zstd_cctx_free,
        .dsize = NULL,
    },
    .data = NULL,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

rb_data_type_t vibe_zstd_dctx_type = {
    .wrap_struct_name = "vibe_zstd_dctx",
    .function = {
        .dmark = NULL,
        .dfree = (RUBY_DATA_FUNC)vibe_zstd_dctx_free,
        .dsize = NULL,
    },
    .data = NULL,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

rb_data_type_t vibe_zstd_cdict_type = {
    .wrap_struct_name = "vibe_zstd_cdict",
    .function = {
        .dmark = NULL,
        .dfree = (RUBY_DATA_FUNC)vibe_zstd_cdict_free,
        .dsize = NULL,
    },
    .data = NULL,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

rb_data_type_t vibe_zstd_ddict_type = {
    .wrap_struct_name = "vibe_zstd_ddict",
    .function = {
        .dmark = NULL,
        .dfree = (RUBY_DATA_FUNC)vibe_zstd_ddict_free,
        .dsize = NULL,
    },
    .data = NULL,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

rb_data_type_t vibe_zstd_cstream_type = {
    .wrap_struct_name = "vibe_zstd_cstream",
    .function = {
        .dmark = (RUBY_DATA_FUNC)vibe_zstd_cstream_mark,
        .dfree = (RUBY_DATA_FUNC)vibe_zstd_cstream_free,
        .dsize = NULL,
    },
    .data = NULL,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

rb_data_type_t vibe_zstd_dstream_type = {
    .wrap_struct_name = "vibe_zstd_dstream",
    .function = {
        .dmark = (RUBY_DATA_FUNC)vibe_zstd_dstream_mark,
        .dfree = (RUBY_DATA_FUNC)vibe_zstd_dstream_free,
        .dsize = NULL,
    },
    .data = NULL,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

// Free functions
static void
vibe_zstd_cctx_free(void* ptr) {
    vibe_zstd_cctx* cctx = ptr;
    if (cctx->cctx) {
        ZSTD_freeCCtx(cctx->cctx);
    }
    ruby_xfree(cctx);
}

static void
vibe_zstd_dctx_free(void* ptr) {
    vibe_zstd_dctx* dctx = ptr;
    if (dctx->dctx) {
        ZSTD_freeDCtx(dctx->dctx);
    }
    ruby_xfree(dctx);
}

static void
vibe_zstd_cdict_free(void* ptr) {
    vibe_zstd_cdict* cdict = ptr;
    if (cdict->cdict) {
        ZSTD_freeCDict(cdict->cdict);
    }
    ruby_xfree(cdict);
}

static void
vibe_zstd_ddict_free(void* ptr) {
    vibe_zstd_ddict* ddict = ptr;
    if (ddict->ddict) {
        ZSTD_freeDDict(ddict->ddict);
    }
    ruby_xfree(ddict);
}

static void
vibe_zstd_cstream_mark(void* ptr) {
    vibe_zstd_cstream* cstream = ptr;
    rb_gc_mark(cstream->io);
}

static void
vibe_zstd_cstream_free(void* ptr) {
    vibe_zstd_cstream* cstream = ptr;
    if (cstream->cstream) {
        ZSTD_freeCStream(cstream->cstream);
    }
    ruby_xfree(cstream);
}

static void
vibe_zstd_dstream_mark(void* ptr) {
    vibe_zstd_dstream* dstream = ptr;
    rb_gc_mark(dstream->io);
    rb_gc_mark(dstream->input_data);
}

static void
vibe_zstd_dstream_free(void* ptr) {
    vibe_zstd_dstream* dstream = ptr;
    if (dstream->dstream) {
        ZSTD_freeDStream(dstream->dstream);
    }
    ruby_xfree(dstream);
}

// Alloc functions
static VALUE
vibe_zstd_cctx_alloc(VALUE klass) {
    vibe_zstd_cctx* cctx = ALLOC(vibe_zstd_cctx);
    cctx->cctx = ZSTD_createCCtx();
    if (!cctx->cctx) {
        ruby_xfree(cctx);
        rb_raise(rb_eRuntimeError, "Failed to create ZSTD_CCtx");
    }
    return TypedData_Wrap_Struct(klass, &vibe_zstd_cctx_type, cctx);
}

static VALUE
vibe_zstd_dctx_alloc(VALUE klass) {
    vibe_zstd_dctx* dctx = ALLOC(vibe_zstd_dctx);
    dctx->dctx = ZSTD_createDCtx();
    if (!dctx->dctx) {
        ruby_xfree(dctx);
        rb_raise(rb_eRuntimeError, "Failed to create ZSTD_DCtx");
    }
    dctx->initial_capacity = 0;  // 0 = use class default
    return TypedData_Wrap_Struct(klass, &vibe_zstd_dctx_type, dctx);
}

static VALUE
vibe_zstd_cdict_alloc(VALUE klass) {
    vibe_zstd_cdict* cdict = ALLOC(vibe_zstd_cdict);
    cdict->cdict = NULL; // Will be set in initialize
    return TypedData_Wrap_Struct(klass, &vibe_zstd_cdict_type, cdict);
}

static VALUE
vibe_zstd_ddict_alloc(VALUE klass) {
    vibe_zstd_ddict* ddict = ALLOC(vibe_zstd_ddict);
    ddict->ddict = NULL; // Will be set in initialize
    return TypedData_Wrap_Struct(klass, &vibe_zstd_ddict_type, ddict);
}

static VALUE
vibe_zstd_cstream_alloc(VALUE klass) {
    vibe_zstd_cstream* cstream = ALLOC(vibe_zstd_cstream);
    cstream->cstream = NULL;
    cstream->io = Qnil;
    return TypedData_Wrap_Struct(klass, &vibe_zstd_cstream_type, cstream);
}

static VALUE
vibe_zstd_dstream_alloc(VALUE klass) {
    vibe_zstd_dstream* dstream = ALLOC(vibe_zstd_dstream);
    dstream->dstream = NULL;
    dstream->io = Qnil;
    dstream->input_data = Qnil;
    dstream->input.src = NULL;
    dstream->input.size = 0;
    dstream->input.pos = 0;
    return TypedData_Wrap_Struct(klass, &vibe_zstd_dstream_type, dstream);
}

// Module-level version and compression level functions
static VALUE
vibe_zstd_version_number(VALUE self) {
    (void)self;
    return UINT2NUM(ZSTD_versionNumber());
}

static VALUE
vibe_zstd_version_string(VALUE self) {
    (void)self;
    return rb_str_new_cstr(ZSTD_versionString());
}

static VALUE
vibe_zstd_min_c_level(VALUE self) {
    (void)self;
    return INT2NUM(ZSTD_minCLevel());
}

static VALUE
vibe_zstd_max_c_level(VALUE self) {
    (void)self;
    return INT2NUM(ZSTD_maxCLevel());
}

static VALUE
vibe_zstd_default_c_level(VALUE self) {
    (void)self;
    return INT2NUM(ZSTD_defaultCLevel());
}

// Include the split implementation files
#include "cctx.c"
#include "dctx.c"
#include "dict.c"
#include "streaming.c"
#include "frames.c"

// Main initialization function
RUBY_FUNC_EXPORTED void
Init_vibe_zstd(void)
{
  // Initialize parameter lookup tables
  init_cctx_param_table();
  init_dctx_param_table();

  rb_mVibeZstd = rb_define_module("VibeZstd");

  // Define classes
  rb_cVibeZstdCCtx = rb_define_class_under(rb_mVibeZstd, "CCtx", rb_cObject);
  rb_cVibeZstdDCtx = rb_define_class_under(rb_mVibeZstd, "DCtx", rb_cObject);
  rb_cVibeZstdCDict = rb_define_class_under(rb_mVibeZstd, "CDict", rb_cObject);
  rb_cVibeZstdDDict = rb_define_class_under(rb_mVibeZstd, "DDict", rb_cObject);
  rb_cVibeZstdCompressWriter = rb_define_class_under(rb_mVibeZstd, "CompressWriter", rb_cObject);
  rb_cVibeZstdDecompressReader = rb_define_class_under(rb_mVibeZstd, "DecompressReader", rb_cObject);

  // Initialize each subsystem
  vibe_zstd_cctx_init_class(rb_cVibeZstdCCtx);
  vibe_zstd_dctx_init_class(rb_cVibeZstdDCtx);
  vibe_zstd_dict_init_classes(rb_cVibeZstdCDict, rb_cVibeZstdDDict);
  vibe_zstd_dict_init_module_methods(rb_mVibeZstd);
  vibe_zstd_streaming_init_classes(rb_cVibeZstdCompressWriter, rb_cVibeZstdDecompressReader);
  vibe_zstd_frames_init_module_methods(rb_mVibeZstd);

  // Module-level version information
  rb_define_module_function(rb_mVibeZstd, "version_number", vibe_zstd_version_number, 0);
  rb_define_module_function(rb_mVibeZstd, "version_string", vibe_zstd_version_string, 0);
  rb_define_module_function(rb_mVibeZstd, "min_compression_level", vibe_zstd_min_c_level, 0);
  rb_define_module_function(rb_mVibeZstd, "max_compression_level", vibe_zstd_max_c_level, 0);
  rb_define_module_function(rb_mVibeZstd, "default_compression_level", vibe_zstd_default_c_level, 0);

  // Aliases
  rb_define_module_function(rb_mVibeZstd, "min_level", vibe_zstd_min_c_level, 0);
  rb_define_module_function(rb_mVibeZstd, "max_level", vibe_zstd_max_c_level, 0);
  rb_define_module_function(rb_mVibeZstd, "default_level", vibe_zstd_default_c_level, 0);
}
