// CCtx implementation for VibeZstd
#include "vibe_zstd_internal.h"

// TypedData type - defined in vibe_zstd.c
extern rb_data_type_t vibe_zstd_cctx_type;

// Helper to set CCtx parameter from Ruby keyword argument
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

// CCtx.estimate_memory(level)
static VALUE
vibe_zstd_cctx_estimate_memory(VALUE self, VALUE level) {
    int lvl = NUM2INT(level);
    size_t estimate = ZSTD_estimateCCtxSize(lvl);
    return SIZET2NUM(estimate);
}

// Compress args for GVL release
// This structure packages all arguments needed for compression so we can
// call ZSTD functions without holding Ruby's Global VM Lock (GVL).
// Releasing the GVL allows other Ruby threads to run during CPU-intensive compression.
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

// Compress without holding Ruby's GVL
// Called via rb_thread_call_without_gvl to allow parallel Ruby thread execution
// during CPU-intensive compression operations
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

// CCtx compress - Compress data using this context
//
// Supports per-operation parameters via keyword arguments:
// - level: Compression level (overrides context setting for this operation)
// - dict: CDict to use for compression
// - pledged_size: Expected input size for optimization (optional)
//
// Uses ZSTD_compressBound to allocate worst-case output buffer size,
// which is the recommended approach for one-shot compression.
// Releases GVL during compression to allow other Ruby threads to run.
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
            rb_raise(rb_eRuntimeError, "Failed to set pledged_size %llu: %s", pledged_size, ZSTD_getErrorName(result));
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
    {0, ZSTD_c_nbWorkers, "workers"},
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
// Maps Ruby symbol (e.g., :compression_level) to ZSTD parameter constant
// Returns 1 if found, 0 if unknown parameter
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
DEFINE_CCTX_PARAM_ACCESSORS(workers, ZSTD_c_nbWorkers, "workers")
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

// CCtx reset - reset context to clean state
static VALUE
vibe_zstd_cctx_reset(int argc, VALUE* argv, VALUE self) {
    VALUE reset_mode;
    rb_scan_args(argc, argv, "01", &reset_mode);

    vibe_zstd_cctx* cctx;
    TypedData_Get_Struct(self, vibe_zstd_cctx, &vibe_zstd_cctx_type, cctx);

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

    size_t result = ZSTD_CCtx_reset(cctx->cctx, directive);

    if (ZSTD_isError(result)) {
        rb_raise(rb_eRuntimeError, "Failed to reset compression context: %s", ZSTD_getErrorName(result));
    }

    return self;
}

// Class initialization function called from main Init_vibe_zstd
void
vibe_zstd_cctx_init_class(VALUE rb_cVibeZstdCCtx) {
    // Initialize parameter lookup table
    init_cctx_param_table();

    // Define allocation and basic methods
    rb_define_alloc_func(rb_cVibeZstdCCtx, vibe_zstd_cctx_alloc);
    rb_define_method(rb_cVibeZstdCCtx, "initialize", vibe_zstd_cctx_initialize, -1);
    rb_define_method(rb_cVibeZstdCCtx, "compress", vibe_zstd_cctx_compress, -1);
    rb_define_method(rb_cVibeZstdCCtx, "use_prefix", vibe_zstd_cctx_use_prefix, 1);
    rb_define_method(rb_cVibeZstdCCtx, "reset", vibe_zstd_cctx_reset, -1);
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
    rb_define_method(rb_cVibeZstdCCtx, "workers=", vibe_zstd_cctx_set_workers, 1);
    rb_define_method(rb_cVibeZstdCCtx, "workers", vibe_zstd_cctx_get_workers, 0);
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
}
