# Shared helpers for garth scripts.

if [[ -n "${GARTH_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_COMMON_SH_LOADED=1

# Global runtime flags controlled by bin/garth.
: "${GARTH_DRY_RUN:=false}"
: "${GARTH_YES:=false}"
: "${GARTH_PYTHON_BIN:=python3}"
: "${GARTH_TRACE_PYTHON:=false}"

# Track temporary paths that should be cleaned up on exit.
GARTH_CLEANUP_PATHS=()

garth_color_blue='\033[0;34m'
garth_color_green='\033[0;32m'
garth_color_yellow='\033[1;33m'
garth_color_red='\033[0;31m'
garth_color_reset='\033[0m'

garth_log_info() {
  echo -e "${garth_color_blue}[info]${garth_color_reset} $*"
}

garth_log_success() {
  echo -e "${garth_color_green}[ok]${garth_color_reset}   $*"
}

garth_log_warn() {
  echo -e "${garth_color_yellow}[warn]${garth_color_reset} $*" >&2
}

garth_log_error() {
  echo -e "${garth_color_red}[err]${garth_color_reset}  $*" >&2
}

garth_die() {
  local code="${2:-1}"
  garth_log_error "$1"
  exit "$code"
}

garth_run_cmd() {
  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

garth_ask_yn() {
  local prompt="$1"
  if [[ "$GARTH_YES" == "true" ]]; then
    echo "$prompt [auto-yes]"
    return 0
  fi

  while true; do
    read -r -p "$prompt [y/n] " answer
    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

garth_has_tty() {
  [[ -t 0 && -t 1 ]]
}

garth_prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local answer=""
  read -r -p "$prompt [$default]: " answer
  if [[ -z "$answer" ]]; then
    answer="$default"
  fi
  printf '%s' "$answer"
}

garth_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || garth_die "Missing required command: $cmd" 2
}

garth_is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

# Prefer Homebrew Python on macOS to avoid system toolchain prompts.
if garth_is_macos && [[ -x "/opt/homebrew/bin/python3" ]]; then
  GARTH_PYTHON_BIN="/opt/homebrew/bin/python3"
fi

garth_python() {
  if [[ "$GARTH_TRACE_PYTHON" == "true" && "${GARTH_PYTHON_LOGGED_ONCE:-false}" != "true" ]]; then
    garth_log_info "Using Python runtime: $GARTH_PYTHON_BIN" >&2
    GARTH_PYTHON_LOGGED_ONCE=true
  fi
  "$GARTH_PYTHON_BIN" "$@"
}

garth_now_epoch() {
  date +%s
}

# Parse a duration string like 5s, 10m, 2h, 0m, or forever.
# Prints seconds to stdout. forever => -1
# Returns non-zero on invalid format.
garth_parse_duration_to_seconds() {
  local raw="$1"

  if [[ "$raw" == "forever" ]]; then
    echo "-1"
    return 0
  fi

  if [[ "$raw" =~ ^([0-9]+)([smh])$ ]]; then
    local value="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
      s) echo "$value" ;;
      m) echo $((value * 60)) ;;
      h) echo $((value * 3600)) ;;
      *) return 1 ;;
    esac
    return 0
  fi

  return 1
}

garth_require_duration() {
  local value="$1"
  local field="$2"
  if ! garth_parse_duration_to_seconds "$value" >/dev/null; then
    garth_die "Invalid duration for $field: $value" 1
  fi
}

garth_abs_path() {
  local input="$1"
  if [[ -d "$input" ]]; then
    (cd "$input" && pwd)
  else
    local parent
    parent=$(cd "$(dirname "$input")" && pwd)
    echo "$parent/$(basename "$input")"
  fi
}

garth_join_by() {
  local delimiter="$1"
  shift
  local first=true
  local item
  for item in "$@"; do
    if [[ "$first" == "true" ]]; then
      printf '%s' "$item"
      first=false
    else
      printf '%s%s' "$delimiter" "$item"
    fi
  done
}

garth_json_array_to_lines() {
  local json="$1"
  garth_python - << 'PY' "$json"
import json
import sys
arr = json.loads(sys.argv[1])
if not isinstance(arr, list):
    raise SystemExit(1)
for item in arr:
    print(str(item))
PY
}

