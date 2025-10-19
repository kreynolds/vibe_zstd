#include "vibe_zstd.h"
#include <ruby/thread.h>
#define ZDICT_STATIC_LINKING_ONLY
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
// Helper to set parameter from Ruby keyword argument
static int
vibe_zstd_cctx_init_param_iter(VALUE key, VALUE value, VALUE self) {
    // Build the setter method name: key + "="
    const char* key_str = rb_id2name(SYM2ID(key));
    size_t setter_len = strlen(key_str) + 2;  // +1 for '=' + 1 for '\0'
    char* setter = ALLOC_N(char, setter_len);
    snprintf(setter, setter_len, "%s=", key_str);

    // Call the setter method
    rb_funcall(self, rb_intern(setter), 1, value);

    xfree(setter);
    return ST_CONTINUE;
}

static VALUE
vibe_zstd_cctx_initialize(int argc, VALUE* argv, VALUE self) {
    VALUE options;
    rb_scan_args(argc, argv, "0:", &options);

    // If keyword arguments provided, set parameters
    if (!NIL_P(options)) {
        rb_hash_foreach(options, vibe_zstd_cctx_init_param_iter, self);
    }

    return self;
}

// Helper to set DCtx parameter from Ruby keyword argument
static int
vibe_zstd_dctx_init_param_iter(VALUE key, VALUE value, VALUE self) {
    // Build the setter method name: key + "="
    const char* key_str = rb_id2name(SYM2ID(key));
    size_t setter_len = strlen(key_str) + 2;
    char* setter = ALLOC_N(char, setter_len);
    snprintf(setter, setter_len, "%s=", key_str);

    // Call the setter method
    rb_funcall(self, rb_intern(setter), 1, value);

    xfree(setter);
    return ST_CONTINUE;
}

