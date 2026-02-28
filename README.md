# garth

> Walled workspaces for autonomous agents.

`garth` is a secure multi-project workspace orchestrator for autonomous coding
agents.

It launches a Zellij-based project session, runs agents in Docker (or host mode
when explicitly requested), mints short-lived GitHub App installation tokens
through 1Password, and keeps Git auth refreshed without restarting containers.

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
- In docker mode, the main zellij shell pane is also containerized
- In docker mode, Cursor workspace terminal defaults to a garth sandbox bridge
- GitHub App auth with token rotation from 1Password-managed secrets
- Zellij session layout with one shell pane plus one pane per agent
- Git worktree workflow for parallel branch/task execution
- Best-effort GUI launch helpers (Cursor, Chrome profile, AeroSpace)
- Config-driven safety defaults (`safe` vs `permissive`) and retry policy

## Layout

```text
garth/
  bin/garth
  lib/
  docker/Dockerfile
  config.example.toml
  config.toml
  templates/aerospace.example.toml
```

## Prerequisites

Required:

- `git`
- `python3`
- `op` (1Password CLI, signed in)
- `zellij`
- `docker` (for sandbox mode)

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
- `[features]`: optional runtime/build features (for example Neovim support)
- `[agents.<name>]`: command + safe/permissive args + API key ref

Validation is strict for known fields and warning-only for unknown fields.

Chrome note:

- set `chrome.profiles_dir = ""` to open URLs in your default signed-in profile
- set `chrome.profile_directory` (for example `"Default"`) to pin a specific
  Chrome profile when opening a new window

Neovim note:

- set `features.install_neovim = true` to include `nvim` in rebuilt Docker images
- set `features.mount_neovim_config = true` to mount `~/.config/nvim` into
  containers as read-only

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

### Session control

```bash
garth doctor --repo .
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
  - `--pids-limit=512`
  - `--read-only`
  - tmpfs mounts for writable transient paths

## Platform Notes

- macOS: full launch flow (Cursor/Chrome/AeroSpace)
- non-macOS: core orchestration still runs; unsupported GUI steps are skipped
  with warnings

## Troubleshooting

- `Auth/config check`: run `garth doctor --repo .`
- `Config not found`: run `garth setup`
- `1Password CLI is not signed in`: run `op signin`
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
