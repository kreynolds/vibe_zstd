// Dictionary implementation for VibeZstd
#include "vibe_zstd_internal.h"

// Forward declarations
static VALUE vibe_zstd_cdict_initialize(int argc, VALUE* argv, VALUE self);
static VALUE vibe_zstd_cdict_size(VALUE self);
static VALUE vibe_zstd_cdict_dict_id(VALUE self);
static VALUE vibe_zstd_cdict_estimate_memory(VALUE self, VALUE dict_size, VALUE level);
static VALUE vibe_zstd_ddict_initialize(VALUE self, VALUE dict_data);
static VALUE vibe_zstd_ddict_size(VALUE self);
static VALUE vibe_zstd_ddict_dict_id(VALUE self);
static VALUE vibe_zstd_ddict_estimate_memory(VALUE self, VALUE dict_size);
static VALUE vibe_zstd_train_dict(int argc, VALUE* argv, VALUE self);
static VALUE vibe_zstd_train_dict_cover(int argc, VALUE* argv, VALUE self);
static VALUE vibe_zstd_train_dict_fast_cover(int argc, VALUE* argv, VALUE self);
static VALUE vibe_zstd_get_dict_id(VALUE self, VALUE dict_data);
static VALUE vibe_zstd_get_dict_id_from_frame(VALUE self, VALUE data);
static VALUE vibe_zstd_finalize_dictionary(int argc, VALUE* argv, VALUE self);
static VALUE vibe_zstd_dict_header_size(VALUE self, VALUE dict_data);

// TypedData types - defined in vibe_zstd.c
extern rb_data_type_t vibe_zstd_cdict_type;
extern rb_data_type_t vibe_zstd_ddict_type;

// CDict initialize method
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

// DDict initialize method
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
//
// Memory usage: Allocates memory equal to sum of all sample sizes plus max_dict_size.
// For large datasets, consider training on a representative subset to reduce memory footprint.
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
//
// Memory usage: Allocates memory equal to sum of all sample sizes plus max_dict_size.
// For large datasets, consider training on a representative subset to reduce memory footprint.
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
//
// Memory usage: Allocates memory equal to sum of all sample sizes plus max_dict_size.
// For large datasets, consider training on a representative subset to reduce memory footprint.
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

// Get dictionary ID from compressed frame - module-level utility
// VibeZstd.get_dict_id_from_frame(data)
static VALUE
vibe_zstd_get_dict_id_from_frame(VALUE self, VALUE data) {
    StringValue(data);
    unsigned dict_id = ZSTD_getDictID_fromFrame(RSTRING_PTR(data), RSTRING_LEN(data));
    return UINT2NUM(dict_id);
}

// Finalize raw content into zstd dictionary - module-level utility
// VibeZstd.finalize_dictionary(content:, samples:, max_size:, compression_level: nil, dict_id: nil)
//
// Memory usage: Allocates memory equal to sum of all sample sizes plus max_size.
// For large datasets, consider using a representative subset of samples.
static VALUE
vibe_zstd_finalize_dictionary(int argc, VALUE* argv, VALUE self) {
    VALUE options;
    rb_scan_args(argc, argv, ":", &options);

    if (NIL_P(options)) {
        rb_raise(rb_eArgError, "finalize_dictionary requires keyword arguments");
    }

    // Get required parameters
    VALUE content_val = rb_hash_aref(options, ID2SYM(rb_intern("content")));
    VALUE samples_val = rb_hash_aref(options, ID2SYM(rb_intern("samples")));
    VALUE max_size_val = rb_hash_aref(options, ID2SYM(rb_intern("max_size")));

    if (NIL_P(content_val)) {
        rb_raise(rb_eArgError, "content: parameter is required");
    }
    if (NIL_P(samples_val)) {
        rb_raise(rb_eArgError, "samples: parameter is required");
    }
    if (NIL_P(max_size_val)) {
        rb_raise(rb_eArgError, "max_size: parameter is required");
    }

    StringValue(content_val);
    Check_Type(samples_val, T_ARRAY);
    size_t max_size = NUM2SIZET(max_size_val);

    long num_samples = RARRAY_LEN(samples_val);
    if (num_samples == 0) {
        rb_raise(rb_eArgError, "samples array cannot be empty");
    }

    // Get optional parameters
    VALUE compression_level_val = rb_hash_aref(options, ID2SYM(rb_intern("compression_level")));
    VALUE dict_id_val = rb_hash_aref(options, ID2SYM(rb_intern("dict_id")));

    // Setup ZDICT_params_t
    ZDICT_params_t params;
    memset(&params, 0, sizeof(params));
    params.compressionLevel = NIL_P(compression_level_val) ? 0 : NUM2INT(compression_level_val);
    params.dictID = NIL_P(dict_id_val) ? 0 : NUM2UINT(dict_id_val);
    params.notificationLevel = 0;

    // Calculate total samples size and prepare arrays
    size_t* sample_sizes = ALLOC_N(size_t, num_samples);
    size_t total_samples_size = 0;

    for (long i = 0; i < num_samples; i++) {
        VALUE sample = rb_ary_entry(samples_val, i);
        StringValue(sample);
        sample_sizes[i] = RSTRING_LEN(sample);
        total_samples_size += sample_sizes[i];
    }

    // Allocate and concatenate all samples into single buffer
    char* samples_buffer = ALLOC_N(char, total_samples_size);
    size_t offset = 0;

    for (long i = 0; i < num_samples; i++) {
        VALUE sample = rb_ary_entry(samples_val, i);
        memcpy(samples_buffer + offset, RSTRING_PTR(sample), sample_sizes[i]);
        offset += sample_sizes[i];
    }

    // Allocate dictionary buffer
    void* dict_buffer = ALLOC_N(char, max_size);

    // Finalize the dictionary
    size_t dict_size = ZDICT_finalizeDictionary(
        dict_buffer, max_size,
        RSTRING_PTR(content_val), RSTRING_LEN(content_val),
        samples_buffer, sample_sizes, (unsigned)num_samples,
        params
    );

    // Clean up
    xfree(samples_buffer);
    xfree(sample_sizes);

    // Check for errors
    if (ZDICT_isError(dict_size)) {
        xfree(dict_buffer);
        rb_raise(rb_eRuntimeError, "Dictionary finalization failed: %s", ZDICT_getErrorName(dict_size));
    }

    // Create Ruby string with the finalized dictionary
    VALUE dict_string = rb_str_new(dict_buffer, dict_size);
    xfree(dict_buffer);

    return dict_string;
}

