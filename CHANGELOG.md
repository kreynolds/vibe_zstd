# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Binary search (`bsearch`) for CCtx parameter lookup instead of O(n) linear scan
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

[1.1.0]: https://github.com/kreynolds/vibe_zstd/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/kreynolds/vibe_zstd/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/kreynolds/vibe_zstd/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/kreynolds/vibe_zstd/releases/tag/v1.0.0
