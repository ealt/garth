# Plan: `garth` CLI — Secure Multi-Project Agent Workspace Orchestrator

> **garth** — from Old Norse *garðr* ("enclosure"), the root of *garden*, *yard*,
> and *guard*. A garth is the protected courtyard within walls — the enclosed
> workspace where controlled work happens.
>
> *Walled workspaces for autonomous agents.*

## Context

Running autonomous coding agents (Claude Code, Codex, OpenCode, Gemini CLI) with
the full shell environment means agent == user: they inherit SSH keys, GitHub CLI
auth, AWS creds, and full filesystem access. Meanwhile, managing multiple
concurrent projects/tasks across windows is a chaotic mess of context switching.

This plan builds a single CLI that:

1. Boots isolated project workspaces (Cursor + browser launch + Zellij layout)
2. Runs agents in Docker containers (only the worktree mounted, no host secrets)
3. Uses GitHub App installation tokens (minted on demand, 1hr expiry, via 1Password)
4. Supports git worktrees for parallel tasks in the same repo

Location: `/Users/ericalt/Documents/toolchain/garth/` (part of toolchain repo).

---

## File Structure

```
toolchain/garth/
├── bin/
│   └── garth                       # Main CLI entrypoint (bash)
├── lib/
│   ├── common.sh                  # Logging, config parsing, shared utils
│   ├── git.sh                     # Git repo/worktree detection & helpers
│   ├── workspace.sh               # Browser, Cursor, Ghostty launchers
│   ├── zellij.sh                  # Zellij session & layout generation
│   ├── container.sh               # Docker container build/run lifecycle
│   ├── github-app.sh              # JWT generation & installation token minting
│   ├── secrets.sh                 # 1Password CLI (`op`) wrapper
│   └── config-parser.py           # TOML → shell vars (Python 3.12+ tomllib)
├── docker/
│   └── Dockerfile                 # Multi-stage agent sandbox image
├── config/
│   └── garth.example.toml          # Example user configuration
└── README.md                      # Complete setup & usage guide
```

---

## CLI Subcommands

### `garth boot <dir> [flags]`

The primary workflow. Resolves git context, mints credentials, generates a Zellij
layout, and launches the full workspace.

**Sequence:**

