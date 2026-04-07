#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-cli-new-smoke.XXXXXX")"
GARTH_LIB_COPY="$(mktemp "$GARTH_ROOT/bin/garth-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT" "$GARTH_LIB_COPY"' EXIT

ORIGIN_BARE="$TMP_ROOT/origin.git"
SEED_REPO="$TMP_ROOT/seed"
REPO="$TMP_ROOT/repo"
PEER_REPO="$TMP_ROOT/peer"

git init --bare "$ORIGIN_BARE" >/dev/null
git --git-dir="$ORIGIN_BARE" symbolic-ref HEAD refs/heads/main

git init -b main "$SEED_REPO" >/dev/null
git -C "$SEED_REPO" config user.email "test@example.com"
git -C "$SEED_REPO" config user.name "Test User"
echo "seed" > "$SEED_REPO/README.md"
git -C "$SEED_REPO" add README.md
git -C "$SEED_REPO" commit -m "seed" >/dev/null
git -C "$SEED_REPO" remote add origin "$ORIGIN_BARE"
git -C "$SEED_REPO" push -u origin main >/dev/null

git clone "$ORIGIN_BARE" "$REPO" >/dev/null
git clone "$ORIGIN_BARE" "$PEER_REPO" >/dev/null
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test User"
git -C "$PEER_REPO" config user.email "test@example.com"
git -C "$PEER_REPO" config user.name "Test User"

sed '$d' "$GARTH_ROOT/bin/garth" > "$GARTH_LIB_COPY"
source "$GARTH_LIB_COPY"
garth_launch_workspace() {
  :
}
trap 'rm -rf "$TMP_ROOT" "$GARTH_LIB_COPY"' EXIT
GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml"

LOCAL_MAIN_BEFORE_SYNC="$(git -C "$REPO" rev-parse main)"

echo "peer-main" >> "$PEER_REPO/README.md"
git -C "$PEER_REPO" add README.md
git -C "$PEER_REPO" commit -m "peer-main" >/dev/null
git -C "$PEER_REPO" push origin main >/dev/null
LATEST_MAIN="$(git -C "$PEER_REPO" rev-parse HEAD)"

SYNC_OUT="$(cmd_new "$REPO" feature/synced 2>&1)"
[[ "$(git -C "$REPO" rev-parse refs/heads/feature/synced)" == "$LATEST_MAIN" ]]
echo "$SYNC_OUT" | grep -q "Base: origin/main (synced from origin)"
WT_DIR=$(garth_git_find_worktree_for_branch "$REPO" "feature/synced")
[[ "$(git -C "$WT_DIR" config --get push.default)" == "current" ]]

git -C "$REPO" checkout -b somebranch main >/dev/null
echo "local-base" > "$REPO/local-base.txt"
git -C "$REPO" add local-base.txt
git -C "$REPO" commit -m "local-base" >/dev/null
LOCAL_BASE_COMMIT="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout main >/dev/null

git -C "$PEER_REPO" checkout -b somebranch main >/dev/null
echo "remote-base" > "$PEER_REPO/remote-base.txt"
git -C "$PEER_REPO" add remote-base.txt
git -C "$PEER_REPO" commit -m "remote-base" >/dev/null
git -C "$PEER_REPO" push -u origin somebranch >/dev/null
REMOTE_BASE_COMMIT="$(git -C "$PEER_REPO" rev-parse HEAD)"
git -C "$REPO" fetch origin somebranch >/dev/null
[[ "$(git -C "$REPO" rev-parse refs/remotes/origin/somebranch)" == "$REMOTE_BASE_COMMIT" ]]

cmd_new "$REPO" feature/from-explicit --base somebranch >/dev/null 2>&1
[[ "$(git -C "$REPO" rev-parse refs/heads/feature/from-explicit)" == "$LOCAL_BASE_COMMIT" ]]
[[ "$(git -C "$REPO" rev-parse refs/heads/feature/from-explicit)" != "$REMOTE_BASE_COMMIT" ]]

NO_FETCH_OUT="$(cmd_new "$REPO" feature/no-fetch --no-fetch 2>&1)"
[[ "$(git -C "$REPO" rev-parse refs/heads/feature/no-fetch)" == "$LOCAL_MAIN_BEFORE_SYNC" ]]
if echo "$NO_FETCH_OUT" | grep -q "synced from origin"; then
  echo "FAIL: --no-fetch should not report origin sync" >&2
  exit 1
fi

cmd_up "$REPO" --new-branch feature/up-no-fetch --no-fetch >/dev/null 2>&1
[[ "$(git -C "$REPO" rev-parse refs/heads/feature/up-no-fetch)" == "$LOCAL_MAIN_BEFORE_SYNC" ]]

echo "cli_new_smoke: ok"
