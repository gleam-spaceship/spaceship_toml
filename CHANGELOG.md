# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2024-12-XX

### Changed

- Added pre-commit hook and fixed warnings
- Improved cross-platform compatibility

## [0.1.0] - 2024-12-XX

### Added

- TOML parsing API (`parse`, `parse_or_error`)
- TOML tokenizer and parser with support for:
  - Tables and nested tables
  - Arrays and inline tables
  - Strings (basic, literal, multiline)
  - Integers and floats
  - Booleans
  - Date and datetime
- TOML editor for modifications (`get`, `set`, `add_table`, `add_array_of_tables`)
- TOML serializer with human-readable output
- JavaScript target support with FFI for float/int conversion
- Cross-platform support (Erlang and JavaScript targets)
