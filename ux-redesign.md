# Garth: Branch, Worktree & Session UX Redesign

## Context

When running `garth boot <dir>`, the tool silently uses whatever git branch
happens to be checked out, provides no visibility into existing worktrees or
sessions, and requires a separate `garth worktree` command for worktree
management. This makes it easy to accidentally boot on the wrong branch, hard to
discover or reuse existing state, and forces the user to think in terms of
infrastructure (branches, worktrees, containers, sessions) rather than intent
("I want to start something new" or "I want to look at this repo").

The goal is to redesign the CLI surface so that:
1. Users can express high-level intent with a single command (`new`, `open`)
2. An interactive wizard (`up`) guides users when they don't know exactly what
   they want
3. Every parameter can be explicitly controlled via flags for power users and
   scripting
4. The four layers of state (branch, worktree, container, session) are visible
   and manageable

## Commands

### `garth new <dir> <name> [--base <ref>]`

"I'm starting something new." Creates everything fresh.

- Creates branch `<name>` (must not already exist; error if it does, pointing
  to `garth open`)
- `--base` defaults to the repo's auto-detected default branch (via
  `git symbolic-ref refs/remotes/origin/HEAD`, with config override, falling
  back to main/master)
- Creates worktree, container, session — all derived from `<name>`
- No prompts, no wizard
- Validates `--base` ref exists before creating anything; on failure, lists
  available branches

Equivalent to:
`garth up <dir> --new-branch <name> [--base <ref>] --auto-worktree --auto-session`

### `garth open <dir> [<branch>]`

"I want to look at / work on something existing."

- `<branch>` must already exist locally or on the remote; error with "did you
  mean?" suggestions if not found
- If the branch exists only on the remote, Garth fetches and creates a local
  tracking branch (like `git checkout <branch>` does automatically). When
  multiple remotes contain the same branch name, `origin` wins by default.
  A `--remote <name>` flag can override this for repos with multiple remotes
- Defaults to the repo's default branch if omitted
- If a live session exists for that branch, reattaches (idempotent)
- If a worktree exists for that branch, reuses it
- Creates worktree/container/session as needed for anything that doesn't exist
- No prompts, no wizard

Session lookup for reattachment is by repo + branch (not by session ID or name).
The session state files store both `repo_root` and `branch`, so Garth queries:
"find sessions where repo matches and branch matches." This is how idempotent
reattach works despite session IDs being random.

Equivalent to:
`garth up <dir> --branch <branch> --auto-worktree --auto-session`

### `garth up <dir> [flags]`

The universal command. Interactive wizard with no flags, fully explicit with all
flags, or anywhere in between.

#### Interactive wizard (no flags, or partial flags)

Three sequential steps. Each step shows numbered options; the user picks a
number or hits Enter for the default. Steps for which an explicit flag was
provided are skipped.

