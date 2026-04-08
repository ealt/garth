#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$GARTH_ROOT/lib/config-parser.py" validate "$GARTH_ROOT/config.example.toml"
ENV_OUT=$("$GARTH_ROOT/lib/config-parser.py" env "$GARTH_ROOT/config.example.toml")

echo "$ENV_OUT" | grep -q '^GARTH_DEFAULTS_SAFETY_MODE='
echo "$ENV_OUT" | grep -q '^GARTH_DEFAULTS_DEFAULT_BRANCH='
echo "$ENV_OUT" | grep -q '^GARTH_DEFAULTS_TERMINAL_LAUNCHER='
echo "$ENV_OUT" | grep -q '^GARTH_DEFAULTS_ZELLIJ_MOUSE_MODE='
echo "$ENV_OUT" | grep -q '^GARTH_AGENT_CLAUDE_BASE_COMMAND='
echo "$ENV_OUT" | grep -q '^GARTH_SECURITY_PROTECTED_PATHS_JSON='
echo "$ENV_OUT" | grep -q '^GARTH_SECURITY_SECCOMP_PROFILE='
echo "$ENV_OUT" | grep -q '^GARTH_FEATURES_PACKAGES_JSON='
echo "$ENV_OUT" | grep -q '^GARTH_FEATURES_NPM_PACKAGES_JSON='
echo "$ENV_OUT" | grep -q '^GARTH_FEATURES_MOUNTS_JSON='
echo "$ENV_OUT" | grep -q '^GARTH_BROWSER_ENGINE='
echo "$ENV_OUT" | grep -q '^GARTH_TOKEN_REFRESH_CACHE_GITHUB_APP_SECRETS='
echo "$ENV_OUT" | grep -q '^GARTH_TOKEN_REFRESH_BACKGROUND_AUTO_SIGNIN='
echo "$ENV_OUT" | grep -q '^GARTH_AGENT_CODEX_PACKAGES_JSON='
echo "$ENV_OUT" | grep -q '^GARTH_AGENT_CODEX_NPM_PACKAGES_JSON='
if echo "$ENV_OUT" | grep -q '^GARTH_CHROME_'; then
  echo "unexpected legacy GARTH_CHROME env var emission"
  exit 1
fi
if echo "$ENV_OUT" | grep -q '^GARTH_DEFAULTS_WORKSPACE='; then
  echo "unexpected legacy GARTH_DEFAULTS_WORKSPACE in env output"
  exit 1
fi

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

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
"$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG"
ENV_OUT=$("$GARTH_ROOT/lib/config-parser.py" env "$TMP_CFG")
printf '%s\n' "$ENV_OUT" | grep -q "^GARTH_AGENT_CODEX_API_KEY_REF=''\$"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
python3 - "$TMP_CFG" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

replacements = [
    (
        'packages = ["neovim", "uv", "bun", "shellcheck"]\n# Optional global npm packages to install in all selected agent images.\n# Supports unscoped names ("typescript") and scoped names ("@biomejs/biome").\nnpm_packages = []',
        'packages = ["ripgrep"]\n# Optional global npm packages to install in all selected agent images.\n# Supports unscoped names ("typescript") and scoped names ("@biomejs/biome").\nnpm_packages = ["typescript", "@biomejs/biome"]',
    ),
    (
        '[agents.codex]\nbase_command = "codex"\nsafe_args = []\npermissive_args = ["--dangerously-bypass-approvals-and-sandbox"]\napi_key_env = "OPENAI_API_KEY"\napi_key_ref = ""\npackages = []\nnpm_packages = []',
        '[agents.codex]\nbase_command = "codex"\nsafe_args = []\npermissive_args = ["--dangerously-bypass-approvals-and-sandbox"]\napi_key_env = "OPENAI_API_KEY"\napi_key_ref = ""\npackages = ["fd-find"]\nnpm_packages = ["eslint"]',
    ),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(f"missing fixture block: {old.splitlines()[0]}")
    text = text.replace(old, new, 1)

path.write_text(text)
PY
"$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG"
ENV_OUT=$("$GARTH_ROOT/lib/config-parser.py" env "$TMP_CFG")
printf '%s\n' "$ENV_OUT" | grep -q "GARTH_FEATURES_NPM_PACKAGES_JSON='\\[\"typescript\",\"@biomejs/biome\"\\]'"
printf '%s\n' "$ENV_OUT" | grep -q "GARTH_AGENT_CODEX_PACKAGES_JSON='\\[\"fd-find\"\\]'"
printf '%s\n' "$ENV_OUT" | grep -q "GARTH_AGENT_CODEX_NPM_PACKAGES_JSON='\\[\"eslint\"\\]'"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -0pi -e 's/npm_packages = \[\]/npm_packages = ["Bad Package"]/s' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected invalid features.npm_packages validation to fail"
  exit 1
fi
grep -q 'features.npm_packages\[0\]' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -0pi -e 's/\[browser\]/[chrome]/' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected [chrome] validation to fail"
  exit 1
fi
grep -q '\[chrome\] is no longer supported' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -0pi -e 's/engine = "chromium"/engine = "opera"/' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected invalid browser.engine validation to fail"
  exit 1
fi
grep -q 'browser.engine must be one of: chromium, firefox, open, none' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -0pi -e 's/engine = "chromium"/engine = "none"/' "$TMP_CFG"
"$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"
grep -q 'browser.profiles_dir is ignored when browser.engine=none' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -pi -e 's/safety_mode = "permissive"/safety_mode = "yolo"/' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected invalid safety_mode validation to fail"
  exit 1
fi
grep -q 'defaults.safety_mode must be one of: safe, permissive' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -pi -e 's/auth_passthrough = \["claude", "codex"\]/auth_passthrough = ["claude", "bogus"]/' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected invalid auth_passthrough validation to fail"
  exit 1
fi
grep -q 'defaults.auth_passthrough references missing agents.bogus' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -pi -e 's/terminal_launcher = "auto"/terminal_launcher = "tmux"/' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected invalid terminal_launcher validation to fail"
  exit 1
fi
grep -q 'defaults.terminal_launcher must be one of' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -pi -e 's/zellij_mouse_mode = "enabled"/zellij_mouse_mode = "always"/' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected invalid zellij_mouse_mode validation to fail"
  exit 1
fi
grep -q 'defaults.zellij_mouse_mode must be one of: enabled, disabled' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -pi -e 's/sandbox = "docker"/sandbox = "host"/' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected invalid sandbox validation to fail"
  exit 1
fi
grep -q 'defaults.sandbox must be one of: docker, none' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -pi -e 's/network = "bridge"/network = "host"/' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected invalid network validation to fail"
  exit 1
fi
grep -q 'defaults.network must be one of: bridge, none' "$TMP_ERR"

cp "$GARTH_ROOT/config.example.toml" "$TMP_CFG"
perl -pi -e 's/installation_strategy = "by_owner"/installation_strategy = "auto"/' "$TMP_CFG"
if "$GARTH_ROOT/lib/config-parser.py" validate "$TMP_CFG" > /dev/null 2> "$TMP_ERR"; then
  echo "expected invalid installation_strategy validation to fail"
  exit 1
fi
grep -q 'github_app.installation_strategy must be one of' "$TMP_ERR"

echo "config_parser_smoke: ok"
