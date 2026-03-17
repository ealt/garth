#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source lib/common.sh

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-homebrew-setup.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/Cellar/garth/0.3.1/bin" "$TMP_ROOT/bin"
touch "$TMP_ROOT/Cellar/garth/0.3.1/bin/garth" "$TMP_ROOT/bin/garth"
chmod +x "$TMP_ROOT/Cellar/garth/0.3.1/bin/garth" "$TMP_ROOT/bin/garth"

RESULT="$(garth_homebrew_stable_bin_path "$TMP_ROOT/Cellar/garth/0.3.1/bin/garth")"
EXPECTED="$(garth_abs_path "$TMP_ROOT/bin/garth")"
[[ "$RESULT" == "$EXPECTED" ]] || {
  echo "FAIL: expected stable Homebrew launcher"
  exit 1
}

if garth_homebrew_stable_bin_path "$TMP_ROOT/bin/garth" >/dev/null 2>&1; then
  echo "FAIL: non-Cellar path should not resolve as Homebrew-managed"
  exit 1
fi

rm -f "$TMP_ROOT/bin/garth"
if garth_homebrew_stable_bin_path "$TMP_ROOT/Cellar/garth/0.3.1/bin/garth" >/dev/null 2>&1; then
  echo "FAIL: missing stable launcher should fail resolution"
  exit 1
fi

echo "homebrew_setup_smoke: ok"
