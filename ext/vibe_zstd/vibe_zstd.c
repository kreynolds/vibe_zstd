#include "vibe_zstd.h"
#include <ruby/thread.h>
#include <zdict.h>

VALUE rb_mVibeZstd;
VALUE rb_cVibeZstdCCtx;
VALUE rb_cVibeZstdDCtx;
VALUE rb_cVibeZstdCDict;
VALUE rb_cVibeZstdDDict;
VALUE rb_mVibeZstdCompress;
VALUE rb_mVibeZstdDecompress;
VALUE rb_cVibeZstdCompressWriter;
VALUE rb_cVibeZstdDecompressReader;

// Forward declarations
static void vibe_zstd_cctx_free(void* ptr);
static void vibe_zstd_dctx_free(void* ptr);
static void vibe_zstd_cdict_free(void* ptr);
static void vibe_zstd_ddict_free(void* ptr);
static void vibe_zstd_cstream_free(void* ptr);
static void vibe_zstd_cstream_mark(void* ptr);
static void vibe_zstd_dstream_free(void* ptr);
static void vibe_zstd_dstream_mark(void* ptr);

// TypedData types
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

// Initialize functions
static VALUE
vibe_zstd_cctx_initialize(VALUE self) {
    return self;
}

static VALUE
vibe_zstd_dctx_initialize(VALUE self) {
    return self;
}

static VALUE
vibe_zstd_cdict_initialize(int argc, VALUE* argv, VALUE self) {
    VALUE dict_data, level = Qnil;
    rb_scan_args(argc, argv, "11", &dict_data, &level);
    vibe_zstd_cdict* cdict;
    TypedData_Get_Struct(self, vibe_zstd_cdict, &vibe_zstd_cdict_type, cdict);
    StringValue(dict_data);
    int lvl = NIL_P(level) ? ZSTD_defaultCLevel() : NUM2INT(level);
    cdict->cdict = ZSTD_createCDict(RSTRING_PTR(dict_data), RSTRING_LEN(dict_data), lvl);
    if (!cdict->cdict) {
        rb_raise(rb_eRuntimeError, "Failed to create ZSTD_CDict");
    }

    // Store dictionary data and level for later retrieval
    rb_ivar_set(self, rb_intern("@dict_data"), dict_data);
    rb_ivar_set(self, rb_intern("@compression_level"), INT2NUM(lvl));

    return self;
}

// CDict size method - returns the size in memory
static VALUE
vibe_zstd_cdict_size(VALUE self) {
    vibe_zstd_cdict* cdict;
    TypedData_Get_Struct(self, vibe_zstd_cdict, &vibe_zstd_cdict_type, cdict);
    if (!cdict->cdict) {
        rb_raise(rb_eRuntimeError, "CDict not initialized");
    }
    size_t size = ZSTD_sizeof_CDict(cdict->cdict);
    return SIZET2NUM(size);
}

// CDict dict_id method - returns dictionary ID
static VALUE
vibe_zstd_cdict_dict_id(VALUE self) {
    vibe_zstd_cdict* cdict;
    TypedData_Get_Struct(self, vibe_zstd_cdict, &vibe_zstd_cdict_type, cdict);
    if (!cdict->cdict) {
        rb_raise(rb_eRuntimeError, "CDict not initialized");
    }
    unsigned dictID = ZSTD_getDictID_fromCDict(cdict->cdict);
    return UINT2NUM(dictID);
}

static VALUE
vibe_zstd_ddict_initialize(VALUE self, VALUE dict_data) {
    vibe_zstd_ddict* ddict;
    TypedData_Get_Struct(self, vibe_zstd_ddict, &vibe_zstd_ddict_type, ddict);
    StringValue(dict_data);
    ddict->ddict = ZSTD_createDDict(RSTRING_PTR(dict_data), RSTRING_LEN(dict_data));
    if (!ddict->ddict) {
        rb_raise(rb_eRuntimeError, "Failed to create ZSTD_DDict");
    }
    return self;
}

