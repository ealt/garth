#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-wt-protect-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

REPO="$TMP_ROOT/repo"
ORIGIN_BARE="$TMP_ROOT/origin.git"

# --- Setup: repo with a worktree ---
git init --bare "$ORIGIN_BARE" >/dev/null
git --git-dir="$ORIGIN_BARE" symbolic-ref HEAD refs/heads/main

git init -b main "$REPO" >/dev/null
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test User"
echo "init" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -m "init" >/dev/null
git -C "$REPO" remote add origin "$ORIGIN_BARE"
git -C "$REPO" push -u origin main >/dev/null

# Create a worktree — .git will be a file in the worktree directory.
WT="$TMP_ROOT/wt-feature"
git -C "$REPO" worktree add "$WT" -b feature main >/dev/null

# Add .github and .gitmodules to worktree so non-.git protected paths exist.
mkdir -p "$WT/.github"
echo "# workflows" > "$WT/.github/README.md"
echo "[submodule]" > "$WT/.gitmodules"

# Ensure the parent repo also has .git/hooks and .git/config for Test 2.
[[ -d "$REPO/.git/hooks" ]] || mkdir -p "$REPO/.git/hooks"
mkdir -p "$REPO/.github"
echo "# workflows" > "$REPO/.github/README.md"
echo "[submodule]" > "$REPO/.gitmodules"

# --- Source libraries ---
source "$GARTH_ROOT/lib/common.sh"
source "$GARTH_ROOT/lib/container.sh"

# ============================================================
# Test 1: worktree mode — .git file mounted ro, .git/* skipped
# ============================================================
OUT1="$(garth_container_emit_protected_path_mounts_lines "$WT" "/sandbox")"

# .git pointer file is mounted read-only
echo "$OUT1" | grep -q "${WT}/.git:/sandbox/.git:ro"

# .git/hooks and .git/config must NOT appear (they don't exist under a file)
if echo "$OUT1" | grep -q ".git/hooks"; then
  echo "FAIL: worktree mode should not emit .git/hooks mount" >&2
  exit 1
fi
if echo "$OUT1" | grep -q ".git/config"; then
  echo "FAIL: worktree mode should not emit .git/config mount" >&2
  exit 1
fi

# .github and .gitmodules should still be mounted
echo "$OUT1" | grep -q "${WT}/.github:/sandbox/.github:ro"
echo "$OUT1" | grep -q "${WT}/.gitmodules:/sandbox/.gitmodules:ro"

# ============================================================
# Test 2: normal repo mode — .git/* mounted, no bare .git mount
# ============================================================
OUT2="$(garth_container_emit_protected_path_mounts_lines "$REPO" "/sandbox")"

echo "$OUT2" | grep -q ".git/hooks:/sandbox/.git/hooks:ro"
echo "$OUT2" | grep -q ".git/config:/sandbox/.git/config:ro"
echo "$OUT2" | grep -q ".github:/sandbox/.github:ro"
echo "$OUT2" | grep -q ".gitmodules:/sandbox/.gitmodules:ro"

# Must NOT have a bare .git:...:ro line (only sub-paths)
if echo "$OUT2" | grep -qE "^${REPO}/\.git:/sandbox/\.git:ro$"; then
  echo "FAIL: normal repo mode should not emit bare .git mount" >&2
  exit 1
fi

# ============================================================
# Tests 3-6: GARTH_EXPECT_GIT_FILE env var emission
# ============================================================

# Stubs for functions called by garth_container_args_lines / shell_args_lines
# that we don't need for this test.
garth_agent_command_string() { echo "echo test"; }
garth_agent_runtime_wrap_command() { echo "$2"; }
garth_container_emit_seccomp_opt_lines() { :; }
garth_container_emit_auth_mounts_lines() { return 1; }
garth_container_emit_feature_mounts_lines() { return 1; }
garth_claude_runtime_preamble() { echo ":"; }

ENV_FILE="$TMP_ROOT/test.env"
TOKEN_DIR="$TMP_ROOT/tokens"
mkdir -p "$TOKEN_DIR"
touch "$ENV_FILE"

# Test 3: agent args — worktree → env var present
AGENT_WT_OUT="$(garth_container_args_lines "test-session" "$REPO" "$WT" "claude" "$ENV_FILE" "$TOKEN_DIR" "bridge" "garth" "safe" "false")"
echo "$AGENT_WT_OUT" | grep -q "GARTH_EXPECT_GIT_FILE=true"

# Test 4: agent args — normal repo → env var absent
AGENT_REPO_OUT="$(garth_container_args_lines "test-session" "$REPO" "$REPO" "claude" "$ENV_FILE" "$TOKEN_DIR" "bridge" "garth" "safe" "false")"
if echo "$AGENT_REPO_OUT" | grep -q "GARTH_EXPECT_GIT_FILE"; then
  echo "FAIL: normal repo agent args should not emit GARTH_EXPECT_GIT_FILE" >&2
  exit 1
fi

# Test 5: shell args — worktree → env var present
SHELL_WT_OUT="$(garth_container_shell_args_lines "test-session" "$REPO" "$WT" "$TOKEN_DIR" "bridge" "garth" "claude" "false")"
echo "$SHELL_WT_OUT" | grep -q "GARTH_EXPECT_GIT_FILE=true"

# Test 6: shell args — normal repo → env var absent
SHELL_REPO_OUT="$(garth_container_shell_args_lines "test-session" "$REPO" "$REPO" "$TOKEN_DIR" "bridge" "garth" "claude" "false")"
if echo "$SHELL_REPO_OUT" | grep -q "GARTH_EXPECT_GIT_FILE"; then
  echo "FAIL: normal repo shell args should not emit GARTH_EXPECT_GIT_FILE" >&2
  exit 1
fi

echo "worktree_protected_paths_smoke: ok"
