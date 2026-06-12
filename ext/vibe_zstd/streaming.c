// Streaming implementation for VibeZstd
#include "vibe_zstd_internal.h"

// Cached method IDs for frequently called methods
static ID id_write;
static ID id_read;

// Forward declarations
static VALUE vibe_zstd_writer_initialize(int argc, VALUE *argv, VALUE self);
static VALUE vibe_zstd_writer_write(VALUE self, VALUE data);
static VALUE vibe_zstd_writer_flush(VALUE self);
static VALUE vibe_zstd_writer_finish(VALUE self);
static VALUE vibe_zstd_reader_initialize(int argc, VALUE *argv, VALUE self);
static VALUE vibe_zstd_reader_read(int argc, VALUE *argv, VALUE self);
static VALUE vibe_zstd_reader_eof(VALUE self);

// State struct for rb_ensure-based string lock/unlock in vibe_zstd_writer_write
typedef struct {
    vibe_zstd_cstream* cstream;
    VALUE data;
} vibe_zstd_write_state;

// TypedData types - defined in vibe_zstd.c
extern rb_data_type_t vibe_zstd_cstream_type;
extern rb_data_type_t vibe_zstd_dstream_type;

// CompressWriter implementation
// Wraps ZSTD streaming compression to write compressed data to an IO object
static VALUE
vibe_zstd_writer_initialize(int argc, VALUE *argv, VALUE self) {
    VALUE io, options;
    rb_scan_args(argc, argv, "11", &io, &options);

    vibe_zstd_cstream* cstream;
    TypedData_Get_Struct(self, vibe_zstd_cstream, &vibe_zstd_cstream_type, cstream);

    // Validate IO object responds to write (duck typing)
    if (!rb_respond_to(io, id_write)) {
        rb_raise(rb_eTypeError, "IO object must respond to write");
    }

    // Store IO object (write barrier for WB_PROTECTED)
    RB_OBJ_WRITE(self, &cstream->io, io);
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
        // Retain the CDict object so GC won't free it while the stream holds a raw
        // pointer to its internal ZSTD_CDict (ZSTD_CCtx_refCDict stores no Ruby ref)
        rb_ivar_set(self, rb_intern("@dict"), dict);
    }

    // Allocate reusable output buffer (write barrier for WB_PROTECTED)
    RB_OBJ_WRITE(self, &cstream->output_buffer, rb_str_buf_new(ZSTD_CStreamOutSize()));

    return self;
}

// Body of the rb_ensure wrapper: runs the compress loop with data locked
static VALUE
vibe_zstd_writer_write_body(VALUE arg) {
    vibe_zstd_write_state* state = (vibe_zstd_write_state*)arg;
    vibe_zstd_cstream* cstream = state->cstream;
    VALUE data = state->data;

    // Input buffer: pos advances as ZSTD consumes data.
    // data is locked (rb_str_locktmp) for the duration of this call so that
    // RSTRING_PTR remains valid even when rb_funcall runs arbitrary Ruby code.
    ZSTD_inBuffer input = {
        .src = RSTRING_PTR(data),
        .size = RSTRING_LEN(data),
        .pos = 0
    };

    size_t outBufferSize = ZSTD_CStreamOutSize();
    VALUE outBuffer = cstream->output_buffer;

    // Process all input data in chunks
    while (input.pos < input.size) {
        // Unshare buffer if COW-shared by a prior IO#write receiver (Ruby 3.3+),
        // then restore capacity which may have shrunk during unsharing
        rb_str_modify(outBuffer);
        rb_str_resize(outBuffer, (long)outBufferSize);
        rb_str_set_len(outBuffer, 0);
        ZSTD_outBuffer output = {
            .dst = RSTRING_PTR(outBuffer),
            .size = outBufferSize,
            .pos = 0
        };

        // ZSTD_e_continue: continue compression without flushing
        // Return value is a hint for preferred input size (can be ignored)
        size_t result = ZSTD_compressStream2((ZSTD_CCtx*)cstream->cstream, &output, &input, ZSTD_e_continue);
        if (ZSTD_isError(result)) {
            rb_raise(rb_eRuntimeError, "Compression failed: %s", ZSTD_getErrorName(result));
        }

        // Write any compressed output that was produced
        if (output.pos > 0) {
            rb_str_set_len(outBuffer, output.pos);
            // rb_funcall may run arbitrary Ruby code, but input.src stays valid
            // because data is locked against mutation/reallocation
            rb_funcall(cstream->io, id_write, 1, outBuffer);
        }
    }

    return Qnil;
}

