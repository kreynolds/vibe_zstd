// DCtx implementation for VibeZstd
#include "vibe_zstd_internal.h"
#include <stdlib.h>  // malloc, realloc, free for no-GVL decompression path

// TypedData type - defined in vibe_zstd.c
extern rb_data_type_t vibe_zstd_dctx_type;

// Class-level default for initial capacity (0 = use ZSTD_DStreamOutSize)
static size_t default_initial_capacity = 0;

// Class-level default output-size limit (0 = unlimited)
static size_t default_max_decompressed_size = 0;

// VibeZstd::DecompressedSizeExceeded - raised when output exceeds the limit.
// Defined in vibe_zstd_dctx_init_class, cached here for use on the error path.
static VALUE rb_eDecompressedSizeExceeded;

// Helper to set DCtx parameter from Ruby keyword argument
static int
vibe_zstd_dctx_init_param_iter(VALUE key, VALUE value, VALUE self) {
    // Guard: only Symbol keys are valid.  A non-Symbol key (e.g. a String like
    // "format" => 1) would make SYM2ID undefined behaviour, so reject it early.
    if (!SYMBOL_P(key)) {
        rb_raise(rb_eArgError,
                 "DCtx.new option keys must be Symbols (got %"PRIsVALUE")",
                 rb_inspect(key));
    }

    // Build the setter method name: key + "="
    const char* key_str = rb_id2name(SYM2ID(key));
    char setter[256];
    snprintf(setter, sizeof(setter), "%s=", key_str);

    // Call the setter method
    rb_funcall(self, rb_intern(setter), 1, value);

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
    {0, ZSTD_d_windowLogMax, "window_log_max"},
    {0, ZSTD_d_format, "format"}
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
// Maps Ruby symbol (e.g., :window_log_max) to ZSTD parameter constant
// Returns 1 if found, 0 if unknown parameter
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
DEFINE_DCTX_PARAM_ACCESSORS(format, ZSTD_d_format, "format")

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

// DCtx default_max_decompressed_size getter (class method); 0 = unlimited
static VALUE
vibe_zstd_dctx_get_default_max_decompressed_size(VALUE self) {
    return SIZET2NUM(default_max_decompressed_size);
}

// DCtx default_max_decompressed_size setter (class method)
static VALUE
vibe_zstd_dctx_set_default_max_decompressed_size(VALUE self, VALUE value) {
    if (NIL_P(value)) {
        default_max_decompressed_size = 0;  // unlimited
    } else {
        default_max_decompressed_size = NUM2SIZET(value);
    }
    return value;
}

// DCtx max_decompressed_size getter (instance method); reports the effective
// limit, falling back to the class default. Returns 0 when unlimited.
static VALUE
vibe_zstd_dctx_get_max_decompressed_size(VALUE self) {
    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);

    if (dctx->max_decompressed_size == 0) {
        return SIZET2NUM(default_max_decompressed_size);
    }
    return SIZET2NUM(dctx->max_decompressed_size);
}

// DCtx max_decompressed_size setter (instance method); nil = inherit class default
static VALUE
vibe_zstd_dctx_set_max_decompressed_size(VALUE self, VALUE value) {
    vibe_zstd_dctx* dctx;
    TypedData_Get_Struct(self, vibe_zstd_dctx, &vibe_zstd_dctx_type, dctx);

    if (NIL_P(value)) {
        dctx->max_decompressed_size = 0;  // inherit class default
    } else {
        size_t limit = NUM2SIZET(value);
        if (limit == 0) {
            rb_raise(rb_eArgError, "max_decompressed_size must be positive (or nil to inherit the class default)");
        }
        dctx->max_decompressed_size = limit;
    }
    return value;
}

// Decompress args for GVL release
// This structure packages all arguments needed for decompression so we can
// call ZSTD functions without holding Ruby's Global VM Lock (GVL).
// Releasing the GVL allows other Ruby threads to run during CPU-intensive decompression.
typedef struct {
    ZSTD_DCtx* dctx;
    ZSTD_DDict* ddict;
    const void* src;
    size_t srcSize;
    void* dst;
    size_t dstCapacity;
    size_t result;
} decompress_args;

// Decompress without holding Ruby's GVL
// Called via rb_thread_call_without_gvl to allow parallel Ruby thread execution
// during CPU-intensive decompression operations
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