garth_json_get() {
  local json="$1"
  local key="$2"
  garth_python - << 'PY' "$json" "$key"
import json
import sys
obj = json.loads(sys.argv[1])
key = sys.argv[2]
if not isinstance(obj, dict):
    raise SystemExit(1)
val = obj.get(key)
if val is None:
    raise SystemExit(2)
print(val)
PY
}

garth_make_temp_dir() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/garth.XXXXXX")
  chmod 700 "$dir"
  garth_register_cleanup_path "$dir"
  echo "$dir"
}

garth_register_cleanup_path() {
  local path="$1"
  GARTH_CLEANUP_PATHS+=("$path")
}

garth_cleanup_paths() {
  local path
  for path in "${GARTH_CLEANUP_PATHS[@]:-}"; do
    [[ -z "$path" ]] && continue
    rm -rf "$path" 2>/dev/null || true
  done
}

garth_install_cleanup_trap() {
  trap garth_cleanup_paths EXIT INT TERM
}

# Normalize branch names into safe path slug components.
garth_slugify_branch() {
  local branch="$1"
  local slug
  slug=$(echo "$branch" | sed -E 's|/|__|g; s|[^A-Za-z0-9._-]|-|g; s|-+|-|g; s|__+|__|g')
  slug=$(echo "$slug" | sed -E 's|^[-_.]+||; s|[-_.]+$||')
  if [[ -z "$slug" ]]; then
    slug="branch"
  fi
  echo "$slug"
}

garth_token_prefix() {
  local token="$1"
  [[ -n "$token" ]] || return 0
  local prefix="${token:0:8}"
  if [[ ${#token} -gt 8 ]]; then
    printf '%s...' "$prefix"
  else
    printf '%s' "$prefix"
  fi
}

garth_op_ref_vault_name() {
  local ref="$1"
  if [[ "$ref" =~ ^op://([^/]+)/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

garth_redact_secret_text() {
  local value="$1"
  garth_python - << 'PY' "$value"
import re
import sys

text = sys.argv[1]
patterns = [
    (r'op://[^\s"\']+', "op://[REDACTED]"),
    (r"\bghs_[A-Za-z0-9_]+\b", "ghs_[REDACTED]"),
    (r"\bgithub_pat_[A-Za-z0-9_]+\b", "github_pat_[REDACTED]"),
    (r"\bsk-[A-Za-z0-9_-]{12,}\b", "sk-[REDACTED]"),
    (r"(Bearer\s+)[A-Za-z0-9._-]+", r"\1[REDACTED]"),
]

for pattern, replacement in patterns:
    text = re.sub(pattern, replacement, text)

print(text)
PY
}

garth_audit_log() {
  local session_dir="$1"
  local event="$2"
  shift 2 || true

  [[ -n "$session_dir" ]] || return 0
  local audit_file="$session_dir/audit.log"
  if [[ ! -f "$audit_file" ]]; then
    umask 077
    : > "$audit_file"
    chmod 600 "$audit_file"
  fi

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local -a fields=()
  fields+=("timestamp=${timestamp}")
  fields+=("event=${event}")

  local pair key value vault
  for pair in "$@"; do
    [[ "$pair" == *=* ]] || continue
    key="${pair%%=*}"
    value="${pair#*=}"
    case "$key" in
      token|github_token|access_token)
        fields+=("token_prefix=$(garth_token_prefix "$value")")
        ;;
      api_key|api_key_value|secret|secret_value)
        ;;
      api_key_env|token_expires_at|session|repo_root|worktree|branch|owner_repo|agents|agent|network|sandbox|safety_mode|state|installation_id|exit_code|sensitive_paths_csv|sensitive_count|refresher_pid|auth_passthrough)
        fields+=("${key}=${value}")
        ;;
      *ref)
        vault=$(garth_op_ref_vault_name "$value")
        if [[ -n "$vault" ]]; then
          fields+=("ref_vault=${vault}")
        fi
        ;;
      *)
        fields+=("${key}=$(garth_redact_secret_text "$value")")
        ;;
    esac
  done

  local json_line
  if ! json_line=$(garth_python - << 'PY' "${fields[@]}"
import json
import sys

obj = {}
for raw in sys.argv[1:]:
    if "=" not in raw:
        continue
    key, value = raw.split("=", 1)
    obj[key] = value
print(json.dumps(obj, separators=(",", ":")))
PY
  ); then
    return 0
  fi

  printf '%s\n' "$json_line" >> "$audit_file"
  chmod 600 "$audit_file" 2>/dev/null || true
}
