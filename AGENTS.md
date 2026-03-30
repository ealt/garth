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

### Workspace Lifecycle

- `garth new . feature/branch` — create branch + worktree + session
- `garth new . feature/branch --base origin/main` — with explicit base ref
- `garth new . feature/branch --no-fetch` — skip syncing the implicit default base
- `garth open <id>` — resume a session by ID
- `garth open -d .` — open default branch (reuse session if exists)
- `garth open -d . feature/branch` — open existing branch
- `garth up .` — interactive wizard
- `garth up . --auto` — non-interactive with wizard defaults

### Session Management

- `garth ps` — list sessions with status
- `garth ps -q` — list session IDs only (for piping)
- `garth containers <id>` — list container IDs for a session
- `garth stop <id>` — stop a session (preserve worktree and state)
- `garth down <id>` — remove session and all resources
- `garth down <id> -y` — remove without confirmation

### Other

- `garth agent . codex --sandbox docker` — run a single agent
- `garth refresh-images --agents claude,codex` — force-refresh Docker images
- `garth token .` — mint a GitHub App token
- `garth doctor --repo .` — diagnose setup and auth health

### Testing

- `bash tests/config_parser_smoke.sh`
- `bash tests/git_helpers_smoke.sh`
- `bash tests/zellij_layout_smoke.sh`
- `bash tests/zellij_launcher_smoke.sh`
- `bash tests/secrets_auto_signin_guard_smoke.sh`
- `bash tests/session_helpers_smoke.sh`
- `bash tests/cli_new_smoke.sh`
- `bash tests/cli_open_smoke.sh`
- `bash tests/refresh_images_smoke.sh`
- `bash tests/github_app_override_smoke.sh`
- `bash tests/token_cache_lock_smoke.sh`

### Syntax Checks

- `bash -n bin/garth lib/*.sh` — shell syntax check
- `python3 -m py_compile lib/config-parser.py` — Python syntax check

### Docker Images

- `docker build --target claude -t garth-claude:latest docker/`
- Targets: `claude`, `codex`, `opencode`, `gemini`

## Architecture

### Entry Point Flow

`bin/garth` is the CLI entrypoint and command router.

1. Resolves symlinks to find `GARTH_ROOT`
2. Sources all `lib/*.sh` modules (each uses include-once guards)
3. Sets `GARTH_STATE_ROOT` (`$XDG_STATE_HOME/garth`), `GARTH_CONFIG_PATH`,
   `GARTH_BIN_PATH`
4. Installs EXIT/INT/TERM cleanup trap
5. Dispatches to the appropriate `cmd_*` function:

| Command | Function |
|---------|----------|
| `new` | `cmd_new` |
| `open` | `cmd_open` |
| `up` | `cmd_up` |
| `ps` | `cmd_ps` |
| `containers` | `cmd_containers` |
| `stop` | `cmd_stop` |
| `down` | `cmd_down` |
| `agent` | `cmd_agent` |
| `refresh-images` | `cmd_refresh_images` |
| `token` | `cmd_token` |
| `setup` | `cmd_setup` |
| `internal-refresh` | `cmd_internal_refresh` |
| `doctor` | `cmd_doctor` |

The workspace launch commands (`new`, `open`, `up`) all delegate to an internal
`garth_launch_workspace` function which handles token minting, Zellij layout
generation, container setup, and session state persistence. `cmd_up` provides
an interactive wizard that collects branch/worktree/session choices and then
calls `cmd_new` or `cmd_open` with the resolved flags.

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

### lib/git.sh

Thin wrappers around `git` for repo introspection, remote URL parsing,
session-name generation, worktree management, and default branch detection.

**Key functions:** `garth_git_repo_root`, `garth_git_current_branch`,
`garth_git_repo_name`, `garth_git_remote_url`,
`garth_git_owner_repo_from_remote` (parse `owner/repo` from SSH/HTTPS URLs),
`garth_git_https_url_from_remote`, `garth_git_session_name` (deterministic
`garth-<repo>-<branch-slug>`, capped at 80 chars), `garth_git_default_branch`
(config → `origin/HEAD` → `main` → `master` fallback),
`garth_git_fetch_and_resolve_default_base` (fetch origin, then prefer
`origin/<default>` for implicit new-branch bases),
`garth_git_worktree_path`, `garth_git_create_worktree`,
`garth_git_list_worktrees`, `garth_git_find_worktree_for_branch` (look up
existing worktree by branch name).

