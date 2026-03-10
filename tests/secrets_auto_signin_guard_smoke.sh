#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$GARTH_ROOT/lib/common.sh"
source "$GARTH_ROOT/lib/secrets.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-secrets-auto-signin-guard-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

CALLS_FILE="$TMP_ROOT/op-calls.log"
ERR_DISABLED="$TMP_ROOT/disabled.err"
ERR_ENABLED="$TMP_ROOT/enabled.err"
: > "$CALLS_FILE"

garth_require_cmd() {
  return 0
}

op() {
  local cmd="${1:-}"
  printf '%s\n' "$*" >> "$CALLS_FILE"
  case "$cmd" in
    whoami)
      return 1
      ;;
    signin)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if (GARTH_OP_AUTO_SIGNIN=false GARTH_OP_SESSION_READY=false garth_require_op) 2>"$ERR_DISABLED"; then
  echo "expected garth_require_op to fail when op whoami fails"
  exit 1
fi
grep -q "auto sign-in is disabled" "$ERR_DISABLED"
if grep -q '^signin' "$CALLS_FILE"; then
  echo "op signin should not be attempted when GARTH_OP_AUTO_SIGNIN=false"
  exit 1
fi

if (GARTH_OP_AUTO_SIGNIN=true GARTH_OP_SESSION_READY=false garth_require_op) 2>"$ERR_ENABLED"; then
  echo "expected garth_require_op to fail when op whoami fails"
  exit 1
fi
grep -q "not signed in" "$ERR_ENABLED"

echo "secrets_auto_signin_guard_smoke: ok"
