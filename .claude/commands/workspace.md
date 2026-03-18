# Workspace — Create or Resume a Garth Workspace

You are helping the user start a Garth workspace for a coding task.

## Input

The user's task description (and optional flags) is: $ARGUMENTS

## Instructions

### 1. Parse input

Extract from `$ARGUMENTS`:
- **Task description**: the natural-language description of what the user wants to work on
- **Target repo**: which repository the work belongs in (see below)
- **`--auto` flag**: if present, skip confirmations and act autonomously
- **`--base <ref>` flag**: if present, use as the base ref for the new branch

If `$ARGUMENTS` is empty, ask the user what they want to work on before
proceeding.

### 1b. Identify the target repo

**Do NOT default to the current directory (`.`) or the garth repo.** The user
often invokes `/workspace` from within garth but intends to work in a different
repo.

- If the task description names a project or repo (e.g., "simplex-infra",
  "virgil"), resolve it under `~/Documents/<name>`. Verify the directory exists
  before proceeding.
- If the task description is ambiguous, **ask the user** which repo to target.
- Only use `.` if the user explicitly says "this repo" or "garth".

### 2. Generate a branch name

From the task description, generate a branch name following this convention:
- **Prefix**: choose the most appropriate from `feature/`, `fix/`, `refactor/`,
  `docs/`, `test/`, `chore/`
- **Body**: 2-4 lowercase hyphen-joined words summarizing the task
- **Max length**: 50 characters total (including prefix)
- **Examples**: `feature/api-auth`, `fix/login-timeout`,
  `refactor/config-parser`, `docs/setup-guide`

### 3. Housekeeping and conflict check

First, run `garth gc` to clear any stopped sessions or orphaned resources.
Briefly report what was cleaned (if anything).

Then check for conflicts:
```bash
garth ps
git -C <repo-path> branch --list '*<branch-body-pattern>*'
```

Look for:
- An existing Garth session on a matching or similar branch
- An existing git branch with the same or similar name

### 4. Resume or create

**If a matching session exists:**
- In `--auto` mode: resume it directly with `garth open <session-id>`
- Otherwise: tell the user about the existing session and offer to resume it

**If a matching branch exists but no session:**
- Offer to open it with `garth open -d <repo-path> <branch>`

**If no match found:**
- In `--auto` mode: run `garth new <repo-path> <branch>` directly (add
  `--base <ref>` if specified)
- Otherwise: show the proposed branch name, target repo, and `garth new`
  command, then ask the user to confirm before running

### 5. Verify

After running the garth command, run `garth ps` to confirm the session is
active. Report the session ID and status to the user.

## Cleaning up workspaces

When the user asks to clean up a workspace, follow these steps:

1. **Stop the session**: `garth stop <id> --clean`
2. **Remove the worktree**: `git -C <repo-path> worktree remove <worktree-path>`
3. **Delete the branch**: try `git -C <repo-path> branch -d <branch>` first

If `git branch -d` fails with "not fully merged", the branch was likely
**squash-merged** via a PR. Squash merges rewrite history so git cannot detect
that the changes are already in main. To verify:

```bash
gh pr list --repo <owner>/<repo> --head <branch> --state merged --json number,title,state
```

If a merged PR is found, the branch is safe to force-delete with
`git branch -D <branch>`. Do **not** prompt the user for confirmation in this
case — just delete it and note it was squash-merged.

If no merged PR is found and the branch has unmerged commits, **ask the user**
before force-deleting.

## Error handling

- **`garth` not on PATH**: fall back to `bin/garth` (relative to repo root)
- **Command failure**: suggest running `garth doctor --repo .` to diagnose
- **`garth` not found at all**: suggest running `./setup.sh` to bootstrap

## CLI resolution

Always try `garth` first. If it fails with "command not found", retry with
`bin/garth`. Mention this fallback to the user if it occurs.
