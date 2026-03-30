#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$GARTH_ROOT/lib/common.sh"
source "$GARTH_ROOT/lib/git.sh"

[[ "$(garth_slugify_branch 'feature/my-branch')" == "feature__my-branch" ]]
[[ "$(garth_git_owner_repo_from_remote 'git@github.com:foo/bar.git')" == "foo/bar" ]]
[[ "$(garth_git_owner_repo_from_remote 'https://github.com/foo/bar.git')" == "foo/bar" ]]
[[ "$(garth_git_https_url_from_remote 'git@github.com:foo/bar.git')" == "https://github.com/foo/bar" ]]

TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/garth-git-smoke.XXXXXX")"
trap 'rm -rf "$TMP_REPO"' EXIT

git -C "$TMP_REPO" init -b main >/dev/null
git -C "$TMP_REPO" config user.email "test@example.com"
git -C "$TMP_REPO" config user.name "Test User"
touch "$TMP_REPO/README.md"
git -C "$TMP_REPO" add README.md
git -C "$TMP_REPO" commit -m "init" >/dev/null

[[ "$(garth_git_default_branch "$TMP_REPO")" == "main" ]]
GARTH_DEFAULTS_DEFAULT_BRANCH="trunk"
[[ "$(garth_git_default_branch "$TMP_REPO")" == "trunk" ]]
unset GARTH_DEFAULTS_DEFAULT_BRANCH

git -C "$TMP_REPO" branch feature/auth
mkdir -p "$TMP_REPO/wt"
git -C "$TMP_REPO" worktree add "$TMP_REPO/wt/feature__auth" feature/auth >/dev/null
[[ "$(garth_git_find_worktree_for_branch "$TMP_REPO" "feature/auth")" == "$TMP_REPO/wt/feature__auth" ]]
[[ "$(garth_git_repo_name "$TMP_REPO/wt/feature__auth")" == "$(basename "$TMP_REPO")" ]]

HELPER_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-git-helper-smoke.XXXXXX")"
trap 'rm -rf "$TMP_REPO" "$HELPER_ROOT"' EXIT

ORIGIN_BARE="$HELPER_ROOT/origin.git"
SEED_REPO="$HELPER_ROOT/seed"
PRIMARY_REPO="$HELPER_ROOT/primary"
PEER_REPO="$HELPER_ROOT/peer"

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

git clone "$ORIGIN_BARE" "$PRIMARY_REPO" >/dev/null
git clone "$ORIGIN_BARE" "$PEER_REPO" >/dev/null
git -C "$PRIMARY_REPO" config user.email "test@example.com"
git -C "$PRIMARY_REPO" config user.name "Test User"
git -C "$PEER_REPO" config user.email "test@example.com"
git -C "$PEER_REPO" config user.name "Test User"

echo "peer-main" >> "$PEER_REPO/README.md"
git -C "$PEER_REPO" add README.md
git -C "$PEER_REPO" commit -m "peer-main" >/dev/null
git -C "$PEER_REPO" push origin main >/dev/null
LATEST_MAIN="$(git -C "$PEER_REPO" rev-parse HEAD)"

[[ "$(garth_git_fetch_and_resolve_default_base "$PRIMARY_REPO")" == "origin/main" ]]
[[ "$(git -C "$PRIMARY_REPO" rev-parse origin/main)" == "$LATEST_MAIN" ]]

git -C "$PRIMARY_REPO" remote remove origin
[[ "$(garth_git_fetch_and_resolve_default_base "$PRIMARY_REPO")" == "main" ]]

git -C "$PRIMARY_REPO" remote add origin "$ORIGIN_BARE"
git -C "$PEER_REPO" checkout -b trunk >/dev/null
git -C "$PEER_REPO" push -u origin trunk >/dev/null
GARTH_DEFAULTS_DEFAULT_BRANCH="trunk"
[[ "$(garth_git_fetch_and_resolve_default_base "$PRIMARY_REPO")" == "origin/trunk" ]]
unset GARTH_DEFAULTS_DEFAULT_BRANCH

echo "git_helpers_smoke: ok"
