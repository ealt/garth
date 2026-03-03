# Garth Security Review: Findings and Improvements

## Context

Garth provides Docker-based sandboxing for AI coding agents. This review compares
garth's security model against Claude Code's native sandbox (Seatbelt/bwrap +
proxy) and OpenAI Codex's sandbox (Seatbelt/Landlock+seccomp), identifies gaps,
and proposes concrete improvements.

**Garth's current strengths are significant**: `--cap-drop=ALL`,
`--security-opt no-new-privileges:true`, `--read-only` root filesystem,
`--pids-limit 512`, memory/CPU limits, non-root user, no $HOME/SSH/Docker socket
access, 1Password-managed secrets, short-lived GitHub App tokens with atomic
rotation, and granular tmpfs mounts with `mode=0700` and `noexec` on cache.

---

## Is Docker categorically better than OS-level sandboxing?

**Neither is categorically better.** Each has distinct advantages:

### Where Docker is stronger
- **Full namespace isolation** — PID, network, mount, UTS separation. Agents
  can't see host processes, sniff loopback traffic, or discover host paths.
- **Resource limits** — Native cgroup-based CPU/memory/PID limits. Seatbelt has
  no equivalent.
- **Multi-agent isolation** — Each agent gets its own container. OS-level
  sandboxing doesn't naturally isolate agents from each other.
- **Reproducible environments** — Same base image regardless of host state.

### Where Docker is weaker
- **Network granularity** — Docker is binary: `bridge` (full internet) or `none`.
  Claude Code's proxy-based domain allowlist is far more nuanced. **This is
  garth's single biggest gap.**
- **Startup latency** — 1-3s per container vs milliseconds for Seatbelt/bwrap.
- **macOS filesystem performance** — Bind mounts go through VirtioFS; file
  watchers may not propagate correctly.
- **Daemon dependency** — Docker daemon runs as root, adding attack surface.
  OS-level sandboxing uses kernel primitives directly.

### Verdict for garth

Docker is the right choice for garth's multi-agent orchestration use case. The
namespace isolation and reproducible environments outweigh the drawbacks. **The
network granularity gap is the primary thing worth solving.**

---

## What's already been addressed (since initial review)

- **tmpfs mode fixed**: Now `mode=0700` with `uid=1001,gid=1001` (was `1777`)
- **Granular tmpfs separation**: `/home/agent/.cache` has `noexec`,
  `/home/agent/.local` is a separate mount with tighter size limits (256m)
- **`.claude.json` no longer directly writable**: Mounted read-only at
  `/run/garth-host-claude.json:ro` as a seed, with a runtime preamble that
  handles OAuth state restoration from backups
- **Explicit PATH in container env**: Prevents PATH manipulation

---

## Remaining improvements

## Implementation status (as of February 28, 2026)

| Item | Status | Notes |
|------|--------|-------|
| 1.1 Protect `.git/hooks`, `.git/config`, `.github` | ✅ Implemented | Configurable protected-path mounts are active; defaults now include `.gitmodules` as read-only too. |
| 1.2 Auth passthrough hardening matrix | 🟡 Partially implemented | Per-mount `ro/rw` controls are implemented; experiment matrix execution and default flips to `ro` are still pending. |
| 2.1 Custom seccomp profile | ✅ Implemented | `docker/seccomp-profile.json` wired into container args. |
| 2.2 Session audit logging | ✅ Implemented | `audit.log` JSONL with `0600` perms and redaction is in place. |
| 2.3 Post-session change report | ✅ Implemented | `git diff --stat` + sensitive-path flagging is wired on stop. |
| 3.1 Proxy-based domain filtering | ⏳ Not started | Still a future enhancement. |
| 3.2 Per-agent token scoping | ⏳ Not started | Still a future enhancement. |

### Tier 1: High-impact, low-effort

#### 1.1 Protect `.git/hooks`, `.git/config`, and `.github` as read-only

**Status (February 28, 2026): ✅ Implemented**

The worktree is mounted fully read-write. An agent can:
- Rewrite `.git/hooks/pre-commit` → arbitrary code on host at next `git commit`
- Modify `.git/config` → redirect pushes to attacker repo
- Alter `.github/workflows/` → inject CI pipeline commands
- Tamper with `.gitmodules` → point submodules at malicious repos

Both Claude Code and Codex protect `.git` as read-only.

**Primary approach: targeted protection.** Mounting all of `.git` as `:ro`
would break `git add` (writes `.git/index`), `git commit` (writes
`.git/objects` and `.git/refs`), and `git stash`. Agents need these operations,
so we protect only the dangerous subtrees:

