# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-03-30

### Added

- `--no-fetch` for `garth new` and `garth up --new-branch` to keep the local
  default branch as-is when creating a new branch
- New `tests/cli_new_smoke.sh` coverage for `cmd_new` / `cmd_up --new-branch`
  base-selection behavior

### Changed

- `garth new` now fetches `origin` before branching from the implicit default
  base and prefers the updated remote-tracking default branch when available

## [1.0.1] - 2026-03-24

### Fixed

- Chromium default-profile case-insensitive app name comparison now uses
  `tr` instead of Bash 4+ `${var,,}` syntax, fixing launch failures on
  macOS (which ships Bash 3.2)

## [1.0.0] - 2026-03-24

### Added

- Generic browser configuration via `[browser]` with `chromium`, `firefox`,
  `open`, and `none` engines
- Dedicated browser launcher smoke coverage in `tests/browser_launch_smoke.sh`
- README browser migration guidance and common config examples for Chrome,
  Brave, Firefox, Safari, and Arc-style setups

### Changed

- Browser launch config now uses `[browser]` instead of `[chrome]`
- Browser launch env emission now uses `GARTH_BROWSER_*` instead of
  `GARTH_CHROME_*`
- Workspace launch docs and references now describe browser launch behavior
  generically instead of assuming Chrome-only integration
- Existing configs that still set `defaults.workspace` now emit
  `warning: Unknown key: defaults.workspace`; delete that key after upgrading

### Removed

- `[chrome]` config support and the dead `profile_directory` field
- `garth_launch_chrome_profile()` in favor of engine-based browser dispatch
- AeroSpace integration has been removed entirely, including the
  `--workspace` CLI flag, automatic workspace movement during launch, setup and
  doctor references, and the `templates/aerospace.example.toml` template
- `defaults.workspace` is no longer part of the config schema and
  `GARTH_DEFAULTS_WORKSPACE` is no longer emitted by the config parser

### Fixed

- `garth new`, `garth open`, and `garth up` now fail fast on deprecated
  `GARTH_SKIP_CHROME` and `GARTH_CHROME_PROFILES_DIR` env vars instead of
  silently ignoring them
- macOS Chrome default-profile launch now treats `app = "google chrome"` the
  same as `app = "Google Chrome"` when deciding whether to use the AppleScript
  new-window path

## [0.3.4] - 2026-03-19

### Added

- `GITHUB_TOKEN` is now exported inside Docker containers via
  `/etc/profile.d/garth-gh-token.sh`, so `gh` CLI and other tools that read the
  env var can authenticate (previously only `git` worked via the credential
  helper)
- `garth doctor --deep` verifies `GITHUB_TOKEN` is exported in Docker containers
  and flags stale images missing the profile.d script
- `garth doctor` warns when `TMPDIR` is long enough that zellij session names
  risk exceeding the macOS 104-byte Unix socket path limit
- `garth_zellij_validate_session_name` checks socket path length before launch
  and prints a clear error instead of letting zellij hang silently

### Fixed

- Session names now dynamically compute their max length from the actual
  `TMPDIR` path, reserving room for the zellij socket prefix and conflict-
  avoidance suffix (`-NN`).  Previously the 36-char cap was sufficient for the
  session name alone but the `-2`, `-3`, ... `-15` suffix from
  `garth_unique_session_name` could push the full socket path past macOS's
  104-byte `sun_path` limit, causing zellij to hang silently.
- Ghostty terminal launcher on macOS now skips the CLI binary path (which
  cannot launch terminal windows on macOS per Ghostty docs) and goes directly
  to the `open -na Ghostty.app` app launcher.  The `ghostty` and `auto`
  launcher modes now fall through to the app launcher instead of falling back
  to `current_shell` when the CLI path fails.
- Docker images must be rebuilt (`garth refresh-images`) to pick up the
  `GITHUB_TOKEN` profile.d script

## [0.3.3] - 2026-03-19

### Fixed

- `agents.<name>.api_key_ref` may now be set to `""` in config for setups that
  rely on local Claude/Codex CLI login auth instead of API keys
- Config examples and README auth guidance now document empty `api_key_ref`
  values as the supported way to skip placeholder secret refs when using auth
  passthrough or `--sandbox none`

## [0.3.2] - 2026-03-17

### Added

- `defaults.zellij_mouse_mode` config (`disabled` or `enabled`) to control
  whether Garth asks Zellij to consume mouse events

### Fixed

- Zellij launches now disable mouse mode by default so mouse wheel scrolling
  reaches the host terminal scrollback again; this fixes the case where
  agent-level `--no-alt-screen` was set but Zellij still intercepted scroll
  events

