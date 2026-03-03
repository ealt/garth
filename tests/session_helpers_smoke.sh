#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$GARTH_ROOT/lib/common.sh"
source "$GARTH_ROOT/lib/session.sh"

TMP_STATE="$(mktemp -d "${TMPDIR:-/tmp}/garth-session-smoke.XXXXXX")"
trap 'rm -rf "$TMP_STATE"' EXIT
GARTH_STATE_ROOT="$TMP_STATE/state"

ensure_state_root

session_dir="$(session_dir_for "example-session")"
mkdir -p "$session_dir"
write_state_value "$session_dir" "repo_root" "/tmp/repo"
write_state_value "$session_dir" "branch" "feature/auth"
write_state_value "$session_dir" "id" "a1b2c3"

[[ "$(read_state_value "$session_dir" "repo_root")" == "/tmp/repo" ]]
[[ "$(garth_session_id_for_dir "$session_dir")" == "a1b2c3" ]]
[[ "$(garth_session_name_for_dir "$session_dir")" == "example-session" ]]
[[ "$(garth_find_sessions_for_branch "/tmp/repo" "feature/auth")" == "$session_dir" ]]
[[ "$(garth_find_sessions_by_id_prefix "a1b")" == "$session_dir" ]]

echo "session_helpers_smoke: ok"
