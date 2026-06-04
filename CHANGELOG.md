# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[1.1.1]: https://github.com/kreynolds/vibe_zstd/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/kreynolds/vibe_zstd/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/kreynolds/vibe_zstd/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/kreynolds/vibe_zstd/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/kreynolds/vibe_zstd/releases/tag/v1.0.0
