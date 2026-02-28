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
garth boot .                               # launch workspace
garth doctor --repo .                      # validate prerequisites
bash tests/config_parser_smoke.sh          # run config tests
bash tests/git_helpers_smoke.sh            # run git tests
bash tests/zellij_layout_smoke.sh          # run layout tests
bash -n bin/garth lib/*.sh                 # shell syntax check
python3 -m py_compile lib/config-parser.py # Python syntax check
```