// Decompress stream args for GVL release (unknown content size path)
// Uses plain C malloc/realloc since Ruby API calls are not allowed without GVL
typedef struct {
    ZSTD_DCtx *dctx;
    const char *src;
    size_t src_size;
    char *dst;
    size_t dst_capacity;
    size_t dst_size;
    size_t initial_capacity;
    size_t max_size;   // 0 = unlimited; otherwise output must not exceed this
    int error;
    int limit_exceeded;  // set if output would exceed max_size
    int truncated;        // set if input was exhausted before the frame completed
    const char *error_name;
} decompress_stream_nogvl_args;

// Decompress stream without holding Ruby's GVL (unknown content size path)
// Performs the entire ZSTD_decompressStream loop using C malloc/realloc.
// No Ruby API calls allowed here.
static void*
decompress_stream_without_gvl(void* arg) {
    decompress_stream_nogvl_args* args = arg;
    args->error = 0;
    args->limit_exceeded = 0;
    args->truncated = 0;
    args->error_name = NULL;

    args->dst_capacity = args->initial_capacity;
    // Never allocate more than the configured limit up front.
    if (args->max_size && args->dst_capacity > args->max_size) {
        args->dst_capacity = args->max_size;
    }
    args->dst = malloc(args->dst_capacity);
    if (!args->dst) {
        args->error = 1;
        args->error_name = "malloc failed for decompression buffer";
        return NULL;
    }
    args->dst_size = 0;

    ZSTD_inBuffer input = { args->src, args->src_size, 0 };
    size_t last_ret = 1;  // sentinel: non-zero = frame not yet complete

    while (input.pos < input.size) {
        // Ensure we have room for output
        if (args->dst_size >= args->dst_capacity) {
            size_t new_capacity = args->dst_capacity * 2;
            // Clamp growth to the configured limit. If we cannot grow past the
            // current capacity, the output would exceed the limit.
            if (args->max_size && new_capacity > args->max_size) {
                new_capacity = args->max_size;
            }
            if (new_capacity <= args->dst_capacity) {
                args->limit_exceeded = 1;
                return NULL;
            }
            char* new_buf = realloc(args->dst, new_capacity);
            if (!new_buf) {
                args->error = 1;
                args->error_name = "realloc failed during decompression";
                return NULL;
            }
            args->dst = new_buf;
            args->dst_capacity = new_capacity;
        }

        ZSTD_outBuffer output = {
            args->dst + args->dst_size,
            args->dst_capacity - args->dst_size,
            0
        };

        size_t ret = ZSTD_decompressStream(args->dctx, &output, &input);
        if (ZSTD_isError(ret)) {
            args->error = 1;
            args->error_name = ZSTD_getErrorName(ret);
            return NULL;
        }

        args->dst_size += output.pos;
        last_ret = ret;

        // ret == 0 means frame is complete
        if (ret == 0) break;
    }

    // If we consumed all input but the last call still reported a non-zero hint
    // (more input needed), the frame was cut short — flag it as truncated.
    if (last_ret != 0) {
        args->truncated = 1;
    }

    return NULL;
}

// State for the rb_ensure-wrapped unknown-size decompression path.
// Groups everything the body needs to run the no-GVL stream loop and everything
// the cleanup needs to release on any exit (raise, async exception, success).
typedef struct {
    ZSTD_DCtx* dctx;
    ZSTD_DDict* ddict;
    decompress_stream_nogvl_args* args;
    VALUE data;
    size_t max_size;
} dctx_stream_decompress_state;

// Body: run the no-GVL stream loop (source string locked), check the outcome,
// and build the result string. Raising here is safe: cleanup always runs.
static VALUE
vibe_zstd_dctx_stream_decompress_body(VALUE p) {
    dctx_stream_decompress_state* state = (dctx_stream_decompress_state*)p;

    // Lock the source string while the GVL is released: another Ruby thread
    // holding the same string must not mutate or GC it mid-decompression.
    vibe_zstd_nogvl_with_str_locked(decompress_stream_without_gvl, state->args, state->data);

    if (state->args->limit_exceeded) {
        rb_raise(rb_eDecompressedSizeExceeded,
                 "Decompressed output exceeds limit of %zu bytes", state->max_size);
    }

    if (state->args->error) {
        rb_raise(rb_eRuntimeError, "Decompression failed: %s", state->args->error_name);
    }

    if (state->args->truncated) {
        rb_raise(rb_eRuntimeError, "Truncated frame: incomplete zstd data");
    }

    // Create Ruby string from the C buffer; cleanup frees the buffer
    return rb_str_new(state->args->dst, state->args->dst_size);
}

