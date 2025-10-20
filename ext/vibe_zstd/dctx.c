// DCtx implementation for VibeZstd
#include "vibe_zstd_internal.h"

// TypedData type - defined in vibe_zstd.c
extern rb_data_type_t vibe_zstd_dctx_type;

// Class-level default for initial capacity (0 = use ZSTD_DStreamOutSize)
static size_t default_initial_capacity = 0;

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

// Memory estimation class method
// DCtx.estimate_memory()
static VALUE
vibe_zstd_dctx_estimate_memory(VALUE self) {
    size_t estimate = ZSTD_estimateDCtxSize();
    return SIZET2NUM(estimate);
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

// DCtx default_initial_capacity getter (class method)
static VALUE
vibe_zstd_dctx_get_default_initial_capacity(VALUE self) {
    if (default_initial_capacity == 0) {
        return SIZET2NUM(ZSTD_DStreamOutSize());
    }
    return SIZET2NUM(default_initial_capacity);
}

// DCtx default_initial_capacity setter (class method)
static VALUE
vibe_zstd_dctx_set_default_initial_capacity(VALUE self, VALUE value) {
    if (NIL_P(value)) {
        default_initial_capacity = 0;  // Reset to default
    } else {
        size_t capacity = NUM2SIZET(value);
        if (capacity == 0) {
            rb_raise(rb_eArgError, "initial_capacity must be positive (or nil to reset to default)");
        }
        default_initial_capacity = capacity;
    }
    return value;
}

// DCtx initial_capacity getter (instance method)
static VALUE
vibe_zstd_dctx_get_initial_capacity(VALUE self) {
    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);

    if (dctx->initial_capacity == 0) {
        // Return the class default
        return vibe_zstd_dctx_get_default_initial_capacity(Qnil);
    }
    return SIZET2NUM(dctx->initial_capacity);
}

// DCtx initial_capacity setter (instance method)
static VALUE
vibe_zstd_dctx_set_initial_capacity(VALUE self, VALUE value) {
    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);

    if (NIL_P(value)) {
        dctx->initial_capacity = 0;  // Use class default
    } else {
        size_t capacity = NUM2SIZET(value);
        if (capacity == 0) {
            rb_raise(rb_eArgError, "initial_capacity must be positive (or nil to use class default)");
        }
        dctx->initial_capacity = capacity;
    }
    return value;
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
    const char* src = RSTRING_PTR(data);
    size_t srcSize = RSTRING_LEN(data);
    size_t offset = 0;

    // Skip any leading skippable frames
    while (offset < srcSize && ZSTD_isSkippableFrame(src + offset, srcSize - offset)) {
        size_t frameSize = ZSTD_findFrameCompressedSize(src + offset, srcSize - offset);
        if (ZSTD_isError(frameSize)) {
            rb_raise(rb_eRuntimeError, "Invalid skippable frame at offset %zu: %s", offset, ZSTD_getErrorName(frameSize));
        }
        offset += frameSize;
    }

    // Now check the actual compressed frame
    if (offset >= srcSize) {
        rb_raise(rb_eRuntimeError, "No compressed frame found in %zu bytes (only skippable frames)", srcSize);
    }

    src += offset;
    srcSize -= offset;

    unsigned long long contentSize = ZSTD_getFrameContentSize(src, srcSize);
    if (contentSize == ZSTD_CONTENTSIZE_ERROR) {
        rb_raise(rb_eRuntimeError, "Invalid compressed data: not a valid zstd frame (size: %zu bytes)", srcSize);
    }

    // Extract keyword arguments
    ZSTD_DDict* ddict = NULL;
    size_t initial_capacity = 0;  // 0 = not specified in per-call options

    if (!NIL_P(options)) {
        VALUE dict_val = rb_hash_aref(options, ID2SYM(rb_intern("dict")));
        if (!NIL_P(dict_val)) {
            vibe_zstd_ddict* ddict_struct;
            TypedData_Get_Struct(dict_val, vibe_zstd_ddict, &vibe_zstd_ddict_type, ddict_struct);
            ddict = ddict_struct->ddict;
        }

        VALUE initial_capacity_val = rb_hash_aref(options, ID2SYM(rb_intern("initial_capacity")));
        if (!NIL_P(initial_capacity_val)) {
            initial_capacity = NUM2SIZET(initial_capacity_val);
            if (initial_capacity == 0) {
                rb_raise(rb_eArgError, "initial_capacity must be positive");
            }
        }
    }

    // Resolve initial_capacity fallback chain: per-call > instance > class default > ZSTD default
    if (initial_capacity == 0) {
        initial_capacity = dctx->initial_capacity;  // Instance default
        if (initial_capacity == 0) {
            initial_capacity = default_initial_capacity;  // Class default
            if (initial_capacity == 0) {
                initial_capacity = ZSTD_DStreamOutSize();  // ZSTD default (~128KB)
            }
        }
    }

    // If content size is unknown, use streaming decompression with exponential growth
    if (contentSize == ZSTD_CONTENTSIZE_UNKNOWN) {
        size_t chunk_size = ZSTD_DStreamOutSize();  // Fixed chunk buffer size
        VALUE tmpBuffer = rb_str_buf_new(chunk_size);

        // Start with configured initial capacity
        size_t result_capacity = initial_capacity;
        size_t result_size = 0;
        VALUE result = rb_str_buf_new(result_capacity);

        ZSTD_inBuffer input = { src, srcSize, 0 };

        while (input.pos < input.size) {
            ZSTD_outBuffer output = { RSTRING_PTR(tmpBuffer), chunk_size, 0 };

            size_t ret = ZSTD_decompressStream(dctx->dctx, &output, &input);
            if (ZSTD_isError(ret)) {
                rb_raise(rb_eRuntimeError, "Decompression failed: %s", ZSTD_getErrorName(ret));
            }

            if (output.pos > 0) {
                // Grow result buffer exponentially if needed
                if (result_size + output.pos > result_capacity) {
                    // Double capacity until it fits
                    while (result_capacity < result_size + output.pos) {
                        result_capacity *= 2;
                    }
                    rb_str_resize(result, result_capacity);
                }

                // Copy directly into result buffer
                memcpy(RSTRING_PTR(result) + result_size, RSTRING_PTR(tmpBuffer), output.pos);
                result_size += output.pos;
            }
        }

        // Trim to actual size
        rb_str_resize(result, result_size);
        return result;
    }
    VALUE result = rb_str_new(NULL, contentSize);
    decompress_args args = {
        .dctx = dctx->dctx,
        .ddict = ddict,
        .src = src,
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

// DCtx reset - reset context to clean state
static VALUE
vibe_zstd_dctx_reset(int argc, VALUE* argv, VALUE self) {
    VALUE reset_mode;
    rb_scan_args(argc, argv, "01", &reset_mode);

    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);

    // Default to SESSION_AND_PARAMETERS if no argument provided
    ZSTD_ResetDirective directive = ZSTD_reset_session_and_parameters;

    if (!NIL_P(reset_mode)) {
        int mode = NUM2INT(reset_mode);
        if (mode == ZSTD_reset_session_only) {
            directive = ZSTD_reset_session_only;
        } else if (mode == ZSTD_reset_parameters) {
            directive = ZSTD_reset_parameters;
        } else if (mode == ZSTD_reset_session_and_parameters) {
            directive = ZSTD_reset_session_and_parameters;
        } else {
            rb_raise(rb_eArgError, "Invalid reset_mode %d: must be ResetDirective::SESSION (1), PARAMETERS (2), or BOTH (3)", mode);
        }
    }

    size_t result = ZSTD_DCtx_reset(dctx->dctx, directive);

    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to reset decompression context: %s", ZSTD_getErrorName(result));
    }

    return self;
}

