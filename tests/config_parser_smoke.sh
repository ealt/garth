#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$GARTH_ROOT/lib/config-parser.py" validate "$GARTH_ROOT/config.example.toml"
ENV_OUT=$("$GARTH_ROOT/lib/config-parser.py" env "$GARTH_ROOT/config.example.toml")

echo "$ENV_OUT" | grep -q '^GARTH_DEFAULTS_SAFETY_MODE='
echo "$ENV_OUT" | grep -q '^GARTH_AGENT_CLAUDE_BASE_COMMAND='

echo "config_parser_smoke: ok"
