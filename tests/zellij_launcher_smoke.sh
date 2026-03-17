#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$GARTH_ROOT/lib/common.sh"
source "$GARTH_ROOT/lib/zellij.sh"

garth_is_macos() {
  return 0
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-zellij-launcher-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/zellij" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list-sessions" ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_BIN/zellij"

cat > "$FAKE_BIN/ghostty" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$FAKE_BIN/ghostty"

cat > "$FAKE_BIN/osascript" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$FAKE_BIN/osascript"

PATH="$FAKE_BIN:$PATH"
export PATH

LAYOUT_FILE="$TMP_ROOT/layout.kdl"
printf '%s\n' 'layout {}' > "$LAYOUT_FILE"

GARTH_DRY_RUN=true
unset GARTH_ZELLIJ_TERMINAL_LAUNCHER
unset GARTH_DEFAULTS_TERMINAL_LAUNCHER

OUT_AUTO="$(garth_zellij_launch smoke-session "$LAYOUT_FILE" 2>&1)"
echo "$OUT_AUTO" | grep -q '\[dry-run\] .*zellij -s smoke-session --new-session-with-layout .* options --disable-mouse-mode'
echo "$OUT_AUTO" | grep -q "\[dry-run\] ghostty -e /bin/bash -lc"

GARTH_DEFAULTS_TERMINAL_LAUNCHER="current_shell"
OUT_SHELL="$(garth_zellij_launch smoke-session "$LAYOUT_FILE" 2>&1)"
echo "$OUT_SHELL" | grep -q "terminal launcher disabled; zellij will run in current shell"
if echo "$OUT_SHELL" | grep -q "ghostty -e /bin/bash -lc"; then
  echo "unexpected ghostty launch line for current_shell launcher"
  exit 1
fi
if echo "$OUT_SHELL" | grep -q "osascript Terminal"; then
  echo "unexpected terminal launch line for current_shell launcher"
  exit 1
fi

GARTH_ZELLIJ_TERMINAL_LAUNCHER="terminal"
OUT_TERMINAL="$(garth_zellij_launch smoke-session "$LAYOUT_FILE" 2>&1)"
echo "$OUT_TERMINAL" | grep -q "\[dry-run\] osascript Terminal -> /bin/bash -lc"

GARTH_ZELLIJ_TERMINAL_LAUNCHER="bogus-launcher"
OUT_BOGUS="$(garth_zellij_launch smoke-session "$LAYOUT_FILE" 2>&1)"
echo "$OUT_BOGUS" | grep -q "Unknown terminal launcher 'bogus-launcher'; falling back to auto"
echo "$OUT_BOGUS" | grep -q "\[dry-run\] ghostty -e /bin/bash -lc"

GARTH_ZELLIJ_TERMINAL_LAUNCHER="current_shell"
GARTH_DEFAULTS_ZELLIJ_MOUSE_MODE="enabled"
OUT_MOUSE_ENABLED="$(garth_zellij_launch smoke-session "$LAYOUT_FILE" 2>&1)"
if echo "$OUT_MOUSE_ENABLED" | grep -q "disable-mouse-mode"; then
  echo "unexpected zellij mouse-mode override when enabled"
  exit 1
fi

echo "zellij_launcher_smoke: ok"
