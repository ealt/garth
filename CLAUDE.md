# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Garth?

Garth is a secure multi-project workspace orchestrator for autonomous AI coding agents. It's a Bash-first CLI that boots isolated Docker-sandboxed workspaces, mints short-lived GitHub App tokens through 1Password, and manages Zellij terminal sessions with per-agent panes. Named from Old Norse *gardhr* ("enclosure").

## Commands

**Setup & diagnostics:**
- `./setup.sh` or `./setup.sh --yes` — bootstrap local setup
- `bin/garth doctor --repo .` — validate prerequisites
- `bin/garth doctor --repo . --deep` — deep checks including Docker probes

**Running:**
- `garth boot .` — primary workflow: mint token, generate Zellij layout, launch agents
- `garth worktree . feature/branch --from origin/main` — create worktree and boot
- `garth agent . codex --sandbox docker` — run a single agent
- `garth token .` — mint a GitHub App token
- `garth status` / `garth status --json` — show active sessions
- `garth stop <session>` / `garth stop --repo .` / `garth stop --all --yes`

**Testing (run all before PRs):**
- `bash tests/config_parser_smoke.sh`
- `bash tests/git_helpers_smoke.sh`
- `bash tests/zellij_layout_smoke.sh`

**Syntax checks:**
- `bash -n bin/garth lib/*.sh` — shell syntax check
- `python3 -m py_compile lib/config-parser.py` — Python syntax check

**Docker images:**
- `docker build --target claude -t garth-claude:latest docker/`
- Targets: `claude`, `codex`, `opencode`, `gemini`

## Architecture

**Entry point flow** (`bin/garth`): resolves symlinks to find `GARTH_ROOT`, sources all `lib/*.sh` modules (each uses include-once guards), installs cleanup trap, then dispatches to `cmd_boot`, `cmd_worktree`, `cmd_agent`, `cmd_token`, `cmd_doctor`, `cmd_status`, `cmd_stop`, `cmd_setup`, or `cmd_internal_refresh`.

**Config flow**: `config.example.toml` → user copies to `config.toml` (gitignored) → `lib/config-parser.py` validates strictly and emits `GARTH_*` env vars as shell-safe `KEY='value'` lines → `bin/garth` evals into shell environment.

**Module pattern**: Each `lib/*.sh` uses a `GARTH_*_SH_LOADED` include-once guard. Functions are `garth_`-prefixed. All modules are sourced eagerly at startup.

**Security model (layered)**:
- Docker: `--cap-drop=ALL`, `--security-opt no-new-privileges:true`, custom seccomp, `--read-only`, pids/mem/cpu limits
- Non-root `agent` user (UID 1001) inside containers
- GitHub tokens mounted as files at `/run/garth/github_token`, rotated atomically
- API keys via `0600` env files (never in process args or layout files)
- Protected read-only overlays for `.git/hooks`, `.git/config`, `.github`, `.gitmodules`

**Token refresh** (`cmd_internal_refresh`): background process spawned during boot, polls session state, re-mints before expiry with configurable lead time and exponential backoff on failure.

**Session state**: file-based under `$XDG_STATE_HOME/garth/sessions/<session>/` with individual key-value files.

## Key Conventions

- Bash: `#!/usr/bin/env bash`, `set -euo pipefail`, 2-space indent, `snake_case`, local variables
- Python: `snake_case`, stdlib-only (`tomllib` from Python 3.11+, zero external deps)
- Env vars: `GARTH_` prefix, uppercase with underscores
- Agent config keys: `GARTH_AGENT_<UPPERNAME>_<FIELD>`
- Session names: `garth-<repo>-<branch-slug>`
- Container names: `<session>-<agent>` (sanitized for Docker)
- Tests: deterministic smoke scripts, source lib modules directly, mock stubs where needed, assert with `grep -q`/`[[ ]]`, print `<name>_smoke: ok` on success
- Commits: imperative subject lines (`Add ...`, `Fix ...`, `Refactor ...`), logically scoped
- macOS-first GUI features (Cursor, Chrome, AeroSpace, Ghostty) are `garth_is_macos()` guarded

## Supported Agents

Configured in TOML, each with a Docker build target in `docker/Dockerfile`:
- **claude** — Anthropic Claude Code CLI
- **codex** — OpenAI Codex CLI
- **opencode** — OpenCode CLI
- **gemini** — Google Gemini CLI
