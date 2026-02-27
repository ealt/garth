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

# Creates per-agent env file (0600) and prints path.
garth_prepare_agent_env_file() {
  local session_dir="$1"
  local agent="$2"

  local api_key_env api_key_ref
  api_key_env=$(garth_agent_field "$agent" "API_KEY_ENV")
  api_key_ref=$(garth_agent_field "$agent" "API_KEY_REF")

  [[ -n "$api_key_env" ]] || garth_die "Missing api_key_env for agent: $agent" 1
  [[ -n "$api_key_ref" ]] || garth_die "Missing api_key_ref for agent: $agent" 1

  local api_key
  api_key=$(garth_secret_read "$api_key_ref")

  local env_file="$session_dir/agent-${agent}.env"
  umask 077
  {
    printf 'TERM=xterm-256color\n'
    printf 'GARTH_GITHUB_TOKEN_FILE=/run/garth/github_token\n'
    printf '%s=%s\n' "$api_key_env" "$api_key"
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
  echo "/home/agent/.cache:rw,noexec,nosuid,size=512m"
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
  echo "--env-file"
  echo "$env_file"
  echo "-w"
  echo "/work"
  echo "$image"
  echo "bash"
  echo "-lc"
  echo "$command_string"
}

garth_docker_build_agent_image() {
  local agent="$1"
  local image_prefix="$2"
  garth_require_cmd docker
  garth_run_cmd docker build --target "$agent" -t "${image_prefix}-${agent}:latest" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker"
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
