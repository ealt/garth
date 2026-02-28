# Zellij session + layout helpers.

if [[ -n "${GARTH_ZELLIJ_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_ZELLIJ_SH_LOADED=1
: "${GARTH_ZELLIJ_LAUNCH_ASYNC:=false}"

garth_kdl_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

garth_kdl_write_args_line() {
  local -a args=("$@")
  printf '              args'
  local arg
  for arg in "${args[@]}"; do
    printf ' "%s"' "$(garth_kdl_escape "$arg")"
  done
  printf '\n'
}

garth_zellij_session_state() {
  local target_session="$1"
  local line name

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    name="${line%% *}"
    if [[ "$name" == "$target_session" ]]; then
      if [[ "$line" == *"(EXITED"* ]]; then
        echo "exited"
      else
        echo "running"
      fi
      return 0
    fi
  done < <(zellij list-sessions -n 2>/dev/null || true)

  echo "missing"
}

garth_zellij_session_exists() {
  local target_session="$1"
  [[ "$(garth_zellij_session_state "$target_session")" != "missing" ]]
}

garth_zellij_wait_for_running() {
  local target_session="$1"
  local checks="${2:-25}"
  local i state
  for ((i = 0; i < checks; i++)); do
    state="$(garth_zellij_session_state "$target_session")"
    if [[ "$state" == "running" ]]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

# Args:
#   layout_file worktree session repo_root token_dir network image_prefix safety_mode sandbox auth_passthrough_csv agent...
garth_generate_zellij_layout() {
  local layout_file="$1"
  local worktree="$2"
  local session="$3"
  local repo_root="$4"
  local token_dir="$5"
  local network="$6"
  local image_prefix="$7"
  local safety_mode="$8"
  local sandbox="$9"
  local auth_passthrough_csv="${10}"
  shift 10
  local agents=("$@")

  local tmp_file="${layout_file}.tmp"
  : > "$tmp_file"

  {
    echo "layout {"
    echo "  tab name=\"dev\" focus=true {"
    echo "    pane split_direction=\"vertical\" size=\"100%\" {"
    if [[ "$sandbox" == "docker" ]]; then
      local shell_agent="${agents[0]:-claude}"
      echo "      pane name=\"shell\" size=\"35%\" command=\"docker\" {"
      local -a shell_args=()
      local shell_arg
      while IFS= read -r shell_arg; do
        shell_args+=("$shell_arg")
      done < <(garth_container_shell_args_lines "$session" "$repo_root" "$worktree" "$token_dir" "$network" "$image_prefix" "$shell_agent")
      garth_kdl_write_args_line "${shell_args[@]}"
      echo "      }"
    else
      echo "      pane name=\"shell\" size=\"35%\" cwd=\"$(garth_kdl_escape "$worktree")\""
    fi
    echo "      pane split_direction=\"horizontal\" size=\"65%\" {"

    local agent
    for agent in "${agents[@]}"; do
      if [[ "$sandbox" == "docker" ]]; then
        echo "        pane name=\"$(garth_kdl_escape "$agent")\" command=\"docker\" {"
        local auth_passthrough_enabled="false"
        if [[ -n "$auth_passthrough_csv" ]]; then
          case ",$auth_passthrough_csv," in
            *",$agent,"*) auth_passthrough_enabled="true" ;;
          esac
        fi
        local -a pane_args=()
        local pane_arg
        while IFS= read -r pane_arg; do
          pane_args+=("$pane_arg")
        done < <(garth_container_args_lines "$session" "$repo_root" "$worktree" "$agent" "$token_dir/agent-${agent}.env" "$token_dir" "$network" "$image_prefix" "$safety_mode" "$auth_passthrough_enabled")
        garth_kdl_write_args_line "${pane_args[@]}"
        echo "        }"
      else
        local cmd
        cmd=$(garth_agent_command_string "$agent" "$safety_mode")
        local host_script
        host_script="set -a; source \"${token_dir}/agent-${agent}.env\"; set +a; export GITHUB_TOKEN=\"\$(cat \"${token_dir}/github_token\")\"; cd \"${worktree}\"; ${cmd}"
        echo "        pane name=\"$(garth_kdl_escape "$agent")\" command=\"bash\" {"
        garth_kdl_write_args_line "-lc" "$host_script"
        echo "        }"
      fi
    done

    echo "      }"
    echo "    }"
    echo "  }"
    echo "}"
  } > "$tmp_file"

  mv "$tmp_file" "$layout_file"
}

garth_zellij_launch() {
  local session="$1"
  local layout_file="$2"
  local zellij_bin
  local -a zellij_args=()
  local pre_state
  GARTH_ZELLIJ_LAUNCH_ASYNC=false
  zellij_bin=$(command -v zellij 2>/dev/null || true)
  pre_state="$(garth_zellij_session_state "$session")"
  if garth_zellij_session_exists "$session"; then
    zellij_args=(attach "$session")
  else
    zellij_args=(-s "$session" --new-session-with-layout "$layout_file")
  fi
  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    if [[ -n "$zellij_bin" ]]; then
      echo "[dry-run] $zellij_bin ${zellij_args[*]}"
    else
      echo "[dry-run] zellij ${zellij_args[*]}"
    fi
    if garth_is_macos; then
      if command -v osascript >/dev/null 2>&1; then
        if [[ -n "$zellij_bin" ]]; then
          echo "[dry-run] osascript Terminal -> $zellij_bin ${zellij_args[*]}"
        else
          echo "[dry-run] osascript Terminal -> zellij ${zellij_args[*]}"
        fi
      elif command -v ghostty >/dev/null 2>&1; then
        if [[ -n "$zellij_bin" ]]; then
          echo "[dry-run] ghostty -e $zellij_bin ${zellij_args[*]}"
        else
          echo "[dry-run] ghostty -e zellij ${zellij_args[*]}"
        fi
      else
        echo "[dry-run] (no terminal launcher found; zellij will run in current shell)"
      fi
    fi
    return 0
  fi
  garth_require_cmd zellij
  zellij_bin=$(command -v zellij)
  if garth_zellij_session_exists "$session"; then
    zellij_args=(attach "$session")
  else
    zellij_args=(-s "$session" --new-session-with-layout "$layout_file")
  fi

  if garth_is_macos; then
    if command -v osascript >/dev/null 2>&1; then
      local script_cmd
      printf -v script_cmd '%q' "$zellij_bin"
      local arg
      for arg in "${zellij_args[@]}"; do
        printf -v script_cmd '%s %q' "$script_cmd" "$arg"
      done
      if osascript \
        -e "tell application \"Terminal\" to do script \"$script_cmd\"" \
        -e "tell application \"Terminal\" to activate" >/dev/null 2>&1; then
        if [[ "$pre_state" == "running" ]] || garth_zellij_wait_for_running "$session" 25; then
          GARTH_ZELLIJ_LAUNCH_ASYNC=true
          return 0
        fi
        garth_log_warn "Terminal launch did not reach running session state; falling back to current shell"
      else
        garth_log_warn "Failed to open Terminal for zellij; falling back to current shell"
      fi
    fi
    if command -v ghostty >/dev/null 2>&1; then
      ghostty -e "$zellij_bin" "${zellij_args[@]}" >/dev/null 2>&1 &
      if [[ "$pre_state" == "running" ]] || garth_zellij_wait_for_running "$session" 25; then
        GARTH_ZELLIJ_LAUNCH_ASYNC=true
        return 0
      fi
      garth_log_warn "Ghostty launch did not reach running session state; falling back to current shell"
    elif [[ -d "/Applications/Ghostty.app" ]] && command -v open >/dev/null 2>&1; then
      if open -na "Ghostty" --args -e "$zellij_bin" "${zellij_args[@]}" >/dev/null 2>&1; then
        if [[ "$pre_state" == "running" ]] || garth_zellij_wait_for_running "$session" 25; then
          GARTH_ZELLIJ_LAUNCH_ASYNC=true
          return 0
        fi
        garth_log_warn "Ghostty.app launch did not reach running session state; falling back to current shell"
      fi
    fi
  fi
  "$zellij_bin" "${zellij_args[@]}"
}

garth_zellij_list_sessions() {
  if ! command -v zellij >/dev/null 2>&1; then
    return 0
  fi
  zellij list-sessions -s -n 2>/dev/null | sed '/^$/d'
}

garth_zellij_kill_session() {
  local session="$1"
  if ! command -v zellij >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] zellij delete-session $session"
    return 0
  fi
  zellij delete-session "$session" >/dev/null 2>&1 || true
}
