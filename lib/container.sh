# Docker lifecycle helpers for garth.

if [[ -n "${GARTH_CONTAINER_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_CONTAINER_SH_LOADED=1

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
    if ! api_key=$(garth_secret_read "$api_key_ref"); then
      garth_log_error "Failed to read agents.$agent.api_key_ref: $api_key_ref"
      return 1
    fi
    has_api_key=true
  else
    # Host mode can rely on existing local CLI auth sessions (consumer subscriptions).
    if [[ -n "$api_key_ref" && "$api_key_ref" != *"<"* ]]; then
      if api_key=$(garth_secret_read "$api_key_ref"); then
        has_api_key=true
      else
        garth_log_warn "Could not read agents.$agent.api_key_ref; continuing with local CLI auth in sandbox=none"
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

garth_container_emit_auth_mounts_lines() {
  local agent="$1"
  local count=0

  if [[ "$agent" == "codex" ]]; then
    if [[ -d "$HOME/.codex" ]]; then
      echo "-v"
      echo "$HOME/.codex:/home/agent/.codex:rw"
      count=$((count + 1))
    fi
  fi

  if [[ "$agent" == "claude" ]]; then
    if [[ -d "$HOME/.claude" ]]; then
      echo "-v"
      echo "$HOME/.claude:/home/agent/.claude:rw"
      count=$((count + 1))
    fi
    if [[ -f "$HOME/.claude.json" ]]; then
      echo "-v"
      echo "$HOME/.claude.json:/home/agent/.claude.json:rw"
      count=$((count + 1))
    fi
    if [[ -d "$HOME/.config/claude" ]]; then
      echo "-v"
      echo "$HOME/.config/claude:/home/agent/.config/claude:rw"
      count=$((count + 1))
    fi
  fi

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
  echo "--pids-limit"
  echo "512"
  echo "--read-only"
  echo "--tmpfs"
  echo "/tmp:rw,noexec,nosuid,size=256m"
  echo "--tmpfs"
  echo "/home/agent:rw,exec,nosuid,size=1024m,mode=1777"
  echo "--memory"
  echo "8g"
  echo "--cpus"
  echo "4"
  echo "--network"
  echo "$network"
  echo "-v"
  echo "${worktree}:/work"
  echo "-v"
  echo "${token_dir}:/run/garth:ro"
  if [[ "$auth_passthrough_enabled" == "true" ]]; then
    if ! garth_container_emit_auth_mounts_lines "$agent"; then
      garth_log_warn "Docker auth passthrough enabled for '$agent' but no local auth files were found"
      garth_log_warn "Run local login first (for example: 'codex login' or 'claude auth login')"
    fi
  fi
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
  echo "-w"
  echo "/work"
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
  local image="${image_prefix}-${shell_agent}:latest"
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
  echo "--pids-limit"
  echo "512"
  echo "--read-only"
  echo "--tmpfs"
  echo "/tmp:rw,noexec,nosuid,size=256m"
  echo "--tmpfs"
  echo "/home/agent:rw,exec,nosuid,size=1024m,mode=1777"
  echo "--network"
  echo "$network"
  echo "-v"
  echo "${worktree}:/work"
  echo "-v"
  echo "${token_dir}:/run/garth:ro"
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
  echo "-w"
  echo "/work"
  echo "$image"
  echo "bash"
}

garth_docker_build_agent_image() {
  local agent="$1"
  local image_prefix="$2"
  garth_require_cmd docker
  garth_run_cmd docker build --target "$agent" -t "${image_prefix}-${agent}:latest" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker"
}

garth_docker_image_has_binary() {
  local image="$1"
  local binary="$2"
  garth_require_cmd docker
  docker run --rm --entrypoint /bin/bash "$image" -lc "command -v $(printf '%q' "$binary") >/dev/null"
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

  if garth_docker_image_has_binary "$image" "$binary"; then
    return 0
  fi

  garth_log_warn "Image $image is missing expected binary '$binary'; rebuilding"
  garth_docker_build_agent_image "$agent" "$image_prefix" || return 1
  if ! garth_docker_image_has_binary "$image" "$binary"; then
    garth_log_error "Image $image still missing '$binary' after rebuild"
    return 1
  fi
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
