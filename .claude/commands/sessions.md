# Sessions — List and Manage Garth Sessions

You are helping the user view and manage their Garth sessions.

## Input

Optional session ID or filter: $ARGUMENTS

## Instructions

### 1. List sessions

Run `garth ps` (or `bin/garth ps` if not on PATH) and parse the output.

### 2. Present sessions grouped by status

Organize sessions into these groups, in this order:
1. **Degraded** — highlight these prominently, they need attention
2. **Running / Attached** — currently active sessions
3. **Detached** — running but not attached
4. **Stopped** — inactive sessions

For each session, show: session ID, branch/name, status, and any notable
details from the output.

### 3. Focus on a specific session

If `$ARGUMENTS` contains a session ID (6-char hex like `a1b2c3`), focus on
that session:
- Show its full details
- Offer contextual actions based on its status

### 4. Offer contextual actions

Based on each session's status, offer the user relevant actions:

| Status | Available actions |
|--------|-------------------|
| **Degraded** | Recover (suggest `/recover`), stop, force down |
| **Running** | Open (`garth open <id>`), stop |
| **Detached** | Open (`garth open <id>`), stop, down |
| **Stopped** | Open (`garth open <id>`), down (remove) |

If there are stopped sessions that look stale (no recent activity), proactively
suggest cleaning them up with `garth down <id>` or `garth gc`.

### 5. Execute requested actions

When the user picks an action:
- **Open**: `garth open <session-id>`
- **Stop**: prefer `garth stop <session-id> --clean` unless the user explicitly
  wants to preserve state for later resume
- **Down**: confirm first (destructive), then `garth down <session-id>`
- **Recover**: suggest running `/recover <session-id>`

After executing, re-run `garth ps` to show updated state.

## CLI resolution

Always try `garth` first. If it fails with "command not found", retry with
`bin/garth`.