**Dependencies:** `lib/common.sh`.

### lib/session.sh

Session state management: reading/writing session state files, generating
random session IDs, and looking up sessions by branch or ID prefix.

**Key functions:** `ensure_state_root`, `session_dir_for`, `write_state_value`,
`read_state_value`, `garth_session_list_dirs`, `garth_session_id_for_dir`,
`garth_session_name_for_dir`, `garth_session_generate_id` (random 6-char hex),
`garth_find_sessions_for_branch` (lookup by repo+branch),
`garth_find_sessions_by_id_prefix`.

**Dependencies:** `lib/common.sh`.

### lib/secrets.sh (108 lines)

Wraps the 1Password CLI (`op`) for secret retrieval with auto sign-in retry.

**Key functions:** `garth_require_op` (assert `op` installed and signed in),
`garth_secret_read` (read `op://` reference, retry on session expiry),
`garth_ensure_secret_access` (probe-read without returning value),
`garth_secret_write_file` (read secret and write atomically at `0600`).

**Dependencies:** `lib/common.sh`.

### lib/github-app.sh (348 lines)

Mints short-lived GitHub App installation tokens: constructs RS256 JWTs,
resolves installation IDs, exchanges for access tokens via the GitHub REST API.

**Key functions:** `garth_base64url` (URL-safe base64 for JWT segments),
`garth_github_api_json_fast` (timeout-constrained GET for best-effort lookups),
`garth_github_generate_app_jwt` (build and sign RS256 JWT),
`garth_github_private_key_valid` (validate PEM via `openssl pkey`),
`garth_github_validate_app_jwt` (verify JWT against `GET /app`),
`garth_github_resolve_installation_id` (strategies: `single`, `static_map`,
`by_owner`), `garth_github_mint_installation_token` (full orchestration,
prints `token\texpires_at\tinstallation_id`), `garth_iso8601_to_epoch`,
`garth_github_context_url` (resolve best GitHub URL: PR page, branch tree, or
base repo).

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

### lib/workspace.sh

macOS GUI integrations: Cursor and browser launch helpers.

**Key functions:** `garth_cursor_binary_path` (find Cursor.app),
`garth_ensure_gui_python_shim` (create Python symlink for GUI apps),
`garth_ensure_macos_gui_path` (set `launchctl` PATH/PYTHON3 for Dock-launched
apps), `garth_launch_cursor` (open directory in Cursor with correct env),
`garth_configure_cursor_terminal_bridge` (write
`.vscode/garth-sandbox-shell.sh` + update `settings.json` so Cursor terminal
attaches to Docker shell), `garth_launch_browser` / `garth_launch_chromium_browser` /
`garth_launch_firefox_browser` / `garth_launch_url_only_browser`.

**Dependencies:** `lib/common.sh`.

### lib/config-parser.py

TOML validation and env-var emission using Python stdlib only (`tomllib` from
3.11+, zero external deps).

**CLI modes:**
- `config-parser.py validate <config>` — validate only, exit non-zero on errors
- `config-parser.py env <config>` — validate then print `GARTH_*` assignments

**Key functions:** `load_toml`, `validate_duration`, `require_str`,
`warn_unknown_keys`, `normalize_config` (walk config tree, apply defaults,
validate `[browser]` and other sections, collect errors), `emit_env`
(serialize to `KEY='value'` via `shlex.quote`).

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

Default mount modes are chosen to balance isolation with agent functionality:

| Key | Default | Rationale |
|-----|---------|-----------|
| `claude_dot_claude` | `rw` | Claude writes auth/settings here (`appendFileSync`) |
| `claude_config` | `rw` | Claude writes config here |
| `claude_state` | `rw` | Session state — container writes expected |
| `claude_share` | `ro` | Contains installed binaries — protects host from overwrites |
| `claude_cache` | `rw` | Cache — container writes expected |

