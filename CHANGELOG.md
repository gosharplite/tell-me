# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-24

### Added
- **Formalized SOPs**: Comprehensive Standard Operating Procedures in `SOP/` for developers.
- **Testing Standards**: New SOP for testing and a mirrored `tests/` structure.
- **Agent Tools**: New `estimate_cost` tool for real-time session cost tracking.
- **Public Release SOP**: Formalized process for publishing releases.
- **SPDX Headers**: Standard license headers added to all core scripts.

### Changed
- **Directory Structure**: Refactored `lib/` and `tests/` into functional subdirectories.
- **Test Discovery**: Updated `run_tests.sh` to find tests recursively.
- **README.md**: Updated with new features, tools, and developer notes.

### Fixed
- **Path Issues**: Resolved relative path dependencies in test scripts after structural refactoring.
- **History Pruning**: Improved reliability of context management in edge cases.