1. Resolve `<dir>` to absolute path, validate git repo
2. Detect repo root, branch, worktree status
3. Derive GitHub HTTPS URL from remote (support `git@` and `https://` formats)
4. Mint GitHub App installation token via 1Password → `lib/github-app.sh`
5. Retrieve agent API keys from 1Password → `lib/secrets.sh`
6. Generate a Zellij layout KDL file (temporary) with panes for:
   - User shell (cd'd to worktree)
   - Each requested agent running via `docker run -it` with scoped credentials
7. Launch Zellij: `zellij -s "garth-<repo>-<branch>" --layout <generated.kdl>`
8. Open Cursor: `open -a "Cursor" "$dir"`
9. Open browser: engine-specific launch with optional per-project profile isolation

**Flags:** `--agents claude,codex` (default from config), `--no-sandbox`,
`--network on|off`, `--dry-run`, `--yes`

### `garth worktree <repo-dir> <branch> [--from <base>]`

Create a git worktree at `<repo>/wt/<branch>`, then call `garth boot` on it.

### `garth agent <dir> <name> [--sandbox docker|none] [--network on|off]`

Run a single agent in a container for the given directory. Used internally by
`garth boot` and also directly for re-launching an agent.

### `garth token <dir>`

Mint and print a GitHub App installation token for the repo containing `<dir>`.
Useful for piping into other tools or manual use.

### `garth status`

Show running Zellij sessions, Docker containers, and active worktrees managed by
`garth`.

### `garth stop <session>`

Kill agent containers and Zellij session for a project. Does NOT delete worktrees.

### `garth setup`

Guided first-time setup: check prerequisites, guide GitHub App creation, store
credentials in 1Password, build Docker image, link `garth` to PATH.

---

## Zellij Layout Generation

Zellij's declarative KDL layouts replace all tmux scripting. `garth boot` generates
a layout file dynamically (since it contains runtime values like paths and docker
commands), then launches Zellij with it.

**Generated layout for 2 agents (e.g., claude + codex):**

```kdl
layout {
    tab name="dev" focus=true {
        pane split_direction="vertical" size="100%" {
            pane name="claude" size="50%" command="docker" {
                args "run" "-it" "--rm"
                     "--name" "garth-myrepo-claude"
                     "-v" "/path/to/worktree:/work"
                     "-w" "/work"
                     "-e" "GITHUB_TOKEN=ghs_xxx"
                     "-e" "ANTHROPIC_API_KEY=sk-xxx"
                     "-e" "TERM=xterm-256color"
                     "garth-claude:latest"
                     "claude" "--dangerously-skip-permissions"
            }
            pane split_direction="horizontal" size="50%" {
                pane name="codex" size="60%" command="docker" {
                    args "run" "-it" "--rm"
                         "--name" "garth-myrepo-codex"
                         "-v" "/path/to/worktree:/work"
                         "-w" "/work"
                         "-e" "GITHUB_TOKEN=ghs_xxx"
                         "-e" "OPENAI_API_KEY=sk-xxx"
                         "-e" "TERM=xterm-256color"
                         "garth-codex:latest"
                         "codex" "exec" "--dangerously-bypass-approvals-and-sandbox"
                }
                pane name="shell" size="40%" cwd="/path/to/worktree"
            }
        }
    }
}
```

**For single agent:**

```kdl
layout {
    tab name="dev" focus=true {
        pane split_direction="horizontal" size="100%" {
            pane name="claude" size="65%" command="docker" { ... }
            pane name="shell" size="35%" cwd="/path/to/worktree"
        }
    }
}
```

The layout file is written to a temp dir and cleaned up on exit. Zellij's named
sessions (`-s`) allow `garth status` and `garth stop` to find/manage them.

---

## Docker Sandbox

### Dockerfile (multi-stage, one target per agent)

```
toolchain/garth/docker/Dockerfile
```

- **Base stage**: Ubuntu 24.04 + git, curl, jq, openssl, Node.js 22 LTS, Python 3
- **Per-agent stages**: `FROM base AS claude`, `FROM base AS codex`, etc.
  - Each installs the agent CLI via npm/curl
  - Runs as non-root `agent` user
  - `WORKDIR /work`

Build specific agents: `docker build --target claude -t garth-claude docker/`

### Container run configuration

```
docker run -it --rm \
  --name "garth-<repo>-<agent>" \
  -v "<worktree>:/work" \
  -w /work \
  -e GITHUB_TOKEN="<installation-token>" \
  -e <AGENT_API_KEY_ENV>="<api-key>" \
  -e TERM=xterm-256color \
  --memory=8g \
  --cpus=4 \
  garth-<agent>:latest \
  <agent-command> <agent-flags>
```

**What the container does NOT have:**
- No `$HOME` mount (no SSH keys, no `~/.aws`, no `~/.config/gh`)
- No `SSH_AUTH_SOCK`
- No Docker socket
- No host network (uses bridge by default, `--network=none` optional)

**Git credentials inside container:** Configure via env-based credential helper
so `git push` uses the `GITHUB_TOKEN`:

```bash
git config --global credential.helper \
  '!f() { echo "protocol=https"; echo "host=github.com"; echo "username=x-access-token"; echo "password=$GITHUB_TOKEN"; }; f'
```

This is done in the Dockerfile or entrypoint script.

---

## GitHub App Token Minting (`lib/github-app.sh`)

> **GitHub App is the only supported credential method.** No fine-grained PATs.
> This provides short-lived tokens (1hr), separate bot identity, cleaner audit
> trail, and installation-scoped access.

**Setup (one-time, guided by `garth setup`):**

1. Create a GitHub App at github.com/settings/apps with minimal permissions:
   - Repository: Contents (Read & Write), Pull requests (Read & Write)
   - No org/admin scopes
2. Install the App on selected repos only
3. Store in 1Password: App ID, Installation ID, Private Key (as a document)

**Runtime flow (per `garth boot` / `garth token`):**

1. Read App ID, installation ID, and private key from 1Password via `op read`
2. Generate RS256 JWT using `openssl`:
   - Header: `{"alg":"RS256","typ":"JWT"}`
   - Payload: `{"iss":"<app_id>","iat":<now-60>,"exp":<now+600>}`
   - Sign with private key via `openssl dgst -sha256 -sign`
3. Request installation access token:
   `POST https://api.github.com/app/installations/<id>/access_tokens`
4. Token is valid for 1 hour — agents running longer need a token refresh
   (re-run `garth token` and inject, or restart the agent container)

**1Password references** (stored in `~/.config/garth/config.toml`):

```toml
[github_app]
app_id_ref = "op://Development/GitHub App/app-id"
private_key_ref = "op://Development/GitHub App/private-key"
installation_id_ref = "op://Development/GitHub App/installation-id"
```

---

## Configuration (`~/.config/garth/config.toml`)

Parsed by `lib/config-parser.py` using Python 3.12+ `tomllib` (stdlib, no deps).
The Python helper outputs `KEY=VALUE` lines that bash can eval.

```toml
[defaults]
agents = ["claude", "codex"]
sandbox = "docker"
network = "bridge"          # "bridge" or "none"
docker_image_prefix = "garth"

[agents.claude]
command = "claude --dangerously-skip-permissions"
api_key_env = "ANTHROPIC_API_KEY"
api_key_ref = "op://Development/Anthropic/api-key"

[agents.codex]
command = "codex exec --dangerously-bypass-approvals-and-sandbox"
api_key_env = "OPENAI_API_KEY"
api_key_ref = "op://Development/OpenAI/api-key"

[agents.opencode]
command = "opencode"
api_key_env = "OPENAI_API_KEY"
api_key_ref = "op://Development/OpenAI/api-key"

[agents.gemini]
command = "gemini --yolo"
api_key_env = "GOOGLE_API_KEY"
api_key_ref = "op://Development/Google AI/api-key"

[github_app]
app_id_ref = "op://Development/GitHub App/app-id"
private_key_ref = "op://Development/GitHub App/private-key"
installation_id_ref = "op://Development/GitHub App/installation-id"

[browser]
engine = "chromium"
app = "Google Chrome"
binary = ""
profiles_dir = "~/Library/Application Support/Chrome-ProjectProfiles"
```

---

## Security Model Summary

| Layer | What it protects against |
|-------|------------------------|
| Docker container (no $HOME mount) | Agent accessing SSH keys, AWS creds, gh auth, browser sessions |
| GitHub App token (1hr expiry, repo-scoped) | Unlimited PAT scope, long-lived credential theft |
| Branch protection (server-side) | Agent pushing to/deleting/force-pushing main |
| 1Password CLI (secrets never in env/files) | Credential leakage in config files or shell history |
| Non-root container user | Container privilege escalation |
| Optional `--network=none` | Data exfiltration |

---

## Implementation Order

### Phase 1: Foundation
1. `garth/lib/common.sh` — Logging, flag parsing, `run_cmd()`, `ask_yn()`
   (adapt from `toolchain/setup.sh` lines 10-78)
2. `garth/lib/config-parser.py` — TOML parser using `tomllib`
3. `garth/config/garth.example.toml` — Default config template
4. `garth/bin/garth` — Main script with subcommand dispatch (stubs)

### Phase 2: Git & Secrets
5. `garth/lib/git.sh` — Repo detection, GitHub URL derivation, worktree helpers
   (adapt patterns from `toolchain/scripts/doc-new.sh`)
6. `garth/lib/secrets.sh` — 1Password `op read` wrappers
7. `garth/lib/github-app.sh` — JWT generation, token minting

### Phase 3: Docker
8. `garth/docker/Dockerfile` — Multi-stage base + per-agent targets
9. `garth/lib/container.sh` — Image build, container run, cleanup

### Phase 4: Zellij & Workspace
10. `garth/lib/zellij.sh` — Layout KDL generation, session management
11. `garth/lib/workspace.sh` — browser, Cursor, Ghostty launch helpers

### Phase 5: Subcommands
12. Implement `garth boot` — full orchestration (uses phases 1-4)
13. Implement `garth worktree` — create worktree + boot
14. Implement `garth agent` — standalone container agent launch
15. Implement `garth token` — standalone token minting
16. Implement `garth status` / `garth stop`

### Phase 6: Setup & Polish
17. Implement `garth setup` — guided first-time setup
18. `garth/README.md` — Prerequisites, setup, usage, troubleshooting
19. Add `garth` symlink to `toolchain/setup.sh`

---

## Critical Files to Reference

| File | Why |
|------|-----|
| `toolchain/setup.sh` | Pattern for arg parsing, logging helpers, phased execution |
| `toolchain/scripts/doc-new.sh` | Pattern for worktree creation, branch naming |
| `toolchain/guides/shell.md` | Style: 2-space indent, `set -euo pipefail`, ShellCheck, `[[ ]]` |
| `toolchain/static-analysis/shell/.shellcheckrc` | ShellCheck config to use |
| `~/.config/zellij/config.kdl` | User's existing Zellij keybindings (don't conflict) |

---

## Prerequisites to Install

- **Zellij**: `brew install zellij` (config already exists at `~/.config/zellij/`)
- **GitHub App**: Create at github.com/settings/apps with Contents + PRs
  permissions only (guided by `garth setup`)
- **1Password items**: Store App ID, private key (document), installation ID,
  and each agent's API key (Anthropic, OpenAI, Google)
- **Branch protection**: Enable on `main` for all repos (PRs required, no force push)

---

## Verification

1. `garth boot .` in a test repo opens Cursor, a browser (optionally isolated), and
   Zellij with user shell + agent panes in Docker containers
2. Inside agent container: `echo $SSH_AUTH_SOCK` is empty, `echo $HOME` is NOT
   the host home, `ls /Users` fails
3. Agent can `git push` to a feature branch using the GitHub App token
4. Agent CANNOT `git push` to `main` (branch protection blocks it)
5. `garth token .` prints a valid GitHub installation token
6. `garth worktree . test-branch` creates a worktree and boots it
7. `garth stop <session>` kills containers and Zellij session
8. `garth status` shows running sessions, containers, and worktrees