// Ensure function: always unlocks data regardless of raise/return
static VALUE
vibe_zstd_writer_write_unlock(VALUE arg) {
    rb_str_unlocktmp((VALUE)arg);
    return Qnil;
}

static VALUE
vibe_zstd_writer_write(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    vibe_zstd_cstream* cstream;
    TypedData_Get_Struct(self, vibe_zstd_cstream, &vibe_zstd_cstream_type, cstream);

    // Lock data for the duration of the compress loop so that RSTRING_PTR(data)
    // stays valid even when io.write (called inside the loop) runs Ruby code that
    // could otherwise mutate or resize the string.  rb_str_locktmp raises if the
    // string is already locked; the ensure always unlocks it.
    rb_str_locktmp(data);

    vibe_zstd_write_state state = { cstream, data };
    rb_ensure(vibe_zstd_writer_write_body, (VALUE)&state,
              vibe_zstd_writer_write_unlock, data);

    return self;
}

static VALUE
vibe_zstd_writer_flush(VALUE self) {
    vibe_zstd_cstream* cstream;
    TypedData_Get_Struct(self, vibe_zstd_cstream, &vibe_zstd_cstream_type, cstream);

    size_t outBufferSize = ZSTD_CStreamOutSize();
    VALUE outBuffer = cstream->output_buffer;

    ZSTD_inBuffer input = { NULL, 0, 0 };
    size_t remaining;

    // ZSTD_e_flush: flush internal buffers, making all data readable
    // Loop until remaining == 0 (flush complete)
    do {
        rb_str_modify(outBuffer);
        rb_str_resize(outBuffer, (long)outBufferSize);
        rb_str_set_len(outBuffer, 0);
        ZSTD_outBuffer output = {
            .dst = RSTRING_PTR(outBuffer),
            .size = outBufferSize,
            .pos = 0
        };

        // Return value > 0 means more flushing needed
        remaining = ZSTD_compressStream2((ZSTD_CCtx*)cstream->cstream, &output, &input, ZSTD_e_flush);
        if (ZSTD_isError(remaining)) {
            rb_raise(rb_eRuntimeError, "Flush failed: %s", ZSTD_getErrorName(remaining));
        }

        if (output.pos > 0) {
            rb_str_set_len(outBuffer, output.pos);
            rb_funcall(cstream->io, id_write, 1, outBuffer);
        }
    } while (remaining > 0);

    return self;
}

static VALUE
vibe_zstd_writer_finish(VALUE self) {
    vibe_zstd_cstream* cstream;
    TypedData_Get_Struct(self, vibe_zstd_cstream, &vibe_zstd_cstream_type, cstream);

    size_t outBufferSize = ZSTD_CStreamOutSize();
    VALUE outBuffer = cstream->output_buffer;

    ZSTD_inBuffer input = { NULL, 0, 0 };
    size_t remaining;

    // ZSTD_e_end: finalize frame with checksum and epilogue
    // Loop until remaining == 0 (frame complete)
    do {
        rb_str_modify(outBuffer);
        rb_str_resize(outBuffer, (long)outBufferSize);
        rb_str_set_len(outBuffer, 0);
        ZSTD_outBuffer output = {
            .dst = RSTRING_PTR(outBuffer),
            .size = outBufferSize,
            .pos = 0
        };

        // Return value > 0 means more epilogue data to write
        remaining = ZSTD_compressStream2((ZSTD_CCtx*)cstream->cstream, &output, &input, ZSTD_e_end);
        if (ZSTD_isError(remaining)) {
            rb_raise(rb_eRuntimeError, "Finish failed: %s", ZSTD_getErrorName(remaining));
        }

        if (output.pos > 0) {
            rb_str_set_len(outBuffer, output.pos);
            rb_funcall(cstream->io, id_write, 1, outBuffer);
        }
    } while (remaining > 0);

    return self;
}

