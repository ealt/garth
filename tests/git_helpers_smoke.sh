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

echo "git_helpers_smoke: ok"
