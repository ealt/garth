# CLAUDE.md

Garth is a secure multi-project workspace orchestrator for autonomous AI coding
agents. Bash-first CLI that boots Docker-sandboxed workspaces, mints short-lived
GitHub App tokens through 1Password, and manages Zellij terminal sessions with
per-agent panes.

## Agent Reference

All architecture details, module documentation, security model, naming
conventions, coding style, and testing guidelines live in
[`AGENTS.md`](AGENTS.md).

## Quick Commands

```bash
./setup.sh --yes                           # bootstrap
garth up .                                 # interactive launcher
garth new . feature/my-feature             # new branch + worktree + session
garth open -d .                            # open default branch
garth open a1b2c3                          # resume by session ID
garth ps                                   # list sessions
garth refresh-images --agents claude       # rebuild one Docker image
garth doctor --repo .                      # validate prerequisites
bash tests/config_parser_smoke.sh          # run config tests
bash tests/git_helpers_smoke.sh            # run git tests
bash tests/zellij_layout_smoke.sh          # run layout tests
bash tests/session_helpers_smoke.sh        # run session tests
bash tests/cli_open_smoke.sh              # run CLI open tests
bash tests/refresh_images_smoke.sh         # run Docker refresh CLI test
bash -n bin/garth lib/*.sh                 # shell syntax check
python3 -m py_compile lib/config-parser.py # Python syntax check
```

## Slash Commands

Claude Code slash commands for workspace management. Use these inside Claude
Code to interact with Garth via natural language.

| Command | Arguments | Description |
|---------|-----------|-------------|
| `/workspace` | `<task description> [--auto] [--base <ref>]` | Create or resume a workspace for a task |
| `/sessions` | `[session-id]` | List and manage Garth sessions |
| `/recover` | `[session-id] [--auto]` | Diagnose and fix degraded sessions |
| `/cleanup` | `[--auto] [--dry-run] [--deep]` | Clean up stale resources |

### Autonomy mode

Pass `--auto` to any command to skip confirmations. Maps to Garth's `--yes`
flag for destructive operations. Without `--auto`, commands present plans and
ask before acting.

### CLI resolution order

Commands try `garth` on PATH first, then fall back to `bin/garth` (relative to
repo root). If neither is found, they suggest running `./setup.sh`.
