// Frame utilities implementation for VibeZstd
#include "vibe_zstd_internal.h"

// VibeZstd.compress_bound(size)
static VALUE
vibe_zstd_compress_bound(VALUE self, VALUE size) {
    size_t src_size = NUM2SIZET(size);
    size_t bound = ZSTD_compressBound(src_size);
    return SIZET2NUM(bound);
}

static VALUE
vibe_zstd_skippable_frame_p(VALUE self, VALUE data) {
    (void)self;
    StringValue(data);
    unsigned result = ZSTD_isSkippableFrame(RSTRING_PTR(data), RSTRING_LEN(data));
    return result ? Qtrue : Qfalse;
}

static VALUE
vibe_zstd_write_skippable_frame(int argc, VALUE *argv, VALUE self) {
    (void)self;
    VALUE data, options;
    rb_scan_args(argc, argv, "11", &data, &options);

    StringValue(data);

    unsigned magic_variant = 0;  // Default to 0
    if (!NIL_P(options)) {
        Check_Type(options, T_HASH);
        VALUE magic_num = rb_hash_aref(options, ID2SYM(rb_intern("magic_number")));
        if (!NIL_P(magic_num)) {
            magic_variant = NUM2UINT(magic_num);
            if (magic_variant > 15) {
                rb_raise(rb_eArgError, "magic_number %u out of bounds (valid: 0-15)", magic_variant);
            }
        }
    }

    const char* src = RSTRING_PTR(data);
    size_t src_size = RSTRING_LEN(data);

    // Skippable frame structure: 4-byte magic (0x184D2A5X) + 4-byte size + content
    // Decoders skip these frames, allowing custom metadata/padding
    size_t frame_size = 8 + src_size;
    VALUE result = rb_str_buf_new(frame_size);

    size_t written = ZSTD_writeSkippableFrame(
        RSTRING_PTR(result),
        frame_size,
        src,
        src_size,
        magic_variant
    );

    if (ZSTD_isError(written)) {
        rb_raise(rb_eRuntimeError, "ZSTD error: %s", ZSTD_getErrorName(written));
    }

    rb_str_set_len(result, written);
    return result;
}

static VALUE
vibe_zstd_read_skippable_frame(VALUE self, VALUE data) {
    (void)self;
    StringValue(data);

    if (!ZSTD_isSkippableFrame(RSTRING_PTR(data), RSTRING_LEN(data))) {
        rb_raise(rb_eArgError, "data is not a skippable frame (%zu bytes provided)", RSTRING_LEN(data));
    }

    const char* src = RSTRING_PTR(data);
    size_t src_size = RSTRING_LEN(data);

    // Content size is in bytes 4-7 (little-endian uint32)
    if (src_size < 8) {
        rb_raise(rb_eArgError, "skippable frame too small (%zu bytes, minimum 8 bytes required)", src_size);
    }

    uint32_t content_size;
    memcpy(&content_size, src + 4, 4);

    VALUE result = rb_str_buf_new(content_size);
    unsigned magic_variant;

    size_t bytes_read = ZSTD_readSkippableFrame(
        RSTRING_PTR(result),
        content_size,
        &magic_variant,
        src,
        src_size
    );

    if (ZSTD_isError(bytes_read)) {
        rb_raise(rb_eRuntimeError, "ZSTD error: %s", ZSTD_getErrorName(bytes_read));
    }

    rb_str_set_len(result, bytes_read);

    // Return [content, magic_variant]
    VALUE result_ary = rb_ary_new_capa(2);
    rb_ary_push(result_ary, result);
    rb_ary_push(result_ary, UINT2NUM(magic_variant));
    return result_ary;
}

static VALUE
vibe_zstd_find_frame_compressed_size(VALUE self, VALUE data) {
    (void)self;
    StringValue(data);

    // Returns compressed size of first complete frame (including header/checksum)
    // Useful for splitting concatenated frames in multi-frame archives
    size_t frame_size = ZSTD_findFrameCompressedSize(RSTRING_PTR(data), RSTRING_LEN(data));

    if (ZSTD_isError(frame_size)) {
        rb_raise(rb_eRuntimeError, "ZSTD error: %s", ZSTD_getErrorName(frame_size));
    }

    return SIZET2NUM(frame_size);
}

// Module method initialization called from main Init_vibe_zstd
void
vibe_zstd_frames_init_module_methods(VALUE rb_mVibeZstd) {
    rb_define_module_function(rb_mVibeZstd, "compress_bound", vibe_zstd_compress_bound, 1);
    rb_define_module_function(rb_mVibeZstd, "skippable_frame?", vibe_zstd_skippable_frame_p, 1);
    rb_define_module_function(rb_mVibeZstd, "write_skippable_frame", vibe_zstd_write_skippable_frame, -1);
    rb_define_module_function(rb_mVibeZstd, "read_skippable_frame", vibe_zstd_read_skippable_frame, 1);
    rb_define_module_function(rb_mVibeZstd, "find_frame_compressed_size", vibe_zstd_find_frame_compressed_size, 1);
}
