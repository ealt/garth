#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$GARTH_ROOT/lib/common.sh"
source "$GARTH_ROOT/lib/git.sh"
source "$GARTH_ROOT/lib/github-app.sh"

TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/garth-ctx-url-smoke.XXXXXX")"
trap 'rm -rf "$TMP_REPO"' EXIT

git -C "$TMP_REPO" init -b main >/dev/null
git -C "$TMP_REPO" config user.email "test@example.com"
git -C "$TMP_REPO" config user.name "Test User"
touch "$TMP_REPO/README.md"
git -C "$TMP_REPO" add README.md
git -C "$TMP_REPO" commit -m "init" >/dev/null

# Test 1: default branch returns base URL
result=$(garth_github_context_url "foo/bar" "main" "fake-token" "$TMP_REPO")
[[ "$result" == "https://github.com/foo/bar" ]]

# Test 2: dry-run mode returns tree URL (no API call)
GARTH_DRY_RUN=true
result=$(garth_github_context_url "foo/bar" "feature/auth" "fake-token" "$TMP_REPO")
[[ "$result" == "https://github.com/foo/bar/tree/feature/auth" ]]
GARTH_DRY_RUN=false

# Test 3: API failure falls back to tree URL
# Use a stub that always fails by overriding garth_github_api_json_fast
garth_github_api_json_fast() { return 1; }
result=$(garth_github_context_url "foo/bar" "feature/auth" "fake-token" "$TMP_REPO")
[[ "$result" == "https://github.com/foo/bar/tree/feature/auth" ]]

# Test 4: API returning PR JSON returns PR URL
garth_github_api_json_fast() { printf '[{"number":42}]'; }
result=$(garth_github_context_url "foo/bar" "feature/auth" "fake-token" "$TMP_REPO")
[[ "$result" == "https://github.com/foo/bar/pull/42" ]]

# Test 5: API returning empty array falls back to tree URL
garth_github_api_json_fast() { printf '[]'; }
result=$(garth_github_context_url "foo/bar" "feature/auth" "fake-token" "$TMP_REPO")
[[ "$result" == "https://github.com/foo/bar/tree/feature/auth" ]]

echo "github_context_url_smoke: ok"
