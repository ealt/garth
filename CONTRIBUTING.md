# Contributing to Garth

Thanks for your interest in contributing. This guide covers the development
workflow from setup through PR submission.

For architecture details, module documentation, and naming conventions, see
[`AGENTS.md`](AGENTS.md).

## Development Setup

```bash
# Clone and bootstrap
git clone <repo-url> && cd garth
./setup.sh --yes

# Verify everything works
bin/garth doctor --repo .
```

Prerequisites: `git`, `python3` (3.11+), `op` (1Password CLI), `zellij`,
`docker`. See [`README.md`](README.md#prerequisites) for details.

## Development Workflow

### Making Changes

1. Create a feature branch from `main`
2. Make your changes
3. Run syntax checks and all smoke tests (see below)
4. Open a PR

### Syntax Checks

Run these before every commit:

```bash
# Shell syntax (all modules)
bash -n bin/garth lib/*.sh

# Python syntax
python3 -m py_compile lib/config-parser.py
```

### Running Tests

Run all smoke tests before opening a PR:

```bash
bash tests/config_parser_smoke.sh
bash tests/git_helpers_smoke.sh
bash tests/zellij_layout_smoke.sh
bash tests/session_helpers_smoke.sh
bash tests/cli_open_smoke.sh
bash tests/refresh_images_smoke.sh
```

### One-Command Check

Run `make check` to lint and test everything at once. This is the recommended
pre-PR command:

```bash
make check
```

CI runs the same checks automatically on every PR.

Each test prints `<name>_smoke: ok` on success and exits non-zero on failure.

### Docker Rebuilds

After changes to `docker/Dockerfile` or the seccomp profile:

```bash
docker build --target claude -t garth-claude:latest docker/
docker build --target codex -t garth-codex:latest docker/
```

Or run `garth refresh-images --agents claude,codex` (equivalent forced rebuild),
or let `garth setup` rebuild automatically.

## Testing

### Smoke Test Pattern

Tests live in `tests/` and follow a consistent pattern:

1. **Source modules directly** — `source lib/common.sh`, etc.
2. **Stub external dependencies** — mock functions for `docker`, `op`, `zellij`,
   and other tools that aren't under test
3. **Exercise functions** — call target functions with known inputs
4. **Assert results** — use `grep -q` and `[[ ]]` for assertions
5. **Print success** — echo `<name>_smoke: ok` at the end

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh

# Stub
docker() { echo "mock"; }

# Test
result="$(garth_slugify_branch "feature/my-branch")"
[[ "$result" == "feature__my-branch" ]] || { echo "FAIL"; exit 1; }

echo "my_module_smoke: ok"
```

### Adding New Tests

- Name the file `tests/<module>_smoke.sh`
- Source only the modules under test plus their dependencies
- Keep tests deterministic: no network calls, no Docker daemon required
- Test edge cases (empty strings, long inputs, special characters)

## Pull Request Process

### Pre-PR Checklist

- [ ] `bash -n bin/garth lib/*.sh` passes
- [ ] `python3 -m py_compile lib/config-parser.py` passes
- [ ] All smoke tests pass
- [ ] `bin/garth doctor --repo .` passes
- [ ] README/docs updated if CLI behavior changed

### PR Description

Include in every PR:

- **What** changed and **why**
- **Config/security impact** — any changes to `config.example.toml`,
  `docker/seccomp-profile.json`, or the auth flow
- **Tests run** — commands executed and key outputs

## Code Style

Bash and Python style conventions are documented in
[`AGENTS.md`](AGENTS.md#coding-style). The short version:

- Bash: `set -euo pipefail`, 2-space indent, `snake_case`, explicit `local`
- Python: stdlib only, `snake_case`, zero external deps

## Commit Messages

Use imperative, concise subject lines:

- `Add token cache to avoid repeated 1Password prompts`
- `Fix worktree path collision when branch names overlap`
- `Refactor container arg assembly into helper functions`

Keep commits logically scoped. Don't mix unrelated refactors with behavior
changes.
