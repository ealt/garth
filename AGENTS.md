# Garth — Agent & Developer Reference

Garth is a secure multi-project workspace orchestrator for autonomous AI coding
agents. It boots isolated Docker-sandboxed workspaces, mints short-lived GitHub
App tokens through 1Password, and manages Zellij terminal sessions with
per-agent panes. Named from Old Norse *garðr* ("enclosure").

This file is the single source of truth for architecture, conventions, and
development workflow. See also:

- [`README.md`](README.md) — installation, config, usage, troubleshooting
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — PR workflow and development setup

## Commands

### Setup & Diagnostics

- `./setup.sh` (or `./setup.sh --yes`) — bootstrap local setup
- `bin/garth setup` — interactive setup flow
- `bin/garth doctor --repo .` — validate auth/config/runtime prerequisites
- `bin/garth doctor --repo . --deep` — deep checks including Docker probes

### Running

- `garth boot .` — primary workflow: mint token, generate Zellij layout, launch
  agents
- `garth worktree . feature/branch --from origin/main` — create worktree and
  boot
- `garth agent . codex --sandbox docker` — run a single agent
- `garth token .` — mint a GitHub App token
- `garth status` / `garth status --json` — show active sessions
- `garth stop <session>` / `garth stop --repo .` / `garth stop --all --yes`

### Testing

- `bash tests/config_parser_smoke.sh`
- `bash tests/git_helpers_smoke.sh`
- `bash tests/zellij_layout_smoke.sh`

### Syntax Checks

- `bash -n bin/garth lib/*.sh` — shell syntax check
- `python3 -m py_compile lib/config-parser.py` — Python syntax check

### Docker Images

- `docker build --target claude -t garth-claude:latest docker/`
- Targets: `claude`, `codex`, `opencode`, `gemini`

## Architecture

### Entry Point Flow

`bin/garth` (~2229 lines) is the CLI entrypoint and command router.

1. Resolves symlinks to find `GARTH_ROOT`
2. Sources all `lib/*.sh` modules (each uses include-once guards)
3. Sets `GARTH_STATE_ROOT` (`$XDG_STATE_HOME/garth`), `GARTH_CONFIG_PATH`,
   `GARTH_BIN_PATH`
4. Installs EXIT/INT/TERM cleanup trap
5. Dispatches to the appropriate `cmd_*` function:

| Command | Function | Line |
|---------|----------|------|
| `boot` | `cmd_boot` | 314 |
| `worktree` | `cmd_worktree` | 651 |
| `agent` | `cmd_agent` | 706 |
| `token` | `cmd_token` | 894 |
| `status` | `cmd_status` | 1003 |
| `stop` | `cmd_stop` | 1148 |
| `setup` | `cmd_setup` | 1510 |
| `internal-refresh` | `cmd_internal_refresh` | 1639 |
| `doctor` | `cmd_doctor` | 1772 |

### Config Flow

1. User copies `config.example.toml` → `config.toml` (gitignored)
2. `lib/config-parser.py validate <config>` checks schema strictly
3. `lib/config-parser.py env <config>` emits `GARTH_*` env vars as shell-safe
   `KEY='value'` lines
4. `bin/garth` evals the output into the shell environment

### Module Pattern

Every `lib/*.sh` module uses a three-line include-once guard:

```bash
if [[ -n "${GARTH_<MODULE>_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_<MODULE>_SH_LOADED=1
```

All functions are `garth_`-prefixed. Modules are sourced eagerly at startup.

## Module Reference

### lib/common.sh (327 lines)

Foundation module: logging, dry-run control, temp-file lifecycle, secret
redaction, audit logging, and general-purpose string/JSON utilities.

**Key functions:** `garth_log_info`, `garth_log_success`, `garth_log_warn`,
`garth_log_error` (color-coded logging), `garth_die` (log error + exit),
`garth_run_cmd` (execute or dry-run print), `garth_ask_yn` (y/n prompt,
auto-yes support), `garth_require_cmd` (assert binary on PATH),
`garth_is_macos` (platform check), `garth_python` (invoke configured Python),
`garth_parse_duration_to_seconds` (parse `5s`/`10m`/`2h`/`forever`),
`garth_abs_path` (resolve relative paths), `garth_slugify_branch` (safe
session-name slugs), `garth_make_temp_dir` / `garth_cleanup_paths` (temp
lifecycle), `garth_redact_secret_text` (scrub secrets from strings),
`garth_audit_log` (append JSONL audit events with auto-redaction).