// DecompressReader implementation
// Wraps ZSTD streaming decompression to read from a compressed IO object
static VALUE
vibe_zstd_reader_initialize(int argc, VALUE *argv, VALUE self) {
    VALUE io, options;
    rb_scan_args(argc, argv, "11", &io, &options);

    vibe_zstd_dstream* dstream;
    TypedData_Get_Struct(self, vibe_zstd_dstream, &vibe_zstd_dstream_type, dstream);

    // Validate IO object responds to read (duck typing)
    if (!rb_respond_to(io, id_read)) {
        rb_raise(rb_eTypeError, "IO object must respond to read");
    }

    // Store IO object (write barrier for WB_PROTECTED)
    RB_OBJ_WRITE(self, &dstream->io, io);
    rb_ivar_set(self, rb_intern("@io"), io);

    // Parse options
    VALUE dict = Qnil;
    size_t initial_chunk_size = 0;  // 0 = use default ZSTD_DStreamOutSize()
    if (!NIL_P(options)) {
        Check_Type(options, T_HASH);
        dict = rb_hash_aref(options, ID2SYM(rb_intern("dict")));

        VALUE v_chunk_size = rb_hash_aref(options, ID2SYM(rb_intern("initial_chunk_size")));
        if (!NIL_P(v_chunk_size)) {
            initial_chunk_size = NUM2SIZET(v_chunk_size);
            if (initial_chunk_size == 0) {
                rb_raise(rb_eArgError, "initial_chunk_size must be greater than 0");
            }
        }
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
        // Retain the DDict object so GC won't free it while the stream holds a raw
        // pointer to its internal ZSTD_DDict (ZSTD_DCtx_refDDict stores no Ruby ref)
        rb_ivar_set(self, rb_intern("@dict"), dict);
    }

    // Initialize input buffer management
    RB_OBJ_WRITE(self, &dstream->input_data, rb_str_new(NULL, 0));
    dstream->input.src = NULL;
    dstream->input.size = 0;
    dstream->input.pos = 0;
    dstream->eof = 0;
    dstream->initial_chunk_size = initial_chunk_size;

    return self;
}

// DecompressReader read - Read decompressed data from stream
//
// Handles streaming decompression with buffered input management:
// - Requested size: Reads up to specified number of bytes
// - No size (nil): Reads one chunk (default: ZSTD_DStreamOutSize ~128KB)
//
// Buffer management:
// - Maintains internal compressed input buffer that refills from IO as needed
// - Calls ZSTD_decompressStream incrementally to produce output
// - Tracks EOF state based on IO exhaustion and frame completion
// - Input chunks are stored as frozen copies so that IOs which mutate/reuse
//   the returned string cannot invalidate dstream->input.src between calls
//
// EOF handling:
// - Returns nil when no more data available
// - Sets eof flag when: IO returns nil, frame complete (ret==0), or no progress made
// - read(0) always returns "" immediately without touching stream state
//
// Allocation strategy:
// - Initial buffer is capped at ZSTD_DStreamOutSize() to avoid gigabyte
//   allocations for large size arguments on small streams
// - Buffer grows geometrically (doubling) up to requested_size as needed
//
// This implements proper streaming semantics for incremental decompression
// of arbitrarily large files without loading everything into memory.
static VALUE
vibe_zstd_reader_read(int argc, VALUE *argv, VALUE self) {
    VALUE size_arg;
    rb_scan_args(argc, argv, "01", &size_arg);

    vibe_zstd_dstream* dstream;
    TypedData_Get_Struct(self, vibe_zstd_dstream, &vibe_zstd_dstream_type, dstream);

    // read(0): per IO semantics, always return "" without touching stream state
    if (!NIL_P(size_arg) && NUM2SIZET(size_arg) == 0) {
        return rb_str_new(NULL, 0);
    }

    if (dstream->eof) {
        return Qnil;
    }

    // Unbounded reads use configurable chunk size (defaults to ZSTD_DStreamOutSize() ~128KB)
    // This provides chunked streaming behavior for true streaming use cases
    size_t default_chunk_size = (dstream->initial_chunk_size > 0) ? dstream->initial_chunk_size : ZSTD_DStreamOutSize();
    size_t requested_size = NIL_P(size_arg) ? default_chunk_size : NUM2SIZET(size_arg);
    size_t inBufferSize = ZSTD_DStreamInSize();

    // Cap the initial allocation to avoid multi-gigabyte pre-allocations when
    // the caller passes a huge size argument for a small stream.  The buffer
    // grows geometrically below as output accumulates.
    size_t default_out_size = ZSTD_DStreamOutSize();
    size_t initial_alloc = (requested_size < default_out_size) ? requested_size : default_out_size;
    VALUE result = rb_str_buf_new((long)initial_alloc);

    size_t total_read = 0;
    int made_progress = 0;

    while (total_read < requested_size) {
        // Refill input buffer when all compressed data consumed
        if (dstream->input.pos >= dstream->input.size) {
            VALUE chunk = rb_funcall(dstream->io, id_read, 1, SIZET2NUM(inBufferSize));
            if (NIL_P(chunk)) {
                dstream->eof = 1;
                if (total_read == 0 && !made_progress) {
                    return Qnil;
                }
                break;
            }

            // The IO is duck-typed: read may return anything. Convert via to_str
            // (raising TypeError otherwise) so RSTRING below never sees a non-String.
            StringValue(chunk);

            // Store a private frozen copy so that an IO that reuses/mutates its
            // returned buffer string cannot invalidate dstream->input.src between
            // successive read() calls.  rb_str_new_frozen is cheap (copy-on-write
            // snapshot) when the string is already frozen, and allocates a
            // separate copy otherwise.
            VALUE frozen_chunk = rb_str_new_frozen(chunk);

            // Reset input buffer with new data (write barrier for WB_PROTECTED)
            RB_OBJ_WRITE(self, &dstream->input_data, frozen_chunk);
            dstream->input.src = RSTRING_PTR(frozen_chunk);
            dstream->input.size = RSTRING_LEN(frozen_chunk);
            dstream->input.pos = 0;
        }

        if (dstream->input.size == 0) {
            dstream->eof = 1;
            break;
        }

        // Grow the output buffer geometrically when it is full, capped at
        // requested_size.  We must recompute RSTRING_PTR after any resize
        // because the backing allocation may move.
        size_t current_capacity = (size_t)rb_str_capacity(result);
        if (total_read >= current_capacity) {
            size_t new_capacity = current_capacity * 2;
            if (new_capacity > requested_size) new_capacity = requested_size;
            rb_str_resize(result, (long)new_capacity);
        }

        // Cap space_left at (requested_size - total_read) to ensure read(n) never
        // returns more than n bytes: rb_str_capacity may exceed the requested size
        // due to malloc's internal size-class rounding (e.g. request 100, get 135).
        size_t effective_capacity = (size_t)rb_str_capacity(result);
        if (effective_capacity > requested_size) effective_capacity = requested_size;
        size_t space_left = effective_capacity - total_read;

        ZSTD_outBuffer output = {
            .dst = RSTRING_PTR(result) + total_read,
            .size = space_left,
            .pos = 0
        };

        // ZSTD_decompressStream advances input.pos and output.pos
        // Return value: 0 = frame complete, >0 = hint for next input size, error if < 0
        size_t ret = ZSTD_decompressStream(dstream->dstream, &output, &dstream->input);
        if (ZSTD_isError(ret)) {
            rb_raise(rb_eRuntimeError, "Decompression failed: %s", ZSTD_getErrorName(ret));
        }

        if (output.pos > 0) {
            total_read += output.pos;
            made_progress = 1;
        }

        // Exit when we've read enough data
        if (total_read >= requested_size) {
            break;
        }

        // ret == 0 signals end of current frame
        if (ret == 0) {
            dstream->eof = 1;
            break;
        }

        // No output produced: need more input
        if (output.pos == 0) {
            continue;
        }
    }

    if (total_read == 0) {
        dstream->eof = 1;
        return Qnil;
    }

    rb_str_set_len(result, total_read);
    return result;
}

