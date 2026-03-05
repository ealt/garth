#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$GARTH_ROOT/lib/common.sh"
source "$GARTH_ROOT/lib/zellij.sh"

garth_container_args_lines() {
  local agent="$4"
  echo "run"
  echo "--rm"
  echo "--name"
  echo "mock-${agent}"
  echo "garth-${agent}:latest"
  echo "bash"
  echo "-lc"
  echo "echo ${agent}"
}

garth_agent_command_string() {
  local agent="$1"
  echo "$agent"
}

tmp_layout="$(mktemp)"
tmp_tokens="$(mktemp -d)"
trap 'rm -f "$tmp_layout"; rm -rf "$tmp_tokens"' EXIT

garth_generate_zellij_layout "$tmp_layout" "/tmp/worktree" "test-session" "/tmp/repo" "$tmp_tokens" \
  "bridge" "garth" "safe" "docker" "" "claude" "codex"

grep -q 'default_tab_template {' "$tmp_layout"
grep -q 'plugin location="zellij:tab-bar"' "$tmp_layout"
grep -q 'plugin location="zellij:status-bar"' "$tmp_layout"
grep -q 'tab name="claude" focus=true {' "$tmp_layout"
grep -q 'tab name="codex" {' "$tmp_layout"

[[ "$(grep -c 'pane split_direction="vertical" size="100%"' "$tmp_layout")" -eq 2 ]]
[[ "$(grep -c 'pane name="shell" size="35%" cwd="/tmp/worktree"' "$tmp_layout")" -eq 2 ]]
[[ "$(grep -c 'size="65%" command="docker"' "$tmp_layout")" -eq 2 ]]

launch_script="$(garth_zellij_launcher_script "/usr/local/bin/zellij" "test-session" "/tmp/layout.kdl")"
grep -q 'list-sessions -n' <<< "$launch_script"
grep -q -- '--new-session-with-layout' <<< "$launch_script"

echo "zellij_layout_smoke: ok"