**Step 1: Branch**
```
Branch:
  1) feature/auth        * checked out
  2) main                  default
  3) docs/update
  4) feature/old-thing
[1] > _
```
- Default: currently checked out branch
- Typing a non-number string creates a new branch with that name
- If a new branch name is entered, a follow-up prompt asks for the base ref
  (as a numbered list of branches; default is the currently checked out branch,
  with the repo's default branch as the second option if different)

**Step 2: Worktree**

Adapts based on step 1. If a worktree exists for the selected branch:
```
Worktree:
  1) wt/feature__auth      exists
  2) New worktree
  3) No worktree
[1] > _
```

If no worktree exists:
```
Worktree:
  1) Create worktree       recommended
  2) No worktree
[1] > _
```

**Step 3: Session**

If a live/detached session exists for the branch/worktree:
```
Session:
  1) garth-simplex-docs-feature__auth  a1b2c3  detached  2h ago
  2) New session
[1] > _
```

If no session exists, just creates one (still shown as a step, not skipped):
```
Session:
  1) New session
[1] > _
```

If no TTY is detected and the wizard would need to prompt, error with:
"Interactive mode requires a terminal. Use --auto or explicit flags."

#### Explicit flags

**Selecting specific values (accept only literal identifiers):**
- `--branch <name>` — use this existing branch
- `--worktree <path>` — use this specific worktree path
- `--session <name>` — use this specific session

**Creating new resources:**
- `--new-branch <name>` — create a new branch (must not exist)
- `--base <ref>` — base ref for `--new-branch` (default: repo's default branch)
- `--new-worktree` — force create a new worktree even if one exists
- `--new-session` — force create a new session even if one exists

**Using wizard defaults without interaction:**
- `--auto-branch` — use wizard default (current branch)
- `--auto-worktree` — reuse if exists, create if not
- `--auto-session` — resume if exists, create if not
- `--auto` — all of the above

**Opting out:**
- `--no-worktree` — boot in-place, no worktree

### `garth ps`

List all sessions. One row per session, columnar output.

```
ID       SESSION                              REPO                   BRANCH         WORKTREE             AGENTS         STATUS     UPTIME
a1b2c3   garth-simplex-docs-feature__auth     simplex-documentation  feature/auth   wt/feature__auth     claude,codex   running    2h
d4e5f6   garth-simplex-docs-main              simplex-documentation  main           -                    claude         stopped    1d
```

- `-q` (quiet) flag outputs just session IDs, one per line, no header — for
  piping: `garth ps -q | xargs garth stop`
- Default output includes a header row (human-readable)
- Session IDs are random short hashes (like Docker container IDs)
- Status reflects real state by checking Zellij sessions, Docker containers,
  and state files — not just reading Garth's own records

**Status model (precedence order):**
- `running` — Zellij session alive and attached, all containers running
- `running(?)` — Zellij session alive, all containers running, but attachment
  state could not be determined (avoids silently hiding detachment)
- `detached` — Zellij session alive but confirmed not attached
- `stopped` — explicitly stopped via `garth stop`; worktree and state preserved
- `degraded` — layers out of sync; brief reason appended in output, e.g.:
  `degraded (container exited)`, `degraded (zellij gone, containers alive)`

### `garth containers <id>`

Output container IDs for a session, one per line. Designed for piping:

```bash
garth containers a1b2c3 | xargs docker logs
```

### `garth stop <id>`

Stop a session's Zellij session and Docker containers. Preserve worktree,
branch, and session state files. Session shows as "stopped" in `garth ps`.

Short prefix matching on IDs (like Docker): `garth stop a1b`. If the prefix is
ambiguous (matches multiple sessions), error: "Multiple sessions match prefix
'a1b'. Be more specific." Never guess on ambiguity.

### `garth down <id> [-y]`

Remove everything: containers, Zellij session, session state, and worktree.

- Warns before deleting worktree if there's uncommitted/unpushed work
- Shows what will be deleted and gives the user the opportunity to abort
- `-y` skips the warning

Short prefix matching on IDs. Same ambiguity error behavior as `garth stop`.

### `garth doctor`

Health checks and repair. Finds orphaned containers, stale state files,
mismatches between layers. Offers to clean up.

(Existing command — expanded to cover the new state model.)

## Commands Removed

- `garth boot` — replaced by `garth up`, `garth new`, `garth open`
- `garth worktree` — functionality absorbed into `garth new` and `garth up`

## Info Output

All commands that launch a workspace (`new`, `open`, `up`) print a clear
summary before starting:

```
[info] Repo:      simplex-documentation (owner/simplex-documentation)
[info] Branch:    feature/auth
[info] Worktree:  wt/feature__auth (created|reused|none)
[info] Session:   garth-simplex-docs-feature__auth  a1b2c3  (new|resumed)
[info] Agents:    claude, codex
```

If degraded state is detected for the repo, a warning is shown with a pointer
to `garth doctor`:

```
[warn] Orphaned containers found for simplex-documentation (run 'garth doctor' to clean up)
```

## Default Branch Detection

Used by `garth new` (default `--base`), `garth open` (default branch), and the
wizard (labeling the default branch).

Resolution order:
1. Config value: `[defaults] default_branch = "main"` in config.toml
2. Auto-detect: `git symbolic-ref refs/remotes/origin/HEAD`
3. Fallback: `main`, then `master`

## Session IDs

- Random short hashes generated at session creation
- Stored in session state directory
- Support prefix matching for all commands that accept IDs (`stop`, `down`,
  `containers`, etc.)
- Ambiguous prefixes always error — never guess

## Session Lookup for Reattachment

`garth open` and the wizard's "resume session" option need to find existing
sessions for a given repo + branch. This is done by scanning session state
directories and matching on `repo_root` + `branch` fields. Session IDs and
session names are for human reference and CLI targeting — they are not the
lookup key for reattachment.

**Multiple sessions for the same repo+branch** (possible via `--new-session` or
if a previous session was stopped but not downed):
- `garth open` auto-selects the best candidate: running/detached sessions are
  preferred over stopped ones, and among those, the most recently started wins.
- The wizard in `garth up` shows all matching sessions and lets the user pick.

## Status Precedence

When multiple status signals conflict, the following precedence applies
(highest wins):

1. `degraded` — always wins; indicates something needs attention regardless of
   other signals. E.g., `garth stop` ran but cleanup partially failed, leaving
   an orphaned container → `degraded`, not `stopped`.
2. `running` / `running(?)` / `detached` — session is actively alive.
3. `stopped` — session was intentionally stopped; all resources properly halted.

This ensures `garth ps` output is deterministic: each session maps to exactly
one status based on real-state inspection, with degraded always surfaced.

## Error Handling

- `garth new` with an existing branch name: error, point to `garth open`
- `garth new` with invalid `--base`: error, list available branches
- `garth open` with nonexistent branch: error, suggest close matches (like git's
  "did you mean?" behavior)
- `garth open` with remote-only branch: fetch and create local tracking branch
  (`origin` wins by default; `--remote <name>` overrides when the branch exists
  on multiple remotes)
- `garth up` wizard with no TTY and no explicit/auto flags: error, suggest
  `--auto` or explicit flags
- `garth up` with conflicting flags (e.g., `--branch` + `--new-branch`): error
  with explanation
- Ambiguous session ID prefix: error listing matches, ask user to be more
  specific

## Files to Modify

- `bin/garth` — main CLI: replace `cmd_boot`/`cmd_worktree` with `cmd_new`,
  `cmd_open`, `cmd_up`; add `cmd_ps`, `cmd_containers`, `cmd_down`; refactor
  `cmd_stop`; add session ID generation and prefix matching
- `lib/git.sh` — add `garth_git_default_branch()`, add
  `garth_git_find_worktree_for_branch()`
- `lib/session.sh` (new) — session state logic extracted from `bin/garth`
  (`session_dir_for`, `write_state_value`, `read_state_value`) plus new
  `garth_find_sessions_for_branch()`, session ID generation, prefix matching
- `lib/common.sh` — add wizard/prompt utilities (numbered selection, text input,
  TTY detection)
- `lib/container.sh` — add `garth_list_containers_for_session()` for
  `garth containers` command
- `config.example.toml` — add `default_branch` option under `[defaults]`
- `lib/config-parser.py` — parse new config field

## Verification

- `garth new <dir> test-feature` creates branch + worktree + container + session
- `garth new <dir> test-feature` again errors with "branch already exists"
- `garth new <dir> test-feature --base nonexistent` errors with branch list
- `garth open <dir> test-feature` reattaches to the session created above
- `garth open <dir>` with no branch opens the default branch
- `garth open <dir> nonexistent` errors with suggestions
- `garth open <dir> remote-only-branch` fetches and creates tracking branch
- `garth up <dir>` with no flags launches the interactive wizard
- `garth up <dir> --auto` uses defaults without prompting
- `garth up <dir> --branch test-feature` skips step 1, prompts for steps 2-3
- `garth up <dir> --branch X --new-branch Y` errors with conflict explanation
- `garth ps` shows the session with correct status, repo, branch, worktree
- `garth ps -q` outputs just IDs with no header
- `garth ps -q | xargs garth stop` works end-to-end
- `garth containers <id>` outputs container IDs
- `garth stop <id>` stops session, `garth ps` shows it as stopped
- `garth stop <ambiguous-prefix>` errors with list of matches
- `garth down <id>` removes everything, `garth ps` no longer shows it
- `garth down <id>` warns if worktree has uncommitted work
- `garth down <id> -y` skips the warning
- No-TTY detection: `echo | garth up <dir>` errors with helpful message
- Shell syntax check: `bash -n bin/garth lib/*.sh`
- Existing smoke tests adapted for new command names