// DDict size method - returns the size in memory
static VALUE
vibe_zstd_ddict_size(VALUE self) {
    vibe_zstd_ddict* ddict;
    TypedData_Get_Struct(self, vibe_zstd_ddict, &vibe_zstd_ddict_type, ddict);
    if (!ddict->ddict) {
        rb_raise(rb_eRuntimeError, "DDict not initialized");
    }
    size_t size = ZSTD_sizeof_DDict(ddict->ddict);
    return SIZET2NUM(size);
}

// DDict dict_id method - returns dictionary ID
static VALUE
vibe_zstd_ddict_dict_id(VALUE self) {
    vibe_zstd_ddict* ddict;
    TypedData_Get_Struct(self, vibe_zstd_ddict, &vibe_zstd_ddict_type, ddict);
    if (!ddict->ddict) {
        rb_raise(rb_eRuntimeError, "DDict not initialized");
    }
    unsigned dictID = ZSTD_getDictID_fromDDict(ddict->ddict);
    return UINT2NUM(dictID);
}

// Train dictionary from samples - module-level method
// VibeZstd.train_dict(samples, max_dict_size: 112640)
static VALUE
vibe_zstd_train_dict(int argc, VALUE* argv, VALUE self) {
    VALUE samples, options;
    rb_scan_args(argc, argv, "1:", &samples, &options);

    // Parse samples array
    Check_Type(samples, T_ARRAY);
    long num_samples = RARRAY_LEN(samples);

    if (num_samples == 0) {
        rb_raise(rb_eArgError, "samples array cannot be empty");
    }

    // Parse options
    VALUE max_dict_size_val = Qnil;
    if (!NIL_P(options)) {
        max_dict_size_val = rb_hash_aref(options, ID2SYM(rb_intern("max_dict_size")));
    }

    // Default max dictionary size is 112KB (zstd default)
    size_t max_dict_size = NIL_P(max_dict_size_val) ? (112 * 1024) : NUM2SIZET(max_dict_size_val);

    // Calculate total samples size and prepare arrays
    size_t* sample_sizes = ALLOC_N(size_t, num_samples);
    size_t total_samples_size = 0;

    for (long i = 0; i < num_samples; i++) {
        VALUE sample = rb_ary_entry(samples, i);
        StringValue(sample);
        sample_sizes[i] = RSTRING_LEN(sample);
        total_samples_size += sample_sizes[i];
    }

    // Allocate and concatenate all samples into single buffer
    char* samples_buffer = ALLOC_N(char, total_samples_size);
    size_t offset = 0;

    for (long i = 0; i < num_samples; i++) {
        VALUE sample = rb_ary_entry(samples, i);
        memcpy(samples_buffer + offset, RSTRING_PTR(sample), sample_sizes[i]);
        offset += sample_sizes[i];
    }

    // Allocate dictionary buffer
    void* dict_buffer = ALLOC_N(char, max_dict_size);

    // Train the dictionary
    size_t dict_size = ZDICT_trainFromBuffer(
        dict_buffer, max_dict_size,
        samples_buffer, sample_sizes, (unsigned)num_samples
    );

    // Clean up
    xfree(samples_buffer);
    xfree(sample_sizes);

    // Check for errors
    if (ZDICT_isError(dict_size)) {
        xfree(dict_buffer);
        rb_raise(rb_eRuntimeError, "Dictionary training failed: %s", ZDICT_getErrorName(dict_size));
    }

    // Create Ruby string with the trained dictionary
    VALUE dict_string = rb_str_new(dict_buffer, dict_size);
    xfree(dict_buffer);

    return dict_string;
}

// Get dictionary ID from raw dictionary data - module-level utility
// VibeZstd.get_dict_id(dict_data)
static VALUE
vibe_zstd_get_dict_id(VALUE self, VALUE dict_data) {
    StringValue(dict_data);
    unsigned dict_id = ZDICT_getDictID(RSTRING_PTR(dict_data), RSTRING_LEN(dict_data));
    return UINT2NUM(dict_id);
}

// Compress args for GVL
typedef struct {
    ZSTD_CCtx* cctx;
    ZSTD_CDict* cdict;
    const void* src;
    size_t srcSize;
    void* dst;
    size_t dstCapacity;
    int compressionLevel;
    size_t result;
} compress_args;

