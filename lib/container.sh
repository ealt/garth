# Docker lifecycle helpers for garth.

if [[ -n "${GARTH_CONTAINER_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_CONTAINER_SH_LOADED=1

garth_sandbox_dir_name() {
  local repo_root="$1"
  local repo_name
  repo_name=$(basename "$repo_root")
  repo_name=$(echo "$repo_name" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')
  [[ -n "$repo_name" ]] || repo_name="repo"
  echo "${repo_name}-sandbox"
}

garth_sandbox_workdir() {
  local repo_root="$1"
  echo "/$(garth_sandbox_dir_name "$repo_root")"
}

garth_agent_key() {
  local name="$1"
  echo "$name" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]/_/g'
}

garth_agent_field() {
  local agent="$1"
  local field="$2"
  local key
  key=$(garth_agent_key "$agent")
  local var="GARTH_AGENT_${key}_${field}"
  printf '%s' "${!var:-}"
}

garth_agent_command_string() {
  local agent="$1"
  local safety_mode="$2"

  local base_command
  base_command=$(garth_agent_field "$agent" "BASE_COMMAND")
  [[ -n "$base_command" ]] || garth_die "Unknown agent config: $agent" 1

  local args_json
  if [[ "$safety_mode" == "permissive" ]]; then
    args_json=$(garth_agent_field "$agent" "PERMISSIVE_ARGS_JSON")
  else
    args_json=$(garth_agent_field "$agent" "SAFE_ARGS_JSON")
  fi

  local cmd="$base_command"
  local arg
  while IFS= read -r arg; do
    [[ -z "$arg" ]] && continue
    cmd+=" $(printf '%q' "$arg")"
  done < <(garth_json_array_to_lines "${args_json:-[]}")

  printf '%s' "$cmd"
}

garth_claude_runtime_preamble() {
  cat <<'SCRIPT'
seed_claude_json_from_host() {
  local host_seed="/run/garth-host-claude.json"
  if [[ ! -f "$host_seed" ]]; then
    return 1
  fi
  if ! jq -e . "$host_seed" >/dev/null 2>&1; then
    return 1
  fi
  cp "$host_seed" /home/agent/.claude.json
  echo "[garth] Seeded /home/agent/.claude.json from $host_seed"
  return 0
}

find_claude_backup_with_oauth() {
  local backup
  while IFS= read -r backup; do
    [[ -n "$backup" ]] || continue
    if ! jq -e . "$backup" >/dev/null 2>&1; then
      continue
    fi
    if jq -e '.oauthAccount and (.oauthAccount | type == "object")' "$backup" >/dev/null 2>&1; then
      printf '%s\n' "$backup"
      return 0
    fi
  done < <(ls -1t /home/agent/.claude/backups/.claude.json.backup.* /home/agent/.claude/backups/.claude.json.corrupted.* 2>/dev/null || true)
  return 1
}

find_any_valid_claude_backup() {
  local backup
  while IFS= read -r backup; do
    [[ -n "$backup" ]] || continue
    if jq -e . "$backup" >/dev/null 2>&1; then
      printf '%s\n' "$backup"
      return 0
    fi
  done < <(ls -1t /home/agent/.claude/backups/.claude.json.backup.* /home/agent/.claude/backups/.claude.json.corrupted.* 2>/dev/null || true)
  return 1
}

ensure_claude_state_from_backup() {
  if jq -e '.oauthAccount and (.oauthAccount | type == "object") and .firstStartTime' /home/agent/.claude.json >/dev/null 2>&1; then
    return 0
  fi

  local backup=""
  if ! backup="$(find_claude_backup_with_oauth)"; then
    return 1
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  if jq --slurp '
    (.[0] // {}) as $current
    | (.[1] // {}) as $backup
    | ($backup + $current + {oauthAccount: ($current.oauthAccount // $backup.oauthAccount)})
  ' /home/agent/.claude.json "$backup" > "$tmp_file"; then
    if cp "$tmp_file" /home/agent/.claude.json; then
      echo "[garth] Merged /home/agent/.claude.json with backup state from $backup"
    else
      cp "$backup" /home/agent/.claude.json
      echo "[garth] Replaced /home/agent/.claude.json from $backup"
    fi
  else
    cp "$backup" /home/agent/.claude.json
    echo "[garth] Replaced /home/agent/.claude.json from $backup"
  fi
  rm -f "$tmp_file"
  return 0
}

ensure_claude_startup_state() {
  local workdir="${PWD:-/home/agent}"
  if [[ "$workdir" != /* ]]; then
    workdir="/home/agent"
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  if jq --arg wd "$workdir" '
    .theme = (
      if (.theme | type) == "string" and (.theme | length) > 0
      then .theme
      else "dark"
      end
    )
    | .hasCompletedOnboarding = true
    | .lastOnboardingVersion = (.lastOnboardingVersion // .lastReleaseNotesSeen // "2.1.62")
    | .projects = (
        (.projects // {})
        + {
            ($wd): (
              ((.projects // {})[$wd] // {})
              + {
                  hasTrustDialogAccepted: true,
                  projectOnboardingSeenCount: (
                    (((.projects // {})[$wd].projectOnboardingSeenCount // 0)
                    | if . < 1 then 1 else . end)
                  )
                }
            )
          }
      )
  ' /home/agent/.claude.json > "$tmp_file"; then
    cp "$tmp_file" /home/agent/.claude.json
    echo "[garth] Ensured Claude startup state for $workdir"
  fi
  rm -f "$tmp_file"
  return 0
}

ensure_claude_native_launcher() {
  local native_dir="/home/agent/.local/bin"
  local native_cmd="$native_dir/claude"
  local fallback_cmd="/usr/local/bin/claude"

  mkdir -p "$native_dir"

  if [[ ! -x "$native_cmd" && -x "$fallback_cmd" ]]; then
    if ! ln -sf "$fallback_cmd" "$native_cmd" 2>/dev/null; then
      cp "$fallback_cmd" "$native_cmd"
      chmod 755 "$native_cmd" 2>/dev/null || true
    fi
    echo "[garth] Ensured Claude native launcher at $native_cmd"
  fi
  return 0
}

restore_claude_json() {
  local restored=""
  local backup=""
  if seed_claude_json_from_host; then
    restored="/run/garth-host-claude.json"
  fi
  if [[ -z "$restored" ]]; then
    if backup="$(find_claude_backup_with_oauth)"; then
      cp "$backup" /home/agent/.claude.json
      restored="$backup"
    elif backup="$(find_any_valid_claude_backup)"; then
      cp "$backup" /home/agent/.claude.json
      restored="$backup"
    fi
  fi

  if [[ -n "$restored" ]]; then
    echo "[garth] Restored /home/agent/.claude.json from $restored"
  else
    printf "{}\n" > /home/agent/.claude.json
    echo "[garth] Reinitialized /home/agent/.claude.json with empty JSON"
  fi

  ensure_claude_state_from_backup || true
}

if [[ ! -f /home/agent/.claude.json ]]; then
  restore_claude_json
elif ! jq -e . /home/agent/.claude.json >/dev/null 2>&1; then
  restore_claude_json
fi

ensure_claude_state_from_backup || true
ensure_claude_startup_state || true
ensure_claude_native_launcher || true
SCRIPT
}

garth_agent_runtime_wrap_command() {
  local agent="$1"
  local cmd="$2"

  if [[ "$agent" == "claude" ]]; then
    local preamble
    local preamble_escaped
    preamble=$(garth_claude_runtime_preamble)
    printf -v preamble_escaped '%q' "$preamble"
    printf '%s' "eval ${preamble_escaped}; ${cmd}"
    return 0
  fi

  printf '%s' "$cmd"
}

garth_agent_primary_binary() {
  local agent="$1"
  local base_command
  base_command=$(garth_agent_field "$agent" "BASE_COMMAND")
  [[ -n "$base_command" ]] || return 1

  local primary=""
  IFS=' ' read -r primary _ <<< "$base_command"
  [[ -n "$primary" ]] || return 1
  printf '%s' "$primary"
}

# Creates per-agent env file (0600) and prints path.
garth_prepare_agent_env_file() {
  local session_dir="$1"
  local agent="$2"
  local require_api_key="${3:-true}"

  local api_key_env api_key_ref
  api_key_env=$(garth_agent_field "$agent" "API_KEY_ENV")
  api_key_ref=$(garth_agent_field "$agent" "API_KEY_REF")

  [[ -n "$api_key_env" ]] || garth_die "Missing api_key_env for agent: $agent" 1

  local has_api_key=false
  local api_key=""

  if [[ "$require_api_key" == "true" ]]; then
    [[ -n "$api_key_ref" ]] || garth_die "Missing api_key_ref for agent: $agent" 1
    if [[ "$api_key_ref" == *"<"* ]]; then
      garth_log_error "Agent '$agent' api_key_ref is still a placeholder: $api_key_ref"
      garth_log_error "Set a real 1Password ref for agents.$agent.api_key_ref in config.toml"
      garth_log_error "Or run with --sandbox none to use local CLI login auth."
      return 1
    fi
    garth_require_op
    if ! api_key=$(garth_secret_read "$api_key_ref"); then
      garth_log_error "Failed to read agents.$agent.api_key_ref: $api_key_ref"
      return 1
    fi
    has_api_key=true
  else
    # Host mode can rely on existing local CLI auth sessions (consumer subscriptions).
    # Skip secret read for empty, placeholder, or explicitly disabled refs.
    if [[ -n "$api_key_ref" && "$api_key_ref" != *"<"* && "$api_key_ref" != "none" ]]; then
      if api_key=$(garth_secret_read "$api_key_ref"); then
        has_api_key=true
      else
        garth_log_warn "Could not read agents.$agent.api_key_ref; continuing with CLI auth passthrough"
      fi
    fi
  fi

  local env_file="$session_dir/agent-${agent}.env"
  umask 077
  {
    printf 'TERM=xterm-256color\n'
    printf 'GARTH_GITHUB_TOKEN_FILE=/run/garth/github_token\n'
    if [[ "$has_api_key" == "true" ]]; then
      printf '%s=%s\n' "$api_key_env" "$api_key"
    fi
  } > "$env_file"
  chmod 600 "$env_file"

  echo "$env_file"
}

# Writes or rotates the github token file atomically.
garth_write_token_file() {
  local session_dir="$1"
  local token="$2"

  local token_file="$session_dir/github_token"
  local tmp_file="$token_file.tmp.$$"

  umask 077
  printf '%s\n' "$token" > "$tmp_file"
  chmod 600 "$tmp_file"
  mv "$tmp_file" "$token_file"

  echo "$token_file"
}

garth_container_name() {
  local session="$1"
  local agent="$2"
  local name="${session}-${agent}"
  # Docker names allow [a-zA-Z0-9][a-zA-Z0-9_.-]
  name=$(echo "$name" | sed -E 's/[^A-Za-z0-9_.-]/-/g')
  echo "${name:0:80}"
}

garth_container_auth_mount_mode() {
  local key="$1"
  local default_mode="${2:-rw}"
  local env_key
  env_key=$(echo "$key" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]/_/g')
  local env_var="GARTH_SECURITY_AUTH_MOUNT_MODE_${env_key}"
  local mode="${!env_var:-$default_mode}"
  if [[ "$mode" != "ro" && "$mode" != "rw" ]]; then
    mode="$default_mode"
  fi
  printf '%s' "$mode"
}

garth_container_seccomp_profile_path() {
  local profile="${GARTH_SECURITY_SECCOMP_PROFILE:-docker/seccomp-profile.json}"
  [[ -n "$profile" ]] || return 1

  if [[ "$profile" != /* ]]; then
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    profile="${root}/${profile}"
  fi

  [[ -f "$profile" ]] || return 1
  printf '%s' "$profile"
}

garth_container_emit_seccomp_opt_lines() {
  local profile
  profile=$(garth_container_seccomp_profile_path) || return 0
  echo "--security-opt"
  echo "seccomp=${profile}"
}

garth_container_emit_protected_path_mounts_lines() {
  local worktree="$1"
  local sandbox_workdir="$2"
  local protected_json="${GARTH_SECURITY_PROTECTED_PATHS_JSON:-[\".git/hooks\",\".git/config\",\".github\",\".gitmodules\"]}"
  local count=0
  local rel_path host_path container_path

  while IFS= read -r rel_path; do
    [[ -n "$rel_path" ]] || continue
    rel_path="${rel_path#./}"
    if [[ "$rel_path" == /* ]]; then
      garth_log_warn "Ignoring absolute protected path outside worktree scope: $rel_path"
      continue
    fi

    host_path="${worktree}/${rel_path}"
    container_path="${sandbox_workdir}/${rel_path}"
    if [[ -e "$host_path" ]]; then
      echo "-v"
      echo "${host_path}:${container_path}:ro"
      count=$((count + 1))
    fi
  done < <(garth_json_array_to_lines "$protected_json" 2>/dev/null || true)

  [[ "$count" -gt 0 ]]
}

garth_container_emit_auth_mounts_lines() {
  local agent="$1"
  local count=0

  if [[ "$agent" == "codex" ]]; then
    local codex_mode
    codex_mode=$(garth_container_auth_mount_mode "codex_dot_codex" "rw")
    if [[ -d "$HOME/.codex" ]]; then
      echo "-v"
      echo "$HOME/.codex:/home/agent/.codex:${codex_mode}"
      count=$((count + 1))
    fi
  fi

  if [[ "$agent" == "claude" ]]; then
    local claude_dot_claude_mode claude_config_mode claude_state_mode claude_share_mode claude_cache_mode
    claude_dot_claude_mode=$(garth_container_auth_mount_mode "claude_dot_claude" "rw")
    claude_config_mode=$(garth_container_auth_mount_mode "claude_config" "rw")
    claude_state_mode=$(garth_container_auth_mount_mode "claude_state" "rw")
    claude_share_mode=$(garth_container_auth_mount_mode "claude_share" "ro")
    claude_cache_mode=$(garth_container_auth_mount_mode "claude_cache" "rw")

    if [[ -d "$HOME/.claude" ]]; then
      echo "-v"
      echo "$HOME/.claude:/home/agent/.claude:${claude_dot_claude_mode}"
      count=$((count + 1))
    fi
    if [[ -f "$HOME/.claude.json" ]]; then
      echo "-v"
      echo "$HOME/.claude.json:/run/garth-host-claude.json:ro"
      count=$((count + 1))
    fi
    if [[ -d "$HOME/.config/claude" ]]; then
      echo "-v"
      echo "$HOME/.config/claude:/home/agent/.config/claude:${claude_config_mode}"
      count=$((count + 1))
    fi
    # Claude may persist auth/session state across these XDG paths.
    local claude_runtime_dirs=(
      "$HOME/.local/state/claude"
      "$HOME/.local/share/claude"
      "$HOME/.cache/claude"
    )
    local claude_dir
    for claude_dir in "${claude_runtime_dirs[@]}"; do
      mkdir -p "$claude_dir" >/dev/null 2>&1 || true
    done
    if [[ -d "$HOME/.local/state/claude" ]]; then
      echo "-v"
      echo "$HOME/.local/state/claude:/home/agent/.local/state/claude:${claude_state_mode}"
      count=$((count + 1))
    fi
    if [[ -d "$HOME/.local/share/claude" ]]; then
      echo "-v"
      echo "$HOME/.local/share/claude:/home/agent/.local/share/claude:${claude_share_mode}"
      count=$((count + 1))
    fi
    if [[ -d "$HOME/.cache/claude" ]]; then
      echo "-v"
      echo "$HOME/.cache/claude:/home/agent/.cache/claude:${claude_cache_mode}"
      count=$((count + 1))
    fi
  fi

  [[ "$count" -gt 0 ]]
}

garth_expand_home_path() {
  local path="$1"
  if [[ "$path" == "~" ]]; then
    printf '%s' "$HOME"
    return 0
  fi
  # Intentionally matching literal ~/prefix from config values
  # shellcheck disable=SC2088
  if [[ "$path" == "~/"* ]]; then
    printf '%s' "$HOME/${path#\~/}"
    return 0
  fi
  printf '%s' "$path"
}

garth_features_mount_specs_lines() {
  local mounts_json="${GARTH_FEATURES_MOUNTS_JSON:-[]}"
  garth_python - <<'PY' "$mounts_json"
import json
import sys

try:
    mounts = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)

if not isinstance(mounts, list):
    raise SystemExit(1)

for item in mounts:
    if not isinstance(item, dict):
        continue
    host = item.get("host_path", "")
    container = item.get("container_path", "")
    mode = item.get("mode", "ro")
    if not isinstance(host, str):
        continue
    host = host.strip()
    if not host:
        continue
    if not isinstance(container, str):
        container = ""
    else:
        container = container.strip()
    if not isinstance(mode, str):
        mode = "ro"
    mode = mode.strip().lower()
    if mode not in {"ro", "rw"}:
        mode = "ro"
    print(f"{host}|{container}|{mode}")
PY
}

garth_features_packages_lines() {
  local packages_json="${GARTH_FEATURES_PACKAGES_JSON:-[]}"
  garth_json_array_to_lines "$packages_json" 2>/dev/null || true
}

garth_features_npm_packages_lines() {
  local packages_json="${GARTH_FEATURES_NPM_PACKAGES_JSON:-[]}"
  garth_json_array_to_lines "$packages_json" 2>/dev/null || true
}

garth_agent_extra_packages_lines() {
  local agent="$1"
  local packages_json
  packages_json=$(garth_agent_field "$agent" "PACKAGES_JSON")
  garth_json_array_to_lines "${packages_json:-[]}" 2>/dev/null || true
}

garth_agent_extra_npm_packages_lines() {
  local agent="$1"
  local packages_json
  packages_json=$(garth_agent_field "$agent" "NPM_PACKAGES_JSON")
  garth_json_array_to_lines "${packages_json:-[]}" 2>/dev/null || true
}

garth_unique_lines() {
  local seen=$'\n'
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$seen" in
      *$'\n'"$line"$'\n'*) continue ;;
    esac
    printf '%s\n' "$line"
    seen+="${line}"$'\n'
  done
}

garth_lines_to_csv() {
  local first=true
  local out=""
  local item
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if [[ "$first" == "true" ]]; then
      out="$item"
      first=false
    else
      out="${out},${item}"
    fi
  done
  printf '%s' "$out"
}

garth_agent_feature_packages_lines() {
  local agent="$1"
  {
    garth_features_packages_lines
    garth_agent_extra_packages_lines "$agent"
  } | garth_unique_lines
}

garth_agent_feature_npm_packages_lines() {
  local agent="$1"
  {
    garth_features_npm_packages_lines
    garth_agent_extra_npm_packages_lines "$agent"
  } | garth_unique_lines
}

garth_features_packages_csv() {
  garth_features_packages_lines | garth_lines_to_csv
}

garth_agent_feature_packages_csv() {
  local agent="$1"
  garth_agent_feature_packages_lines "$agent" | garth_lines_to_csv
}

garth_agent_feature_npm_packages_csv() {
  local agent="$1"
  garth_agent_feature_npm_packages_lines "$agent" | garth_lines_to_csv
}

garth_container_emit_feature_mounts_lines() {
  local count=0
  local host_raw container_raw mode host_path container_path
  while IFS='|' read -r host_raw container_raw mode; do
    [[ -n "$host_raw" ]] || continue
    host_path=$(garth_expand_home_path "$host_raw")
    container_path="$container_raw"
    if [[ -z "$container_path" ]]; then
      # Default to same absolute path to preserve host symlink targets.
      container_path="$host_path"
    fi
    if [[ -e "$host_path" ]]; then
      echo "-v"
      echo "${host_path}:${container_path}:${mode}"
      count=$((count + 1))
    else
      garth_log_warn "Configured mount source is missing: $host_path"
    fi
  done < <(garth_features_mount_specs_lines 2>/dev/null || true)

  [[ "$count" -gt 0 ]]
}

# Print docker args one per line for zellij KDL serialization.
garth_container_args_lines() {
  local session="$1"
  local repo_root="$2"
  local worktree="$3"
  local agent="$4"
  local env_file="$5"
  local token_dir="$6"
  local network="$7"
  local image_prefix="$8"
  local safety_mode="$9"
  local auth_passthrough_enabled="${10:-false}"

  local command_string
  command_string=$(garth_agent_command_string "$agent" "$safety_mode")
  command_string=$(garth_agent_runtime_wrap_command "$agent" "$command_string")
  local sandbox_workdir
  sandbox_workdir=$(garth_sandbox_workdir "$repo_root")

  local image="${image_prefix}-${agent}:latest"
  local name
  name=$(garth_container_name "$session" "$agent")

  echo "run"
  echo "-it"
  echo "--rm"
  echo "--name"
  echo "$name"
  echo "--label"
  echo "garth.session=$session"
  echo "--label"
  echo "garth.repo=$repo_root"
  echo "--label"
  echo "garth.agent=$agent"
  echo "--cap-drop=ALL"
  echo "--security-opt"
  echo "no-new-privileges:true"
  garth_container_emit_seccomp_opt_lines
  echo "--pids-limit"
  echo "512"
  echo "--read-only"
  echo "--tmpfs"
  echo "/tmp:rw,noexec,nosuid,size=256m"
  echo "--tmpfs"
  echo "/home/agent:rw,exec,nosuid,size=1024m,uid=1001,gid=1001,mode=0700"
  echo "--tmpfs"
  echo "/home/agent/.cache:rw,noexec,nosuid,size=1024m,uid=1001,gid=1001,mode=0700"
  echo "--tmpfs"
  echo "/home/agent/.local:rw,exec,nosuid,size=256m,uid=1001,gid=1001,mode=0700"
  echo "--memory"
  echo "8g"
  echo "--cpus"
  echo "4"
  echo "--network"
  echo "$network"
  echo "-v"
  echo "${worktree}:${sandbox_workdir}"
  garth_container_emit_protected_path_mounts_lines "$worktree" "$sandbox_workdir" || true
  echo "-v"
  echo "${token_dir}:/run/garth:ro"
  if [[ "$auth_passthrough_enabled" == "true" ]]; then
    if ! garth_container_emit_auth_mounts_lines "$agent"; then
      garth_log_warn "Docker auth passthrough enabled for '$agent' but no local auth files were found"
      garth_log_warn "Run local login first (for example: 'codex login' or 'claude auth login')"
    fi
  fi
  garth_container_emit_feature_mounts_lines || true
  echo "--env-file"
  echo "$env_file"
  echo "--env"
  echo "HOME=/home/agent"
  echo "--env"
  echo "XDG_CACHE_HOME=/home/agent/.cache"
  echo "--env"
  echo "XDG_CONFIG_HOME=/home/agent/.config"
  echo "--env"
  echo "XDG_STATE_HOME=/home/agent/.local/state"
  echo "--env"
  echo "PATH=/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  echo "-w"
  echo "${sandbox_workdir}"
  echo "$image"
  echo "bash"
  echo "-lc"
  echo "$command_string"
}

garth_container_shell_args_lines() {
  local session="$1"
  local repo_root="$2"
  local worktree="$3"
  local token_dir="$4"
  local network="$5"
  local image_prefix="$6"
  local shell_agent="${7:-claude}"
  local auth_passthrough_enabled="${8:-false}"
  local image="${image_prefix}-${shell_agent}:latest"
  local sandbox_workdir
  sandbox_workdir=$(garth_sandbox_workdir "$repo_root")
  local name
  name=$(garth_container_name "$session" "shell")

  echo "run"
  echo "-it"
  echo "--rm"
  echo "--name"
  echo "$name"
  echo "--label"
  echo "garth.session=$session"
  echo "--label"
  echo "garth.repo=$repo_root"
  echo "--label"
  echo "garth.agent=shell"
  echo "--cap-drop=ALL"
  echo "--security-opt"
  echo "no-new-privileges:true"
  garth_container_emit_seccomp_opt_lines
  echo "--pids-limit"
  echo "512"
  echo "--read-only"
  echo "--tmpfs"
  echo "/tmp:rw,noexec,nosuid,size=256m"
  echo "--tmpfs"
  echo "/home/agent:rw,exec,nosuid,size=1024m,uid=1001,gid=1001,mode=0700"
  echo "--tmpfs"
  echo "/home/agent/.cache:rw,noexec,nosuid,size=1024m,uid=1001,gid=1001,mode=0700"
  echo "--tmpfs"
  echo "/home/agent/.local:rw,exec,nosuid,size=256m,uid=1001,gid=1001,mode=0700"
  echo "--network"
  echo "$network"
  echo "-v"
  echo "${worktree}:${sandbox_workdir}"
  garth_container_emit_protected_path_mounts_lines "$worktree" "$sandbox_workdir" || true
  echo "-v"
  echo "${token_dir}:/run/garth:ro"
  if [[ "$auth_passthrough_enabled" == "true" ]]; then
    if ! garth_container_emit_auth_mounts_lines "$shell_agent"; then
      garth_log_warn "Docker auth passthrough enabled for shell agent '$shell_agent' but no local auth files were found"
      garth_log_warn "Run local login first (for example: 'codex login' or 'claude auth login')"
    fi
  fi
  garth_container_emit_feature_mounts_lines || true
  echo "--env"
  echo "GARTH_GITHUB_TOKEN_FILE=/run/garth/github_token"
  echo "--env"
  echo "HOME=/home/agent"
  echo "--env"
  echo "XDG_CACHE_HOME=/home/agent/.cache"
  echo "--env"
  echo "XDG_CONFIG_HOME=/home/agent/.config"
  echo "--env"
  echo "XDG_STATE_HOME=/home/agent/.local/state"
  echo "--env"
  echo "PATH=/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  echo "-w"
  echo "${sandbox_workdir}"
  echo "$image"
  local shell_command="exec bash"
  if [[ "$shell_agent" == "claude" ]]; then
    local preamble
    local preamble_escaped
    preamble=$(garth_claude_runtime_preamble)
    printf -v preamble_escaped '%q' "$preamble"
    shell_command="eval ${preamble_escaped}; ${shell_command}"
  fi
  echo "bash"
  echo "-lc"
  echo "$shell_command"
}

garth_docker_build_agent_image() {
  local agent="$1"
  local image_prefix="$2"
  local features_packages_csv
  local features_npm_packages_csv
  features_packages_csv="$(garth_agent_feature_packages_csv "$agent")"
  features_npm_packages_csv="$(garth_agent_feature_npm_packages_csv "$agent")"
  if [[ "$GARTH_DRY_RUN" != "true" ]]; then
    garth_require_cmd docker
  fi
  garth_run_cmd docker build \
    --build-arg "GARTH_FEATURE_APT_PACKAGES=${features_packages_csv}" \
    --build-arg "GARTH_FEATURE_NPM_PACKAGES=${features_npm_packages_csv}" \
    --target "$agent" \
    -t "${image_prefix}-${agent}:latest" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker"
}

garth_docker_refresh_agent_image() {
  local agent="$1"
  local image_prefix="$2"
  local features_packages_csv
  local features_npm_packages_csv
  features_packages_csv="$(garth_agent_feature_packages_csv "$agent")"
  features_npm_packages_csv="$(garth_agent_feature_npm_packages_csv "$agent")"
  if [[ "$GARTH_DRY_RUN" != "true" ]]; then
    garth_require_cmd docker
  fi
  garth_run_cmd docker build \
    --pull \
    --no-cache \
    --build-arg "GARTH_FEATURE_APT_PACKAGES=${features_packages_csv}" \
    --build-arg "GARTH_FEATURE_NPM_PACKAGES=${features_npm_packages_csv}" \
    --target "$agent" \
    -t "${image_prefix}-${agent}:latest" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker"
}

garth_docker_image_has_binary() {
  local image="$1"
  local binary="$2"
  garth_require_cmd docker
  docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=256m \
    --tmpfs /home/agent:rw,exec,nosuid,size=1024m,uid=1001,gid=1001,mode=0700 \
    --entrypoint /bin/bash "$image" \
    -lc "command -v $(printf '%q' "$binary") >/dev/null"
}

garth_docker_image_has_feature_package() {
  local image="$1"
  local package="$2"
  garth_require_cmd docker

  if [[ "$package" == "uv" ]]; then
    garth_docker_image_has_binary "$image" "uv"
    return $?
  fi

  if [[ "$package" == "bun" ]]; then
    garth_docker_image_has_binary "$image" "bun"
    return $?
  fi

  docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=256m \
    --tmpfs /home/agent:rw,exec,nosuid,size=1024m,uid=1001,gid=1001,mode=0700 \
    --entrypoint /bin/bash "$image" \
    -lc "dpkg-query -W -f='\${Status}' $(printf '%q' "$package") 2>/dev/null | grep -q 'install ok installed'"
}

garth_docker_image_has_npm_feature_package() {
  local image="$1"
  local package="$2"
  garth_require_cmd docker

  docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=256m \
    --tmpfs /home/agent:rw,exec,nosuid,size=1024m,uid=1001,gid=1001,mode=0700 \
    --entrypoint /bin/bash "$image" \
    -lc "npm list -g --depth=0 $(printf '%q' "$package") >/dev/null 2>&1"
}

garth_ensure_agent_image_ready() {
  local agent="$1"
  local image_prefix="$2"
  local image="${image_prefix}-${agent}:latest"
  local state
  local binary

  binary=$(garth_agent_primary_binary "$agent") || {
    garth_log_error "Unable to determine primary binary for agent '$agent'"
    return 1
  }

  state=$(garth_docker_image_state "$image")
  case "$state" in
    present) ;;
    missing)
      garth_log_info "Docker image missing for '$agent'; building $image"
      garth_docker_build_agent_image "$agent" "$image_prefix" || return 1
      ;;
    unavailable:*)
      garth_log_error "Docker unavailable while checking $image: ${state#unavailable:}"
      return 1
      ;;
  esac

  local rebuild=false
  if ! garth_docker_image_has_binary "$image" "$binary"; then
    garth_log_warn "Image $image is missing expected binary '$binary'; rebuilding"
    rebuild=true
  fi

  local package_name
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    if ! garth_docker_image_has_feature_package "$image" "$package_name"; then
      garth_log_warn "Image $image is missing configured feature package '$package_name'; rebuilding"
      rebuild=true
    fi
  done < <(garth_agent_feature_packages_lines "$agent")

  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    if ! garth_docker_image_has_npm_feature_package "$image" "$package_name"; then
      garth_log_warn "Image $image is missing configured npm package '$package_name'; rebuilding"
      rebuild=true
    fi
  done < <(garth_agent_feature_npm_packages_lines "$agent")

  if [[ "$rebuild" == "true" ]]; then
    garth_docker_build_agent_image "$agent" "$image_prefix" || return 1
  fi

  if ! garth_docker_image_has_binary "$image" "$binary"; then
    garth_log_error "Image $image still missing '$binary' after rebuild"
    return 1
  fi

  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    if ! garth_docker_image_has_feature_package "$image" "$package_name"; then
      garth_log_error "Image $image still missing feature package '$package_name' after rebuild"
      return 1
    fi
  done < <(garth_agent_feature_packages_lines "$agent")

  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    if ! garth_docker_image_has_npm_feature_package "$image" "$package_name"; then
      garth_log_error "Image $image still missing npm package '$package_name' after rebuild"
      return 1
    fi
  done < <(garth_agent_feature_npm_packages_lines "$agent")
}

garth_stop_containers_for_session() {
  local session="$1"
  local ids
  ids=$(docker ps -q --filter "label=garth.session=$session")
  [[ -n "$ids" ]] || return 0
  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "$ids" | tr '\n' ' '
    return 0
  fi
  echo "$ids" | xargs -n 1 docker rm -f >/dev/null
}

garth_list_garth_containers_json() {
  docker ps --filter label=garth.session --format '{{json .}}'
}

garth_list_containers_for_session() {
  local session="$1"
  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi
  docker ps -aq --filter "label=garth.session=$session"
}