static VALUE
vibe_zstd_dctx_initialize(int argc, VALUE* argv, VALUE self) {
    VALUE options;
    rb_scan_args(argc, argv, "0:", &options);

    // If keyword arguments provided, set parameters
    if (!NIL_P(options)) {
        rb_hash_foreach(options, vibe_zstd_dctx_init_param_iter, self);
    }

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

// VibeZstd.train_dict_cover(samples, max_dict_size: 112640, k: 0, d: 0, steps: 0, split_point: 1.0, shrink_dict: false, shrink_dict_max_regression: 0, nb_threads: 0)
static VALUE
vibe_zstd_train_dict_cover(int argc, VALUE* argv, VALUE self) {
    VALUE samples, options;
    rb_scan_args(argc, argv, "1:", &samples, &options);

    // Parse samples array
    Check_Type(samples, T_ARRAY);
    long num_samples = RARRAY_LEN(samples);

    if (num_samples == 0) {
        rb_raise(rb_eArgError, "samples array cannot be empty");
    }

    // Initialize COVER parameters with defaults
    ZDICT_cover_params_t params;
    memset(&params, 0, sizeof(params));
    params.splitPoint = 1.0;  // Default split point

    // Parse options
    if (!NIL_P(options)) {
        VALUE v;

        v = rb_hash_aref(options, ID2SYM(rb_intern("k")));
        if (!NIL_P(v)) params.k = NUM2UINT(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("d")));
        if (!NIL_P(v)) params.d = NUM2UINT(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("steps")));
        if (!NIL_P(v)) params.steps = NUM2UINT(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("split_point")));
        if (!NIL_P(v)) params.splitPoint = NUM2DBL(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("shrink_dict")));
        if (!NIL_P(v)) params.shrinkDict = RTEST(v) ? 1 : 0;

        v = rb_hash_aref(options, ID2SYM(rb_intern("shrink_dict_max_regression")));
        if (!NIL_P(v)) params.shrinkDictMaxRegression = NUM2UINT(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("nb_threads")));
        if (!NIL_P(v)) params.nbThreads = NUM2UINT(v);
    }

    // Get max_dict_size (default 112KB)
    VALUE max_dict_size_val = Qnil;
    if (!NIL_P(options)) {
        max_dict_size_val = rb_hash_aref(options, ID2SYM(rb_intern("max_dict_size")));
    }
    size_t max_dict_size = NIL_P(max_dict_size_val) ? (112 * 1024) : NUM2SIZET(max_dict_size_val);
    params.zParams.compressionLevel = 0;  // Use default compression level

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

    // Train the dictionary using COVER algorithm
    size_t dict_size = ZDICT_trainFromBuffer_cover(
        dict_buffer, max_dict_size,
        samples_buffer, sample_sizes, (unsigned)num_samples,
        params
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

// VibeZstd.train_dict_fast_cover(samples, max_dict_size: 112640, k: 0, d: 0, f: 0, split_point: 1.0, accel: 0, shrink_dict: false, shrink_dict_max_regression: 0, nb_threads: 0)
static VALUE
vibe_zstd_train_dict_fast_cover(int argc, VALUE* argv, VALUE self) {
    VALUE samples, options;
    rb_scan_args(argc, argv, "1:", &samples, &options);

    // Parse samples array
    Check_Type(samples, T_ARRAY);
    long num_samples = RARRAY_LEN(samples);

    if (num_samples == 0) {
        rb_raise(rb_eArgError, "samples array cannot be empty");
    }

    // Initialize COVER parameters with defaults
    ZDICT_fastCover_params_t params;
    memset(&params, 0, sizeof(params));
    params.splitPoint = 1.0;  // Default split point

    // Parse options
    if (!NIL_P(options)) {
        VALUE v;

        v = rb_hash_aref(options, ID2SYM(rb_intern("k")));
        if (!NIL_P(v)) params.k = NUM2UINT(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("d")));
        if (!NIL_P(v)) params.d = NUM2UINT(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("f")));
        if (!NIL_P(v)) params.f = NUM2UINT(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("split_point")));
        if (!NIL_P(v)) params.splitPoint = NUM2DBL(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("accel")));
        if (!NIL_P(v)) params.accel = NUM2UINT(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("shrink_dict")));
        if (!NIL_P(v)) params.shrinkDict = RTEST(v) ? 1 : 0;

        v = rb_hash_aref(options, ID2SYM(rb_intern("shrink_dict_max_regression")));
        if (!NIL_P(v)) params.shrinkDictMaxRegression = NUM2UINT(v);

        v = rb_hash_aref(options, ID2SYM(rb_intern("nb_threads")));
        if (!NIL_P(v)) params.nbThreads = NUM2UINT(v);
    }

    // Get max_dict_size (default 112KB)
    VALUE max_dict_size_val = Qnil;
    if (!NIL_P(options)) {
        max_dict_size_val = rb_hash_aref(options, ID2SYM(rb_intern("max_dict_size")));
    }
    size_t max_dict_size = NIL_P(max_dict_size_val) ? (112 * 1024) : NUM2SIZET(max_dict_size_val);
    params.zParams.compressionLevel = 0;  // Use default compression level

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

    // Train the dictionary using fast COVER algorithm
    size_t dict_size = ZDICT_trainFromBuffer_fastCover(
        dict_buffer, max_dict_size,
        samples_buffer, sample_sizes, (unsigned)num_samples,
        params
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

// Get compression bound - module-level utility
// VibeZstd.compress_bound(size)
static VALUE
vibe_zstd_compress_bound(VALUE self, VALUE size) {
    size_t src_size = NUM2SIZET(size);
    size_t bound = ZSTD_compressBound(src_size);
    return SIZET2NUM(bound);
}

// Get dictionary ID from compressed frame - module-level utility
// VibeZstd.get_dict_id_from_frame(data)
static VALUE
vibe_zstd_get_dict_id_from_frame(VALUE self, VALUE data) {
    StringValue(data);
    unsigned dict_id = ZSTD_getDictID_fromFrame(RSTRING_PTR(data), RSTRING_LEN(data));
    return UINT2NUM(dict_id);
}

// Memory estimation class methods
// CCtx.estimate_memory(level)
static VALUE
vibe_zstd_cctx_estimate_memory(VALUE self, VALUE level) {
    int lvl = NUM2INT(level);
    size_t estimate = ZSTD_estimateCCtxSize(lvl);
    return SIZET2NUM(estimate);
}

// DCtx.estimate_memory()
static VALUE
vibe_zstd_dctx_estimate_memory(VALUE self) {
    size_t estimate = ZSTD_estimateDCtxSize();
    return SIZET2NUM(estimate);
}

// CDict.estimate_memory(dict_size, level)
static VALUE
vibe_zstd_cdict_estimate_memory(VALUE self, VALUE dict_size, VALUE level) {
    size_t size = NUM2SIZET(dict_size);
    int lvl = NUM2INT(level);
    size_t estimate = ZSTD_estimateCDictSize(size, lvl);
    return SIZET2NUM(estimate);
}

// DDict.estimate_memory(dict_size)
static VALUE
vibe_zstd_ddict_estimate_memory(VALUE self, VALUE dict_size) {
    size_t size = NUM2SIZET(dict_size);
    size_t estimate = ZSTD_estimateDDictSize(size, ZSTD_dlm_byCopy);
    return SIZET2NUM(estimate);
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
    VALUE data, options = Qnil;
    rb_scan_args(argc, argv, "1:", &data, &options);
    vibe_zstd_cctx* cctx;
    TypedData_Get_Struct(self, vibe_zstd_cctx, &vibe_zstd_cctx_type, cctx);
    StringValue(data);

    // Extract keyword arguments
    int lvl = ZSTD_defaultCLevel();
    ZSTD_CDict* cdict = NULL;
    unsigned long long pledged_size = ZSTD_CONTENTSIZE_UNKNOWN;

    if (!NIL_P(options)) {
        // Handle level keyword argument
        VALUE level_val = rb_hash_aref(options, ID2SYM(rb_intern("level")));
        if (!NIL_P(level_val)) {
            lvl = NUM2INT(level_val);
        }

        // Handle dict keyword argument
        VALUE dict_val = rb_hash_aref(options, ID2SYM(rb_intern("dict")));
        if (!NIL_P(dict_val)) {
            vibe_zstd_cdict* cdict_struct;
            TypedData_Get_Struct(dict_val, vibe_zstd_cdict, &vibe_zstd_cdict_type, cdict_struct);
            cdict = cdict_struct->cdict;
        }

        // Handle pledged_size keyword argument
        VALUE pledged_size_val = rb_hash_aref(options, ID2SYM(rb_intern("pledged_size")));
        if (!NIL_P(pledged_size_val)) {
            pledged_size = NUM2ULL(pledged_size_val);
        }
    }

    // Set pledged size if provided
    if (pledged_size != ZSTD_CONTENTSIZE_UNKNOWN) {
        size_t result = ZSTD_CCtx_setPledgedSrcSize(cctx->cctx, pledged_size);
        if (ZSTD_isError(result)) {
            rb_raise(rb_eRuntimeError, "Failed to set pledged source size: %s", ZSTD_getErrorName(result));
        }
    }

    size_t srcSize = RSTRING_LEN(data);
    size_t dstCapacity = ZSTD_compressBound(srcSize);
    VALUE result_str = rb_str_new(NULL, dstCapacity);
    compress_args args = {
        .cctx = cctx->cctx,
        .cdict = cdict,
        .src = RSTRING_PTR(data),
        .srcSize = srcSize,
        .dst = RSTRING_PTR(result_str),
        .dstCapacity = dstCapacity,
        .compressionLevel = lvl,
        .result = 0
    };
    rb_thread_call_without_gvl(compress_without_gvl, &args, NULL, NULL);
    if (ZSTD_isError(args.result)) {
        rb_raise(rb_eRuntimeError, "Compression failed: %s", ZSTD_getErrorName(args.result));
    }
    rb_str_set_len(result_str, args.result);
    return result_str;
}

// Parameter lookup table for CCtx
typedef struct {
    ID symbol_id;
    ZSTD_cParameter param;
    const char* name;
} cctx_param_entry;

static cctx_param_entry cctx_param_table[] = {
    {0, ZSTD_c_compressionLevel, "compression_level"},
    {0, ZSTD_c_windowLog, "window_log"},
    {0, ZSTD_c_hashLog, "hash_log"},
    {0, ZSTD_c_chainLog, "chain_log"},
    {0, ZSTD_c_searchLog, "search_log"},
    {0, ZSTD_c_minMatch, "min_match"},
    {0, ZSTD_c_targetLength, "target_length"},
    {0, ZSTD_c_strategy, "strategy"},
    {0, ZSTD_c_targetCBlockSize, "target_cblock_size"},
    {0, ZSTD_c_enableLongDistanceMatching, "enable_long_distance_matching"},
    {0, ZSTD_c_ldmHashLog, "ldm_hash_log"},
    {0, ZSTD_c_ldmMinMatch, "ldm_min_match"},
    {0, ZSTD_c_ldmBucketSizeLog, "ldm_bucket_size_log"},
    {0, ZSTD_c_ldmHashRateLog, "ldm_hash_rate_log"},
    {0, ZSTD_c_contentSizeFlag, "content_size_flag"},
    {0, ZSTD_c_checksumFlag, "checksum_flag"},
    {0, ZSTD_c_dictIDFlag, "dict_id_flag"},
    {0, ZSTD_c_nbWorkers, "nb_workers"},
    {0, ZSTD_c_jobSize, "job_size"},
    {0, ZSTD_c_overlapLog, "overlap_log"},
    {0, ZSTD_c_rsyncable, "rsyncable"},
    {0, ZSTD_c_format, "format"},
    {0, ZSTD_c_forceMaxWindow, "force_max_window"},
    {0, ZSTD_c_forceAttachDict, "force_attach_dict"},
    {0, ZSTD_c_literalCompressionMode, "literal_compression_mode"},
    {0, ZSTD_c_srcSizeHint, "src_size_hint"},
    {0, ZSTD_c_enableDedicatedDictSearch, "enable_dedicated_dict_search"},
    {0, ZSTD_c_stableInBuffer, "stable_in_buffer"},
    {0, ZSTD_c_stableOutBuffer, "stable_out_buffer"},
    {0, ZSTD_c_blockDelimiters, "block_delimiters"},
    {0, ZSTD_c_validateSequences, "validate_sequences"},
    {0, ZSTD_c_useRowMatchFinder, "use_row_match_finder"},
    {0, ZSTD_c_deterministicRefPrefix, "deterministic_ref_prefix"},
    {0, ZSTD_c_prefetchCDictTables, "prefetch_cdict_tables"},
    {0, ZSTD_c_enableSeqProducerFallback, "enable_seq_producer_fallback"},
    {0, ZSTD_c_maxBlockSize, "max_block_size"},
    {0, ZSTD_c_searchForExternalRepcodes, "search_for_external_repcodes"}
};

#define CCTX_PARAM_TABLE_SIZE (sizeof(cctx_param_table) / sizeof(cctx_param_entry))

// Initialize parameter lookup table symbol IDs
static void
init_cctx_param_table(void) {
    for (size_t i = 0; i < CCTX_PARAM_TABLE_SIZE; i++) {
        cctx_param_table[i].symbol_id = rb_intern(cctx_param_table[i].name);
    }
}

// Helper: look up parameter enum from symbol ID
static int
lookup_cctx_param(ID symbol_id, ZSTD_cParameter* param_out, const char** name_out) {
    for (size_t i = 0; i < CCTX_PARAM_TABLE_SIZE; i++) {
        if (cctx_param_table[i].symbol_id == symbol_id) {
            *param_out = cctx_param_table[i].param;
            if (name_out) *name_out = cctx_param_table[i].name;
            return 1;
        }
    }
    return 0;
}

// Generic setter with bounds checking
static VALUE
vibe_zstd_cctx_set_param_generic(VALUE self, VALUE value, ZSTD_cParameter param, const char* param_name) {
    vibe_zstd_cctx* cctx;
    TypedData_Get_Struct(self, vibe_zstd_cctx, &vibe_zstd_cctx_type, cctx);

    int val = NUM2INT(value);

    // Get bounds for validation
    ZSTD_bounds bounds = ZSTD_cParam_getBounds(param);
    if (ZSTD_isError(bounds.error)) {
        rb_raise(rb_eRuntimeError, "Failed to get bounds for %s: %s",
                 param_name, ZSTD_getErrorName(bounds.error));
    }

    // Validate value is within bounds
    if (val < bounds.lowerBound || val > bounds.upperBound) {
        rb_raise(rb_eArgError, "%s must be between %d and %d (got %d)",
                 param_name, bounds.lowerBound, bounds.upperBound, val);
    }

    size_t result = ZSTD_CCtx_setParameter(cctx->cctx, param, val);
    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to set %s: %s",
                 param_name, ZSTD_getErrorName(result));
    }

    return self;
}

