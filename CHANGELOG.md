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
- New smoke test coverage for Docker refresh command behavior
  (`tests/refresh_images_smoke.sh`)
- `features.packages` support for `bun` via upstream installer script, including
  image validation checks for the `bun` binary
- `garth open <id>` support to resume sessions directly by ID/prefix
- Short flag aliases for branch/worktree/session selectors:
  `-b` / `-w` / `-s` (for `garth open` and `garth up`)
- `garth agent` now supports launching from non-git directories (skips GitHub
  token minting when no repository metadata is available)
- `garth agent` now uses `defaults.agents` when no agent is provided and can
  launch multi-agent adhoc sessions (or use `--agents`)
- `garth agent` now auto-detects local Claude/Codex CLI auth state and
  auto-enables Docker auth passthrough to avoid unnecessary API key fallback
- `garth gc` command for non-interactive cleanup of stopped session state dirs,
  orphan Zellij sessions, orphan Docker containers, and local git branches
  whose upstream has been deleted (`[gone]`); supports `--repos <dir>` to sweep
  branches across all git repos under a parent directory
- `garth stop --clean` flag to remove session state after stopping, preventing
  stale state accumulation without requiring a full `garth down`
- `garth doctor` now warns when `claude_share` auth mount mode is set to `rw`

### Fixed

- Empty `forward` array expansion crash under `set -u` in `cmd_up`, `cmd_new`,
  and `cmd_open` launch paths
- Pre-existing ShellCheck warnings (SC2221, SC2259, SC2034, SC1090, SC2088)
- `cli_open_smoke` test failure on CI due to missing config in XDG fallback path
- Session ID lookup now prefers exact matches before prefix matches, preventing
  false ambiguity for `garth stop`, `garth down`, and `garth containers`
- `garth ps` now reports the correct repository name for worktree-backed
  sessions instead of showing the worktree directory name

### Changed

- CI now runs `make check` as single source of truth (no duplicated steps)
- `garth open` positional syntax now treats the first argument as session ID;
  directory-based branch open is now explicit via `-d/--dir`
- Documentation now includes Docker refresh command usage and troubleshooting
  guidance

### Security

- Default auth mount mode for `claude_share` changed from `rw` to `ro` to
  prevent container auto-updaters from overwriting host binaries with
  wrong-platform builds
  ([#29661](https://github.com/anthropics/claude-code/issues/29661))
- `claude_dot_claude`, `claude_config`, `claude_state`, and `claude_cache`
  remain `rw` (Claude writes auth/config data there; `ro` causes `EROFS`)

## [0.1.0] - 2026-03-04

### Added

- Homebrew tap and curl installer distribution
- `--version` flag and version display in usage header
- XDG config path fallback for non-clone installs
- Release workflow (GitHub Actions, triggered on VERSION change to main)
- CHANGELOG.md

[0.2.1]: https://github.com/ealt/garth/releases/tag/v0.2.1
[0.2.0]: https://github.com/ealt/garth/releases/tag/v0.2.0
[0.1.1]: https://github.com/ealt/garth/releases/tag/v0.1.1
[0.1.0]: https://github.com/ealt/garth/releases/tag/v0.1.0