`garth doctor` warns if `claude_share` is overridden to `rw`, since a
container auto-updater could overwrite host binaries with wrong-platform
builds. `claude_dot_claude` and `claude_config` must remain `rw` — setting
them to `ro` causes `EROFS` errors inside the container.

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
| Session IDs | random 6-char hex | `a1b2c3` |
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

## Claude Code Slash Commands

Garth provides slash commands for Claude Code (`.claude/commands/*.md`) that let
users describe tasks in natural language and have Claude manage workspaces.

### Commands

| Command | File | Description |
|---------|------|-------------|
| `/workspace` | `.claude/commands/workspace.md` | Create or resume a workspace from a task description |
| `/sessions` | `.claude/commands/sessions.md` | List and manage sessions by status |
| `/recover` | `.claude/commands/recover.md` | Diagnose and fix degraded sessions |
| `/cleanup` | `.claude/commands/cleanup.md` | Clean up stopped sessions and orphan resources |

### Branch naming convention

`/workspace` generates branch names from task descriptions:
- **Prefix**: `feature/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/`
- **Body**: 2-4 lowercase hyphen-joined words
- **Max length**: 50 characters total
- **Examples**: `feature/api-auth`, `fix/login-timeout`, `docs/setup-guide`

### Autonomy modes

- **Interactive (default)**: commands present plans and ask before acting
- **`--auto` flag**: per-invocation opt-in to skip confirmations; maps to
  Garth's `--yes` flag for destructive operations

### CLI resolution

Commands try `garth` on PATH first, then fall back to `bin/garth` relative to
the repo root. On complete failure, they suggest `./setup.sh` or
`garth doctor --repo .`.

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
├── .claude/
│   └── commands/
│       ├── workspace.md                  # /workspace — create or resume workspace
│       ├── sessions.md                   # /sessions — list and manage sessions
│       ├── recover.md                    # /recover — fix degraded sessions
│       └── cleanup.md                    # /cleanup — clean up stale resources
├── .github/
│   ├── workflows/ci.yml               # CI: lint + smoke tests on push/PR
│   ├── workflows/release.yml          # Release: tag → tarball + GitHub Release
│   ├── dependabot.yml                 # Docker + Actions version bumps
│   └── PULL_REQUEST_TEMPLATE.md       # PR checklist template
├── bin/garth                          # CLI entrypoint, command routing
├── lib/
│   ├── common.sh                      # Logging, dry-run, cleanup, utilities
│   ├── git.sh                         # Git repo/worktree helpers
│   ├── session.sh                     # Session state management, ID generation
│   ├── secrets.sh                     # 1Password secret retrieval
│   ├── github-app.sh                  # GitHub App JWT + token minting
│   ├── container.sh                   # Docker lifecycle, security hardening
│   ├── zellij.sh                      # Zellij session/layout management
│   ├── workspace.sh                   # macOS GUI integrations
│   └── config-parser.py               # TOML validation, env export (Python)
├── docker/
│   ├── Dockerfile                     # Multi-target: claude, codex, opencode, gemini
│   └── seccomp-profile.json           # Custom seccomp policy
├── tests/
│   ├── config_parser_smoke.sh         # Config parser smoke tests
│   ├── git_helpers_smoke.sh           # Git helper smoke tests
│   ├── zellij_layout_smoke.sh         # Zellij layout smoke tests
│   ├── zellij_launcher_smoke.sh       # Zellij launcher selection smoke tests
│   ├── secrets_auto_signin_guard_smoke.sh # 1Password auto-signin guard smoke tests
│   ├── session_helpers_smoke.sh       # Session state smoke tests
│   ├── cli_new_smoke.sh               # CLI new command smoke tests
│   ├── cli_open_smoke.sh              # CLI open command smoke tests
│   ├── github_app_override_smoke.sh   # GitHub app env-override token mint smoke test
│   ├── refresh_images_smoke.sh        # Docker refresh command smoke tests
│   └── token_cache_lock_smoke.sh      # Concurrent token-mint lock smoke test
├── docs/
│   ├── security-model.md              # Security model, controls, and tradeoffs
│   └── github-app-setup.md            # GitHub App wiring guide
├── VERSION                            # Semver version string (e.g. 0.1.0)
├── CHANGELOG.md                       # Release history (Keep a Changelog)
├── install.sh                         # Curl-pipe-bash installer
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