// Boolean setter with Ruby true/false support
static VALUE
vibe_zstd_cctx_set_param_bool(VALUE self, VALUE value, ZSTD_cParameter param, const char* param_name) {
    vibe_zstd_cctx* cctx;
    TypedData_Get_Struct(self, vibe_zstd_cctx, &vibe_zstd_cctx_type, cctx);

    // Convert Ruby boolean or integer to 0/1
    // Handle integers explicitly: 0 -> false, non-zero -> true
    // Handle booleans: false/nil -> false, everything else -> true
    int val;
    if (FIXNUM_P(value)) {
        val = NUM2INT(value) != 0 ? 1 : 0;
    } else {
        val = RTEST(value) ? 1 : 0;
    }

    // Get bounds for validation
    ZSTD_bounds bounds = ZSTD_cParam_getBounds(param);
    if (ZSTD_isError(bounds.error)) {
        rb_raise(rb_eRuntimeError, "Failed to get bounds for %s: %s",
                 param_name, ZSTD_getErrorName(bounds.error));
    }

    // Validate value is within bounds
    if (val < bounds.lowerBound || val > bounds.upperBound) {
        rb_raise(rb_eArgError, "%s must be between %d and %d (got %d)",
                 param_name, bounds.lowerBound, bounds.upperBound, val);
    }

    size_t result = ZSTD_CCtx_setParameter(cctx->cctx, param, val);
    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to set %s: %s",
                 param_name, ZSTD_getErrorName(result));
    }

    return self;
}

// Generic getter
static VALUE
vibe_zstd_cctx_get_param_generic(VALUE self, ZSTD_cParameter param, const char* param_name) {
    vibe_zstd_cctx* cctx;
    TypedData_Get_Struct(self, vibe_zstd_cctx, &vibe_zstd_cctx_type, cctx);

    int value;
    size_t result = ZSTD_CCtx_getParameter(cctx->cctx, param, &value);
    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to get %s: %s",
                 param_name, ZSTD_getErrorName(result));
    }

    return INT2NUM(value);
}

