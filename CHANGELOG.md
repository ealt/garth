# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.0] - Unreleased

### Added

- Setup-managed cron image refresh job (weekly by default) with idempotent
  updates and schedule override via `GARTH_IMAGE_REFRESH_CRON_SCHEDULE`
- `features.packages` support for `bun` via upstream installer script, including
  image validation checks for the `bun` binary

### Fixed

- Empty `forward` array expansion crash under `set -u` in `cmd_up`, `cmd_new`,
  and `cmd_open` launch paths
- Pre-existing ShellCheck warnings (SC2221, SC2259, SC2034, SC1090, SC2088)
- `cli_open_smoke` test failure on CI due to missing config in XDG fallback path

### Changed

- CI now runs `make check` as single source of truth (no duplicated steps)

## [0.1.0] - 2026-03-04

### Added

- Homebrew tap and curl installer distribution
- `--version` flag and version display in usage header
- XDG config path fallback for non-clone installs
- Release workflow (GitHub Actions, triggered on VERSION change to main)
- CHANGELOG.md

[0.2.0]: https://github.com/ealt/garth/releases/tag/v0.2.0
[0.1.1]: https://github.com/ealt/garth/releases/tag/v0.1.1
[0.1.0]: https://github.com/ealt/garth/releases/tag/v0.1.0
