// Streaming implementation for VibeZstd
#include "vibe_zstd_internal.h"

// Forward declarations
static VALUE vibe_zstd_writer_initialize(int argc, VALUE *argv, VALUE self);
static VALUE vibe_zstd_writer_write(VALUE self, VALUE data);
static VALUE vibe_zstd_writer_flush(VALUE self);
static VALUE vibe_zstd_writer_finish(VALUE self);
static VALUE vibe_zstd_reader_initialize(int argc, VALUE *argv, VALUE self);
static VALUE vibe_zstd_reader_read(int argc, VALUE *argv, VALUE self);
static VALUE vibe_zstd_reader_eof(VALUE self);

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
    if (!rb_respond_to(io, rb_intern("write"))) {
        rb_raise(rb_eTypeError, "IO object must respond to write");
    }

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

    // Input buffer: pos advances as ZSTD consumes data
    ZSTD_inBuffer input = {
        .src = RSTRING_PTR(data),
        .size = RSTRING_LEN(data),
        .pos = 0
    };

    size_t outBufferSize = ZSTD_CStreamOutSize();
    VALUE outBuffer = rb_str_buf_new(outBufferSize);

    // Process all input data in chunks
    while (input.pos < input.size) {
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
            rb_funcall(cstream->io, rb_intern("write"), 1, outBuffer);
            // No need to resize - buffer capacity remains at outBufferSize
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

    // ZSTD_e_flush: flush internal buffers, making all data readable
    // Loop until remaining == 0 (flush complete)
    do {
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
            rb_funcall(cstream->io, rb_intern("write"), 1, outBuffer);
            // No need to resize - buffer capacity remains at outBufferSize
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

    // ZSTD_e_end: finalize frame with checksum and epilogue
    // Loop until remaining == 0 (frame complete)
    do {
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
            rb_funcall(cstream->io, rb_intern("write"), 1, outBuffer);
            // No need to resize - buffer capacity remains at outBufferSize
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
    if (!rb_respond_to(io, rb_intern("read"))) {
        rb_raise(rb_eTypeError, "IO object must respond to read");
    }

    // Store IO object
    dstream->io = io;
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
    }

    // Initialize input buffer management
    dstream->input_data = rb_str_new(NULL, 0);
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
//
// EOF handling:
// - Returns nil when no more data available
// - Sets eof flag when: IO returns nil, frame complete (ret==0), or no progress made
//
// This implements proper streaming semantics for incremental decompression
// of arbitrarily large files without loading everything into memory.
static VALUE
vibe_zstd_reader_read(int argc, VALUE *argv, VALUE self) {
    VALUE size_arg;
    rb_scan_args(argc, argv, "01", &size_arg);

    vibe_zstd_dstream* dstream;
    TypedData_Get_Struct(self, vibe_zstd_dstream, &vibe_zstd_dstream_type, dstream);

    if (dstream->eof) {
        return Qnil;
    }

    // Unbounded reads use configurable chunk size (defaults to ZSTD_DStreamOutSize() ~128KB)
    // This provides chunked streaming behavior for true streaming use cases
    size_t default_chunk_size = (dstream->initial_chunk_size > 0) ? dstream->initial_chunk_size : ZSTD_DStreamOutSize();
    size_t requested_size = NIL_P(size_arg) ? default_chunk_size : NUM2SIZET(size_arg);
    size_t inBufferSize = ZSTD_DStreamInSize();

    // Preallocate buffer for requested size
    VALUE result = rb_str_buf_new(requested_size);

    size_t total_read = 0;
    int made_progress = 0;

    while (total_read < requested_size) {
        // Refill input buffer when all compressed data consumed
        if (dstream->input.pos >= dstream->input.size) {
            VALUE chunk = rb_funcall(dstream->io, rb_intern("read"), 1, SIZET2NUM(inBufferSize));
            if (NIL_P(chunk)) {
                dstream->eof = 1;
                if (total_read == 0 && !made_progress) {
                    return Qnil;
                }
                break;
            }

            // Reset input buffer with new data
            dstream->input_data = chunk;
            dstream->input.src = RSTRING_PTR(chunk);
            dstream->input.size = RSTRING_LEN(chunk);
            dstream->input.pos = 0;
        }

        if (dstream->input.size == 0) {
            dstream->eof = 1;
            break;
        }

        size_t space_left = requested_size - total_read;

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