**Dependencies:** None (base module).

### lib/git.sh (125 lines)

Thin wrappers around `git` for repo introspection, remote URL parsing,
session-name generation, and worktree management.

**Key functions:** `garth_git_repo_root`, `garth_git_current_branch`,
`garth_git_repo_name`, `garth_git_remote_url`,
`garth_git_owner_repo_from_remote` (parse `owner/repo` from SSH/HTTPS URLs),
`garth_git_https_url_from_remote`, `garth_git_session_name` (deterministic
`garth-<repo>-<branch-slug>`, capped at 80 chars), `garth_git_worktree_path`,
`garth_git_create_worktree`, `garth_git_list_worktrees`.

**Dependencies:** `lib/common.sh`.

### lib/secrets.sh (108 lines)

Wraps the 1Password CLI (`op`) for secret retrieval with auto sign-in retry.

**Key functions:** `garth_require_op` (assert `op` installed and signed in),
`garth_secret_read` (read `op://` reference, retry on session expiry),
`garth_ensure_secret_access` (probe-read without returning value),
`garth_secret_write_file` (read secret and write atomically at `0600`).

**Dependencies:** `lib/common.sh`.

### lib/github-app.sh (278 lines)

Mints short-lived GitHub App installation tokens: constructs RS256 JWTs,
resolves installation IDs, exchanges for access tokens via the GitHub REST API.

**Key functions:** `garth_base64url` (URL-safe base64 for JWT segments),
`garth_github_generate_app_jwt` (build and sign RS256 JWT),
`garth_github_private_key_valid` (validate PEM via `openssl pkey`),
`garth_github_validate_app_jwt` (verify JWT against `GET /app`),
`garth_github_resolve_installation_id` (strategies: `single`, `static_map`,
`by_owner`), `garth_github_mint_installation_token` (full orchestration,
prints `token\texpires_at\tinstallation_id`), `garth_iso8601_to_epoch`.

**Dependencies:** `lib/common.sh`, `lib/secrets.sh`.

### lib/container.sh (840 lines)

Assembles hardened `docker run` argument lists, manages env files and token
files, handles auth passthrough mounts, drives Docker image builds and
lifecycle.

**Key functions:** `garth_sandbox_dir_name` / `garth_sandbox_workdir` (container
workdir paths), `garth_agent_field` (read `GARTH_AGENT_<KEY>_<FIELD>` vars),
`garth_agent_command_string` (build agent shell command with safe/permissive
args), `garth_claude_runtime_preamble` (`.claude.json` state seeding),
`garth_prepare_agent_env_file` (write `0600` env file with token path + API
key), `garth_write_token_file` (atomic token write), `garth_container_name`
(Docker-safe name, capped at 80 chars), `garth_container_args_lines` (full
`docker run` argument list), `garth_container_shell_args_lines` (shell pane
args), `garth_docker_build_agent_image`, `garth_ensure_agent_image_ready`
(rebuild if binary/packages missing), `garth_stop_containers_for_session`,
`garth_features_mount_specs_lines` / `garth_features_packages_lines` (parse
feature config).

**Dependencies:** `lib/common.sh`, `lib/secrets.sh`.

### lib/zellij.sh (249 lines)

Generates Zellij KDL layout files and launches/attaches to Zellij sessions.

**Key functions:** `garth_kdl_escape` / `garth_kdl_write_args_line` (KDL string
escaping), `garth_zellij_session_state` (query session status: `running`,
`exited`, `missing`), `garth_generate_zellij_layout` (write KDL layout with
one tab per agent: 65% agent pane, 35% shell pane),
`garth_zellij_launch` (launch/attach with macOS terminal fallbacks: Ghostty →
Terminal.app → current shell), `garth_zellij_kill_session`.

