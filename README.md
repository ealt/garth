# garth

[![CI](https://github.com/ealt/garth/actions/workflows/ci.yml/badge.svg)](https://github.com/ealt/garth/actions/workflows/ci.yml) [![Dependabot Updates](https://github.com/ealt/garth/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/ealt/garth/actions/workflows/dependabot/dependabot-updates)

> One command to launch a full dev environment per task. MIT licensed.

![Garth Logo](logo.png)

`garth` is a workspace orchestrator for autonomous coding agents. One command
gives you a git branch, worktree, Docker-sandboxed agents, and a Zellij terminal
session — all wired together and ready to go. Run multiple tasks across multiple
repos with multiple agents in parallel, each in its own isolated workspace.

```bash
garth new . feature/auth           # branch + worktree + containers + session
garth new ../other-repo fix/bug    # same thing, different repo
garth open -d . feature/auth       # open an existing branch
garth open a1b2c3                  # resume a session by ID
garth refresh-images               # rebuild configured Docker images
garth ps                           # see everything running
```

## Name

**garth** comes from Old Norse *garðr* ("enclosure"), the root of *garden*,
*yard*, and *guard*. A garth is the protected courtyard within walls: an
enclosed workspace where controlled work happens.

In monastic architecture, the garth was the cloister garden: a calm, ordered
space surrounded by the structure that protects it.

## Why garth

**Organization.** Working on three features across two repos with Claude and
Codex means juggling branches, worktrees, terminal sessions, containers, editor
windows, and browser tabs. `garth` treats all of that as a single operation:
pick a task, get a workspace — complete with Cursor pointed at the worktree,
a Chrome window open to the GitHub repo, and agents ready in their panes.
Resume it later, or tear it down. `garth ps` shows everything at a glance.

**Sandboxing unlocks autonomy.** Agents are most productive when they can run
without constantly blocking on permission prompts. But running them with full
access to your machine — SSH keys, cloud credentials, Docker socket — means
you can't safely let them operate unattended. `garth` resolves this tension:
robust container isolation lets you grant agents permissive execution within
strict boundaries. Each agent gets only:

- a mounted worktree
- a short-lived GitHub App token
- an agent API key

No home directory, no SSH agent, no Docker socket. That's what makes it safe
to kick off several long-running agents and walk away.

**Convenience.** One command handles what would otherwise be a sequence of git
branch, git worktree, docker run, zellij, credential plumbing, and editor/browser
setup. Token rotation, image builds, and session state are managed automatically.

## Installation

### Homebrew (macOS)

```bash
brew install ealt/tap/garth
garth setup
```

If `garth` is not found in the same terminal right after `brew install`, start
a new shell or refresh the shell command cache with `rehash` (zsh) or
`hash -r` (bash), then run `garth setup`.

If a new shell still cannot find `garth`, make sure Homebrew is initializing
your PATH in your shell startup files:

- Apple Silicon:
  `echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile`
- Intel macOS:
  `echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile`

You can always run setup directly from Homebrew's stable launcher with
`"$(brew --prefix)"/bin/garth setup`.

### Curl installer (macOS / Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/ealt/garth/main/install.sh | bash
garth setup
```

### From source

```bash
git clone https://github.com/ealt/garth.git && cd garth
./setup.sh --yes
```

## Quick Start

```bash
garth new . feature/my-feature     # new branch + worktree + session
garth open -d .                    # open default branch
garth up .                         # interactive launcher
```

## Features

### Workspace lifecycle
- One command to create a branch, worktree, containers, and terminal session
- Launches Cursor pointed at the worktree, Chrome open to the PR page, branch
  tree, or repo (context-aware)
- Resume or reattach to existing workspaces without recreating anything
- Interactive wizard or fully explicit flags — your choice
- Git worktree workflow for parallel branch/task execution

### Agent sandboxing
- Isolated Docker runtime with strict hardening defaults (`--cap-drop=ALL`,
  `--read-only`, custom seccomp, PID limits)
- Agent panes are containerized while shell panes stay local
- Cursor workspace terminal bridges into the sandbox automatically
- Config-driven safety defaults (`safe` vs `permissive`) and retry policy

### Auth and credentials
- GitHub App auth with token rotation from 1Password-managed secrets
- Short-lived tokens — no long-lived credentials in containers

### Session management
- Zellij session layout with one tab per agent (agent left, shell right)
- `garth ps` for a dashboard of all sessions, branches, and status
- Stop, resume, or tear down sessions and their resources independently
- AeroSpace workspace integration for per-project screen real estate

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

## OS Support

`garth`'s core workflow is cross-platform at the host level and is exercised in
CI on Ubuntu: git/worktree management, config parsing, token handling, Docker
container orchestration, and Zellij session generation all run outside the
macOS-only GUI helpers.

- Works on macOS and Linux for core orchestration:
  `garth new`, `garth open`, `garth up`, `garth ps`, session state management,
  Docker sandboxing, token refresh, and Zellij layout/session startup.
- macOS-only integrations:
  Cursor auto-launch, Chrome profile/window launch, AeroSpace workspace
  placement, and the `launchctl` GUI PATH/Python setup.
- Linux behavior:
  unsupported GUI integrations are skipped with warnings, and Zellij falls back
  to launching in the current shell instead of using macOS terminal-app
  launchers.
- Config note:
  the default `chrome.profiles_dir` in `config.example.toml` uses a macOS
  path. That setting only matters if you enable Chrome launching on macOS.

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
- optionally installs/updates a managed weekly cron job to rebuild default
  agent images with `--pull --no-cache`
- validates agent binaries in Docker images at launch and rebuilds if needed

For automation/non-interactive runs:

```bash
./setup.sh --yes
```

In `--yes` mode, setup attempts `op signin` automatically if the 1Password CLI
session is missing.
On macOS with Homebrew available, it also auto-installs Homebrew Python when
`python3` resolves to `/usr/bin/python3`.
When `crontab` is available, it also auto-installs/updates the managed weekly
image-refresh cron job.

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
- optionally install/update a managed weekly cron job that rebuilds configured
  default agent images (`--pull --no-cache`)

Cron note:

- default schedule is `15 3 * * 0` (weekly Sunday 03:15 local time)
- override schedule with `GARTH_IMAGE_REFRESH_CRON_SCHEDULE`, for example:
  `GARTH_IMAGE_REFRESH_CRON_SCHEDULE="0 2 * * 1-5" garth setup`

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
  workspace target, safety mode, terminal launcher mode,
  optional `auth_passthrough`
- `[token_refresh]`: lead time, retry window (`0m..forever`), backoff behavior, optional background GitHub App secret caching
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

Terminal launcher note:

- set `defaults.terminal_launcher = "current_shell"` to disable macOS app
  launching (`Ghostty`/`Terminal`) for zellij attach/start and run in your
  current shell instead
- valid values: `auto`, `current_shell`, `ghostty`, `ghostty_app`, `terminal`

Zellij mouse note:

- `--no-alt-screen` on an agent like Codex does not affect zellij itself
- `defaults.zellij_mouse_mode = "disabled"` forwards wheel scrolling to the
  host terminal and is the default in `config.example.toml`
- set `defaults.zellij_mouse_mode = "enabled"` if you prefer zellij mouse
  pane handling instead

Feature notes:

- set `features.packages` to install optional tools in image builds
  (generic apt package names, plus special support for `uv` and `bun`)
- set `features.mounts` to add optional host mounts (files or directories)
- string mount entries default to read-only and mount at the same absolute path
- table mount entries support explicit `host_path`, optional `container_path`,
  and optional `mode` (`ro|rw`)
- mounting toolchain can help when command/rule files in `~/.claude`/`~/.codex`
  are symlinks into your toolchain repo

Token refresh note:

- set `token_refresh.cache_github_app_secrets = true` (opt-in) to read GitHub
  App secrets once when the background refresher starts and reuse them for later
  token mints, avoiding repeated 1Password prompts during the day
- set `token_refresh.background_auto_signin = false` (opt-in) to prevent
  background refresh from auto-running `op signin`; this avoids popup
  interruptions but can leave sessions degraded until you re-auth manually
- security tradeoff: this keeps GitHub App secret material resident in the
  refresher process for the lifetime of that session

## Usage

### Start a new feature

```bash
garth new . feature/auth                    # branch from default branch
garth new . hotfix-login --base release/2.1 # branch from a specific ref
```

Creates a new branch, worktree, Docker containers, and Zellij session — all
derived from the branch name.

### Open an existing branch

```bash
garth open -d .                             # open the repo's default branch
garth open -d . feature/auth                # open an existing feature branch
garth open a1b2c3                           # resume an existing session by ID
```

Reuses existing worktrees and sessions when available. If a live session exists
for the branch, reattaches to it automatically.

### Interactive launcher

```bash
garth up .                                  # full interactive wizard
garth up . --auto                           # non-interactive, all defaults
garth up . --branch feature/auth            # skip branch step, wizard for rest
```

When run with no flags, presents a step-by-step wizard to select a branch,
worktree, and session. Each step has smart defaults (hit Enter to accept).
Typing a non-number at the branch step creates a new branch with that name.

### List sessions

```bash
garth ps                                    # full table with status
garth ps -q                                 # session IDs only (for piping)
```

### Stop and remove sessions

```bash
garth stop a1b2c3                           # stop session (preserves worktree)
garth stop a1b2c3 --clean                   # stop + remove session state
garth down a1b2c3                           # remove session + all resources
garth down a1b2c3 -y                        # remove without confirmation
garth ps -q | xargs garth stop              # stop all sessions
```

`garth stop` halts a session's Zellij session and Docker containers but
preserves the worktree and session state so it can be resumed later with
`garth open`. Use `--clean` to also remove the session state directory
(lighter than `garth down` — keeps worktrees). `garth down` removes
everything including managed worktrees (warns before deleting if there are
uncommitted changes).

### Garbage collection

```bash
garth gc                                    # clean stopped sessions + orphans
garth gc --dry-run                          # preview what would be cleaned
garth gc --repos ~/Documents               # also sweep branches across repos
```

`garth gc` performs a non-interactive sweep that removes:

- stopped session state directories
- orphan Zellij sessions (`garth-*` with no matching state)
- orphan Docker containers (labeled `garth.session` with no matching state)
- local git branches whose upstream has been deleted (`[gone]`)

Without `--repos`, only the current repo's branches are checked. With
`--repos <dir>`, every git repo under `<dir>` is fetched and pruned.
The flag is repeatable for multiple parent directories.

### Pipe container IDs to Docker

```bash
garth containers a1b2c3 | xargs docker logs
garth containers a1b | xargs docker stats
```

### Refresh Docker images

```bash
garth refresh-images                           # rebuild defaults.agents
garth refresh-images --agents claude,codex     # rebuild specific agents
garth refresh-images --agents claude --dry-run # preview docker build command
```

`garth refresh-images` rebuilds selected agent images with
`docker build --pull --no-cache` and preserves configured `features.packages`.

### Common options

These flags apply to `new`, `open`, and `up`:

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
- `garth agent` auto-detects local `claude`/`codex` CLI auth state and
  auto-enables passthrough for those agents in Docker mode
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

### Run agent(s) directly

```bash
garth agent . --sandbox docker                 # use defaults.agents
garth agent . codex --sandbox docker           # single agent override
garth agent . --agents claude,codex --sandbox docker
```

### Mint a token

```bash
garth token .
```

`garth` caches recently minted GitHub installation tokens in
`$XDG_STATE_HOME/garth/token-cache` (permissions `0700/0600`) and reuses them
until they are near expiry. This avoids unnecessary 1Password prompts.

### Diagnostics

```bash
garth doctor --repo .
garth doctor --repo . --deep
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

For detailed security architecture, controls, and tradeoff guidance, see
[`docs/security-model.md`](docs/security-model.md). For module-level
implementation details, see [`AGENTS.md`](AGENTS.md#security-model).

## Platform Notes

- macOS: full launch flow, including GUI integrations
- Linux: core orchestration path is supported; macOS-only GUI integrations are
  skipped with warnings

## Troubleshooting

- `Auth/config check`: run `garth doctor --repo .`
- `Runtime auth/startup probe`: run `garth doctor --repo . --deep`
- `Config not found`: run `garth setup`
- `1Password CLI is not signed in`: run `eval "$(op signin)"`
- `1Password sign-in keeps getting requested`: ensure you are running `garth`
  interactively (TTY attached) so auto sign-in can prompt, and verify `op whoami`
  succeeds in the same shell
- `garth keeps prompting for 1Password`: check token cache reuse with
  `garth token . --machine`; if the token is near expiry, a fresh `op` auth is
  expected
- `I only want to authenticate once per workspace`: opt into
  `token_refresh.cache_github_app_secrets = true` in `config.toml`
- `I never want background auth popups`: set
  `token_refresh.background_auto_signin = false` in `config.toml`
- `Ghostty would like to access data from other apps`: set
  `defaults.terminal_launcher = "current_shell"` to avoid macOS app-launch
  permission prompts from Ghostty/Terminal automation
- `Mouse wheel still does not scroll in zellij`: `--no-alt-screen` only
  affects the agent process, not zellij. Reattach with `garth open <id>` so
  garth applies `--disable-mouse-mode`, or set
  `defaults.zellij_mouse_mode = "enabled"` if you explicitly want zellij to
  keep consuming mouse events
- `Can't connect to AeroSpace server`: start app with `open -a AeroSpace`
- `"isn't a vault in this account"`: update `op://...` refs in
  `config.toml` to your actual vault/item/field names
- `Claude native installer mismatch`: if you see messages like
  `installMethod is native` or `Native installation exists but ...`, rebuild
  `garth-claude:latest` (for example `garth refresh-images --agents claude`)
- `bash: line 1: claude: command not found`: rebuild `garth-claude:latest`
  from the `garth` repo (`garth refresh-images --agents claude` is simplest)
- `Unsupported remote URL`: ensure repo uses a GitHub remote URL
- `Session already exists`: run `garth stop <id>` first (find the ID with
  `garth ps`)
- `garth: command not found` right after `brew install`: open a new shell or
  run `rehash` (zsh) / `hash -r` (bash). If that still fails in a fresh shell,
  add Homebrew to login PATH with `eval "$(/opt/homebrew/bin/brew shellenv)"`
  on Apple Silicon or `eval "$(/usr/local/bin/brew shellenv)"` on Intel macOS.
  As a fallback, run `$(brew --prefix)/bin/garth setup` directly.
- `macOS asks to install Developer Tools for python3`: ensure
  `/opt/homebrew/bin/python3` exists (`brew install python`); `garth` prefers
  that interpreter at runtime. On macOS, `garth` also updates GUI app PATH
  via `launchctl setenv PATH ...`; it also creates a `python` shim at
  `~/.local/state/garth/gui-bin/python` for tools that invoke `python` (not
  `python3`). Fully quit/reopen Cursor after launching a session so the new
  environment is picked up.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for development setup, testing patterns,
and the PR workflow.