// Cleanup: free the C output buffer and return the context to no-dictionary
// mode so subsequent calls on this DCtx are not affected.
static VALUE
vibe_zstd_dctx_stream_decompress_cleanup(VALUE p) {
    dctx_stream_decompress_state* state = (dctx_stream_decompress_state*)p;
    if (state->args->dst) {
        free(state->args->dst);
        state->args->dst = NULL;
    }
    if (state->ddict) {
        ZSTD_DCtx_refDDict(state->dctx, NULL);
    }
    return Qnil;
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

// DCtx decompress - Decompress ZSTD-compressed data
//
// This function handles two decompression paths:
// 1. Known content size: Allocates exact buffer size and decompresses in one shot
// 2. Unknown content size: Uses streaming decompression with exponential buffer growth
//
// The unknown-size path uses a standard exponential growth strategy (doubling)
// which provides optimal O(n) amortized performance. Initial capacity can be
// configured via initial_capacity parameter to reduce reallocations for known size ranges.
//
// Dictionary validation is performed to ensure frame requirements match provided dict.
// Skippable frames at the beginning of data are automatically skipped.
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

    // Magicless frames (format = ZSTD_f_zstd1_magicless) carry no magic number,
    // so frame introspection (content size, dict ID, skippable detection) cannot
    // be performed. Force the streaming decompress path, which honors the format
    // parameter set on the context via ZSTD_decompressStream.
    int dformat = 0;
    (void)ZSTD_DCtx_getParameter(dctx->dctx, ZSTD_d_format, &dformat);
    int magicless = (dformat == ZSTD_f_zstd1_magicless);

    unsigned long long contentSize;
    unsigned int frame_dict_id;

    if (magicless) {
        contentSize = ZSTD_CONTENTSIZE_UNKNOWN;  // route to streaming path
        frame_dict_id = 0;                        // cannot read dict ID without magic
    } else {
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

        contentSize = ZSTD_getFrameContentSize(src, srcSize);
        if (contentSize == ZSTD_CONTENTSIZE_ERROR) {
            rb_raise(rb_eRuntimeError, "Invalid compressed data: not a valid zstd frame (size: %zu bytes)", srcSize);
        }

        // Check dictionary requirements from the frame
        frame_dict_id = ZSTD_getDictID_fromFrame(src, srcSize);
    }

    // Extract keyword arguments
    ZSTD_DDict* ddict = NULL;
    unsigned int provided_dict_id = 0;
    size_t initial_capacity = 0;  // 0 = not specified in per-call options
    size_t max_size = 0;          // 0 = not specified in per-call options

    if (!NIL_P(options)) {
        VALUE dict_val = rb_hash_aref(options, ID2SYM(rb_intern("dict")));
        if (!NIL_P(dict_val)) {
            vibe_zstd_ddict* ddict_struct;
            TypedData_Get_Struct(dict_val, vibe_zstd_ddict, &vibe_zstd_ddict_type, ddict_struct);
            ddict = ddict_struct->ddict;
            provided_dict_id = ZSTD_getDictID_fromDDict(ddict);
        }

        VALUE initial_capacity_val = rb_hash_aref(options, ID2SYM(rb_intern("initial_capacity")));
        if (!NIL_P(initial_capacity_val)) {
            initial_capacity = NUM2SIZET(initial_capacity_val);
            if (initial_capacity == 0) {
                rb_raise(rb_eArgError, "initial_capacity must be positive");
            }
        }

        // Per-call output-size limit; accepts :max_decompressed_size or :max_size.
        VALUE max_size_val = rb_hash_aref(options, ID2SYM(rb_intern("max_decompressed_size")));
        if (NIL_P(max_size_val)) {
            max_size_val = rb_hash_aref(options, ID2SYM(rb_intern("max_size")));
        }
        if (!NIL_P(max_size_val)) {
            max_size = NUM2SIZET(max_size_val);
            if (max_size == 0) {
                rb_raise(rb_eArgError, "max_decompressed_size must be positive");
            }
        }
    }

    // Resolve max_size fallback chain: per-call > instance > class default.
    // A value of 0 at every level means unlimited.
    if (max_size == 0) {
        max_size = dctx->max_decompressed_size;  // instance
        if (max_size == 0) {
            max_size = default_max_decompressed_size;  // class
        }
    }

    // Validate dictionary matches frame requirements
    if (frame_dict_id != 0 && ddict == NULL) {
        rb_raise(rb_eArgError, "Data requires dictionary (dict_id: %u) but none provided", frame_dict_id);
    }

    if (ddict != NULL && frame_dict_id != 0 && provided_dict_id != frame_dict_id) {
        rb_raise(rb_eArgError, "Dictionary mismatch: frame requires dict_id %u, provided dict_id %u",
                 frame_dict_id, provided_dict_id);
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

    // If content size is unknown, use streaming decompression with exponential growth.
    // Releases GVL to allow other Ruby threads to run during decompression.
    // Uses C malloc/realloc (not Ruby allocators) since Ruby API calls are forbidden without GVL.
    if (contentSize == ZSTD_CONTENTSIZE_UNKNOWN) {
        // Reference the dictionary on the context before streaming decompression.
        // ZSTD_decompressStream uses whatever dict is referenced on the DCtx, so
        // without this the dictionary would be ignored on the unknown-size path
        // (every dict frame produced by CompressWriter has unknown content size).
        if (ddict) {
            size_t rd = ZSTD_DCtx_refDDict(dctx->dctx, ddict);
            if (ZSTD_isError(rd)) {
                rb_raise(rb_eRuntimeError, "Failed to reference dictionary: %s", ZSTD_getErrorName(rd));
            }
        }

        decompress_stream_nogvl_args stream_args = {
            .dctx = dctx->dctx,
            .src = src,
            .src_size = srcSize,
            .dst = NULL,
            .dst_capacity = 0,
            .dst_size = 0,
            .initial_capacity = initial_capacity,
            .max_size = max_size,
            .error = 0,
            .limit_exceeded = 0,
            .truncated = 0,
            .error_name = NULL
        };

        // Run the streaming decompression and build the result under rb_ensure:
        // the cleanup frees the C buffer and un-references the dictionary on
        // every exit path, including the raises below and async exceptions
        // delivered when the GVL is reacquired.
        dctx_stream_decompress_state state = {
            .dctx = dctx->dctx,
            .ddict = ddict,
            .args = &stream_args,
            .data = data,
            .max_size = max_size
        };
        return rb_ensure(vibe_zstd_dctx_stream_decompress_body, (VALUE)&state,
                         vibe_zstd_dctx_stream_decompress_cleanup, (VALUE)&state);
    }
    // Reject a frame whose declared content size exceeds the limit before
    // allocating the output buffer (the header is attacker-controlled).
    if (max_size && contentSize > (unsigned long long)max_size) {
        rb_raise(rb_eDecompressedSizeExceeded,
                 "Declared content size %llu exceeds limit of %zu bytes", contentSize, max_size);
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
    // Lock the source string while the GVL is released: another Ruby thread
    // holding the same string must not mutate or GC it mid-decompression.
    // The helper unlocks via rb_ensure so an async exception cannot leave
    // the string permanently locked.
    vibe_zstd_nogvl_with_str_locked(decompress_without_gvl, &args, data);
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

    // Define VibeZstd::Error (base) and VibeZstd::DecompressedSizeExceeded.
    // Defined here (rather than only in Ruby) so the error is available even if
    // the C extension is required without the Ruby wrapper. Ruby's
    // `class Error < StandardError` simply reopens the same class.
    VALUE rb_eVibeZstdError = rb_define_class_under(rb_mVibeZstd, "Error", rb_eStandardError);
    rb_eDecompressedSizeExceeded = rb_define_class_under(rb_mVibeZstd, "DecompressedSizeExceeded", rb_eVibeZstdError);

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
    rb_define_method(rb_cVibeZstdDCtx, "format=", vibe_zstd_dctx_set_format, 1);
    rb_define_method(rb_cVibeZstdDCtx, "format", vibe_zstd_dctx_get_format, 0);

    // Instance-level initial_capacity accessors
    rb_define_method(rb_cVibeZstdDCtx, "initial_capacity", vibe_zstd_dctx_get_initial_capacity, 0);
    rb_define_method(rb_cVibeZstdDCtx, "initial_capacity=", vibe_zstd_dctx_set_initial_capacity, 1);

    // Class-level default_max_decompressed_size accessors (0 = unlimited)
    rb_define_singleton_method(rb_cVibeZstdDCtx, "default_max_decompressed_size", vibe_zstd_dctx_get_default_max_decompressed_size, 0);
    rb_define_singleton_method(rb_cVibeZstdDCtx, "default_max_decompressed_size=", vibe_zstd_dctx_set_default_max_decompressed_size, 1);

    // Instance-level max_decompressed_size accessors (with shorter max_size alias)
    rb_define_method(rb_cVibeZstdDCtx, "max_decompressed_size", vibe_zstd_dctx_get_max_decompressed_size, 0);
    rb_define_method(rb_cVibeZstdDCtx, "max_decompressed_size=", vibe_zstd_dctx_set_max_decompressed_size, 1);
    rb_define_alias(rb_cVibeZstdDCtx, "max_size", "max_decompressed_size");
    rb_define_alias(rb_cVibeZstdDCtx, "max_size=", "max_decompressed_size=");
}