// Boolean getter returning Ruby true/false
static VALUE
vibe_zstd_cctx_get_param_bool(VALUE self, ZSTD_cParameter param, const char* param_name) {
    vibe_zstd_cctx* cctx;
    TypedData_Get_Struct(self, vibe_zstd_cctx, &vibe_zstd_cctx_type, cctx);

    int value;
    size_t result = ZSTD_CCtx_getParameter(cctx->cctx, param, &value);
    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to get %s: %s",
                 param_name, ZSTD_getErrorName(result));
    }

    return value ? Qtrue : Qfalse;
}

// Macro to define setter/getter methods for a parameter
#define DEFINE_CCTX_PARAM_ACCESSORS(rb_name, param_enum, param_str) \
    static VALUE vibe_zstd_cctx_set_##rb_name(VALUE self, VALUE value) { \
        return vibe_zstd_cctx_set_param_generic(self, value, param_enum, param_str); \
    } \
    static VALUE vibe_zstd_cctx_get_##rb_name(VALUE self) { \
        return vibe_zstd_cctx_get_param_generic(self, param_enum, param_str); \
    }

// Macro to define setter/getter/predicate methods for boolean parameters
#define DEFINE_CCTX_PARAM_BOOL_ACCESSORS(rb_name, param_enum, param_str) \
    static VALUE vibe_zstd_cctx_set_##rb_name(VALUE self, VALUE value) { \
        return vibe_zstd_cctx_set_param_bool(self, value, param_enum, param_str); \
    } \
    static VALUE vibe_zstd_cctx_get_##rb_name(VALUE self) { \
        return vibe_zstd_cctx_get_param_bool(self, param_enum, param_str); \
    }

// Define all CCtx parameter accessors
DEFINE_CCTX_PARAM_ACCESSORS(compression_level, ZSTD_c_compressionLevel, "compression_level")
DEFINE_CCTX_PARAM_ACCESSORS(window_log, ZSTD_c_windowLog, "window_log")
DEFINE_CCTX_PARAM_ACCESSORS(hash_log, ZSTD_c_hashLog, "hash_log")
DEFINE_CCTX_PARAM_ACCESSORS(chain_log, ZSTD_c_chainLog, "chain_log")
DEFINE_CCTX_PARAM_ACCESSORS(search_log, ZSTD_c_searchLog, "search_log")
DEFINE_CCTX_PARAM_ACCESSORS(min_match, ZSTD_c_minMatch, "min_match")
DEFINE_CCTX_PARAM_ACCESSORS(target_length, ZSTD_c_targetLength, "target_length")
DEFINE_CCTX_PARAM_ACCESSORS(strategy, ZSTD_c_strategy, "strategy")
DEFINE_CCTX_PARAM_ACCESSORS(target_cblock_size, ZSTD_c_targetCBlockSize, "target_cblock_size")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(enable_long_distance_matching, ZSTD_c_enableLongDistanceMatching, "enable_long_distance_matching")
DEFINE_CCTX_PARAM_ACCESSORS(ldm_hash_log, ZSTD_c_ldmHashLog, "ldm_hash_log")
DEFINE_CCTX_PARAM_ACCESSORS(ldm_min_match, ZSTD_c_ldmMinMatch, "ldm_min_match")
DEFINE_CCTX_PARAM_ACCESSORS(ldm_bucket_size_log, ZSTD_c_ldmBucketSizeLog, "ldm_bucket_size_log")
DEFINE_CCTX_PARAM_ACCESSORS(ldm_hash_rate_log, ZSTD_c_ldmHashRateLog, "ldm_hash_rate_log")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(content_size_flag, ZSTD_c_contentSizeFlag, "content_size_flag")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(checksum_flag, ZSTD_c_checksumFlag, "checksum_flag")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(dict_id_flag, ZSTD_c_dictIDFlag, "dict_id_flag")
DEFINE_CCTX_PARAM_ACCESSORS(nb_workers, ZSTD_c_nbWorkers, "nb_workers")
DEFINE_CCTX_PARAM_ACCESSORS(job_size, ZSTD_c_jobSize, "job_size")
DEFINE_CCTX_PARAM_ACCESSORS(overlap_log, ZSTD_c_overlapLog, "overlap_log")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(rsyncable, ZSTD_c_rsyncable, "rsyncable")
DEFINE_CCTX_PARAM_ACCESSORS(format, ZSTD_c_format, "format")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(force_max_window, ZSTD_c_forceMaxWindow, "force_max_window")
DEFINE_CCTX_PARAM_ACCESSORS(force_attach_dict, ZSTD_c_forceAttachDict, "force_attach_dict")
DEFINE_CCTX_PARAM_ACCESSORS(literal_compression_mode, ZSTD_c_literalCompressionMode, "literal_compression_mode")
DEFINE_CCTX_PARAM_ACCESSORS(src_size_hint, ZSTD_c_srcSizeHint, "src_size_hint")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(enable_dedicated_dict_search, ZSTD_c_enableDedicatedDictSearch, "enable_dedicated_dict_search")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(stable_in_buffer, ZSTD_c_stableInBuffer, "stable_in_buffer")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(stable_out_buffer, ZSTD_c_stableOutBuffer, "stable_out_buffer")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(block_delimiters, ZSTD_c_blockDelimiters, "block_delimiters")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(validate_sequences, ZSTD_c_validateSequences, "validate_sequences")
DEFINE_CCTX_PARAM_ACCESSORS(use_row_match_finder, ZSTD_c_useRowMatchFinder, "use_row_match_finder")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(deterministic_ref_prefix, ZSTD_c_deterministicRefPrefix, "deterministic_ref_prefix")
DEFINE_CCTX_PARAM_ACCESSORS(prefetch_cdict_tables, ZSTD_c_prefetchCDictTables, "prefetch_cdict_tables")
DEFINE_CCTX_PARAM_BOOL_ACCESSORS(enable_seq_producer_fallback, ZSTD_c_enableSeqProducerFallback, "enable_seq_producer_fallback")
DEFINE_CCTX_PARAM_ACCESSORS(max_block_size, ZSTD_c_maxBlockSize, "max_block_size")
DEFINE_CCTX_PARAM_ACCESSORS(search_for_external_repcodes, ZSTD_c_searchForExternalRepcodes, "search_for_external_repcodes")

