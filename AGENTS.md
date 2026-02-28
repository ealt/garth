# Repository Guidelines

## Project Structure & Module Organization
`garth` is a Bash-first CLI with a small Python config helper.

- `bin/garth`: main entrypoint and command routing (`boot`, `setup`, `doctor`, etc.).
- `lib/*.sh`: core modules (`container.sh`, `workspace.sh`, `zellij.sh`, `git.sh`, `secrets.sh`, `github-app.sh`).
- `lib/config-parser.py`: TOML config validation/env export helper.
- `tests/*_smoke.sh`: smoke tests for config parsing, git helpers, and Zellij layout generation.
- `docker/`: Dockerfile and seccomp profile for sandboxed agent runtime.
- `docs/`: focused setup docs (for example GitHub App wiring).
- `config.example.toml`: baseline config; copy to repo-local `config.toml` (gitignored).

## Build, Test, and Development Commands
- `./setup.sh` (or `./setup.sh --yes`): bootstrap local setup and validate config.
- `bin/garth setup`: interactive setup flow.
- `bin/garth doctor --repo .`: validate auth/config/runtime prerequisites.
- `bash tests/config_parser_smoke.sh`
- `bash tests/git_helpers_smoke.sh`
- `bash tests/zellij_layout_smoke.sh`
- `bash -n bin/garth lib/*.sh`: fast shell syntax check before opening a PR.
- `python3 -m py_compile lib/config-parser.py`: quick Python syntax check.

## Coding Style & Naming Conventions
- Bash scripts should start with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Use 2-space indentation in Bash; prefer small functions with explicit local variables.
- Use `snake_case` for function names and variables in Bash/Python.
- Keep command names and test scripts descriptive: `*_smoke.sh` for smoke coverage.
- Favor clear, defensive error messages (`garth_die`) over silent failures.

## Testing Guidelines
- Tests are smoke-style shell scripts; keep them deterministic and fast.
- Add/extend a `tests/*_smoke.sh` script for every behavior change in `bin/` or `lib/`.
- Run all smoke tests locally before PR submission, plus relevant `garth doctor` checks.

## Commit & Pull Request Guidelines
- Follow existing commit style: imperative, concise subject lines (for example `Add ...`, `Fix ...`, `Refactor ...`, `Enhance ...`).
- Keep commits logically scoped; avoid mixing unrelated refactors with behavior changes.
- PRs should include what changed and why.
- PRs should call out config/security impact (`config.example.toml`, `docker/seccomp-profile.json`, auth flow).
- PRs should list commands/tests run with key outputs.
- PRs should update README/docs when CLI behavior changes.
