# Documentation Pass for UX Redesign

## Context

The CLI commands have been redesigned (boot/worktree/status → new/open/up/ps/
containers/stop/down) but help text is skeletal and repo docs still reference
the old commands. This pass brings all documentation in line with the
implementation.

## 1. CLI `--help` text (`bin/garth`)

Every command's help block needs a description, full flag list, and examples.

### Top-level usage (line ~35)

Update the command table to include short descriptions matching the new design.

### `garth new --help` (line ~868)

```
Usage: garth new <dir> <name> [options]

Create a new branch, worktree, and session. Everything is derived from <name>.

Arguments:
  <dir>                 Path to the git repository
  <name>                Name for the new branch

Options:
  --base <ref>          Base ref for the new branch (default: repo default branch)
  --no-worktree         Create branch in-place instead of a worktree
  --agents <a,b>        Comma-separated agents (overrides config)
  --auth-passthrough <a,b>
                        Docker auth passthrough for selected agents
  --sandbox docker|none Runtime sandbox mode
  --no-sandbox          Alias for --sandbox none
  --network bridge|none Docker network mode
  --safety safe|permissive
                        Agent argument preset
  --workspace <N|auto>  AeroSpace workspace
  --dry-run             Print commands without executing
  --yes, -y             Auto-confirm prompts

Examples:
  garth new . feature/auth          Create feature/auth from default branch
  garth new . hotfix --base v2.1    Create hotfix from v2.1 tag
```

### `garth open --help` (line ~983)

```
Usage: garth open <dir> [<branch>] [options]

Open an existing branch, reusing its session and worktree if they exist.
If a live session exists for the branch, reattaches to it.

Arguments:
  <dir>                 Path to the git repository
  <branch>              Branch to open (default: repo default branch)

Options:
  --remote <name>       Remote to fetch from when branch is remote-only
                        (default: origin)
  --worktree <path>     Use a specific worktree path
  --session <name>      Reattach to a specific session by name
  --new-worktree        Force creation of a new worktree
  --new-session         Force creation of a new session
  --no-worktree         Open branch in-place (fails if working tree is dirty)
  --agents <a,b>        Comma-separated agents (overrides config)
  --auth-passthrough <a,b>
                        Docker auth passthrough for selected agents
  --sandbox docker|none Runtime sandbox mode
  --no-sandbox          Alias for --sandbox none
  --network bridge|none Docker network mode
  --safety safe|permissive
                        Agent argument preset
  --workspace <N|auto>  AeroSpace workspace
  --dry-run             Print commands without executing
  --yes, -y             Auto-confirm prompts

Examples:
  garth open .                      Open the repo's default branch
  garth open . feature/auth         Open an existing feature branch
  garth open . pr-branch --remote upstream
                                    Open a branch from a non-origin remote
```

### `garth up --help` (line ~1177)

```
Usage: garth up <dir> [options]

Interactive workspace launcher. With no flags, presents a step-by-step wizard
to select a branch, worktree, and session. With explicit flags, skips the
corresponding wizard steps. With --auto, uses wizard defaults non-interactively.

Arguments:
  <dir>                 Path to the git repository

Branch selection (wizard step 1):
  --branch <name>       Use an existing branch (skips step 1)
  --new-branch <name>   Create a new branch (skips step 1, implies new worktree)
  --base <ref>          Base ref for --new-branch (default: repo default branch)
  --remote <name>       Remote for fetching remote-only branches (default: origin)
  --auto-branch         Use wizard default: currently checked-out branch

Worktree selection (wizard step 2):
  --worktree <path>     Use a specific worktree path (skips step 2)
  --new-worktree        Force creation of a new worktree (skips step 2)
  --no-worktree         No worktree, boot in-place (skips step 2)
  --auto-worktree       Use wizard default: reuse if exists, create if not

Session selection (wizard step 3):
  --session <name>      Reattach to a specific session by name (skips step 3)
  --new-session         Force creation of a new session (skips step 3)
  --auto-session        Use wizard default: resume if exists, create if not

Shorthand:
  --auto                Equivalent to --auto-branch --auto-worktree --auto-session

General options:
  --agents <a,b>        Comma-separated agents (overrides config)
  --auth-passthrough <a,b>
                        Docker auth passthrough for selected agents
  --sandbox docker|none Runtime sandbox mode
  --no-sandbox          Alias for --sandbox none
  --network bridge|none Docker network mode
  --safety safe|permissive
                        Agent argument preset
  --workspace <N|auto>  AeroSpace workspace
  --dry-run             Print commands without executing
  --yes, -y             Auto-confirm prompts

Examples:
  garth up .                        Full interactive wizard
  garth up . --auto                 Non-interactive, all defaults
  garth up . --branch feature/auth  Skip branch selection, wizard for the rest
  garth up . --new-branch fix/bug --base v2.1
                                    Create new branch, wizard for worktree/session
```

### `garth ps --help` (line ~1885)

```
Usage: garth ps [-q]

List all garth sessions with their status.

Options:
  -q, --quiet           Output only session IDs, one per line (no header).
                        Useful for piping: garth ps -q | xargs garth stop

Output columns:
  ID          Short random session identifier (use with stop, down, containers)
  SESSION     Full session name
  REPO        Repository name
  BRANCH      Git branch
  WORKTREE    Worktree directory (- if none)
  AGENTS      Comma-separated agent list
  STATUS      running, running(?), detached, stopped, or degraded (reason)
  UPTIME      Time since session was started
```

### `garth containers --help` (line ~1944)

