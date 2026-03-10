# Garth Security Model

This document describes Garth's security model, trust boundaries, security
configuration options, and the tradeoffs between isolation, convenience, and
operational reliability.

## Scope

This model covers:

- host-side orchestration (`bin/garth`, `lib/*.sh`)
- Docker sandbox runtime defaults
- GitHub App token minting and refresh
- 1Password secret access behavior
- configurable security controls in `config.toml`

It does not cover:

- security of third-party agent CLIs themselves
- vulnerabilities inside user repositories
- host OS compromise scenarios beyond basic mitigation guidance

## Security Objectives

Primary objectives:

- reduce blast radius of autonomous agents by default
- avoid long-lived credentials in container process args and layout files
- provide explicit, reviewable security/convenience tradeoffs
- preserve forensic visibility through audit logs with redaction

Secondary objectives:

- keep default workflows practical for day-to-day development
- allow explicit opt-ins for lower interruption and higher convenience

## Trust Boundaries

Boundary 1: Host orchestration process.

- `garth` runs with host user privileges.
- It can read local config, call Docker, call `op`, mint GitHub tokens, and
  write state under `$XDG_STATE_HOME/garth`.

Boundary 2: Containerized agent runtime.

- agents run in Docker with restricted capabilities and read-only root FS.
- only selected host paths are mounted.

Boundary 3: External providers.

- 1Password (`op`) for secret retrieval.
- GitHub API for GitHub App JWT validation and installation token minting.

Boundary 4: User workstation controls.

- macOS app-launch permissions (Ghostty/Terminal automation paths).
- local auth directories optionally mounted into containers.

## Credential and Secret Handling

### Agent API keys

- source: 1Password refs (`agents.<name>.api_key_ref`)
- destination: per-agent env files with mode `0600`
- not passed in command arguments or zellij layout text

### GitHub installation tokens

- source: GitHub App flow (JWT signed by app private key)
- destination: token file mounted into containers at `/run/garth/github_token`
- rotation: background refresher loop (`internal-refresh`)
- cache: per-owner/repo token cache under
  `$XDG_STATE_HOME/garth/token-cache` (`0700` dir, `0600` files)
- thundering-herd control: token mint lock prevents concurrent multi-session
  duplicate secret reads/mints for the same repo

### GitHub App private key and app ID

Default behavior:

- read from 1Password during mint operations
- private key material written to short-lived temp file (`0600`) for signing

Optional behavior (`token_refresh.cache_github_app_secrets = true`):

- refresher preloads GitHub App secret material once at refresher startup
- background mints reuse cached override values
- tradeoff: reduced popup interruptions versus longer in-process secret
  residency for the refresher lifetime

### 1Password auto-signin behavior

Default behavior:

- secret reads can auto-attempt `op signin` when interactive and session is
  missing

Optional hard guard (`token_refresh.background_auto_signin = false`):

- background refresher disables auto-signin (`GARTH_OP_AUTO_SIGNIN=false`)
- avoids unattended popup loops during background refresh
- tradeoff: session can become `degraded` until manual re-auth

## Container Isolation Controls

Default Docker hardening:

- `--cap-drop=ALL`
- `--security-opt no-new-privileges:true`
- `--security-opt seccomp=<profile>` when profile exists
- `--read-only`
- `--pids-limit=512`
- tmpfs mounts for writable runtime paths
- read-only overlays for protected repo paths

Protected path overlay defaults:

- `.git/hooks`
- `.git/config`
- `.github`
- `.gitmodules`

Optional auth passthrough:

- disabled by default
- when enabled (`defaults.auth_passthrough`), selected host auth paths are
  mounted into agent containers
- mount mode is configurable per auth path under `[security.auth_mount_mode]`

Security implication:

- auth passthrough is a convenience feature that weakens isolation and should be
  enabled only for trusted workflows

## Configuration Reference and Tradeoffs

### [defaults]

| Key | Default | Security Impact |
|---|---|---|
| `sandbox` | `docker` | `none` disables container isolation entirely |
| `network` | `bridge` | `none` removes container network access |
| `safety_mode` | `safe` | `permissive` increases agent execution latitude |
| `auth_passthrough` | `[]` | non-empty mounts host auth into containers |
| `terminal_launcher` | `auto` | controls app-launch behavior; `current_shell` avoids macOS launcher prompts |

### [token_refresh]

| Key | Default | Security/UX Tradeoff |
|---|---|---|
| `enabled` | `true` | `false` disables background rotation (higher expiration risk) |
| `lead_time` | `15m` | earlier refresh increases retry headroom |
| `failure_retry_window` | `10m` | longer retries can increase auth attempts |
| `retry_backoff` | `exponential` | reduces retry pressure versus fixed cadence |
| `retry_initial_interval` | `5s` | lower values retry more aggressively |
| `retry_max_interval` | `60s` | upper bound on retry interval |
| `cache_github_app_secrets` | `false` | fewer prompts, more in-process secret residency |
| `background_auto_signin` | `true` | `false` prevents background popup loops, but can degrade until manual re-auth |

### [github_app]

| Key | Default | Security Impact |
|---|---|---|
| `app_id_ref` | required | secret reference must be valid |
| `private_key_ref` | required | private key protection is critical |
| `installation_strategy` | `by_owner` | affects installation lookup behavior |
| `installation_id_ref` | empty | required for `single` strategy |
| `installation_id_map` | `{}` | used only for `static_map` strategy |

### [security]

| Key | Default | Security Impact |
|---|---|---|
| `protected_paths` | standard list | protects sensitive repo paths from writes |
| `seccomp_profile` | `docker/seccomp-profile.json` | syscall restriction when present |
| `auth_mount_mode.*` | mixed (`ro`/`rw`) | controls mutability of mounted auth dirs |

### [features]

| Key | Security Consideration |
|---|---|
| `packages` | broadens toolchain and attack surface in images |
| `mounts` | adds host-path exposure into container runtime |

## Operational Signals and Recovery

Session audit logs:

- path: `$XDG_STATE_HOME/garth/sessions/<session>/audit.log`
- format: JSONL (`0600`) with secret-redaction rules
- useful events: token refresher start/stop, refresh success/failure, degraded
  state transitions, secret-cache readiness

Common recovery actions:

- auth recovery: `eval "$(op signin)"`
- token probe: `garth token . --machine`
- health check: `garth doctor --repo .` or `--deep`
- degraded refresher: manual re-auth then reopen/refresh session

## Recommended Security Profiles

Profile A: Maximum isolation.

- `defaults.sandbox = "docker"`
- `defaults.auth_passthrough = []`
- `defaults.safety_mode = "safe"`
- `token_refresh.cache_github_app_secrets = false`
- `token_refresh.background_auto_signin = true`

Profile B: Balanced daily use.

- `defaults.sandbox = "docker"`
- minimal `auth_passthrough` only where needed
- `token_refresh.cache_github_app_secrets = true`
- `token_refresh.background_auto_signin = false`

Profile C: High convenience (lower isolation).

- broader `auth_passthrough`
- permissive safety settings
- optional host mounts/tool packages
- requires stronger trust assumptions about workloads and local environment

## Hardening Checklist

- keep `sandbox = "docker"` unless you accept host execution risk
- keep `auth_passthrough` minimal
- keep `security.protected_paths` enabled
- verify seccomp profile path exists and is version-controlled
- use `token_refresh.background_auto_signin = false` if popup storms are a risk
- monitor `audit.log` for repeated refresh failures/degraded transitions
- rotate compromised credentials and rebuild sessions after incidents
