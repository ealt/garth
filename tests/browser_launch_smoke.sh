#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$GARTH_ROOT/lib/common.sh"
source "$GARTH_ROOT/lib/workspace.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-browser-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN_DIR="$TMP_ROOT/bin"
mkdir -p "$BIN_DIR" "$TMP_ROOT/home"
HOME="$TMP_ROOT/home"
GARTH_DRY_RUN=true

cat > "$BIN_DIR/firefox" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN_DIR/firefox"

cat > "$BIN_DIR/chromium-browser" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN_DIR/chromium-browser"

PATH="$BIN_DIR:$PATH"

resolved="$(garth_find_browser_binary "" firefox chromium-browser)"
[[ "$resolved" == "firefox" ]] || { echo "FAIL: browser binary fallback"; exit 1; }

garth_launch_browser "none" "" "" "" "repo-main" "https://example.com"

garth_is_macos() { return 0; }

OUT="$(garth_launch_browser "chromium" "Brave Browser" "" "~/Profiles" "repo-main" "https://example.com")"
echo "$OUT" | grep -q '\[dry-run\] open -na Brave Browser --args --user-data-dir='"$HOME"'/Profiles/repo-main https://example.com'

OUT="$(garth_launch_browser "chromium" "Google Chrome" "" "" "repo-main" "https://example.com")"
echo "$OUT" | grep -q '\[dry-run\] osascript Google Chrome new window -> https://example.com'

OUT="$(garth_launch_browser "open" "Safari" "" "" "repo-main" "https://example.com")"
echo "$OUT" | grep -q '\[dry-run\] open -a Safari https://example.com'

garth_is_macos() { return 1; }

OUT="$(garth_launch_browser "firefox" "" "firefox" "~/FirefoxProfiles" "repo-main" "https://example.com")"
echo "$OUT" | grep -q '\[dry-run\] firefox -profile '"$HOME"'/FirefoxProfiles/repo-main https://example.com'

OUT="$(garth_launch_browser "chromium" "" "chromium-browser" "" "repo-main" "https://example.com")"
echo "$OUT" | grep -q '\[dry-run\] chromium-browser https://example.com'

echo "browser_launch_smoke: ok"
