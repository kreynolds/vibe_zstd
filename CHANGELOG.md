# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[1.0.0]: https://github.com/kreynolds/vipe_zstd/releases/tag/v1.0.0
