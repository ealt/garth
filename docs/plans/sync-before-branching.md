# Plan: Sync implicit default branch before creating feature branch

## Context

When `garth new` (or `garth up --new-branch`) creates a feature branch, it
bases it on the local default branch (typically `main`). If the local `main` is
behind `origin/main`, the new feature branch starts stale, requiring a manual
fetch + rebase after the fact. This should be handled automatically before
branch creation.

**Root cause:** `cmd_new` resolves `base_ref` to a bare local name like `main`
via `garth_git_default_branch()`, then creates the branch from that local ref
without fetching. There is no fetch anywhere in the `cmd_new` code path.
(Note: `garth_git_create_worktree()` in lib/git.sh has a fetch, but `cmd_new`
never calls it — it creates worktrees inline.)

**Scope:** This fix applies only when no explicit `--base` is provided — i.e.,
when the base is implicitly resolved to the repo's default branch. When the
user explicitly passes `--base <ref>`, their choice is respected as-is; we do
not rewrite explicit base refs.

## Approach

When `cmd_new` resolves the base ref implicitly (no `--base` flag), fetch
origin and use the remote-tracking counterpart (`origin/main` instead of local
`main`) as the branch point. Add `--no-fetch` opt-out flag for offline or
intentional-stale-base use cases.

## Changes

### 1. New helper in `lib/git.sh` (after `garth_git_default_branch`, ~line 71)

Add `garth_git_fetch_and_resolve_default_base()`:

```bash
garth_git_fetch_and_resolve_default_base() {
  local repo_root="$1"

  # Fetch latest refs from origin (non-fatal)
  git -C "$repo_root" fetch origin --quiet 2>/dev/null || true

  # Resolve the default branch name
  local default_branch
  default_branch=$(garth_git_default_branch "$repo_root")

  # Prefer origin/<default> so the new branch starts at the latest remote commit
  if git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
    echo "origin/$default_branch"
  else
    echo "$default_branch"
  fi
}
```

This function is intentionally narrow: it only resolves the *default* branch
and only upgrades to the `origin/` tracking ref. It does not accept an
arbitrary ref parameter.

### 2. Wire into `cmd_new` (`bin/garth`, ~lines 1139-1144)

Replace the existing implicit-base resolution with a conditional:

```bash
# Before (line 1139):
base_ref="${base_ref:-$(garth_git_default_branch "$repo_root")}"

# After:
if [[ -z "$base_ref" ]]; then
  if [[ "$no_fetch" != "true" ]]; then
    base_ref=$(garth_git_fetch_and_resolve_default_base "$repo_root")
    if [[ "$base_ref" == origin/* ]]; then
      garth_log_info "Base: $base_ref (synced from origin)"
    fi
  else
    base_ref=$(garth_git_default_branch "$repo_root")
  fi
fi
```

Key property: when `--base` IS explicitly provided, `base_ref` is already set,
so this block is skipped entirely. Explicit base refs are never fetched or
rewritten.

Both the worktree path (line 1165) and `--no-worktree` path (line 1151) benefit
since the fix is before the branch point.

### 3. Add `--no-fetch` flag to `cmd_new`

- New local variable `no_fetch=false` (near line 1060)
- New case in the arg parser (near line 1069): `--no-fetch) no_fetch=true; shift ;;`
- Add to help text (near line 1093)

### 4. Forward `--no-fetch` through `cmd_up`

`cmd_up` delegates to `cmd_new` at two call sites (lines 1591-1595 and
1698-1703). Add:
- `local no_fetch=false` in `cmd_up` locals
- Case in `cmd_up` arg parser: `--no-fetch) no_fetch=true; shift ;;`
- Add to help text
- At both `cmd_new` delegation sites, append:
  `[[ "$no_fetch" == "true" ]] && args+=(--no-fetch)`

### 5. Tests

#### Unit tests in `tests/git_helpers_smoke.sh`

Add tests using a bare-origin setup (create repo, push to bare remote, advance
origin from a second clone):

1. **Implicit default — local behind origin:** Call
   `garth_git_fetch_and_resolve_default_base`. Verify it returns `origin/main`
   and that ref resolves to the newer commit on origin.
2. **No origin remote:** Remove origin, call helper. Verify it falls back to
   local `main`.
3. **Default branch env override:** Set `GARTH_DEFAULTS_DEFAULT_BRANCH=trunk`,
   verify helper returns `origin/trunk` if it exists, else `trunk`.

#### Command-level smoke test (new file or extend existing)

Create a test that exercises the `cmd_new` integration:

1. Set up bare origin + clone with stale local main.
2. Run `garth new <dir> test-branch` (with session launch stubbed/skipped).
   Verify the created branch points at the same commit as `origin/main`, not
   local `main`.
3. Run `garth new <dir> test-branch-2 --base somebranch`. Verify the branch
   points at `somebranch`, not `origin/somebranch` — explicit base is
   respected.
4. Run `garth new <dir> test-branch-3 --no-fetch`. Verify the branch points at
   local `main` (stale), not `origin/main`.

### 6. Update docs

- `AGENTS.md`: Add `garth_git_fetch_and_resolve_default_base` to the
  `lib/git.sh` module reference.
- Help text updates are covered in steps 3-4.

## Files to modify

| File | Change |
|------|--------|
| `lib/git.sh` | Add `garth_git_fetch_and_resolve_default_base()` (~12 lines) |
| `bin/garth` | `cmd_new`: add `--no-fetch` flag + conditional base resolution (~12 lines) |
| `bin/garth` | `cmd_up`: add `--no-fetch` flag + forward to `cmd_new` (~6 lines) |
| `tests/git_helpers_smoke.sh` | Add 3 unit tests for new helper (~30 lines) |
| `tests/` (new or existing smoke file) | Add command-level smoke tests (~50 lines) |
| `AGENTS.md` | Document new helper in module reference |

## Verification

1. `bash -n bin/garth lib/*.sh` — syntax check
2. `bash tests/git_helpers_smoke.sh` — unit tests pass
3. Run command-level smoke test — integration tests pass
4. All existing tests still pass: `bash tests/cli_open_smoke.sh`,
   `bash tests/session_helpers_smoke.sh`, etc.
