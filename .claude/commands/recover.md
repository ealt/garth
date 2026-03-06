# Recover — Diagnose and Fix Degraded Sessions

You are helping the user recover degraded Garth sessions.

## Input

Optional target session ID or `--auto` flag: $ARGUMENTS

## Instructions

### 1. Find degraded sessions

Run `garth ps` (or `bin/garth ps` if not on PATH) and identify sessions with
"degraded" status.

If `$ARGUMENTS` contains a session ID, focus only on that session. If no
degraded sessions are found, tell the user everything looks healthy.

### 2. Diagnose each degraded session

For each degraded session, gather additional diagnostic information:
```bash
garth containers <session-id>
docker ps -a --filter "name=<session-name>" --format '{{.Names}} {{.Status}}'
zellij list-sessions 2>/dev/null || true
garth doctor --repo .
```

Classify the degradation type:

| Type | Indicators |
|------|------------|
| **Token refresh degraded** | Token refresh process failed or token expired |
| **Container exited** | Docker container exited unexpectedly |
| **Stop incomplete** | Session partially stopped, lingering containers |
| **Zellij gone** | Zellij session missing but state thinks it's running |
| **State mismatch** | State file inconsistent with actual Docker/Zellij state |

### 3. Apply recovery strategy

For each degradation type:

- **Token refresh degraded**: stop the session, then re-open it (mints a fresh
  token on open)
  ```bash
  garth stop <id>
  garth open <id>
  ```

- **Container exited**: stop and re-open
  ```bash
  garth stop <id>
  garth open <id>
  ```

- **Stop incomplete**: stop again, then force-remove any lingering containers
  ```bash
  garth stop <id>
  docker rm -f $(garth containers <id>) 2>/dev/null || true
  ```

- **Zellij gone**: stop and re-open
  ```bash
  garth stop <id>
  garth open <id>
  ```

- **State mismatch**: run doctor, stop, then re-open. If that fails, down and
  recreate
  ```bash
  garth doctor --repo .
  garth stop <id>
  garth open <id>
  ```

### 4. Autonomy mode

If `--auto` is present in `$ARGUMENTS`:
- Apply the recovery strategy immediately for all degraded sessions
- Do not ask for confirmation between steps

Otherwise:
- Present the diagnosis and proposed recovery plan
- Ask the user to confirm before each recovery action

### 5. Verify recovery

After recovery, run `garth ps` and confirm the session is no longer degraded.
Report the final status to the user.

## CLI resolution

Always try `garth` first. If it fails with "command not found", retry with
`bin/garth`.
