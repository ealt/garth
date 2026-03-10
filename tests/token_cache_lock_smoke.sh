#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_PARENT="$GARTH_ROOT/.tmp"
mkdir -p "$TMP_PARENT"
TMP_ROOT="$(mktemp -d "$TMP_PARENT/garth-token-cache-lock-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

REPO="$TMP_ROOT/repo"
FAKE_BIN="$TMP_ROOT/bin"
STATE_HOME="$TMP_ROOT/state"
POST_LOG="$TMP_ROOT/post-calls.log"
KEY_FILE="$TMP_ROOT/app-key.pem"
OUT1="$TMP_ROOT/token-1.tsv"
OUT2="$TMP_ROOT/token-2.tsv"

mkdir -p "$REPO" "$FAKE_BIN" "$STATE_HOME"
: > "$POST_LOG"

git -C "$REPO" init >/dev/null
git -C "$REPO" remote add origin "https://github.com/acme/widgets.git"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$KEY_FILE" >/dev/null 2>&1

cat > "$FAKE_BIN/op" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "whoami" ]]; then
  echo "smoke@example.com"
  exit 0
fi

if [[ "${1:-}" == "read" ]]; then
  : "${FAKE_OP_KEY_PATH:?}"
  ref="${2:-}"
  case "$ref" in
    */app-id)
      sleep 1
      echo "123"
      ;;
    */private-key)
      sleep 1
      cat "$FAKE_OP_KEY_PATH"
      ;;
    *)
      echo "unused"
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "signin" ]]; then
  echo ""
  exit 0
fi

echo "unexpected op args: $*" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/op"

cat > "$FAKE_BIN/curl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${FAKE_CURL_POST_LOG:?}"

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

if [[ "$method" == "GET" && "$url" == "https://api.github.com/repos/acme/widgets/installation" ]]; then
  printf '{"id":456}\n200'
  exit 0
fi

if [[ "$method" == "POST" && "$url" == "https://api.github.com/app/installations/456/access_tokens" ]]; then
  printf 'post\n' >> "$FAKE_CURL_POST_LOG"
  count="$(wc -l < "$FAKE_CURL_POST_LOG" | tr -d ' ')"
  printf '{"token":"token-%s","expires_at":"2099-01-01T00:00:00Z"}\n200' "$count"
  exit 0
fi

printf '{"message":"unexpected request %s %s"}\n500' "$method" "$url"
exit 0
EOF
chmod +x "$FAKE_BIN/curl"

(
  PATH="$FAKE_BIN:$PATH" FAKE_OP_KEY_PATH="$KEY_FILE" FAKE_CURL_POST_LOG="$POST_LOG" \
    XDG_STATE_HOME="$STATE_HOME" GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" \
    "$GARTH_ROOT/bin/garth" token "$REPO" --machine > "$OUT1"
) &
pid1=$!

(
  PATH="$FAKE_BIN:$PATH" FAKE_OP_KEY_PATH="$KEY_FILE" FAKE_CURL_POST_LOG="$POST_LOG" \
    XDG_STATE_HOME="$STATE_HOME" GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" \
    "$GARTH_ROOT/bin/garth" token "$REPO" --machine > "$OUT2"
) &
pid2=$!

wait "$pid1"
wait "$pid2"

[[ "$(wc -l < "$POST_LOG" | tr -d ' ')" -eq 1 ]]

token1="$(cut -f1 "$OUT1")"
token2="$(cut -f1 "$OUT2")"
[[ -n "$token1" && "$token1" == "$token2" ]]

[[ -f "$STATE_HOME/garth/token-cache/acme_widgets.tsv" ]]

echo "token_cache_lock_smoke: ok"
