#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_PARENT="$GARTH_ROOT/.tmp"
mkdir -p "$TMP_PARENT"
TMP_ROOT="$(mktemp -d "$TMP_PARENT/garth-github-app-override-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

REPO="$TMP_ROOT/repo"
FAKE_BIN="$TMP_ROOT/bin"
STATE_HOME="$TMP_ROOT/state"
OP_CALLS="$TMP_ROOT/op-calls.log"
KEY_FILE="$TMP_ROOT/app-key.pem"
OUT="$TMP_ROOT/token.tsv"
CFG="$TMP_ROOT/config.toml"

mkdir -p "$REPO" "$FAKE_BIN" "$STATE_HOME"
: > "$OP_CALLS"

cp "$GARTH_ROOT/config.example.toml" "$CFG"
perl -0pi -e 's/installation_strategy = "by_owner"/installation_strategy = "single"/g' "$CFG"
sed -i.bak 's|installation_id_ref = ""|installation_id_ref = "op://fake/GitHub App/installation-id"|' "$CFG"
rm -f "$CFG.bak"

git -C "$REPO" init >/dev/null
git -C "$REPO" remote add origin "https://github.com/acme/widgets.git"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$KEY_FILE" >/dev/null 2>&1

cat > "$FAKE_BIN/op" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_OP_CALLS:?}"
printf '%s\n' "$*" >> "$FAKE_OP_CALLS"
echo "op should not be called when github app overrides are set" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/op"

cat > "$FAKE_BIN/curl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X)
      method="$2"
      shift 2
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "$method" == "GET" && "$url" == "https://api.github.com/app" ]]; then
  printf '{"id":123}\n200'
  exit 0
fi

if [[ "$method" == "POST" && "$url" == "https://api.github.com/app/installations/456/access_tokens" ]]; then
  printf '{"token":"override-token","expires_at":"2099-01-01T00:00:00Z"}\n200'
  exit 0
fi

printf '{"message":"unexpected request %s %s"}\n500' "$method" "$url"
exit 0
EOF
chmod +x "$FAKE_BIN/curl"

PATH="$FAKE_BIN:$PATH" FAKE_OP_CALLS="$OP_CALLS" XDG_STATE_HOME="$STATE_HOME" GARTH_CONFIG_PATH="$CFG" \
  GARTH_GITHUB_APP_APP_ID_OVERRIDE="123" \
  GARTH_GITHUB_APP_PRIVATE_KEY_FILE_OVERRIDE="$KEY_FILE" \
  GARTH_GITHUB_APP_INSTALLATION_ID_OVERRIDE="456" \
  "$GARTH_ROOT/bin/garth" token "$REPO" --machine > "$OUT"

grep -q '^override-token' "$OUT"
[[ ! -s "$OP_CALLS" ]]

echo "github_app_override_smoke: ok"