```bash
# In garth_container_args_lines() and garth_container_shell_args_lines():
# After the worktree bind mount, overlay dangerous paths as read-only.
-v ${worktree}/.git/hooks:${sandbox_workdir}/.git/hooks:ro
-v ${worktree}/.git/config:${sandbox_workdir}/.git/config:ro
-v ${worktree}/.github:${sandbox_workdir}/.github:ro   # if exists
```

**Files**: `lib/container.sh` — `garth_container_args_lines()` and
`garth_container_shell_args_lines()`. Add a helper
`garth_container_emit_protected_path_mounts_lines()` that checks existence
before emitting each mount.

Consider making the protected-paths list configurable via `config.toml` with
these defaults.

#### 1.2 Auth passthrough mount hardening (experiment matrix)

**Status (February 28, 2026): 🟡 Partially implemented (framework done; matrix testing pending)**

Most auth passthrough mounts are `:rw`. A compromised agent could modify host
agent config, inject settings, or alter conversation history.

**This is fragile territory.** Claude and Codex auth persistence depends on
writing to specific directories during normal operation (session tokens, OAuth
refresh, cache). Changing mounts to `:ro` without testing will break auth. Frame
this as a test matrix:

| Mount | Current | Test `:ro` | Expected outcome |
|-------|---------|------------|------------------|
| `~/.claude` | `:rw` | Yes | Likely breaks — Claude writes session state here |
| `~/.config/claude` | `:rw` | Yes | May work read-only if only read at startup |
| `~/.cache/claude` | `:rw` | Skip | Cache writes expected, leave `:rw` |
| `~/.local/state/claude` | `:rw` | Yes | Likely breaks — session state writes |
| `~/.local/share/claude` | `:rw` | Yes | May work read-only |
| `~/.codex` | `:rw` | Yes | Test if Codex auth works read-only |

**Approach**: For each row marked "Test `:ro`", boot a session with that mount
changed to `:ro`, run the agent through a basic workflow (auth, git push, file
edit), and record pass/fail. Mounts that fail `:ro` stay `:rw` but get
documented as known attack surface. Mounts that pass `:ro` get changed.

**Files**: `lib/container.sh` — `garth_container_emit_auth_mounts_lines()`

##### 1.2 Completion playbook (next steps)

Use this checklist to move from "framework implemented" to "hardened + verified":

1. Create a tracking table in-repo (for example `docs/auth-passthrough-matrix.md`)
   with one row per mount key:
   - `codex_dot_codex`
   - `claude_dot_claude`
   - `claude_config`
   - `claude_state`
   - `claude_share`
   - `claude_cache`
2. For each row marked "Test `:ro`", set only that mount mode to `"ro"` in
   `config.toml` under `[security.auth_mount_mode]`; keep all others at `"rw"`.
3. Run a standard validation workflow for each test case:
   - Boot a fresh session (`garth boot <worktree> --sandbox docker`)
   - Confirm agent startup in both `safe` and `permissive` modes
   - Authenticate if prompted; restart once and verify auth persistence
   - Do file edit + `git add` + `git commit` + `git push` on a throwaway branch
   - Stop session and check `audit.log` for non-zero exits or auth failures
4. Record result for each mount as `PASS(ro)` or `FAIL(keep rw)` with evidence
   (timestamp, branch, short notes, relevant audit event names).
5. Promote defaults:
   - Set all `PASS(ro)` mounts to `"ro"` in `config.example.toml`
   - Keep failing mounts at `"rw"` and explicitly document why
6. Run Tier 1 acceptance criteria after all flips and capture a final sign-off
   entry in the tracking table.

Definition of done for 1.2:
- Every "Test `:ro`" row has an evidence-backed pass/fail result.
- `config.example.toml` reflects the hardened defaults (`ro` where proven safe).
- Remaining `rw` mounts are documented as accepted risk with rationale.

#### Tier 1 acceptance criteria

**Must pass:**
- Agent can `git add`, `git commit`, `git push` to a feature branch
- Agent cannot modify `.git/hooks/*` or `.git/config` (expect
  "Read-only file system")
- Agent cannot modify `.github/workflows/*`
- All agents start and authenticate in both safe and permissive modes
- Auth passthrough agents can still complete OAuth flows for mounts left `:rw`

**May regress (known):**
- Agent cannot run `git config --local` (`.git/config` is read-only) — use
  `git -c key=val` flag syntax instead
- Some auth passthrough mounts may need to stay `:rw` after testing

---

### Tier 2: Medium-effort hardening

#### 2.1 Custom seccomp profile

**Status (February 28, 2026): ✅ Implemented**

Docker's default seccomp blocks ~44 syscalls, but a custom profile adds
defense in depth. Key additions to block: `ptrace`, `personality`,
`mount`/`umount`, `unshare`, `pivot_root`, `reboot`, `init_module`/
`finit_module`, `kexec_load`, `bpf`, `userfaultfd`.