**Dependencies:** `lib/common.sh`, `lib/container.sh`.

### lib/workspace.sh (446 lines)

macOS GUI integrations: Cursor, Chrome profiles, AeroSpace workspace management.

**Key functions:** `garth_cursor_binary_path` (find Cursor.app),
`garth_ensure_gui_python_shim` (create Python symlink for GUI apps),
`garth_ensure_macos_gui_path` (set `launchctl` PATH/PYTHON3 for Dock-launched
apps), `garth_launch_cursor` (open directory in Cursor with correct env),
`garth_configure_cursor_terminal_bridge` (write
`.vscode/garth-sandbox-shell.sh` + update `settings.json` so Cursor terminal
attaches to Docker shell), `garth_launch_chrome_profile` (isolated
`--user-data-dir`), `garth_aerospace_next_workspace`,
`garth_move_windows_to_workspace`.

**Dependencies:** `lib/common.sh`.

### lib/config-parser.py

TOML validation and env-var emission using Python stdlib only (`tomllib` from
3.11+, zero external deps).

**CLI modes:**
- `config-parser.py validate <config>` — validate only, exit non-zero on errors
- `config-parser.py env <config>` — validate then print `GARTH_*` assignments

**Key functions:** `load_toml`, `validate_duration`, `require_str`,
`warn_unknown_keys`, `normalize_config` (walk config tree, apply defaults,
collect errors), `emit_env` (serialize to `KEY='value'` via `shlex.quote`).

## Security Model

### Container Hardening

- `--cap-drop=ALL` — no Linux capabilities
- `--security-opt no-new-privileges:true` — prevent privilege escalation
- `--security-opt seccomp=docker/seccomp-profile.json` — custom seccomp profile
- `--read-only` — read-only root filesystem
- tmpfs mounts for writable transient paths (`/tmp`, `/home/agent/.cache`)
- `--pids-limit=512` — prevent fork bombs
- Memory and CPU limits configurable
- Non-root `agent` user (UID 1001) inside containers

### Secret Management

- Agent API keys delivered via `0600` env files (never in process args or layout
  files)
- GitHub token mounted as a file at `/run/garth/github_token`, rotated
  atomically via `mv`
- Token refresh runs as a background process (`cmd_internal_refresh`), re-minting
  before expiry with configurable lead time and exponential backoff on failure
- Token cache under `$XDG_STATE_HOME/garth/token-cache` (permissions
  `0700`/`0600`)

### Protected Paths

Read-only overlays prevent agents from modifying sensitive repo paths:

- `.git/hooks`
- `.git/config`
- `.github`
- `.gitmodules`

### Auth Passthrough

When agents are listed in `defaults.auth_passthrough`, host CLI auth directories
are mounted into the container. Mount mode (`ro`/`rw`) is configurable via
`[security.auth_mount_mode]`.

### Audit Logging

Session events are written to
`$XDG_STATE_HOME/garth/sessions/<session>/audit.log` (JSONL, `0600`) with
automatic secret redaction.

## Naming Conventions

| Entity | Pattern | Example |
|--------|---------|---------|
| Functions | `garth_<module>_<action>` | `garth_git_repo_root` |
| Env vars | `GARTH_<SECTION>_<KEY>` | `GARTH_DEFAULTS_SANDBOX` |
| Agent config | `GARTH_AGENT_<UPPERNAME>_<FIELD>` | `GARTH_AGENT_CLAUDE_BASE_COMMAND` |
| Session names | `garth-<repo>-<branch-slug>` | `garth-myapp-feature__auth` |
| Container names | `<session>-<agent>` | `garth-myapp-main-claude` |
| Include guards | `GARTH_<MODULE>_SH_LOADED` | `GARTH_CONTAINER_SH_LOADED` |

## Coding Style

### Bash

- Shebang: `#!/usr/bin/env bash`
- Strict mode: `set -euo pipefail`
- 2-space indentation
- `snake_case` for functions and variables
- Explicit `local` for all function variables
- Defensive error messages via `garth_die` (no silent failures)
- macOS-specific code guarded by `garth_is_macos()`

