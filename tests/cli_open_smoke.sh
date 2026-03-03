#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-cli-open-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

REPO="$TMP_ROOT/repo"
ORIGIN_BARE="$TMP_ROOT/origin.git"
UPSTREAM_BARE="$TMP_ROOT/upstream.git"

git init -b main "$REPO" >/dev/null
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test User"
echo "init" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -m "init" >/dev/null

git init --bare "$ORIGIN_BARE" >/dev/null
git init --bare "$UPSTREAM_BARE" >/dev/null
git -C "$REPO" remote add origin "$ORIGIN_BARE"
git -C "$REPO" remote add upstream "$UPSTREAM_BARE"

git -C "$REPO" checkout -b topic >/dev/null
echo "topic" > "$REPO/topic.txt"
git -C "$REPO" add topic.txt
git -C "$REPO" commit -m "topic" >/dev/null
git -C "$REPO" push origin topic >/dev/null
git -C "$REPO" push upstream topic >/dev/null
git -C "$REPO" checkout main >/dev/null
git -C "$REPO" branch -D topic >/dev/null

# Keep refs/remotes from local pushes, but use GitHub-shaped remotes for dry-run launch summary.
git -C "$REPO" remote set-url origin "git@github.com:foo/bar.git"
git -C "$REPO" remote set-url upstream "git@github.com:foo/baz.git"

GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true "$GARTH_ROOT/bin/garth" open "$REPO" topic --dry-run >/dev/null
[[ "$(git -C "$REPO" for-each-ref --format='%(upstream:short)' refs/heads/topic)" == "origin/topic" ]]

git -C "$REPO" checkout main >/dev/null
echo "dirty" > "$REPO/uncommitted.txt"
set +e
DIRTY_OUT="$(GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true "$GARTH_ROOT/bin/garth" open "$REPO" topic --no-worktree --dry-run 2>&1)"
DIRTY_RC=$?
set -e
[[ $DIRTY_RC -ne 0 ]]
echo "$DIRTY_OUT" | grep -q "Cannot switch branches in-place with uncommitted changes"

echo "cli_open_smoke: ok"