static void*
compress_without_gvl(void* arg) {
    compress_args* args = arg;
    if (args->cdict) {
        args->result = ZSTD_compress_usingCDict(args->cctx, args->dst, args->dstCapacity, args->src, args->srcSize, args->cdict);
    } else {
        args->result = ZSTD_compressCCtx(args->cctx, args->dst, args->dstCapacity, args->src, args->srcSize, args->compressionLevel);
    }
    return NULL;
}

// CCtx compress
static VALUE
vibe_zstd_cctx_compress(int argc, VALUE* argv, VALUE self) {
    VALUE data, level = Qnil, dict = Qnil;
    rb_scan_args(argc, argv, "12", &data, &level, &dict);
    vibe_zstd_cctx* cctx;
    TypedData_Get_Struct(self, vibe_zstd_cctx, &vibe_zstd_cctx_type, cctx);
    StringValue(data);
    int lvl = NIL_P(level) ? ZSTD_defaultCLevel() : NUM2INT(level);
    ZSTD_CDict* cdict = NULL;
    if (!NIL_P(dict)) {
        vibe_zstd_cdict* cdict_struct;
        TypedData_Get_Struct(dict, vibe_zstd_cdict, &vibe_zstd_cdict_type, cdict_struct);
        cdict = cdict_struct->cdict;
    }
    size_t srcSize = RSTRING_LEN(data);
    size_t dstCapacity = ZSTD_compressBound(srcSize);
    VALUE result = rb_str_new(NULL, dstCapacity);
    compress_args args = {
        .cctx = cctx->cctx,
        .cdict = cdict,
        .src = RSTRING_PTR(data),
        .srcSize = srcSize,
        .dst = RSTRING_PTR(result),
        .dstCapacity = dstCapacity,
        .compressionLevel = lvl,
        .result = 0
    };
    rb_thread_call_without_gvl(compress_without_gvl, &args, NULL, NULL);
    if (ZSTD_isError(args.result)) {
        rb_raise(rb_eRuntimeError, "Compression failed: %s", ZSTD_getErrorName(args.result));
    }
    rb_str_set_len(result, args.result);
    return result;
}

// Decompress args for GVL
typedef struct {
    ZSTD_DCtx* dctx;
    ZSTD_DDict* ddict;
    const void* src;
    size_t srcSize;
    void* dst;
    size_t dstCapacity;
    size_t result;
} decompress_args;

static void*
decompress_without_gvl(void* arg) {
    decompress_args* args = arg;
    if (args->ddict) {
        args->result = ZSTD_decompress_usingDDict(args->dctx, args->dst, args->dstCapacity, args->src, args->srcSize, args->ddict);
    } else {
        args->result = ZSTD_decompressDCtx(args->dctx, args->dst, args->dstCapacity, args->src, args->srcSize);
    }
    return NULL;
}

// DCtx frame_content_size - class method to get frame content size
static VALUE
vibe_zstd_dctx_frame_content_size(VALUE self, VALUE data) {
    StringValue(data);
    unsigned long long contentSize = ZSTD_getFrameContentSize(RSTRING_PTR(data), RSTRING_LEN(data));

    if (contentSize == ZSTD_CONTENTSIZE_ERROR) {
        return Qnil;  // Invalid frame
    }

    if (contentSize == ZSTD_CONTENTSIZE_UNKNOWN) {
        return Qnil;  // Unknown size
    }

    return ULL2NUM(contentSize);
}

