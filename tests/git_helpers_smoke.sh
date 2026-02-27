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

echo "git_helpers_smoke: ok"
