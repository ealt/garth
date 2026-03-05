#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-agent-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

NON_GIT_DIR="$TMP_ROOT/non-git-workspace"
mkdir -p "$NON_GIT_DIR"

OUT="$(
  GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true \
    "$GARTH_ROOT/bin/garth" agent "$NON_GIT_DIR" codex --sandbox none --dry-run 2>&1
)"

echo "$OUT" | grep -q "Directory is not a git repository"
echo "$OUT" | grep -q "\[dry-run\] source"

# With no explicit agent, defaults.agents should be used (multi-agent zellij launch).
OUT_DEFAULTS="$(
  GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true \
    "$GARTH_ROOT/bin/garth" agent "$NON_GIT_DIR" --sandbox docker --auth-passthrough claude,codex --dry-run 2>&1
)"

echo "$OUT_DEFAULTS" | grep -q "Directory is not a git repository"
echo "$OUT_DEFAULTS" | grep -E -q "\[dry-run\].*new-session-with-layout"

echo "agent_smoke: ok"