**Files to create**: `docker/seccomp-profile.json`
**Files to modify**: `lib/container.sh` — add
`--security-opt seccomp=<path>/seccomp-profile.json` to both container
args functions

Start from Docker's default profile and restrict further. Test each agent.

#### 2.2 Session audit logging

**Status (February 28, 2026): ✅ Implemented**

Add structured JSON-lines logging of security-relevant events to
`$session_dir/audit.log`.

**Events to log**: container start/stop with parameters, token rotation
(success/failure), auth passthrough activation, network/safety mode selection,
non-zero exit codes.

**Redaction rules** (mandatory):
- Never log raw token values — log only `token_prefix=ghs_...xxx` (first 8
  chars) and `token_expires_at`
- Never log API key values — log only `api_key_env=ANTHROPIC_API_KEY` (the
  variable name, not the value)
- Never log 1Password refs verbatim — log only `ref_vault=Development`
  (vault name only, not item/field)
- Strip secrets from any error messages before logging

**File permissions**: `audit.log` must be created with `umask 077` and
`chmod 0600`, matching the existing pattern for token and env files.

**Files**: `lib/common.sh` (add `garth_audit_log()` with redaction), both
container args functions in `lib/container.sh`, `bin/garth` session lifecycle

#### 2.3 Post-session worktree change report

**Status (February 28, 2026): ✅ Implemented**

At session stop, run `git diff --stat` and specifically flag changes to
sensitive paths (`.git/hooks/`, `.github/`, `Makefile`, `*.sh`, CI configs).

**Files**: `bin/garth` — add to `stop_session()` or create
`garth_post_session_report()`

#### Tier 2 acceptance criteria

**Must pass:**
- All agents start and complete basic workflows with seccomp profile active
- `audit.log` is created with 0600 permissions and contains no raw secrets
- Post-session report correctly identifies modified sensitive files

**May regress (known):**
- Agents that use `ptrace`-based debuggers will fail under custom seccomp
- Audit logging adds minor disk I/O per event

---

### Tier 3: Aspirational (maximum security)

#### 3.1 Domain-level network filtering via proxy container

**Status (February 28, 2026): ⏳ Not started**

**The most impactful aspirational improvement.** Run a forward proxy (Squid or
a minimal Go proxy) in a sidecar container. Agent containers route all traffic
through it via `http_proxy`/`https_proxy` env vars. The proxy enforces a domain
allowlist from config.

Default allowlist: `github.com`, `api.github.com`, `registry.npmjs.org`,
`pypi.org`, `files.pythonhosted.org`, `api.anthropic.com`, `api.openai.com`,
`generativelanguage.googleapis.com`.

**Config addition**:
```toml
[network]
mode = "bridge"  # bridge | none | filtered (new)
allowed_domains = [
  "github.com", "api.github.com",
  "registry.npmjs.org", "pypi.org",
  "api.anthropic.com", "api.openai.com",
]
```

**Files to create**: `docker/Dockerfile.proxy`, `docker/proxy-config/`
**Files to modify**: `lib/container.sh`, `lib/config-parser.py`, `bin/garth`

#### 3.2 Per-agent GitHub token scoping

**Status (February 28, 2026): ⏳ Not started**

Mint separate tokens per agent with different permission scopes. Read-only
agents get `contents: read`; write agents get `contents: write,
pull_requests: write`. Uses `permissions` parameter on GitHub's
`POST /app/installations/{id}/access_tokens` endpoint.

**Files**: `lib/github-app.sh`, `lib/container.sh`

#### Tier 3 acceptance criteria

**Must pass:**
- Agents can reach allowed domains (npm install, git push, API calls)
- Agents cannot reach arbitrary domains (curl to external host fails)
- Per-agent tokens have correct scopes (read-only agent cannot push)

**May regress (known):**
- Some agent operations may require domains not in default allowlist
  (discovery via proxy logs)
- Proxy adds latency to all network requests
- Token refresh logic becomes more complex with per-agent tokens

---

## Implementation order (with current status)

| Priority | Item | Effort | Current status |
|----------|------|--------|----------------|
| **Now** | 1.1 Protect `.git/hooks`, `.git/config`, `.github` | ~30 lines | ✅ Implemented |
| **Now** | 1.2 Auth passthrough experiment matrix | Testing + selective changes | 🟡 In progress (framework done; tests pending) |
| **Next** | 2.1 Custom seccomp profile | New JSON file + container.sh changes | ✅ Implemented |
| **Next** | 2.2 Audit logging with redaction | ~80 lines across files | ✅ Implemented |
| **Next** | 2.3 Post-session change report | ~30 lines | ✅ Implemented |
| **Later** | 3.1 Proxy-based network filtering | New container + ~200 lines | ⏳ Not started |
| **Later** | 3.2 Per-agent token scoping | ~50 lines in github-app.sh | ⏳ Not started |
