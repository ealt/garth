# Cleanup — Clean Up Unused Garth Resources

You are helping the user clean up stale or unused Garth resources.

## Input

Optional flags: $ARGUMENTS

Supported flags:
- `--auto` — clean everything non-active without confirmation
- `--dry-run` — survey and report what would be cleaned, but take no action
- `--deep` — include deep doctor checks and orphan detection

## Quick path

For routine cleanup, `garth gc` handles the common cases non-interactively
(stopped state dirs, orphan Zellij/Docker, `[gone]` branches). Use this slash
command for a more thorough, interactive sweep.

## Instructions

### 1. Survey current state

Run these commands to assess the environment:
```bash
garth ps
garth doctor --repo .
```

If `--deep` flag is present, also run:
```bash
garth doctor --repo . --deep
docker ps -a --filter "name=garth-" --format '{{.Names}} {{.Status}}'
zellij list-sessions 2>/dev/null || true
ls "$XDG_STATE_HOME/garth/sessions/" 2>/dev/null || ls ~/.local/state/garth/sessions/ 2>/dev/null || true
```

### 2. Categorize resources

Group discovered resources into these categories:

| Category | Description | Risk |
|----------|-------------|------|
| **Stopped sessions** | Sessions with "stopped" status | Low — safe to remove |
| **Degraded sessions** | Sessions with "degraded" status | Medium — may need recovery first |
| **Orphan containers** | Docker containers with `garth-` prefix that don't belong to any active session | Low — safe to remove |
| **Orphan Zellij sessions** | Zellij sessions matching `garth-*` with no corresponding Garth session | Low — safe to remove |
| **Orphan state dirs** | State directories with no corresponding active session | Low — safe to remove |

### 3. Present the cleanup plan

For each category with items found:
- List the resources (session IDs, container names, paths)
- Show the count and estimated action
- Mark the risk level

If `--dry-run` is set, stop here — present the report and exit.

### 4. Execute cleanup

**In `--auto` mode:**
- Clean all categories except active/running sessions
- Use `garth down <id> -y` for stopped sessions
- Use `garth stop <id>` then `garth down <id> -y` for degraded sessions
- Use `docker rm -f` for orphan containers
- Use `zellij kill-session` for orphan Zellij sessions
- Remove orphan state directories

**In default (interactive) mode:**
- Ask the user which categories they want to clean
- Confirm before executing each category
- For degraded sessions, suggest running `/recover` first

### 5. Report results

After cleanup, run `garth ps` to show the final state. Summarize what was
removed and what remains.

## CLI resolution

Always try `garth` first. If it fails with "command not found", retry with
`bin/garth`.