// Get dictionary header size - module-level utility
// VibeZstd.dict_header_size(dict_data)
static VALUE
vibe_zstd_dict_header_size(VALUE self, VALUE dict_data) {
    StringValue(dict_data);
    size_t header_size = ZDICT_getDictHeaderSize(RSTRING_PTR(dict_data), RSTRING_LEN(dict_data));

    // Check for errors
    if (ZDICT_isError(header_size)) {
        rb_raise(rb_eRuntimeError, "Failed to get dictionary header size: %s", ZDICT_getErrorName(header_size));
    }

    return SIZET2NUM(header_size);
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

// Class initialization functions called from main Init_vibe_zstd
void
vibe_zstd_dict_init_classes(VALUE rb_cVibeZstdCDict, VALUE rb_cVibeZstdDDict) {
    // CDict class setup
    rb_define_alloc_func(rb_cVibeZstdCDict, vibe_zstd_cdict_alloc);
    rb_define_method(rb_cVibeZstdCDict, "initialize", vibe_zstd_cdict_initialize, -1);
    rb_define_method(rb_cVibeZstdCDict, "size", vibe_zstd_cdict_size, 0);
    rb_define_method(rb_cVibeZstdCDict, "dict_id", vibe_zstd_cdict_dict_id, 0);
    rb_define_singleton_method(rb_cVibeZstdCDict, "estimate_memory", vibe_zstd_cdict_estimate_memory, 2);

    // DDict class setup
    rb_define_alloc_func(rb_cVibeZstdDDict, vibe_zstd_ddict_alloc);
    rb_define_method(rb_cVibeZstdDDict, "initialize", vibe_zstd_ddict_initialize, 1);
    rb_define_method(rb_cVibeZstdDDict, "size", vibe_zstd_ddict_size, 0);
    rb_define_method(rb_cVibeZstdDDict, "dict_id", vibe_zstd_ddict_dict_id, 0);
    rb_define_singleton_method(rb_cVibeZstdDDict, "estimate_memory", vibe_zstd_ddict_estimate_memory, 1);
}

void
vibe_zstd_dict_init_module_methods(VALUE rb_mVibeZstd) {
    // Module-level dictionary methods
    rb_define_module_function(rb_mVibeZstd, "train_dict", vibe_zstd_train_dict, -1);
    rb_define_module_function(rb_mVibeZstd, "train_dict_cover", vibe_zstd_train_dict_cover, -1);
    rb_define_module_function(rb_mVibeZstd, "train_dict_fast_cover", vibe_zstd_train_dict_fast_cover, -1);
    rb_define_module_function(rb_mVibeZstd, "get_dict_id", vibe_zstd_get_dict_id, 1);
    rb_define_module_function(rb_mVibeZstd, "get_dict_id_from_frame", vibe_zstd_get_dict_id_from_frame, 1);
    rb_define_module_function(rb_mVibeZstd, "finalize_dictionary", vibe_zstd_finalize_dictionary, -1);
    rb_define_module_function(rb_mVibeZstd, "dict_header_size", vibe_zstd_dict_header_size, 1);
}