static VALUE
vibe_zstd_reader_eof(VALUE self) {
    vibe_zstd_dstream* dstream;
    TypedData_Get_Struct(self, vibe_zstd_dstream, &vibe_zstd_dstream_type, dstream);
    return dstream->eof ? Qtrue : Qfalse;
}

// Class initialization function called from main Init_vibe_zstd
void
vibe_zstd_streaming_init_classes(VALUE rb_cVibeZstdCompressWriter, VALUE rb_cVibeZstdDecompressReader) {
    // Cache method IDs for frequently called methods
    id_write = rb_intern("write");
    id_read = rb_intern("read");

    // CompressWriter setup
    rb_define_alloc_func(rb_cVibeZstdCompressWriter, vibe_zstd_cstream_alloc);
    rb_define_method(rb_cVibeZstdCompressWriter, "initialize", vibe_zstd_writer_initialize, -1);
    rb_define_method(rb_cVibeZstdCompressWriter, "write", vibe_zstd_writer_write, 1);
    rb_define_method(rb_cVibeZstdCompressWriter, "flush", vibe_zstd_writer_flush, 0);
    rb_define_method(rb_cVibeZstdCompressWriter, "finish", vibe_zstd_writer_finish, 0);
    rb_define_method(rb_cVibeZstdCompressWriter, "close", vibe_zstd_writer_finish, 0); // alias

    // DecompressReader setup
    rb_define_alloc_func(rb_cVibeZstdDecompressReader, vibe_zstd_dstream_alloc);
    rb_define_method(rb_cVibeZstdDecompressReader, "initialize", vibe_zstd_reader_initialize, -1);
    rb_define_method(rb_cVibeZstdDecompressReader, "read", vibe_zstd_reader_read, -1);
    rb_define_method(rb_cVibeZstdDecompressReader, "eof?", vibe_zstd_reader_eof, 0);
}