// DCtx decompress
static VALUE
vibe_zstd_dctx_decompress(int argc, VALUE* argv, VALUE self) {
    VALUE data, dict = Qnil;
    rb_scan_args(argc, argv, "11", &data, &dict);
    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);
    StringValue(data);
    size_t srcSize = RSTRING_LEN(data);
    unsigned long long contentSize = ZSTD_getFrameContentSize(RSTRING_PTR(data), srcSize);
    if (contentSize == ZSTD_CONTENTSIZE_ERROR) {
        rb_raise(rb_eRuntimeError, "Invalid compressed data");
    }

    // If content size is unknown, use streaming decompression
    if (contentSize == ZSTD_CONTENTSIZE_UNKNOWN) {
        size_t dstCapacity = ZSTD_DStreamOutSize();
        VALUE result = rb_str_new(NULL, 0);
        VALUE tmpBuffer = rb_str_buf_new(dstCapacity);

        ZSTD_inBuffer input = { RSTRING_PTR(data), srcSize, 0 };

        while (input.pos < input.size) {
            ZSTD_outBuffer output = { RSTRING_PTR(tmpBuffer), dstCapacity, 0 };

            size_t ret = ZSTD_decompressStream(dctx->dctx, &output, &input);
            if (ZSTD_isError(ret)) {
                rb_raise(rb_eRuntimeError, "Decompression failed: %s", ZSTD_getErrorName(ret));
            }

            if (output.pos > 0) {
                rb_str_cat(result, RSTRING_PTR(tmpBuffer), output.pos);
            }
        }

        return result;
    }
    ZSTD_DDict* ddict = NULL;
    if (!NIL_P(dict)) {
        vibe_zstd_ddict* ddict_struct;
        TypedData_Get_Struct(dict, vibe_zstd_ddict, &vibe_zstd_ddict_type, ddict_struct);
        ddict = ddict_struct->ddict;
    }
    VALUE result = rb_str_new(NULL, contentSize);
    decompress_args args = {
        .dctx = dctx->dctx,
        .ddict = ddict,
        .src = RSTRING_PTR(data),
        .srcSize = srcSize,
        .dst = RSTRING_PTR(result),
        .dstCapacity = contentSize,
        .result = 0
    };
    rb_thread_call_without_gvl(decompress_without_gvl, &args, NULL, NULL);
    if (ZSTD_isError(args.result)) {
        rb_raise(rb_eRuntimeError, "Decompression failed: %s", ZSTD_getErrorName(args.result));
    }
    rb_str_set_len(result, args.result);
    return result;
}

// Streaming API - Writer
static VALUE
vibe_zstd_writer_initialize(int argc, VALUE *argv, VALUE self) {
    VALUE io, options;
    rb_scan_args(argc, argv, "11", &io, &options);

    vibe_zstd_cstream* cstream;
    TypedData_Get_Struct(self, vibe_zstd_cstream, &vibe_zstd_cstream_type, cstream);

    // Store IO object
    cstream->io = io;
    rb_ivar_set(self, rb_intern("@io"), io);

    // Parse options
    int level = 3; // default compression level
    VALUE dict = Qnil;

    if (!NIL_P(options)) {
        Check_Type(options, T_HASH);
        VALUE v_level = rb_hash_aref(options, ID2SYM(rb_intern("level")));
        if (!NIL_P(v_level)) {
            level = NUM2INT(v_level);
        }
        dict = rb_hash_aref(options, ID2SYM(rb_intern("dict")));
    }

    // Create compression context (CStream and CCtx are the same since v1.3.0)
    cstream->cstream = ZSTD_createCStream();
    if (!cstream->cstream) {
        rb_raise(rb_eRuntimeError, "Failed to create compression stream");
    }

    // Reset context for streaming and set compression level
    size_t result = ZSTD_CCtx_reset((ZSTD_CCtx*)cstream->cstream, ZSTD_reset_session_only);
    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to reset compression context: %s", ZSTD_getErrorName(result));
    }

    result = ZSTD_CCtx_setParameter((ZSTD_CCtx*)cstream->cstream, ZSTD_c_compressionLevel, level);
    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to set compression level: %s", ZSTD_getErrorName(result));
    }

    // Set dictionary if provided
    if (!NIL_P(dict)) {
        vibe_zstd_cdict* cdict_obj;
        TypedData_Get_Struct(dict, vibe_zstd_cdict, &vibe_zstd_cdict_type, cdict_obj);
        result = ZSTD_CCtx_refCDict((ZSTD_CCtx*)cstream->cstream, cdict_obj->cdict);
        if (ZSTD_isError(result)) {
            rb_raise(rb_eRuntimeError, "Failed to set dictionary: %s", ZSTD_getErrorName(result));
        }
    }

    return self;
}