## [0.3.1] - 2026-03-10

### Fixed

- `op signin` now works in non-TTY contexts (e.g. Claude Code's Bash tool) by
  using `op signin --account` to trigger system-auth through the 1Password
  daemon instead of silently no-oping
- Session names now capped at 36 characters (with hash suffix for uniqueness) to
  comply with Zellij 0.43+ session name limits via Ghostty's login wrapper
- Terminal launchers (Ghostty, Ghostty.app, Terminal.app) now strip `ZELLIJ`,
  `ZELLIJ_SESSION_NAME`, and `ZELLIJ_PANE_ID` env vars before spawning, fixing
  Zellij nesting protection blocking new sessions when garth is invoked from
  inside an existing Zellij pane

## [0.3.0] - 2026-03-10

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
- Context-aware GitHub page opening: Chrome now opens the PR page when the
  current branch has an open pull request, the branch tree view for other
  non-default branches, and the base repo URL on the default branch
- `garth gc` command for non-interactive cleanup of stopped session state dirs,
  orphan Zellij sessions, orphan Docker containers, and local git branches
  whose upstream has been deleted (`[gone]`); supports `--repos <dir>` to sweep
  branches across all git repos under a parent directory
- `garth stop --clean` flag to remove session state after stopping, preventing
  stale state accumulation without requiring a full `garth down`
- `garth doctor` now warns when `claude_share` auth mount mode is set to `rw`
- `docs/security-model.md`: a dedicated security reference covering trust
  boundaries, container hardening, credential handling, configuration controls,
  and tradeoffs
- New smoke tests for security/auth edge cases:
  `tests/token_cache_lock_smoke.sh`, `tests/github_app_override_smoke.sh`,
  `tests/zellij_launcher_smoke.sh`, and
  `tests/secrets_auto_signin_guard_smoke.sh`

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
- Added `defaults.terminal_launcher` config (`auto`, `current_shell`,
  `ghostty`, `ghostty_app`, `terminal`) to control zellij launch behavior on
  macOS and reduce host app permission prompt friction
- README now links to the dedicated security model documentation and includes
  explicit guidance for auth-refresh popup mitigation settings

### Security

- Default auth mount mode for `claude_share` changed from `rw` to `ro` to
  prevent container auto-updaters from overwriting host binaries with
  wrong-platform builds
  ([#29661](https://github.com/anthropics/claude-code/issues/29661))
- `claude_dot_claude`, `claude_config`, `claude_state`, and `claude_cache`
  remain `rw` (Claude writes auth/config data there; `ro` causes `EROFS`)
- Token minting now uses a per-repository cache lock to prevent multi-workspace
  concurrent refresh stampedes (which previously caused repeated 1Password
  prompts)
- Added `token_refresh.cache_github_app_secrets` (opt-in) to preload GitHub App
  credentials for refresher reuse and reduce mid-session secret reads
- Added `token_refresh.background_auto_signin` (opt-in, defaults `true`) to
  disable background `op signin` attempts when desired, eliminating unattended
  popup loops at the cost of possible degraded refresh state until manual
  re-auth

## [0.1.0] - 2026-03-04

### Added

- Homebrew tap and curl installer distribution
- `--version` flag and version display in usage header
- XDG config path fallback for non-clone installs
- Release workflow (GitHub Actions, triggered on VERSION change to main)
- CHANGELOG.md

[1.1.0]: https://github.com/ealt/garth/releases/tag/v1.1.0
[1.0.1]: https://github.com/ealt/garth/releases/tag/v1.0.1
[1.0.0]: https://github.com/ealt/garth/releases/tag/v1.0.0
[0.3.4]: https://github.com/ealt/garth/releases/tag/v0.3.4
[0.3.3]: https://github.com/ealt/garth/releases/tag/v0.3.3
[0.3.2]: https://github.com/ealt/garth/releases/tag/v0.3.2
[0.3.1]: https://github.com/ealt/garth/releases/tag/v0.3.1
[0.3.0]: https://github.com/ealt/garth/releases/tag/v0.3.0
[0.2.2]: https://github.com/ealt/garth/releases/tag/v0.2.2
[0.2.1]: https://github.com/ealt/garth/releases/tag/v0.2.1
[0.2.0]: https://github.com/ealt/garth/releases/tag/v0.2.0
[0.1.1]: https://github.com/ealt/garth/releases/tag/v0.1.1
[0.1.0]: https://github.com/ealt/garth/releases/tag/v0.1.0
