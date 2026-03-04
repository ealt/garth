# Plan: `garth open <id>` — open a session by ID

## Context

`garth open` currently requires `<dir>` (a path to a git repo) and optionally
`<branch>`. Users who run `garth ps`, see a session they want to resume, then
have to remember the repo path and branch to reconstruct the command. Since
session IDs are already displayed by `garth ps` and accepted by `garth stop`,
`garth down`, and `garth containers`, `garth open` should also accept a session
ID as its primary argument.

## Approach

Make session ID the primary positional argument for `garth open`. Move the
directory to a `--dir` / `-d` flag. This is a breaking change to the current
`garth open <dir> [branch]` syntax but aligns `open` with `stop`/`down`/
`containers` which already use positional IDs.

### New syntax

```
garth open <id> [options]                            # resume by session ID
garth open -d <dir> [<branch>] [options]             # open by directory + branch
garth open --dir <dir> [<branch>] [options]          # same, long form
```

### Changes to `cmd_open` in `bin/garth` (~lines 977-1169)

**Argument parsing:**
- Add `--dir` / `-d` as a named flag that captures the directory
- When `--dir` is provided: first positional → `branch` (current behavior)
- When `--dir` is not provided: first positional → `id_prefix`
- Error if both `id_prefix` and `--dir` are given

**ID path (no `--dir`):**
1. `garth_find_session_dir_by_id_prefix "$id_prefix"` to resolve session
2. Read `repo_root`, `branch`, `worktree`, `worktree_managed` from state files
3. Validate `repo_root` exists on disk
4. `garth_attach_if_running` → if running, reattach and return
5. Otherwise, resume via `garth_launch_workspace` with stored state
6. Incompatible flags (`--remote`, `--no-worktree`, `--new-worktree`,
   `--worktree`, `--session`, `--new-session`) error when combined with an ID

**Dir path (`--dir` provided):**
Identical to current behavior. `--dir` value replaces the old positional `<dir>`.
All existing flags work as before.

### Existing functions to reuse

- `garth_find_session_dir_by_id_prefix()` (`bin/garth:1923`) — ID lookup with
  exact/prefix matching and ambiguity errors
- `garth_attach_if_running()` (`bin/garth:844`) — reattach to running session
- `garth_launch_workspace()` (`bin/garth:307`) — resume stopped session
- `read_state_value()` (`lib/session.sh:25`) — read session state files
- `garth_session_name_for_dir()` (`lib/session.sh:52`) — get session name
- `garth_session_id_for_dir()` (`lib/session.sh:41`) — get session ID

### Help text update

```
Usage: garth open <id> [options]
       garth open -d <dir> [<branch>] [options]

Resume a session by ID, or open a branch from a git repository.

Arguments:
  <id>                    Session ID or prefix (from garth ps)

Options:
  -d, --dir <dir>         Path to the git repository (use instead of <id>
                          to open by directory and branch)
  ...existing options...

Examples:
  garth open a1b2c3                   Resume session by ID
  garth open -d .                     Open the repo's default branch
  garth open -d . feature/auth        Open an existing feature branch
  garth open -d . pr-branch --remote upstream
                                      Open a branch from a non-origin remote
```

## Files to modify

1. **`bin/garth`** — `cmd_open` function:
   - Add `-d` / `--dir` to the case statement
   - Restructure positional arg handling
   - Add ID-based resume path after arg parsing
   - Update help text

2. **`docs/plans/ux-redesign.md`** — Update `garth open` section:
   - Change syntax from `garth open <dir> [<branch>]` to
     `garth open <id>` / `garth open -d <dir> [<branch>]`
   - Update the "Session lookup for reattachment" section to note that ID-based
     lookup is now supported directly
   - Update "Session IDs" section to include `open` in the list of commands
     supporting prefix matching

3. **`docs/plans/ux-documentation-plan.md`** — Update `garth open --help` section:
   - Replace the documented help text to match new syntax
   - Update README.md section examples to use `-d` flag
   - Update AGENTS.md section examples

## Verification

1. `bash -n bin/garth` — syntax check
2. `garth open --help` — shows updated usage with ID and `-d`/`--dir`
3. `garth open <id>` — reattach/resume session by ID
4. `garth open abc` (non-existent) — "No session matches ID prefix"
5. `garth open -d . feature/x` — existing behavior via flag
6. `garth open --dir .` — long form works too
7. `bash tests/cli_open_smoke.sh` — run existing tests (update if needed for
   new flag syntax)