// CCtx parameter_bounds - query parameter bounds (class method, kept for introspection)
static VALUE
vibe_zstd_cctx_parameter_bounds(VALUE self, VALUE param_sym) {
    ID symbol_id = SYM2ID(param_sym);
    ZSTD_cParameter param;
    const char* param_name;

    if (!lookup_cctx_param(symbol_id, &param, &param_name)) {
        rb_raise(rb_eArgError, "Unknown parameter: %s", rb_id2name(symbol_id));
    }

    ZSTD_bounds bounds = ZSTD_cParam_getBounds(param);
    if (ZSTD_isError(bounds.error)) {
        rb_raise(rb_eRuntimeError, "Failed to get parameter bounds for %s: %s",
                 param_name, ZSTD_getErrorName(bounds.error));
    }

    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("min")), INT2NUM(bounds.lowerBound));
    rb_hash_aset(result, ID2SYM(rb_intern("max")), INT2NUM(bounds.upperBound));
    return result;
}

// CCtx use_prefix - use raw data as prefix (lightweight dictionary)
static VALUE
vibe_zstd_cctx_use_prefix(VALUE self, VALUE prefix_data) {
    vibe_zstd_cctx* cctx;
    TypedData_Get_Struct(self, vibe_zstd_cctx, &vibe_zstd_cctx_type, cctx);

    StringValue(prefix_data);

    size_t result = ZSTD_CCtx_refPrefix(cctx->cctx, RSTRING_PTR(prefix_data), RSTRING_LEN(prefix_data));

    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to set prefix: %s", ZSTD_getErrorName(result));
    }

    return self;
}

// Parameter lookup table for DCtx
typedef struct {
    ID symbol_id;
    ZSTD_dParameter param;
    const char* name;
} dctx_param_entry;

static dctx_param_entry dctx_param_table[] = {
    {0, ZSTD_d_windowLogMax, "window_log_max"}
};

#define DCTX_PARAM_TABLE_SIZE (sizeof(dctx_param_table) / sizeof(dctx_param_entry))

// Initialize DCtx parameter lookup table symbol IDs
static void
init_dctx_param_table(void) {
    for (size_t i = 0; i < DCTX_PARAM_TABLE_SIZE; i++) {
        dctx_param_table[i].symbol_id = rb_intern(dctx_param_table[i].name);
    }
}

// Helper: look up DCtx parameter enum from symbol ID
static int
lookup_dctx_param(ID symbol_id, ZSTD_dParameter* param_out, const char** name_out) {
    for (size_t i = 0; i < DCTX_PARAM_TABLE_SIZE; i++) {
        if (dctx_param_table[i].symbol_id == symbol_id) {
            *param_out = dctx_param_table[i].param;
            if (name_out) *name_out = dctx_param_table[i].name;
            return 1;
        }
    }
    return 0;
}

// Generic setter with bounds checking for DCtx
static VALUE
vibe_zstd_dctx_set_param_generic(VALUE self, VALUE value, ZSTD_dParameter param, const char* param_name) {
    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);

    int val = NUM2INT(value);

    // Get bounds for validation
    ZSTD_bounds bounds = ZSTD_dParam_getBounds(param);
    if (ZSTD_isError(bounds.error)) {
        rb_raise(rb_eRuntimeError, "Failed to get bounds for %s: %s",
                 param_name, ZSTD_getErrorName(bounds.error));
    }

    // Validate value is within bounds
    if (val < bounds.lowerBound || val > bounds.upperBound) {
        rb_raise(rb_eArgError, "%s must be between %d and %d (got %d)",
                 param_name, bounds.lowerBound, bounds.upperBound, val);
    }

    size_t result = ZSTD_DCtx_setParameter(dctx->dctx, param, val);
    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to set %s: %s",
                 param_name, ZSTD_getErrorName(result));
    }

    return self;
}

// Generic getter for DCtx
static VALUE
vibe_zstd_dctx_get_param_generic(VALUE self, ZSTD_dParameter param, const char* param_name) {
    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);

    int value;
    size_t result = ZSTD_DCtx_getParameter(dctx->dctx, param, &value);
    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to get %s: %s",
                 param_name, ZSTD_getErrorName(result));
    }

    return INT2NUM(value);
}

// Macro to define setter/getter methods for a DCtx parameter
#define DEFINE_DCTX_PARAM_ACCESSORS(rb_name, param_enum, param_str) \
    static VALUE vibe_zstd_dctx_set_##rb_name(VALUE self, VALUE value) { \
        return vibe_zstd_dctx_set_param_generic(self, value, param_enum, param_str); \
    } \
    static VALUE vibe_zstd_dctx_get_##rb_name(VALUE self) { \
        return vibe_zstd_dctx_get_param_generic(self, param_enum, param_str); \
    }

// Define all DCtx parameter accessors
DEFINE_DCTX_PARAM_ACCESSORS(window_log_max, ZSTD_d_windowLogMax, "window_log_max")

