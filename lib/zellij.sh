# Zellij session + layout helpers.

if [[ -n "${GARTH_ZELLIJ_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_ZELLIJ_SH_LOADED=1

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
    echo "      pane name=\"shell\" size=\"35%\" cwd=\"$(garth_kdl_escape "$worktree")\""
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
  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] zellij -s $session --layout $layout_file"
    return 0
  fi
  garth_require_cmd zellij
  zellij -s "$session" --layout "$layout_file"
}

garth_zellij_list_sessions() {
  if ! command -v zellij >/dev/null 2>&1; then
    return 0
  fi
  zellij list-sessions 2>/dev/null | awk '{print $1}' | sed '/^$/d'
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
