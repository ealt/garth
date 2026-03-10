#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$GARTH_ROOT/lib/config-parser.py" validate "$GARTH_ROOT/config.example.toml"
ENV_OUT=$("$GARTH_ROOT/lib/config-parser.py" env "$GARTH_ROOT/config.example.toml")

echo "$ENV_OUT" | grep -q '^GARTH_DEFAULTS_SAFETY_MODE='
echo "$ENV_OUT" | grep -q '^GARTH_DEFAULTS_DEFAULT_BRANCH='
echo "$ENV_OUT" | grep -q '^GARTH_AGENT_CLAUDE_BASE_COMMAND='
echo "$ENV_OUT" | grep -q '^GARTH_SECURITY_PROTECTED_PATHS_JSON='
echo "$ENV_OUT" | grep -q '^GARTH_SECURITY_SECCOMP_PROFILE='
echo "$ENV_OUT" | grep -q '^GARTH_FEATURES_PACKAGES_JSON='
echo "$ENV_OUT" | grep -q '^GARTH_FEATURES_MOUNTS_JSON='
echo "$ENV_OUT" | grep -q '^GARTH_TOKEN_REFRESH_CACHE_GITHUB_APP_SECRETS='

TMP_CFG="$(mktemp "${TMPDIR:-/tmp}/garth-config-smoke.XXXXXX.toml")"
TMP_ERR="$(mktemp "${TMPDIR:-/tmp}/garth-config-smoke.XXXXXX.err")"
trap 'rm -f "$TMP_CFG" "$TMP_ERR"' EXIT
cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -0pi -e 's/\[features\]\n/\[features\]\nfoo = true\n/s' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected unsupported features key validation to fail"
  exit 1
fi
grep -q "Unknown key: features.foo" "$TMP_ERR"

echo "config_parser_smoke: ok"
