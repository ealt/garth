# GitHub App JWT + installation token helpers.

if [[ -n "${GARTH_GITHUB_APP_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_GITHUB_APP_SH_LOADED=1

garth_base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

garth_json_extract() {
  local json="$1"
  local key="$2"
  python3 - << 'PY' "$json" "$key"
import json
import sys
try:
    obj = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)
key = sys.argv[2]
val = obj
for part in key.split('.'):
    if not isinstance(val, dict) or part not in val:
        raise SystemExit(2)
    val = val[part]
if isinstance(val, (dict, list)):
    print(json.dumps(val))
else:
    print(val)
PY
}

garth_github_api_json() {
  local method="$1"
  local path="$2"
  local token="$3"
  local payload="${4:-}"

  local url="https://api.github.com${path}"
  local response
  if [[ -n "$payload" ]]; then
    response=$(curl -sS -X "$method" "$url" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $token" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      -w $'\n%{http_code}') || return 1
  else
    response=$(curl -sS -X "$method" "$url" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $token" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -w $'\n%{http_code}') || return 1
  fi

  local status="${response##*$'\n'}"
  local body="${response%$'\n'*}"

  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    local message="GitHub API request failed: ${method} ${path} (HTTP ${status})"
    if [[ -n "$body" ]]; then
      local gh_error
      gh_error=$(python3 - << 'PY' "$body"
import json
import sys
try:
    obj = json.loads(sys.argv[1])
except Exception:
    print("")
    raise SystemExit(0)
msg = obj.get("message", "") if isinstance(obj, dict) else ""
print(msg)
PY
)
      if [[ -n "$gh_error" ]]; then
        message+=" - ${gh_error}"
      fi
    fi
    garth_log_error "$message"
    return 1
  fi

  printf '%s' "$body"
}

garth_github_generate_app_jwt() {
  local app_id="$1"
  local private_key_file="$2"

  local now
  now=$(garth_now_epoch)
  local iat=$((now - 60))
  local exp=$((now + 600))

  local header='{"alg":"RS256","typ":"JWT"}'
  local payload
  payload=$(printf '{"iss":"%s","iat":%d,"exp":%d}' "$app_id" "$iat" "$exp")

  local header_b64 payload_b64 signature
  header_b64=$(printf '%s' "$header" | garth_base64url) || return 1
  payload_b64=$(printf '%s' "$payload" | garth_base64url) || return 1
  signature=$(printf '%s.%s' "$header_b64" "$payload_b64" | \
    openssl dgst -sha256 -sign "$private_key_file" -binary | garth_base64url) || return 1

  printf '%s.%s.%s' "$header_b64" "$payload_b64" "$signature"
}

garth_github_private_key_valid() {
  local key_file="$1"
  openssl pkey -in "$key_file" -noout >/dev/null 2>&1
}

garth_github_normalize_private_key_file() {
  local key_file="$1"
  python3 - << 'PY' "$key_file"
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")
s = text.strip()

if len(s) >= 2 and ((s[0] == s[-1] == '"') or (s[0] == s[-1] == "'")):
    s = s[1:-1]

s = s.replace("\r\n", "\n").replace("\r", "\n")
s = s.replace("\\n", "\n")

if s and not s.endswith("\n"):
    s += "\n"

path.write_text(s, encoding="utf-8")
PY
}

garth_github_installation_from_map() {
  local owner="$1"
  local map_json="$2"

  python3 - << 'PY' "$owner" "$map_json"
import json
import sys
owner = sys.argv[1]
mapping = json.loads(sys.argv[2])
if not isinstance(mapping, dict):
    raise SystemExit(1)
val = mapping.get(owner)
if val is None:
    raise SystemExit(2)
print(val)
PY
}

garth_github_resolve_installation_id() {
  local owner_repo="$1"
  local app_jwt="$2"

  local owner="${owner_repo%%/*}"
  local strategy="$GARTH_GITHUB_APP_INSTALLATION_STRATEGY"

  case "$strategy" in
    single)
      if [[ -z "$GARTH_GITHUB_APP_INSTALLATION_ID_REF" ]]; then
        garth_die "github_app.installation_id_ref is required for strategy=single" 1
      fi
      garth_secret_read "$GARTH_GITHUB_APP_INSTALLATION_ID_REF" || return 1
      ;;
    static_map)
      local mapped=""
      mapped=$(garth_github_installation_from_map "$owner" "$GARTH_GITHUB_APP_INSTALLATION_ID_MAP_JSON" 2>/dev/null || true)
      if [[ -n "$mapped" ]]; then
        printf '%s' "$mapped"
      else
        garth_log_error "No installation_id_map entry for owner '$owner'"
        return 1
      fi
      ;;
    by_owner)
      local body
      body=$(garth_github_api_json "GET" "/repos/${owner_repo}/installation" "$app_jwt") || return 1
      garth_json_extract "$body" "id" || return 1
      ;;
    *)
      garth_log_error "Unsupported installation strategy: $strategy"
      return 1
      ;;
  esac
}

# Prints tab-separated: token<TAB>expires_at<TAB>installation_id
garth_github_mint_installation_token() {
  local owner_repo="$1"

  local app_id
  app_id=$(garth_secret_read "$GARTH_GITHUB_APP_APP_ID_REF") || return 1
  [[ -n "$app_id" ]] || return 1

  local key_file
  key_file=$(mktemp "${TMPDIR:-/tmp}/garth-app-key.XXXXXX") || return 1
  garth_register_cleanup_path "$key_file"
  garth_secret_write_file "$GARTH_GITHUB_APP_PRIVATE_KEY_REF" "$key_file" || return 1
  if ! garth_github_private_key_valid "$key_file"; then
    # Common pattern: PEM stored as a single escaped string with "\n".
    garth_github_normalize_private_key_file "$key_file"
  fi
  if ! garth_github_private_key_valid "$key_file"; then
    garth_log_error "GitHub App private key is invalid. Ensure ${GARTH_GITHUB_APP_PRIVATE_KEY_REF} contains PEM text with BEGIN/END lines."
    return 1
  fi

  local app_jwt
  app_jwt=$(garth_github_generate_app_jwt "$app_id" "$key_file") || return 1

  local installation_id
  installation_id=$(garth_github_resolve_installation_id "$owner_repo" "$app_jwt") || return 1
  [[ -n "$installation_id" ]] || return 1

  local body
  body=$(garth_github_api_json "POST" "/app/installations/${installation_id}/access_tokens" "$app_jwt" "{}") || return 1

  local token expires_at
  token=$(garth_json_extract "$body" "token") || return 1
  expires_at=$(garth_json_extract "$body" "expires_at") || return 1
  [[ -n "$token" && -n "$expires_at" ]] || return 1

  printf '%s\t%s\t%s\n' "$token" "$expires_at" "$installation_id"
}

garth_iso8601_to_epoch() {
  local value="$1"
  python3 - << 'PY' "$value"
from datetime import datetime
import sys
value = sys.argv[1]
print(int(datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()))
PY
}
