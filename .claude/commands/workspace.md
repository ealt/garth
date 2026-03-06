# Workspace — Create or Resume a Garth Workspace

You are helping the user start a Garth workspace for a coding task.

## Input

The user's task description (and optional flags) is: $ARGUMENTS

## Instructions

### 1. Parse input

Extract from `$ARGUMENTS`:
- **Task description**: the natural-language description of what the user wants to work on
- **`--auto` flag**: if present, skip confirmations and act autonomously
- **`--base <ref>` flag**: if present, use as the base ref for the new branch

If `$ARGUMENTS` is empty, ask the user what they want to work on before
proceeding.

### 2. Generate a branch name

From the task description, generate a branch name following this convention:
- **Prefix**: choose the most appropriate from `feature/`, `fix/`, `refactor/`,
  `docs/`, `test/`, `chore/`
- **Body**: 2-4 lowercase hyphen-joined words summarizing the task
- **Max length**: 50 characters total (including prefix)
- **Examples**: `feature/api-auth`, `fix/login-timeout`,
  `refactor/config-parser`, `docs/setup-guide`

### 3. Check for existing sessions and branches

Run these commands to detect conflicts:
```bash
garth ps
git branch --list '*<branch-body-pattern>*'
```

Look for:
- An existing Garth session on a matching or similar branch
- An existing git branch with the same or similar name

### 4. Resume or create

**If a matching session exists:**
- In `--auto` mode: resume it directly with `garth open <session-id>`
- Otherwise: tell the user about the existing session and offer to resume it

**If a matching branch exists but no session:**
- Offer to open it with `garth open -d . <branch>`

**If no match found:**
- In `--auto` mode: run `garth new . <branch>` directly (add
  `--base <ref>` if specified)
- Otherwise: show the proposed branch name and `garth new` command, then ask
  the user to confirm before running

### 5. Verify

After running the garth command, run `garth ps` to confirm the session is
active. Report the session ID and status to the user.

## Error handling

- **`garth` not on PATH**: fall back to `bin/garth` (relative to repo root)
- **Command failure**: suggest running `garth doctor --repo .` to diagnose
- **`garth` not found at all**: suggest running `./setup.sh` to bootstrap

## CLI resolution

Always try `garth` first. If it fails with "command not found", retry with
`bin/garth`. Mention this fallback to the user if it occurs.
