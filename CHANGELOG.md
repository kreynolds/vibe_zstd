# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-06-11

### Security
- Fixed use-after-free: `CompressWriter` and `DecompressReader` now retain their dictionary object. Previously only the raw `ZSTD_CDict*`/`ZSTD_DDict*` pointer was stored, so a dictionary passed as `dict:` without the caller holding their own reference could be garbage-collected while the stream still used it.
- `DCtx#decompress` now raises `RuntimeError` ("Truncated frame") when an unknown-content-size frame ends mid-stream, instead of silently returning partial output. The known-size path already rejected truncated input; the streaming path now matches.
- Dictionary training (`train_dict`, `train_dict_cover`, `train_dict_fast_cover`, `finalize_dictionary`) no longer crashes or risks a heap overflow when samples are non-String objects responding to `to_str`, or when a malicious `to_str` mutates other samples mid-validation. Converted samples are retained and the copy is capacity-checked.
- Source strings are now locked (`rb_str_locktmp`) while the GVL is released during `CCtx#compress`, `DCtx#decompress`, and across `CompressWriter#write`'s IO calls, preventing a use-after-free read if another thread (or re-entrant IO code) mutates the string mid-operation. Unlocking is async-exception-safe via `rb_ensure`.
- `DecompressReader` snapshots each input chunk (`rb_str_new_frozen`), so IOs that reuse/mutate the buffer string they return can no longer invalidate the decoder's input pointer between reads.
- `DecompressReader#read` raises `TypeError` when the underlying IO's `read` returns a non-String (non-`to_str`-able) object, instead of crashing the VM.
- `CCtx.new` / `DCtx.new` raise `ArgumentError` on non-Symbol keyword keys (e.g. `CCtx.new("level" => 3)`) instead of hitting undefined behavior.

### Fixed
- `DCtx#decompress` (unknown-size path): the C output buffer and per-call dictionary reference are now released via `rb_ensure` on every exit path, so an async exception (e.g. `Timeout`) can no longer leak the buffer or leave the dictionary referenced on the context.
- `DecompressReader#read(0)` returns `""` without latching EOF, matching IO semantics. Previously it returned `nil` and marked the stream finished.
- `DecompressReader#gets` no longer mixes character indexes with byte sizes, fixing line splitting with multibyte separators.
- Build: added `ext/vibe_zstd/depend` so editing the split implementation files (`cctx.c`, `dctx.c`, `dict.c`, `streaming.c`, `frames.c`) or project headers triggers recompilation of the extension.

### Changed
- `DecompressReader#read(n)` caps its initial allocation (~128KB) and grows geometrically up to `n`, instead of preallocating the full requested size up front (`read(1_000_000_000)` on a small stream no longer allocates 1GB).
- `VibeZstd::ThreadLocal` uses true thread-local storage (`Thread#thread_variable_get/set`) instead of fiber-local `Thread.current[]`, so fiber-based servers (Falcon, async) reuse one context pool per OS thread rather than churning a fresh pool per fiber.
- README: prominent warning recommending `max_decompressed_size` when decompressing untrusted input.

## [1.2.0] - 2026-06-06

### Added
- `DCtx#format` / `#format=` (`ZSTD_d_format`) and magicless-format decompression. Frames produced with `format: 1` (`ZSTD_f_zstd1_magicless`) can now be decompressed by setting `format: 1` on the decompression side.
- Opt-in decompressed-size limit on `DCtx#decompress`, configurable per-call (`max_decompressed_size:` / `max_size:`), per-instance (`DCtx#max_decompressed_size=`, alias `max_size=`), and as a class default (`DCtx.default_max_decompressed_size=`). Resolved per-call → instance → class → unlimited. Exceeding the limit raises `VibeZstd::DecompressedSizeExceeded` (a subclass of `VibeZstd::Error`). Off by default, preserving existing behavior.
- `VibeZstd.compress` / `VibeZstd.decompress` now accept context (sticky) parameters as keyword arguments (e.g. `checksum_flag:`, `window_log:`, `workers:`, `format:`), applying them to a fresh context. Per-call options are still passed to the operation.

### Fixed
- `CCtx#compress` now honors parameters configured on the context (`compression_level`, `checksum_flag`, `window_log`, `workers`, `format`, etc.). It previously used `ZSTD_compressCCtx`, which ignores all sticky parameters, so context configuration was silently discarded and one-shot compression always ran at the default level.
- `DCtx#decompress` now applies the dictionary on the unknown-content-size path. Dictionary frames produced by `CompressWriter` (which never pledges a size) previously failed to decompress with "Dictionary mismatch".
- `VibeZstd.read_skippable_frame` caps its allocation to the bytes actually present instead of trusting the frame's content-size header, preventing a tiny truncated input from forcing a multi-gigabyte allocation.
- Passing an unknown keyword to `VibeZstd.compress` / `VibeZstd.decompress` now raises `NoMethodError` instead of being silently ignored.

## [1.1.1] - 2026-03-25

### Fixed
- Fix `RuntimeError: can't set length of shared string` in `CompressWriter` when writing to File IO on Ruby 3.3+ caused by COW buffer sharing during `IO#write`
- Fix vendored zstd build flags (`-DZSTD_MULTITHREAD`, `-DXXH_NAMESPACE`, `-DZSTD_LEGACY_SUPPORT`) not propagating to compiled sources, restoring multithreaded compression support (`workers`, `rsyncable` parameters)

## [1.1.0] - 2026-03-02

### Added
- Release GVL during unknown-size streaming decompression, preventing thread blocking in multi-threaded servers (Puma, etc.)

### Changed
- `DecompressReader#gets` now uses 8KB buffered reads instead of 1-byte-at-a-time, dramatically reducing read call overhead on line-oriented data
- `CompressWriter` reuses a single output buffer across calls instead of allocating ~128KB per `write`/`flush`/`finish`

### Fixed
- Exception safety in dict training: all four training functions now use `rb_ensure` so C buffers are always freed even if a Ruby exception is raised
- Add `dsize` callbacks to all `TypedData` types so the GC sees accurate memory pressure from ZSTD context objects
- Add `RUBY_TYPED_WB_PROTECTED` and proper write barriers to all typed structs for GC correctness

### Performance
- Stack-allocated string buffer in CCtx setter, eliminating a malloc/free per keyword-argument call
- Cache `id_write`/`id_read` as static IDs instead of calling `rb_intern` on every I/O call
- Remove redundant `init_cctx_param_table`/`init_dctx_param_table` calls at startup

## [1.0.2] - 2025-01-20

### Fixed
- Fix extension loading using `require` instead of `require_relative` to resolve intermittent load errors on gem installation

## [1.0.1] - 2025-10-24

### Fixed
- Include assembly files in build to fix compilation on x86_64 Linux platforms

## [1.0.0] - 2025-10-22

### Added
- Initial release of VibeZstd
- Fast, idiomatic Ruby bindings for Zstandard (zstd) compression library
- Compression and decompression functionality
- Support for compression levels and parameters
- Dictionary compression support
- Streaming compression and decompression
- Thread pool support for parallel compression
- Memory-efficient API for large files

[1.2.0]: https://github.com/kreynolds/vibe_zstd/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/kreynolds/vibe_zstd/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/kreynolds/vibe_zstd/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/kreynolds/vibe_zstd/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/kreynolds/vibe_zstd/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/kreynolds/vibe_zstd/releases/tag/v1.0.0