// Class initialization function called from main Init_vibe_zstd
void
vibe_zstd_dctx_init_class(VALUE rb_cVibeZstdDCtx) {
    // Initialize parameter lookup table
    init_dctx_param_table();

    rb_define_alloc_func(rb_cVibeZstdDCtx, vibe_zstd_dctx_alloc);
    rb_define_method(rb_cVibeZstdDCtx, "initialize", vibe_zstd_dctx_initialize, -1);
    rb_define_method(rb_cVibeZstdDCtx, "decompress", vibe_zstd_dctx_decompress, -1);
    rb_define_method(rb_cVibeZstdDCtx, "use_prefix", vibe_zstd_dctx_use_prefix, 1);
    rb_define_method(rb_cVibeZstdDCtx, "reset", vibe_zstd_dctx_reset, -1);
    rb_define_singleton_method(rb_cVibeZstdDCtx, "parameter_bounds", vibe_zstd_dctx_parameter_bounds, 1);
    rb_define_singleton_method(rb_cVibeZstdDCtx, "frame_content_size", vibe_zstd_dctx_frame_content_size, 1);
    rb_define_singleton_method(rb_cVibeZstdDCtx, "estimate_memory", vibe_zstd_dctx_estimate_memory, 0);

    // Class-level default_initial_capacity accessors
    rb_define_singleton_method(rb_cVibeZstdDCtx, "default_initial_capacity", vibe_zstd_dctx_get_default_initial_capacity, 0);
    rb_define_singleton_method(rb_cVibeZstdDCtx, "default_initial_capacity=", vibe_zstd_dctx_set_default_initial_capacity, 1);

    // DCtx parameter accessors
    rb_define_method(rb_cVibeZstdDCtx, "window_log_max=", vibe_zstd_dctx_set_window_log_max, 1);
    rb_define_method(rb_cVibeZstdDCtx, "window_log_max", vibe_zstd_dctx_get_window_log_max, 0);
    rb_define_alias(rb_cVibeZstdDCtx, "max_window_log=", "window_log_max=");
    rb_define_alias(rb_cVibeZstdDCtx, "max_window_log", "window_log_max");

    // Instance-level initial_capacity accessors
    rb_define_method(rb_cVibeZstdDCtx, "initial_capacity", vibe_zstd_dctx_get_initial_capacity, 0);
    rb_define_method(rb_cVibeZstdDCtx, "initial_capacity=", vibe_zstd_dctx_set_initial_capacity, 1);
}