static VALUE
vibe_zstd_writer_write(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    vibe_zstd_cstream* cstream;
    TypedData_Get_Struct(self, vibe_zstd_cstream, &vibe_zstd_cstream_type, cstream);

    ZSTD_inBuffer input = {
        .src = RSTRING_PTR(data),
        .size = RSTRING_LEN(data),
        .pos = 0
    };

    size_t outBufferSize = ZSTD_CStreamOutSize();
    VALUE outBuffer = rb_str_buf_new(outBufferSize);

    while (input.pos < input.size) {
        ZSTD_outBuffer output = {
            .dst = RSTRING_PTR(outBuffer),
            .size = outBufferSize,
            .pos = 0
        };

        size_t result = ZSTD_compressStream2((ZSTD_CCtx*)cstream->cstream, &output, &input, ZSTD_e_continue);
        if (ZSTD_isError(result)) {
            rb_raise(rb_eRuntimeError, "Compression failed: %s", ZSTD_getErrorName(result));
        }

        if (output.pos > 0) {
            rb_str_set_len(outBuffer, output.pos);
            rb_funcall(cstream->io, rb_intern("write"), 1, outBuffer);
            rb_str_resize(outBuffer, outBufferSize);
        }
    }

    return self;
}

static VALUE
vibe_zstd_writer_flush(VALUE self) {
    vibe_zstd_cstream* cstream;
    TypedData_Get_Struct(self, vibe_zstd_cstream, &vibe_zstd_cstream_type, cstream);

    size_t outBufferSize = ZSTD_CStreamOutSize();
    VALUE outBuffer = rb_str_buf_new(outBufferSize);

    ZSTD_inBuffer input = { NULL, 0, 0 };
    size_t remaining;

    do {
        ZSTD_outBuffer output = {
            .dst = RSTRING_PTR(outBuffer),
            .size = outBufferSize,
            .pos = 0
        };

        remaining = ZSTD_compressStream2((ZSTD_CCtx*)cstream->cstream, &output, &input, ZSTD_e_flush);
        if (ZSTD_isError(remaining)) {
            rb_raise(rb_eRuntimeError, "Flush failed: %s", ZSTD_getErrorName(remaining));
        }

        if (output.pos > 0) {
            rb_str_set_len(outBuffer, output.pos);
            rb_funcall(cstream->io, rb_intern("write"), 1, outBuffer);
            rb_str_resize(outBuffer, outBufferSize);
        }
    } while (remaining > 0);

    return self;
}

static VALUE
vibe_zstd_writer_finish(VALUE self) {
    vibe_zstd_cstream* cstream;
    TypedData_Get_Struct(self, vibe_zstd_cstream, &vibe_zstd_cstream_type, cstream);

    size_t outBufferSize = ZSTD_CStreamOutSize();
    VALUE outBuffer = rb_str_buf_new(outBufferSize);

    ZSTD_inBuffer input = { NULL, 0, 0 };
    size_t remaining;

    do {
        ZSTD_outBuffer output = {
            .dst = RSTRING_PTR(outBuffer),
            .size = outBufferSize,
            .pos = 0
        };

        remaining = ZSTD_compressStream2((ZSTD_CCtx*)cstream->cstream, &output, &input, ZSTD_e_end);
        if (ZSTD_isError(remaining)) {
            rb_raise(rb_eRuntimeError, "Finish failed: %s", ZSTD_getErrorName(remaining));
        }

        if (output.pos > 0) {
            rb_str_set_len(outBuffer, output.pos);
            rb_funcall(cstream->io, rb_intern("write"), 1, outBuffer);
            rb_str_resize(outBuffer, outBufferSize);
        }
    } while (remaining > 0);

    return self;
}

