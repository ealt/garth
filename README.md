# garth

[![CI](https://github.com/ealt/garth/actions/workflows/ci.yml/badge.svg)](https://github.com/ealt/garth/actions/workflows/ci.yml)

[![Dependabot Updates](https://github.com/ealt/garth/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/ealt/garth/actions/workflows/dependabot/dependabot-updates)

> Walled workspaces for autonomous agents. MIT licensed.

`garth` is a secure multi-project workspace orchestrator for autonomous coding
agents.

It launches a Zellij-based project session, runs agents in Docker (or host mode
when explicitly requested), mints short-lived GitHub App installation tokens
through 1Password, and keeps Git auth refreshed without restarting containers.

## Quick Start

```bash
git clone <repo-url> && cd garth
./setup.sh --yes
garth boot .
```

## Why garth

Running AI coding agents with your full shell environment means they inherit
everything on your machine: SSH keys, GitHub CLI auth, cloud credentials, and
local secrets. `garth` limits blast radius by giving each agent only what it
needs:

- a mounted worktree
- a short-lived GitHub App token
- an agent API key

By default, agents do not get your home directory, SSH agent, or Docker socket.

## Features

- Isolated agent runtime (`docker`) with strict hardening defaults
- In docker mode, agent panes are containerized while shell panes stay local
- In docker mode, Cursor workspace terminal defaults to a garth sandbox bridge
- GitHub App auth with token rotation from 1Password-managed secrets
- Zellij session layout with one tab per agent (agent left, shell right)
- Git worktree workflow for parallel branch/task execution
- Best-effort GUI launch helpers (Cursor, Chrome profile, AeroSpace)
- Config-driven safety defaults (`safe` vs `permissive`) and retry policy

## Layout

```text
garth/
  bin/garth                          # CLI entrypoint
  lib/                               # Shell and Python modules
  docker/                            # Dockerfile + seccomp profile
  tests/                             # Smoke test scripts
  docs/                              # Setup guides
  templates/                         # Config templates (AeroSpace)
  config.example.toml                # Baseline config
  config.toml                        # Local config (gitignored)
```

## Prerequisites

Required:

- `git`
- `python3` (on macOS, prefer Homebrew Python over `/usr/bin/python3`)
- `op` (1Password CLI, signed in)
- `zellij`
- `docker` (for sandbox mode)

macOS Python note:

- if `python3` resolves to `/usr/bin/python3`, macOS may prompt for Command
  Line Tools updates
- `garth`/`setup.sh` auto-prepend `/opt/homebrew/bin` when available, so once
  Homebrew Python is installed you do not need a shell restart for garth usage
- recommended:
  `brew install python && echo 'export PATH="/opt/homebrew/bin:$PATH"' >> ~/.zshrc`

Optional:

- `Cursor` (macOS app launcher)
- `Google Chrome` (profile-per-project launcher)
- `aerospace` (workspace movement)

## Setup

```bash
./setup.sh
```

This repo bootstrap script:

- runs `bin/garth setup` (interactive by default)
- creates `./config.toml` from `config.example.toml` (if missing)
- validates repo-local config and installs `garth` in `~/.local/bin`
- on macOS, if `python3` is `/usr/bin/python3`, offers to install Homebrew
  Python (auto in `--yes` when Homebrew is installed)
- on macOS, offers to install `aerospace` via Homebrew (auto in `--yes`)
- skips GitHub App ref prompts when already done
- auto-builds missing default Docker images when Docker is available
- validates agent binaries in Docker images at boot and rebuilds if needed

For automation/non-interactive runs:

```bash
./setup.sh --yes
```

In `--yes` mode, setup attempts `op signin` automatically if the 1Password CLI
session is missing.
On macOS with Homebrew available, it also auto-installs Homebrew Python when
`python3` resolves to `/usr/bin/python3`.

Debug launch toggles (env vars):

- `GARTH_SKIP_GUI=true`: skip workspace move + Cursor + Chrome launch
- `GARTH_SKIP_CURSOR=true`: skip Cursor setup/launch only
- `GARTH_SKIP_CHROME=true`: skip Chrome launch only
- `GARTH_SKIP_GUI_PATH_SET=true`: skip macOS GUI PATH update (`launchctl setenv PATH ...`)
- `GARTH_TRACE_PYTHON=true`: log which Python runtime garth is using

If you prefer interactive setup prompts:

```bash
garth setup
```

This will:

- create `config.toml` (repo root) from `config.example.toml`
- optionally switch safety default to `permissive`
- optionally guide you through setting `[github_app]` 1Password refs
- validate config
- symlink `garth` into `~/.local/bin/garth`
- build missing default Docker images (`garth-claude`, `garth-codex`) when possible

## GitHub App Setup

The example config uses placeholder `op://...` refs. You must replace them with
real refs from your vault.

See the dedicated setup guide:

- [`docs/github-app-setup.md`](docs/github-app-setup.md)

## Config

Default config file:

`./config.toml` (repo root, gitignored)

Key sections:

- `[defaults]`: selected agents, sandbox mode, network mode,
  workspace target, safety mode,
  optional `auth_passthrough`
- `[token_refresh]`: lead time, retry window (`0m..forever`), backoff behavior
- `[github_app]`: 1Password refs and installation selection strategy
- `[chrome]`: `profiles_dir` and optional `profile_directory` for Chrome launches
- `[features]`: optional packages and host mounts for agent images
- `[security]`: protected read-only worktree paths, seccomp profile path, and auth passthrough mount modes (`ro|rw`)
- `[agents.<name>]`: command + safe/permissive args + API key ref

Validation is strict for known fields and warning-only for unknown fields.

Chrome note:

- set `chrome.profiles_dir = ""` to open URLs in your default signed-in profile
- set `chrome.profile_directory` (for example `"Default"`) to pin a specific
  Chrome profile when opening a new window

Feature notes:

- set `features.packages` to install optional tools in image builds
  (generic apt package names, plus special support for `uv`)
- set `features.mounts` to add optional host mounts (files or directories)
- string mount entries default to read-only and mount at the same absolute path
- table mount entries support explicit `host_path`, optional `container_path`,
  and optional `mode` (`ro|rw`)
- mounting toolchain can help when command/rule files in `~/.claude`/`~/.codex`
  are symlinks into your toolchain repo

## Usage

### Boot a workspace

```bash
garth boot .
```

Common options:

- `--agents claude,codex`
- `--auth-passthrough claude,codex`
- `--sandbox docker|none`
- `--network bridge|none`
- `--safety safe|permissive`
- `--workspace 3|auto`

Workspace note:

- when `defaults.workspace = "auto"` (default), `garth` uses the next numeric
  AeroSpace workspace (`max + 1`)

Auth note:

- `--sandbox docker`: agent API keys are required unless the agent is listed in
  `defaults.auth_passthrough` (or passed via `--auth-passthrough`)
- `--sandbox none`: local CLI login auth is supported (for example
  `claude auth login`, `codex login`)
- when `claude` is in auth passthrough, `garth` mounts Claude auth/state paths
  (`~/.claude`, `~/.config/claude`, `~/.local/state/claude`,
  `~/.local/share/claude`, `~/.cache/claude`) so login state persists across
  container restarts (mount mode is configurable via `[security.auth_mount_mode]`)
- `~/.claude.json` is not mounted at `/home/agent/.claude.json`; instead it is
  mounted read-only to a side path and used as a startup seed, then `garth`
  merges/restores OAuth state from Claude backups as needed
- container cache root (`/home/agent/.cache`) is writable tmpfs so tools like
  `uv` can create caches even with `--read-only`
- on interactive terminals, when a secret read requires 1Password auth,
  `garth` auto-attempts `eval "$(op signin)"` and retries

### Create and boot a worktree

```bash
garth worktree . feature/new-flow --from origin/main
```

### Run one agent directly

```bash
garth agent . codex --sandbox docker
```

### Mint a token

```bash
garth token .
```

`garth` caches recently minted GitHub installation tokens in
`$XDG_STATE_HOME/garth/token-cache` (permissions `0700/0600`) and reuses them
until they are near expiry. This avoids unnecessary 1Password prompts on every
`boot`.

### Session control

```bash
garth doctor --repo .
garth doctor --repo . --deep
garth status
garth status --json
garth stop garth-myrepo-feature__x
garth stop --repo .
garth stop --all --yes
```

## Security Model

- Secrets are not passed in process args or layout files.
- Agent API keys go through short-lived `0600` env files.
- GitHub token is mounted as a file (`/run/garth/github_token`) and rotated
  atomically.
- Repository mount path inside containers is `/<repo-name>-sandbox` (for
  example `/simplexity-sandbox`).
- Container defaults:
  - `--cap-drop=ALL`
  - `--security-opt no-new-privileges:true`
  - `--security-opt seccomp=<repo>/docker/seccomp-profile.json` (custom profile)
  - `--pids-limit=512`
  - `--read-only`
  - tmpfs mounts for writable transient paths
  - read-only overlays for sensitive repo paths (`.git/hooks`, `.git/config`, `.github`, `.gitmodules`)
- Session events are written to `$XDG_STATE_HOME/garth/sessions/<session>/audit.log` (JSONL, `0600`) with secret redaction.

For implementation details (module-level security functions, seccomp profile
usage, auth mount modes), see [`AGENTS.md`](AGENTS.md#security-model).

## Platform Notes

- macOS: full launch flow (Cursor/Chrome/AeroSpace)
- non-macOS: core orchestration still runs; unsupported GUI steps are skipped
  with warnings

## Troubleshooting

- `Auth/config check`: run `garth doctor --repo .`
- `Runtime auth/startup probe`: run `garth doctor --repo . --deep`
- `Config not found`: run `garth setup`
- `1Password CLI is not signed in`: run `eval "$(op signin)"`
- `1Password sign-in keeps getting requested`: ensure you are running `garth`
  interactively (TTY attached) so auto sign-in can prompt, and verify `op whoami`
  succeeds in the same shell
- `garth boot keeps prompting for 1Password`: check token cache reuse with
  `garth token . --machine`; if the token is near expiry, a fresh `op` auth is
  expected
- `Can't connect to AeroSpace server`: start app with `open -a AeroSpace`
- `"isn't a vault in this account"`: update `op://...` refs in
  `config.toml` to your actual vault/item/field names
- `Claude native installer mismatch`: if you see messages like
  `installMethod is native` or `Native installation exists but ...`, rebuild
  `garth-claude:latest` (for example `garth setup` or `docker build --target claude -t garth-claude:latest docker`)
- `bash: line 1: claude: command not found`: rebuild `garth-claude:latest`
  from the `garth` repo (`garth setup` is simplest)
- `Unsupported remote URL`: ensure repo uses a GitHub remote URL
- `Session already exists`: run `garth stop <session>` first
- `macOS asks to install Developer Tools for python3`: ensure
  `/opt/homebrew/bin/python3` exists (`brew install python`); `garth` prefers
  that interpreter at runtime. On macOS, `garth boot` also updates GUI app PATH
  via `launchctl setenv PATH ...`; it also creates a `python` shim at
  `~/.local/state/garth/gui-bin/python` for tools that invoke `python` (not
  `python3`). Fully quit/reopen Cursor after boot so the new environment is
  picked up.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for development setup, testing patterns,
and the PR workflow.

## Branding

### Name

**garth** comes from Old Norse *garðr* ("enclosure"), the root of *garden*,
*yard*, and *guard*. A garth is the protected courtyard within walls: an
enclosed workspace where controlled work happens.

In monastic architecture, the garth was the cloister garden: a calm, ordered
space surrounded by the structure that protects it.

### Short Description

A CLI that boots secure, Docker-sandboxed workspaces for AI coding agents with
scoped credentials, git worktrees, and a full dev environment in one command.

### Naming Process

Source territory: **The controlled environment where work happens**, drawn from
architecture, metallurgy, and nautical compartmentalization.

Candidates considered and rejected:

| Name | Why rejected |
| ---- | ------------ |
| hearth | Strong but less distinctive; common fireplace association |
| bosh | Cloud Foundry BOSH conflict (major DevOps tool, Homebrew formula) |
| keep | keephq conflict (11k GitHub stars, acquired by Elastic) |
| crucible | Atlassian Crucible conflict (long-standing brand) |
| bailey | Clean availability but less resonant than `garth` |
| kiln | Clean but lacked the enclosure/protection dimension |
| motte | Clean but the metaphor was indirect |
| cope | Clean but the casting-mold metaphor was too niche |

### Availability

| Registry | Status |
| -------- | ------ |
| Homebrew | Available |
| npm | Available |
| PyPI | Taken (Garmin SSO library; not a conflict for this bash CLI) |
| Crates.io | Available |
| "garth cli" on Google | Clean |
