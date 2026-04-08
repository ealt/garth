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
TMP_CFG="$TMP_ROOT/config.toml"
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

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
python3 - "$TMP_CFG" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

replacements = [
    (
        'packages = ["neovim", "uv", "bun", "shellcheck"]\n# Optional global npm packages to install in all selected agent images.\n# Supports unscoped names ("typescript") and scoped names ("@biomejs/biome").\nnpm_packages = []',
        'packages = ["ripgrep"]\n# Optional global npm packages to install in all selected agent images.\n# Supports unscoped names ("typescript") and scoped names ("@biomejs/biome").\nnpm_packages = ["typescript"]',
    ),
    (
        '[agents.codex]\nbase_command = "codex"\nsafe_args = []\npermissive_args = ["--dangerously-bypass-approvals-and-sandbox"]\napi_key_env = "OPENAI_API_KEY"\napi_key_ref = ""\npackages = []\nnpm_packages = []',
        '[agents.codex]\nbase_command = "codex"\nsafe_args = []\npermissive_args = ["--dangerously-bypass-approvals-and-sandbox"]\napi_key_env = "OPENAI_API_KEY"\napi_key_ref = ""\npackages = ["fd-find"]\nnpm_packages = ["eslint"]',
    ),
    (
        '[agents.claude]\nbase_command = "claude"\nsafe_args = []\npermissive_args = ["--dangerously-skip-permissions"]\napi_key_env = "ANTHROPIC_API_KEY"\n# Optional when using local CLI auth via defaults.auth_passthrough or sandbox=none.\napi_key_ref = ""\npackages = []\nnpm_packages = ["@openai/codex"]',
        '[agents.claude]\nbase_command = "claude"\nsafe_args = []\npermissive_args = ["--dangerously-skip-permissions"]\napi_key_env = "ANTHROPIC_API_KEY"\n# Optional when using local CLI auth via defaults.auth_passthrough or sandbox=none.\napi_key_ref = ""\npackages = ["shellcheck"]\nnpm_packages = ["@biomejs/biome"]',
    ),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(f"missing fixture block: {old.splitlines()[0]}")
    text = text.replace(old, new, 1)

path.write_text(text)
PY
: > "$DOCKER_CALLS"

PATH="$FAKE_BIN:$PATH" DOCKER_CALLS="$DOCKER_CALLS" GARTH_CONFIG_PATH="$TMP_CFG" \
  "$GARTH_ROOT/bin/garth" refresh-images --agents claude,codex --image-prefix smoke >/dev/null

[[ "$(wc -l < "$DOCKER_CALLS")" -eq 2 ]]
CODEX_CALL="$(grep -- '--target codex' "$DOCKER_CALLS")"
CLAUDE_CALL="$(grep -- '--target claude' "$DOCKER_CALLS")"

echo "$CODEX_CALL" | grep -q -- 'GARTH_FEATURE_APT_PACKAGES=ripgrep,fd-find'
echo "$CODEX_CALL" | grep -q -- 'GARTH_FEATURE_NPM_PACKAGES=typescript,eslint'
echo "$CLAUDE_CALL" | grep -q -- 'GARTH_FEATURE_APT_PACKAGES=ripgrep,shellcheck'
echo "$CLAUDE_CALL" | grep -q -- 'GARTH_FEATURE_NPM_PACKAGES=typescript,@biomejs/biome'
if echo "$CLAUDE_CALL" | grep -q -- 'fd-find'; then
  echo "claude build unexpectedly included codex-only apt package"
  exit 1
fi
if echo "$CODEX_CALL" | grep -q -- '@biomejs/biome'; then
  echo "codex build unexpectedly included claude-only npm package"
  exit 1
fi

echo "refresh_images_smoke: ok"