// Streaming API - Reader
static VALUE
vibe_zstd_reader_initialize(int argc, VALUE *argv, VALUE self) {
    VALUE io, options;
    rb_scan_args(argc, argv, "11", &io, &options);

    vibe_zstd_dstream* dstream;
    TypedData_Get_Struct(self, vibe_zstd_dstream, &vibe_zstd_dstream_type, dstream);

    // Store IO object
    dstream->io = io;
    rb_ivar_set(self, rb_intern("@io"), io);

    // Parse options
    VALUE dict = Qnil;
    if (!NIL_P(options)) {
        Check_Type(options, T_HASH);
        dict = rb_hash_aref(options, ID2SYM(rb_intern("dict")));
    }

    // Create decompression context (DStream and DCtx are the same since v1.3.0)
    dstream->dstream = ZSTD_createDStream();
    if (!dstream->dstream) {
        rb_raise(rb_eRuntimeError, "Failed to create decompression stream");
    }

    // Reset context for streaming
    size_t result = ZSTD_DCtx_reset((ZSTD_DCtx*)dstream->dstream, ZSTD_reset_session_only);
    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to reset decompression context: %s", ZSTD_getErrorName(result));
    }

    // Set dictionary if provided
    if (!NIL_P(dict)) {
        vibe_zstd_ddict* ddict_obj;
        TypedData_Get_Struct(dict, vibe_zstd_ddict, &vibe_zstd_ddict_type, ddict_obj);
        result = ZSTD_DCtx_refDDict((ZSTD_DCtx*)dstream->dstream, ddict_obj->ddict);
        if (ZSTD_isError(result)) {
            rb_raise(rb_eRuntimeError, "Failed to set dictionary: %s", ZSTD_getErrorName(result));
        }
    }

    // Initialize input buffer management
    dstream->input_data = rb_str_new(NULL, 0);
    dstream->input.src = NULL;
    dstream->input.size = 0;
    dstream->input.pos = 0;
    rb_ivar_set(self, rb_intern("@input_data"), dstream->input_data);

    return self;
}

static VALUE
vibe_zstd_reader_read(int argc, VALUE *argv, VALUE self) {
    VALUE size_arg;
    rb_scan_args(argc, argv, "01", &size_arg);

    vibe_zstd_dstream* dstream;
    TypedData_Get_Struct(self, vibe_zstd_dstream, &vibe_zstd_dstream_type, dstream);

    size_t requested_size = NIL_P(size_arg) ? 0 : NUM2SIZET(size_arg);
    size_t inBufferSize = ZSTD_DStreamInSize();
    size_t outBufferSize = requested_size > 0 ? requested_size : ZSTD_DStreamOutSize();

    VALUE result = rb_str_buf_new(outBufferSize);

    // Decompress until we have requested_size bytes or reach EOF
    size_t total_read = 0;
    int made_progress = 0;

    while ((requested_size == 0 || total_read < requested_size)) {
        // Refill input buffer if we've consumed all input
        if (dstream->input.pos >= dstream->input.size) {
            VALUE chunk = rb_funcall(dstream->io, rb_intern("read"), 1, SIZET2NUM(inBufferSize));
            if (NIL_P(chunk)) {
                // EOF from IO
                if (total_read == 0 && !made_progress) {
                    return Qnil;
                }
                break;
            }

            dstream->input_data = chunk;
            dstream->input.src = RSTRING_PTR(chunk);
            dstream->input.size = RSTRING_LEN(chunk);
            dstream->input.pos = 0;
        }

        // If we have no more input, we're done
        if (dstream->input.size == 0) {
            break;
        }

        // Prepare output buffer
        size_t space_left = outBufferSize - total_read;
        rb_str_resize(result, total_read + space_left);

        ZSTD_outBuffer output = {
            .dst = RSTRING_PTR(result) + total_read,
            .size = space_left,
            .pos = 0
        };

        size_t ret = ZSTD_decompressStream(dstream->dstream, &output, &dstream->input);
        if (ZSTD_isError(ret)) {
            rb_raise(rb_eRuntimeError, "Decompression failed: %s", ZSTD_getErrorName(ret));
        }

        if (output.pos > 0) {
            total_read += output.pos;
            made_progress = 1;
        }

        // If we got data and have a requested size, return it
        if (requested_size > 0 && total_read >= requested_size) {
            break;
        }

        // If frame is complete (ret == 0), we're done
        if (ret == 0) {
            break;
        }

        // If no progress was made, we need more input
        if (output.pos == 0) {
            continue;
        }
    }

    if (total_read == 0) {
        return Qnil;
    }

    rb_str_set_len(result, total_read);
    return result;
}

