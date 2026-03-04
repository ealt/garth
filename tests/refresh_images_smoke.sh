#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_PARENT="$GARTH_ROOT/.tmp"
mkdir -p "$TMP_PARENT"
TMP_ROOT="$(mktemp -d "$TMP_PARENT/garth-refresh-images-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_BIN="$TMP_ROOT/bin"
DOCKER_CALLS="$TMP_ROOT/docker-calls.log"
DOCKER_CALLS_DRY="$TMP_ROOT/docker-calls-dry.log"
mkdir -p "$FAKE_BIN"
: > "$DOCKER_CALLS"
: > "$DOCKER_CALLS_DRY"

cat > "$FAKE_BIN/docker" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${DOCKER_CALLS:?}"
printf '%s\n' "$*" >> "$DOCKER_CALLS"
if [[ "${1:-}" == "build" ]]; then
  exit 0
fi
echo "unexpected docker command: $*" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/docker"

PATH="$FAKE_BIN:$PATH" DOCKER_CALLS="$DOCKER_CALLS" GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" \
  "$GARTH_ROOT/bin/garth" refresh-images --agents codex --image-prefix smoke >/dev/null

[[ "$(wc -l < "$DOCKER_CALLS")" -eq 1 ]]
grep -q -- 'build --pull --no-cache' "$DOCKER_CALLS"
grep -q -- '--target codex' "$DOCKER_CALLS"
grep -q -- '-t smoke-codex:latest' "$DOCKER_CALLS"

DRY_OUT="$(PATH="$FAKE_BIN:$PATH" DOCKER_CALLS="$DOCKER_CALLS_DRY" GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" \
  "$GARTH_ROOT/bin/garth" refresh-images --agents codex --image-prefix smoke --dry-run 2>&1)"

[[ "$(wc -l < "$DOCKER_CALLS_DRY")" -eq 0 ]]
echo "$DRY_OUT" | grep -q '\[dry-run\] docker build --pull --no-cache'

PATH="$FAKE_BIN:$PATH" DOCKER_CALLS="$DOCKER_CALLS_DRY" GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" \
  "$GARTH_ROOT/bin/garth" refresh --agents codex --dry-run >/dev/null

echo "refresh_images_smoke: ok"
