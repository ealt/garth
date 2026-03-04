# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.1] - Unreleased

### Added

- Setup-managed cron image refresh job (weekly by default) with idempotent
  updates and schedule override via `GARTH_IMAGE_REFRESH_CRON_SCHEDULE`
- `garth refresh-images` command (alias: `garth refresh`) to force Docker image
  rebuilds with `--pull --no-cache` for configured or selected agents
- `features.packages` support for `bun` via upstream installer script, including
  image validation checks for the `bun` binary
- `garth open <id>` support to resume sessions directly by ID/prefix
- Short flag aliases for branch/worktree/session selectors:
  `-b` / `-w` / `-s` (for `garth open` and `garth up`)

### Fixed

- Empty `forward` array expansion crash under `set -u` in `cmd_up`, `cmd_new`,
  and `cmd_open` launch paths
- Pre-existing ShellCheck warnings (SC2221, SC2259, SC2034, SC1090, SC2088)
- `cli_open_smoke` test failure on CI due to missing config in XDG fallback path
- Session ID lookup now prefers exact matches before prefix matches, preventing
  false ambiguity for `garth stop`, `garth down`, and `garth containers`

### Changed

- CI now runs `make check` as single source of truth (no duplicated steps)
- `garth open` positional syntax now treats the first argument as session ID;
  directory-based branch open is now explicit via `-d/--dir`

## [0.1.0] - 2026-03-04

### Added

- Homebrew tap and curl installer distribution
- `--version` flag and version display in usage header
- XDG config path fallback for non-clone installs
- Release workflow (GitHub Actions, triggered on VERSION change to main)
- CHANGELOG.md

[0.2.1]: https://github.com/ealt/garth/releases/tag/v0.2.1
[0.1.1]: https://github.com/ealt/garth/releases/tag/v0.1.1
[0.1.0]: https://github.com/ealt/garth/releases/tag/v0.1.0