RUBY_FUNC_EXPORTED void
Init_vibe_zstd(void)
{
  rb_mVibeZstd = rb_define_module("VibeZstd");

  // Define classes
  rb_cVibeZstdCCtx = rb_define_class_under(rb_mVibeZstd, "CCtx", rb_cObject);
  rb_cVibeZstdDCtx = rb_define_class_under(rb_mVibeZstd, "DCtx", rb_cObject);
  rb_cVibeZstdCDict = rb_define_class_under(rb_mVibeZstd, "CDict", rb_cObject);
  rb_cVibeZstdDDict = rb_define_class_under(rb_mVibeZstd, "DDict", rb_cObject);

  // CCtx
  rb_define_alloc_func(rb_cVibeZstdCCtx, vibe_zstd_cctx_alloc);
  rb_define_method(rb_cVibeZstdCCtx, "initialize", vibe_zstd_cctx_initialize, 0);
  rb_define_method(rb_cVibeZstdCCtx, "compress", vibe_zstd_cctx_compress, -1);

   // DCtx
   rb_define_alloc_func(rb_cVibeZstdDCtx, vibe_zstd_dctx_alloc);
   rb_define_method(rb_cVibeZstdDCtx, "initialize", vibe_zstd_dctx_initialize, 0);
   rb_define_method(rb_cVibeZstdDCtx, "decompress", vibe_zstd_dctx_decompress, -1);
   rb_define_singleton_method(rb_cVibeZstdDCtx, "frame_content_size", vibe_zstd_dctx_frame_content_size, 1);

  // CDict
  rb_define_alloc_func(rb_cVibeZstdCDict, vibe_zstd_cdict_alloc);
  rb_define_method(rb_cVibeZstdCDict, "initialize", vibe_zstd_cdict_initialize, -1);
  rb_define_method(rb_cVibeZstdCDict, "size", vibe_zstd_cdict_size, 0);
  rb_define_method(rb_cVibeZstdCDict, "dict_id", vibe_zstd_cdict_dict_id, 0);

  // DDict
  rb_define_alloc_func(rb_cVibeZstdDDict, vibe_zstd_ddict_alloc);
  rb_define_method(rb_cVibeZstdDDict, "initialize", vibe_zstd_ddict_initialize, 1);
  rb_define_method(rb_cVibeZstdDDict, "size", vibe_zstd_ddict_size, 0);
  rb_define_method(rb_cVibeZstdDDict, "dict_id", vibe_zstd_ddict_dict_id, 0);

  // Module-level dictionary methods
  rb_define_module_function(rb_mVibeZstd, "train_dict", vibe_zstd_train_dict, -1);
  rb_define_module_function(rb_mVibeZstd, "get_dict_id", vibe_zstd_get_dict_id, 1);

  // Define modules
  rb_mVibeZstdCompress = rb_define_module_under(rb_mVibeZstd, "Compress");
  rb_mVibeZstdDecompress = rb_define_module_under(rb_mVibeZstd, "Decompress");

  // Streaming API - Writer
  rb_cVibeZstdCompressWriter = rb_define_class_under(rb_mVibeZstdCompress, "Writer", rb_cObject);
  rb_define_alloc_func(rb_cVibeZstdCompressWriter, vibe_zstd_cstream_alloc);
  rb_define_method(rb_cVibeZstdCompressWriter, "initialize", vibe_zstd_writer_initialize, -1);
  rb_define_method(rb_cVibeZstdCompressWriter, "write", vibe_zstd_writer_write, 1);
  rb_define_method(rb_cVibeZstdCompressWriter, "flush", vibe_zstd_writer_flush, 0);
  rb_define_method(rb_cVibeZstdCompressWriter, "finish", vibe_zstd_writer_finish, 0);
  rb_define_method(rb_cVibeZstdCompressWriter, "close", vibe_zstd_writer_finish, 0); // alias

  // Streaming API - Reader
  rb_cVibeZstdDecompressReader = rb_define_class_under(rb_mVibeZstdDecompress, "Reader", rb_cObject);
  rb_define_alloc_func(rb_cVibeZstdDecompressReader, vibe_zstd_dstream_alloc);
  rb_define_method(rb_cVibeZstdDecompressReader, "initialize", vibe_zstd_reader_initialize, -1);
  rb_define_method(rb_cVibeZstdDecompressReader, "read", vibe_zstd_reader_read, -1);
}