// DCtx parameter_bounds - query parameter bounds (class method, kept for introspection)
static VALUE
vibe_zstd_dctx_parameter_bounds(VALUE self, VALUE param_sym) {
    ID symbol_id = SYM2ID(param_sym);
    ZSTD_dParameter param;
    const char* param_name;

    if (!lookup_dctx_param(symbol_id, &param, &param_name)) {
        rb_raise(rb_eArgError, "Unknown parameter: %s", rb_id2name(symbol_id));
    }

    ZSTD_bounds bounds = ZSTD_dParam_getBounds(param);
    if (ZSTD_isError(bounds.error)) {
        rb_raise(rb_eRuntimeError, "Failed to get parameter bounds for %s: %s",
                 param_name, ZSTD_getErrorName(bounds.error));
    }

    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("min")), INT2NUM(bounds.lowerBound));
    rb_hash_aset(result, ID2SYM(rb_intern("max")), INT2NUM(bounds.upperBound));
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
    VALUE data, options = Qnil;
    rb_scan_args(argc, argv, "1:", &data, &options);
    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);
    StringValue(data);
    size_t srcSize = RSTRING_LEN(data);
    unsigned long long contentSize = ZSTD_getFrameContentSize(RSTRING_PTR(data), srcSize);
    if (contentSize == ZSTD_CONTENTSIZE_ERROR) {
        rb_raise(rb_eRuntimeError, "Invalid compressed data");
    }

    // Extract keyword arguments
    ZSTD_DDict* ddict = NULL;
    if (!NIL_P(options)) {
        VALUE dict_val = rb_hash_aref(options, ID2SYM(rb_intern("dict")));
        if (!NIL_P(dict_val)) {
            vibe_zstd_ddict* ddict_struct;
            TypedData_Get_Struct(dict_val, vibe_zstd_ddict, &vibe_zstd_ddict_type, ddict_struct);
            ddict = ddict_struct->ddict;
        }
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

// DCtx use_prefix - use raw data as prefix (lightweight dictionary)
static VALUE
vibe_zstd_dctx_use_prefix(VALUE self, VALUE prefix_data) {
    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);

    StringValue(prefix_data);

    size_t result = ZSTD_DCtx_refPrefix(dctx->dctx, RSTRING_PTR(prefix_data), RSTRING_LEN(prefix_data));

    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to set prefix: %s", ZSTD_getErrorName(result));
    }

    return self;
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
    unsigned long long pledged_size = ZSTD_CONTENTSIZE_UNKNOWN;

    if (!NIL_P(options)) {
        Check_Type(options, T_HASH);
        VALUE v_level = rb_hash_aref(options, ID2SYM(rb_intern("level")));
        if (!NIL_P(v_level)) {
            level = NUM2INT(v_level);
        }
        dict = rb_hash_aref(options, ID2SYM(rb_intern("dict")));

        VALUE v_pledged = rb_hash_aref(options, ID2SYM(rb_intern("pledged_size")));
        if (!NIL_P(v_pledged)) {
            pledged_size = NUM2ULL(v_pledged);
        }
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

    // Set pledged source size if provided
    if (pledged_size != ZSTD_CONTENTSIZE_UNKNOWN) {
        result = ZSTD_CCtx_setPledgedSrcSize((ZSTD_CCtx*)cstream->cstream, pledged_size);
        if (ZSTD_isError(result)) {
            rb_raise(rb_eRuntimeError, "Failed to set pledged source size: %s", ZSTD_getErrorName(result));
        }
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
  // Initialize parameter lookup tables
  init_cctx_param_table();
  init_dctx_param_table();

  rb_mVibeZstd = rb_define_module("VibeZstd");

  // Define classes
  rb_cVibeZstdCCtx = rb_define_class_under(rb_mVibeZstd, "CCtx", rb_cObject);
  rb_cVibeZstdDCtx = rb_define_class_under(rb_mVibeZstd, "DCtx", rb_cObject);
  rb_cVibeZstdCDict = rb_define_class_under(rb_mVibeZstd, "CDict", rb_cObject);
  rb_cVibeZstdDDict = rb_define_class_under(rb_mVibeZstd, "DDict", rb_cObject);

  // CCtx
  rb_define_alloc_func(rb_cVibeZstdCCtx, vibe_zstd_cctx_alloc);
  rb_define_method(rb_cVibeZstdCCtx, "initialize", vibe_zstd_cctx_initialize, -1);
  rb_define_method(rb_cVibeZstdCCtx, "compress", vibe_zstd_cctx_compress, -1);
  rb_define_method(rb_cVibeZstdCCtx, "use_prefix", vibe_zstd_cctx_use_prefix, 1);
  rb_define_singleton_method(rb_cVibeZstdCCtx, "parameter_bounds", vibe_zstd_cctx_parameter_bounds, 1);
  rb_define_singleton_method(rb_cVibeZstdCCtx, "estimate_memory", vibe_zstd_cctx_estimate_memory, 1);

  // CCtx parameter accessors
  rb_define_method(rb_cVibeZstdCCtx, "compression_level=", vibe_zstd_cctx_set_compression_level, 1);
  rb_define_method(rb_cVibeZstdCCtx, "compression_level", vibe_zstd_cctx_get_compression_level, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "level=", "compression_level=");
  rb_define_alias(rb_cVibeZstdCCtx, "level", "compression_level");
  rb_define_method(rb_cVibeZstdCCtx, "window_log=", vibe_zstd_cctx_set_window_log, 1);
  rb_define_method(rb_cVibeZstdCCtx, "window_log", vibe_zstd_cctx_get_window_log, 0);
  rb_define_method(rb_cVibeZstdCCtx, "hash_log=", vibe_zstd_cctx_set_hash_log, 1);
  rb_define_method(rb_cVibeZstdCCtx, "hash_log", vibe_zstd_cctx_get_hash_log, 0);
  rb_define_method(rb_cVibeZstdCCtx, "chain_log=", vibe_zstd_cctx_set_chain_log, 1);
  rb_define_method(rb_cVibeZstdCCtx, "chain_log", vibe_zstd_cctx_get_chain_log, 0);
  rb_define_method(rb_cVibeZstdCCtx, "search_log=", vibe_zstd_cctx_set_search_log, 1);
  rb_define_method(rb_cVibeZstdCCtx, "search_log", vibe_zstd_cctx_get_search_log, 0);
  rb_define_method(rb_cVibeZstdCCtx, "min_match=", vibe_zstd_cctx_set_min_match, 1);
  rb_define_method(rb_cVibeZstdCCtx, "min_match", vibe_zstd_cctx_get_min_match, 0);
  rb_define_method(rb_cVibeZstdCCtx, "target_length=", vibe_zstd_cctx_set_target_length, 1);
  rb_define_method(rb_cVibeZstdCCtx, "target_length", vibe_zstd_cctx_get_target_length, 0);
  rb_define_method(rb_cVibeZstdCCtx, "strategy=", vibe_zstd_cctx_set_strategy, 1);
  rb_define_method(rb_cVibeZstdCCtx, "strategy", vibe_zstd_cctx_get_strategy, 0);
  rb_define_method(rb_cVibeZstdCCtx, "target_cblock_size=", vibe_zstd_cctx_set_target_cblock_size, 1);
  rb_define_method(rb_cVibeZstdCCtx, "target_cblock_size", vibe_zstd_cctx_get_target_cblock_size, 0);
  rb_define_method(rb_cVibeZstdCCtx, "enable_long_distance_matching=", vibe_zstd_cctx_set_enable_long_distance_matching, 1);
  rb_define_method(rb_cVibeZstdCCtx, "enable_long_distance_matching", vibe_zstd_cctx_get_enable_long_distance_matching, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "long_distance_matching=", "enable_long_distance_matching=");
  rb_define_alias(rb_cVibeZstdCCtx, "long_distance_matching", "enable_long_distance_matching");
  rb_define_alias(rb_cVibeZstdCCtx, "long_distance_matching?", "enable_long_distance_matching");
  rb_define_method(rb_cVibeZstdCCtx, "ldm_hash_log=", vibe_zstd_cctx_set_ldm_hash_log, 1);
  rb_define_method(rb_cVibeZstdCCtx, "ldm_hash_log", vibe_zstd_cctx_get_ldm_hash_log, 0);
  rb_define_method(rb_cVibeZstdCCtx, "ldm_min_match=", vibe_zstd_cctx_set_ldm_min_match, 1);
  rb_define_method(rb_cVibeZstdCCtx, "ldm_min_match", vibe_zstd_cctx_get_ldm_min_match, 0);
  rb_define_method(rb_cVibeZstdCCtx, "ldm_bucket_size_log=", vibe_zstd_cctx_set_ldm_bucket_size_log, 1);
  rb_define_method(rb_cVibeZstdCCtx, "ldm_bucket_size_log", vibe_zstd_cctx_get_ldm_bucket_size_log, 0);
  rb_define_method(rb_cVibeZstdCCtx, "ldm_hash_rate_log=", vibe_zstd_cctx_set_ldm_hash_rate_log, 1);
  rb_define_method(rb_cVibeZstdCCtx, "ldm_hash_rate_log", vibe_zstd_cctx_get_ldm_hash_rate_log, 0);
  rb_define_method(rb_cVibeZstdCCtx, "content_size_flag=", vibe_zstd_cctx_set_content_size_flag, 1);
  rb_define_method(rb_cVibeZstdCCtx, "content_size_flag", vibe_zstd_cctx_get_content_size_flag, 0);
  rb_define_method(rb_cVibeZstdCCtx, "checksum_flag=", vibe_zstd_cctx_set_checksum_flag, 1);
  rb_define_method(rb_cVibeZstdCCtx, "checksum_flag", vibe_zstd_cctx_get_checksum_flag, 0);
  rb_define_method(rb_cVibeZstdCCtx, "dict_id_flag=", vibe_zstd_cctx_set_dict_id_flag, 1);
  rb_define_method(rb_cVibeZstdCCtx, "dict_id_flag", vibe_zstd_cctx_get_dict_id_flag, 0);

  // Boolean aliases without _flag suffix and predicate methods
  rb_define_alias(rb_cVibeZstdCCtx, "checksum=", "checksum_flag=");
  rb_define_alias(rb_cVibeZstdCCtx, "checksum", "checksum_flag");
  rb_define_alias(rb_cVibeZstdCCtx, "checksum?", "checksum_flag");
  rb_define_alias(rb_cVibeZstdCCtx, "content_size=", "content_size_flag=");
  rb_define_alias(rb_cVibeZstdCCtx, "content_size", "content_size_flag");
  rb_define_alias(rb_cVibeZstdCCtx, "content_size?", "content_size_flag");
  rb_define_alias(rb_cVibeZstdCCtx, "dict_id=", "dict_id_flag=");
  rb_define_alias(rb_cVibeZstdCCtx, "dict_id", "dict_id_flag");
  rb_define_alias(rb_cVibeZstdCCtx, "dict_id?", "dict_id_flag");
  rb_define_method(rb_cVibeZstdCCtx, "nb_workers=", vibe_zstd_cctx_set_nb_workers, 1);
  rb_define_method(rb_cVibeZstdCCtx, "nb_workers", vibe_zstd_cctx_get_nb_workers, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "workers=", "nb_workers=");
  rb_define_alias(rb_cVibeZstdCCtx, "workers", "nb_workers");
  rb_define_method(rb_cVibeZstdCCtx, "job_size=", vibe_zstd_cctx_set_job_size, 1);
  rb_define_method(rb_cVibeZstdCCtx, "job_size", vibe_zstd_cctx_get_job_size, 0);
  rb_define_method(rb_cVibeZstdCCtx, "overlap_log=", vibe_zstd_cctx_set_overlap_log, 1);
  rb_define_method(rb_cVibeZstdCCtx, "overlap_log", vibe_zstd_cctx_get_overlap_log, 0);
  rb_define_method(rb_cVibeZstdCCtx, "rsyncable=", vibe_zstd_cctx_set_rsyncable, 1);
  rb_define_method(rb_cVibeZstdCCtx, "rsyncable", vibe_zstd_cctx_get_rsyncable, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "rsyncable?", "rsyncable");
  rb_define_method(rb_cVibeZstdCCtx, "format=", vibe_zstd_cctx_set_format, 1);
  rb_define_method(rb_cVibeZstdCCtx, "format", vibe_zstd_cctx_get_format, 0);
  rb_define_method(rb_cVibeZstdCCtx, "force_max_window=", vibe_zstd_cctx_set_force_max_window, 1);
  rb_define_method(rb_cVibeZstdCCtx, "force_max_window", vibe_zstd_cctx_get_force_max_window, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "force_max_window?", "force_max_window");
  rb_define_method(rb_cVibeZstdCCtx, "force_attach_dict=", vibe_zstd_cctx_set_force_attach_dict, 1);
  rb_define_method(rb_cVibeZstdCCtx, "force_attach_dict", vibe_zstd_cctx_get_force_attach_dict, 0);
  rb_define_method(rb_cVibeZstdCCtx, "literal_compression_mode=", vibe_zstd_cctx_set_literal_compression_mode, 1);
  rb_define_method(rb_cVibeZstdCCtx, "literal_compression_mode", vibe_zstd_cctx_get_literal_compression_mode, 0);
  rb_define_method(rb_cVibeZstdCCtx, "src_size_hint=", vibe_zstd_cctx_set_src_size_hint, 1);
  rb_define_method(rb_cVibeZstdCCtx, "src_size_hint", vibe_zstd_cctx_get_src_size_hint, 0);
  rb_define_method(rb_cVibeZstdCCtx, "enable_dedicated_dict_search=", vibe_zstd_cctx_set_enable_dedicated_dict_search, 1);
  rb_define_method(rb_cVibeZstdCCtx, "enable_dedicated_dict_search", vibe_zstd_cctx_get_enable_dedicated_dict_search, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "enable_dedicated_dict_search?", "enable_dedicated_dict_search");
  rb_define_method(rb_cVibeZstdCCtx, "stable_in_buffer=", vibe_zstd_cctx_set_stable_in_buffer, 1);
  rb_define_method(rb_cVibeZstdCCtx, "stable_in_buffer", vibe_zstd_cctx_get_stable_in_buffer, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "stable_in_buffer?", "stable_in_buffer");
  rb_define_method(rb_cVibeZstdCCtx, "stable_out_buffer=", vibe_zstd_cctx_set_stable_out_buffer, 1);
  rb_define_method(rb_cVibeZstdCCtx, "stable_out_buffer", vibe_zstd_cctx_get_stable_out_buffer, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "stable_out_buffer?", "stable_out_buffer");
  rb_define_method(rb_cVibeZstdCCtx, "block_delimiters=", vibe_zstd_cctx_set_block_delimiters, 1);
  rb_define_method(rb_cVibeZstdCCtx, "block_delimiters", vibe_zstd_cctx_get_block_delimiters, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "block_delimiters?", "block_delimiters");
  rb_define_method(rb_cVibeZstdCCtx, "validate_sequences=", vibe_zstd_cctx_set_validate_sequences, 1);
  rb_define_method(rb_cVibeZstdCCtx, "validate_sequences", vibe_zstd_cctx_get_validate_sequences, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "validate_sequences?", "validate_sequences");
  rb_define_method(rb_cVibeZstdCCtx, "use_row_match_finder=", vibe_zstd_cctx_set_use_row_match_finder, 1);
  rb_define_method(rb_cVibeZstdCCtx, "use_row_match_finder", vibe_zstd_cctx_get_use_row_match_finder, 0);
  rb_define_method(rb_cVibeZstdCCtx, "deterministic_ref_prefix=", vibe_zstd_cctx_set_deterministic_ref_prefix, 1);
  rb_define_method(rb_cVibeZstdCCtx, "deterministic_ref_prefix", vibe_zstd_cctx_get_deterministic_ref_prefix, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "deterministic_ref_prefix?", "deterministic_ref_prefix");
  rb_define_method(rb_cVibeZstdCCtx, "prefetch_cdict_tables=", vibe_zstd_cctx_set_prefetch_cdict_tables, 1);
  rb_define_method(rb_cVibeZstdCCtx, "prefetch_cdict_tables", vibe_zstd_cctx_get_prefetch_cdict_tables, 0);
  rb_define_method(rb_cVibeZstdCCtx, "enable_seq_producer_fallback=", vibe_zstd_cctx_set_enable_seq_producer_fallback, 1);
  rb_define_method(rb_cVibeZstdCCtx, "enable_seq_producer_fallback", vibe_zstd_cctx_get_enable_seq_producer_fallback, 0);
  rb_define_alias(rb_cVibeZstdCCtx, "enable_seq_producer_fallback?", "enable_seq_producer_fallback");
  rb_define_method(rb_cVibeZstdCCtx, "max_block_size=", vibe_zstd_cctx_set_max_block_size, 1);
  rb_define_method(rb_cVibeZstdCCtx, "max_block_size", vibe_zstd_cctx_get_max_block_size, 0);
  rb_define_method(rb_cVibeZstdCCtx, "search_for_external_repcodes=", vibe_zstd_cctx_set_search_for_external_repcodes, 1);
  rb_define_method(rb_cVibeZstdCCtx, "search_for_external_repcodes", vibe_zstd_cctx_get_search_for_external_repcodes, 0);

   // DCtx
   rb_define_alloc_func(rb_cVibeZstdDCtx, vibe_zstd_dctx_alloc);
   rb_define_method(rb_cVibeZstdDCtx, "initialize", vibe_zstd_dctx_initialize, -1);
   rb_define_method(rb_cVibeZstdDCtx, "decompress", vibe_zstd_dctx_decompress, -1);
   rb_define_method(rb_cVibeZstdDCtx, "use_prefix", vibe_zstd_dctx_use_prefix, 1);
   rb_define_singleton_method(rb_cVibeZstdDCtx, "parameter_bounds", vibe_zstd_dctx_parameter_bounds, 1);
   rb_define_singleton_method(rb_cVibeZstdDCtx, "frame_content_size", vibe_zstd_dctx_frame_content_size, 1);
   rb_define_singleton_method(rb_cVibeZstdDCtx, "estimate_memory", vibe_zstd_dctx_estimate_memory, 0);

   // DCtx parameter accessors
   rb_define_method(rb_cVibeZstdDCtx, "window_log_max=", vibe_zstd_dctx_set_window_log_max, 1);
   rb_define_method(rb_cVibeZstdDCtx, "window_log_max", vibe_zstd_dctx_get_window_log_max, 0);
   rb_define_alias(rb_cVibeZstdDCtx, "max_window_log=", "window_log_max=");
   rb_define_alias(rb_cVibeZstdDCtx, "max_window_log", "window_log_max");

  // CDict
  rb_define_alloc_func(rb_cVibeZstdCDict, vibe_zstd_cdict_alloc);
  rb_define_method(rb_cVibeZstdCDict, "initialize", vibe_zstd_cdict_initialize, -1);
  rb_define_method(rb_cVibeZstdCDict, "size", vibe_zstd_cdict_size, 0);
  rb_define_method(rb_cVibeZstdCDict, "dict_id", vibe_zstd_cdict_dict_id, 0);
  rb_define_singleton_method(rb_cVibeZstdCDict, "estimate_memory", vibe_zstd_cdict_estimate_memory, 2);

  // DDict
  rb_define_alloc_func(rb_cVibeZstdDDict, vibe_zstd_ddict_alloc);
  rb_define_method(rb_cVibeZstdDDict, "initialize", vibe_zstd_ddict_initialize, 1);
  rb_define_method(rb_cVibeZstdDDict, "size", vibe_zstd_ddict_size, 0);
  rb_define_method(rb_cVibeZstdDDict, "dict_id", vibe_zstd_ddict_dict_id, 0);
  rb_define_singleton_method(rb_cVibeZstdDDict, "estimate_memory", vibe_zstd_ddict_estimate_memory, 1);

  // Module-level dictionary methods
  rb_define_module_function(rb_mVibeZstd, "train_dict", vibe_zstd_train_dict, -1);
  rb_define_module_function(rb_mVibeZstd, "train_dict_cover", vibe_zstd_train_dict_cover, -1);
  rb_define_module_function(rb_mVibeZstd, "train_dict_fast_cover", vibe_zstd_train_dict_fast_cover, -1);
  rb_define_module_function(rb_mVibeZstd, "get_dict_id", vibe_zstd_get_dict_id, 1);
  rb_define_module_function(rb_mVibeZstd, "get_dict_id_from_frame", vibe_zstd_get_dict_id_from_frame, 1);

  // Module-level utility methods
  rb_define_module_function(rb_mVibeZstd, "compress_bound", vibe_zstd_compress_bound, 1);

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