```
Usage: garth containers <id>

List Docker container IDs for a session. Output is one container ID per line,
suitable for piping into docker commands.

Arguments:
  <id>                  Session ID or unambiguous prefix (from garth ps)

Examples:
  garth containers a1b2c3                     List container IDs
  garth containers a1b | xargs docker logs    View logs for all containers
  garth containers a1b | xargs docker stats   Monitor resource usage
```

### `garth stop --help` (line ~1960)

```
Usage: garth stop <id>

Stop a session's Zellij session and Docker containers. The worktree, branch,
and session state are preserved so the session can be resumed later with
'garth open' or removed entirely with 'garth down'.

Arguments:
  <id>                  Session ID or unambiguous prefix (from garth ps)

Examples:
  garth stop a1b2c3                 Stop a specific session
  garth ps -q | xargs garth stop   Stop all sessions
```

### `garth down --help` (line ~2012)

```
Usage: garth down <id> [-y]

Remove a session and all its resources: Zellij session, Docker containers,
session state directory, and managed worktree. Warns before deleting a
worktree that has uncommitted or unpushed changes.

Arguments:
  <id>                  Session ID or unambiguous prefix (from garth ps)

Options:
  -y, --yes             Skip confirmation prompt

Examples:
  garth down a1b2c3                 Remove a session (with confirmation)
  garth down a1b2c3 -y              Remove without confirmation
  garth ps -q | xargs -I{} garth down {} -y
                                    Remove all sessions
```

## 2. README.md

### Quick Start (line ~16)

Replace `garth boot .` with `garth up .` or `garth new . my-feature`.

### Usage section (line ~183)

Replace "Boot a workspace" / "Create and boot a worktree" / "Session control"
with the new command structure. Organize as:

- **Start a new feature**: `garth new . feature/auth`
- **Open an existing branch**: `garth open .` / `garth open . feature/auth`
- **Interactive launcher**: `garth up .`
- **List sessions**: `garth ps`
- **Stop / remove sessions**: `garth stop <id>` / `garth down <id>`
- **Pipe containers to docker**: `garth containers <id>`
- Keep existing sections: Run one agent, Mint a token, Doctor

Remove references to `garth boot`, `garth worktree`, `garth status`,
`garth stop --all`, `garth stop --repo`.

### Troubleshooting (line ~285)

Update `garth boot` references. Update "Session already exists" entry.

## 3. AGENTS.md

### Commands section (line ~14)

Replace Running subsection:

- `garth new . feature/branch` — create branch + worktree + session
- `garth new . feature/branch --base origin/main` — with explicit base
- `garth open .` — open default branch
- `garth open . feature/branch` — open existing branch
- `garth up .` — interactive wizard
- `garth up . --auto` — non-interactive defaults
- `garth ps` — list sessions
- `garth ps -q` — list session IDs only
- `garth containers <id>` — list container IDs for a session
- `garth stop <id>` — stop a session (preserve state)
- `garth down <id>` — remove session and all resources
- `garth agent . codex --sandbox docker` — run a single agent
- `garth token .` — mint a GitHub App token

### Testing subsection (line ~36)

Add `bash tests/session_helpers_smoke.sh` and `bash tests/cli_open_smoke.sh`.

### Entry Point Flow table (line ~62)

Update command-to-function mapping:

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
| `token` | `cmd_token` |
| `setup` | `cmd_setup` |
| `internal-refresh` | `cmd_internal_refresh` |
| `doctor` | `cmd_doctor` |

Remove line numbers (they'll be stale after this change).

### Module Reference

Update lib/git.sh description to mention new functions:
`garth_git_default_branch`, `garth_git_find_worktree_for_branch`.

Add lib/session.sh entry:
Session state management extracted from bin/garth. Functions:
`ensure_state_root`, `session_dir_for`, `write_state_value`,
`read_state_value`, `garth_session_list_dirs`, `garth_session_id_for_dir`,
`garth_session_name_for_dir`, `garth_session_generate_id`,
`garth_find_sessions_for_branch`, `garth_find_sessions_by_id_prefix`.

Update line counts where they appear (these are approximate and can be
dropped or marked as approximate).

### Naming Conventions table (line ~266)

Add session ID row. Update session name description to note random ID.

### File Map (line ~356)

Add `lib/session.sh`, add new test files under `tests/`.

## 4. CLAUDE.md

### Quick Commands (line ~16)

Replace:
```bash
garth boot .                               # launch workspace
```
with:
```bash
garth up .                                 # interactive launcher
garth new . feature/my-feature             # new branch + worktree + session
garth open .                               # open default branch
garth ps                                   # list sessions
```

Add `bash tests/session_helpers_smoke.sh` and `bash tests/cli_open_smoke.sh`
to test commands.

## Files to modify

- `bin/garth` — expand all `--help` blocks
- `README.md` — update Quick Start, Usage, Session control, Troubleshooting
- `AGENTS.md` — update Commands, Entry Point Flow, Module Reference, Naming,
  File Map, Testing
- `CLAUDE.md` — update Quick Commands

## Verification

- `garth new --help` shows full flag list with examples
- `garth open --help` shows full flag list with examples
- `garth up --help` shows full flag list organized by wizard step
- `garth ps --help` explains columns and -q flag
- `garth containers --help` shows piping examples
- `garth stop --help` explains what's preserved
- `garth down --help` explains what's removed and the warning behavior
- No references to `boot`, `worktree`, `status --json`, or `stop --all` remain
  in README.md, AGENTS.md, or CLAUDE.md
- `bash -n bin/garth lib/*.sh` passes