### Python

- `snake_case` for functions and variables
- Stdlib only (`tomllib` from Python 3.11+, zero external deps)
- Auto-re-execs under Python 3.11+ if invoked with an older interpreter

## Testing Guidelines

### Smoke Test Pattern

Tests are deterministic shell scripts under `tests/`. Each test:

1. Sources the relevant `lib/*.sh` modules directly
2. Stubs external dependencies (mock functions for `docker`, `op`, etc.)
3. Exercises target functions with known inputs
4. Asserts results with `grep -q` / `[[ ]]`
5. Prints `<name>_smoke: ok` on success

Example structure:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
source lib/git.sh

# Mock stubs
docker() { echo "mock"; }

# Tests
result="$(garth_git_session_name "/path/to/repo")"
[[ "$result" == "garth-repo-main" ]] || { echo "FAIL: session name"; exit 1; }

echo "git_helpers_smoke: ok"
```

### Adding New Tests

- Create `tests/<module>_smoke.sh` for new modules
- Keep tests fast and deterministic (no network, no Docker daemon)
- Source only the modules under test plus their dependencies
- Run all smoke tests before opening a PR

## Commit & PR Guidelines

- Imperative, concise subject lines: `Add ...`, `Fix ...`, `Refactor ...`
- Logically scoped — don't mix unrelated refactors with behavior changes
- PR descriptions should include:
  - What changed and why
  - Config/security impact (`config.example.toml`, `docker/seccomp-profile.json`,
    auth flow)
  - Commands/tests run with key outputs
- Update README/docs when CLI behavior changes

## Supported Agents

Configured in TOML under `[agents.<name>]`, each with a Docker build target in
`docker/Dockerfile`:

| Agent | Runtime | Description |
|-------|---------|-------------|
| `claude` | Anthropic Claude Code CLI | Default agent with auth passthrough support |
| `codex` | OpenAI Codex CLI | Auth passthrough support |
| `opencode` | OpenCode CLI | Community agent |
| `gemini` | Google Gemini CLI | Google agent |

## File Map

```text
garth/
├── .github/
│   ├── workflows/ci.yml               # CI: lint + smoke tests on push/PR
│   ├── dependabot.yml                 # Docker + Actions version bumps
│   └── PULL_REQUEST_TEMPLATE.md       # PR checklist template
├── bin/garth                          # CLI entrypoint, command routing (~2229 lines)
├── lib/
│   ├── common.sh                      # Logging, dry-run, cleanup, utilities (327 lines)
│   ├── git.sh                         # Git repo/worktree helpers (125 lines)
│   ├── secrets.sh                     # 1Password secret retrieval (108 lines)
│   ├── github-app.sh                  # GitHub App JWT + token minting (278 lines)
│   ├── container.sh                   # Docker lifecycle, security hardening (840 lines)
│   ├── zellij.sh                      # Zellij session/layout management (249 lines)
│   ├── workspace.sh                   # macOS GUI integrations (446 lines)
│   └── config-parser.py               # TOML validation, env export (Python)
├── docker/
│   ├── Dockerfile                     # Multi-target: claude, codex, opencode, gemini
│   └── seccomp-profile.json           # Custom seccomp policy
├── tests/
│   ├── config_parser_smoke.sh         # Config parser smoke tests
│   ├── git_helpers_smoke.sh           # Git helper smoke tests
│   └── zellij_layout_smoke.sh         # Zellij layout smoke tests
├── docs/
│   └── github-app-setup.md            # GitHub App wiring guide
├── templates/
│   └── aerospace.example.toml         # AeroSpace config template
├── .editorconfig                      # Editor formatting rules
├── .shellcheckrc                      # ShellCheck config (source paths, suppressions)
├── Makefile                           # make lint / test / check
├── LICENSE                            # MIT license
├── config.example.toml                # Baseline config (copy to config.toml)
├── setup.sh                           # Bootstrap script
├── README.md                          # Installation, config, usage
├── CONTRIBUTING.md                    # Development workflow, PR process
├── CLAUDE.md                          # Claude Code quick reference
└── AGENTS.md                          # This file
```
