# Zellij session + layout helpers.

if [[ -n "${GARTH_ZELLIJ_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_ZELLIJ_SH_LOADED=1
: "${GARTH_ZELLIJ_LAUNCH_ASYNC:=false}"
: "${GARTH_ZELLIJ_TERMINAL_LAUNCHER:=}"
: "${GARTH_DEFAULTS_ZELLIJ_MOUSE_MODE:=disabled}"

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

garth_zellij_mouse_mode() {
  local configured="${GARTH_ZELLIJ_MOUSE_MODE:-${GARTH_DEFAULTS_ZELLIJ_MOUSE_MODE:-disabled}}"
  case "$configured" in
    enabled|disabled)
      printf '%s' "$configured"
      ;;
    *)
      garth_log_warn "Unknown zellij mouse mode '$configured'; falling back to disabled"
      printf 'disabled'
      ;;
  esac
}

garth_zellij_option_words() {
  local mouse_mode
  mouse_mode="$(garth_zellij_mouse_mode)"
  if [[ "$mouse_mode" == "disabled" ]]; then
    printf '%s\n' "options" "--disable-mouse-mode"
  fi
}

garth_zellij_shell_quote_words() {
  local rendered=""
  local word quoted
  for word in "$@"; do
    printf -v quoted '%q' "$word"
    if [[ -n "$rendered" ]]; then
      rendered+=" "
    fi
    rendered+="$quoted"
  done
  printf '%s' "$rendered"
}

garth_zellij_launcher_script() {
  local zellij_bin="$1"
  local session="$2"
  local layout_file="$3"
  local attach_cmd create_cmd list_cmd awk_program option_word
  local -a attach_args=("$zellij_bin" "attach" "$session")
  local -a create_args=("$zellij_bin" "-s" "$session" "--new-session-with-layout" "$layout_file")
  while IFS= read -r option_word; do
    [[ -n "$option_word" ]] || continue
    attach_args+=("$option_word")
    create_args+=("$option_word")
  done < <(garth_zellij_option_words)
  attach_cmd="$(garth_zellij_shell_quote_words "${attach_args[@]}")"
  create_cmd="$(garth_zellij_shell_quote_words "${create_args[@]}")"
  printf -v list_cmd '%q list-sessions -n 2>/dev/null' "$zellij_bin"
  # awk program — $1 must not expand
  # shellcheck disable=SC2016
  awk_program='{print $1}'
  # Some zellij versions can return success for `attach` when the session is missing.
  # Check existence explicitly so we create the session on first launch.
  printf 'if %s | awk %q | grep -Fxq %q; then %s || %s || %s; else %s || %s; fi' \
    "$list_cmd" "$awk_program" "$session" "$attach_cmd" "$create_cmd" "$attach_cmd" "$create_cmd" "$attach_cmd"
}

garth_zellij_terminal_launcher() {
  local configured="${GARTH_ZELLIJ_TERMINAL_LAUNCHER:-${GARTH_DEFAULTS_TERMINAL_LAUNCHER:-auto}}"
  case "$configured" in
    auto|current_shell|ghostty|ghostty_app|terminal)
      printf '%s' "$configured"
      ;;
    *)
      garth_log_warn "Unknown terminal launcher '$configured'; falling back to auto"
      printf 'auto'
      ;;
  esac
}

garth_zellij_set_async_if_running() {
  local session="$1"
  local pre_state="$2"
  if [[ "$pre_state" == "running" ]] || garth_zellij_wait_for_running "$session" 25; then
    GARTH_ZELLIJ_LAUNCH_ASYNC=true
    return 0
  fi
  return 1
}

# Strip Zellij env vars so new terminal windows don't trigger nesting protection.
garth_zellij_clean_env() {
  env -u ZELLIJ -u ZELLIJ_SESSION_NAME -u ZELLIJ_PANE_ID "$@"
}

garth_zellij_try_launch_ghostty_bin() {
  local session="$1"
  local pre_state="$2"
  local launch_script="$3"
  garth_zellij_clean_env ghostty -e /bin/bash -lc "$launch_script" >/dev/null 2>&1 &
  garth_zellij_set_async_if_running "$session" "$pre_state"
}

garth_zellij_try_launch_ghostty_app() {
  local session="$1"
  local pre_state="$2"
  local launch_script="$3"
  if garth_zellij_clean_env open -na "Ghostty" --args -e /bin/bash -lc "$launch_script" >/dev/null 2>&1; then
    garth_zellij_set_async_if_running "$session" "$pre_state"
    return $?
  fi
  return 1
}

garth_zellij_try_launch_terminal_app() {
  local session="$1"
  local pre_state="$2"
  local launch_script="$3"
  local script_cmd
  printf -v script_cmd '%q -lc %q' "/bin/bash" "$launch_script"
  if garth_zellij_clean_env osascript \
    -e "tell application \"Terminal\" to do script \"$script_cmd\"" \
    -e "tell application \"Terminal\" to activate" >/dev/null 2>&1; then
    garth_zellij_set_async_if_running "$session" "$pre_state"
    return $?
  fi
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
    echo "  default_tab_template {"
    echo "    pane size=1 borderless=true {"
    echo "      plugin location=\"zellij:tab-bar\""
    echo "    }"
    echo "    children"
    echo "    pane size=2 borderless=true {"
    echo "      plugin location=\"zellij:status-bar\""
    echo "    }"
    echo "  }"
    local agent
    local first_tab=true
    for agent in "${agents[@]}"; do
      if [[ "$first_tab" == "true" ]]; then
        echo "  tab name=\"$(garth_kdl_escape "$agent")\" focus=true {"
        first_tab=false
      else
        echo "  tab name=\"$(garth_kdl_escape "$agent")\" {"
      fi
      echo "    pane split_direction=\"vertical\" size=\"100%\" {"
      if [[ "$sandbox" == "docker" ]]; then
        echo "      pane name=\"$(garth_kdl_escape "$agent")\" size=\"65%\" command=\"docker\" {"
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
        echo "      }"
      else
        local cmd
        cmd=$(garth_agent_command_string "$agent" "$safety_mode")
        local host_script
        host_script="set -a; source \"${token_dir}/agent-${agent}.env\"; set +a; export GITHUB_TOKEN=\"\$(cat \"${token_dir}/github_token\")\"; cd \"${worktree}\"; ${cmd}"
        echo "      pane name=\"$(garth_kdl_escape "$agent")\" size=\"65%\" command=\"bash\" {"
        garth_kdl_write_args_line "-lc" "$host_script"
        echo "      }"
      fi
      # Keep shell local so user profile/shell integrations (e.g. Ghostty) behave normally.
      echo "      pane name=\"shell\" size=\"35%\" cwd=\"$(garth_kdl_escape "$worktree")\""
      echo "    }"
      echo "  }"
    done
    echo "}"
  } > "$tmp_file"

  mv "$tmp_file" "$layout_file"
}

garth_zellij_launch() {
  local session="$1"
  local layout_file="$2"
  local zellij_bin
  local launch_script
  local -a zellij_args=()
  local pre_state
  local launcher
  local option_word
  GARTH_ZELLIJ_LAUNCH_ASYNC=false
  zellij_bin=$(command -v zellij 2>/dev/null || true)
  pre_state="$(garth_zellij_session_state "$session")"
  if garth_zellij_session_exists "$session"; then
    zellij_args=(attach "$session")
  else
    zellij_args=(-s "$session" --new-session-with-layout "$layout_file")
  fi
  while IFS= read -r option_word; do
    [[ -n "$option_word" ]] || continue
    zellij_args+=("$option_word")
  done < <(garth_zellij_option_words)
  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    if [[ -n "$zellij_bin" ]]; then
      echo "[dry-run] $zellij_bin ${zellij_args[*]}"
      launch_script=$(garth_zellij_launcher_script "$zellij_bin" "$session" "$layout_file")
    else
      echo "[dry-run] zellij ${zellij_args[*]}"
      launch_script="zellij attach $session || zellij -s $session --new-session-with-layout $layout_file || zellij attach $session"
    fi
    if garth_is_macos; then
      launcher="$(garth_zellij_terminal_launcher)"
      case "$launcher" in
        current_shell)
          echo "[dry-run] (terminal launcher disabled; zellij will run in current shell)"
          ;;
        ghostty)
          if command -v ghostty >/dev/null 2>&1; then
            echo "[dry-run] ghostty -e /bin/bash -lc '$launch_script'"
          else
            echo "[dry-run] ghostty not found; zellij will run in current shell"
          fi
          ;;
        ghostty_app)
          if [[ -d "/Applications/Ghostty.app" ]] && command -v open >/dev/null 2>&1; then
            echo "[dry-run] open -na Ghostty --args -e /bin/bash -lc '$launch_script'"
          else
            echo "[dry-run] Ghostty.app launcher unavailable; zellij will run in current shell"
          fi
          ;;
        terminal)
          if command -v osascript >/dev/null 2>&1; then
            echo "[dry-run] osascript Terminal -> /bin/bash -lc '$launch_script'"
          else
            echo "[dry-run] Terminal launcher unavailable; zellij will run in current shell"
          fi
          ;;
        auto)
          if command -v ghostty >/dev/null 2>&1; then
            echo "[dry-run] ghostty -e /bin/bash -lc '$launch_script'"
          elif [[ -d "/Applications/Ghostty.app" ]] && command -v open >/dev/null 2>&1; then
            echo "[dry-run] open -na Ghostty --args -e /bin/bash -lc '$launch_script'"
          elif command -v osascript >/dev/null 2>&1; then
            echo "[dry-run] osascript Terminal -> /bin/bash -lc '$launch_script'"
          else
            echo "[dry-run] (no terminal launcher found; zellij will run in current shell)"
          fi
          ;;
      esac
    fi
    return 0
  fi
  garth_require_cmd zellij
  zellij_bin=$(command -v zellij)
  launch_script=$(garth_zellij_launcher_script "$zellij_bin" "$session" "$layout_file")
  if garth_zellij_session_exists "$session"; then
    zellij_args=(attach "$session")
  else
    zellij_args=(-s "$session" --new-session-with-layout "$layout_file")
  fi

  if garth_is_macos; then
    launcher="$(garth_zellij_terminal_launcher)"
    case "$launcher" in
      current_shell)
        ;;
      ghostty)
        if command -v ghostty >/dev/null 2>&1; then
          if garth_zellij_try_launch_ghostty_bin "$session" "$pre_state" "$launch_script"; then
            return 0
          fi
          garth_log_warn "Ghostty launch did not reach running session state; falling back to current shell"
        else
          garth_log_warn "ghostty not found; falling back to current shell"
        fi
        ;;
      ghostty_app)
        if [[ -d "/Applications/Ghostty.app" ]] && command -v open >/dev/null 2>&1; then
          if garth_zellij_try_launch_ghostty_app "$session" "$pre_state" "$launch_script"; then
            return 0
          fi
          garth_log_warn "Ghostty.app launch did not reach running session state; falling back to current shell"
        else
          garth_log_warn "Ghostty.app launcher unavailable; falling back to current shell"
        fi
        ;;
      terminal)
        if command -v osascript >/dev/null 2>&1; then
          if garth_zellij_try_launch_terminal_app "$session" "$pre_state" "$launch_script"; then
            return 0
          fi
          garth_log_warn "Terminal launch did not reach running session state; falling back to current shell"
        else
          garth_log_warn "Terminal launcher unavailable; falling back to current shell"
        fi
        ;;
      auto)
        if command -v ghostty >/dev/null 2>&1; then
          if garth_zellij_try_launch_ghostty_bin "$session" "$pre_state" "$launch_script"; then
            return 0
          fi
          garth_log_warn "Ghostty launch did not reach running session state; trying fallback launcher"
        fi
        if [[ -d "/Applications/Ghostty.app" ]] && command -v open >/dev/null 2>&1; then
          if garth_zellij_try_launch_ghostty_app "$session" "$pre_state" "$launch_script"; then
            return 0
          fi
          garth_log_warn "Ghostty.app launch did not reach running session state; trying fallback launcher"
        fi
        if command -v osascript >/dev/null 2>&1; then
          if garth_zellij_try_launch_terminal_app "$session" "$pre_state" "$launch_script"; then
            return 0
          fi
          garth_log_warn "Terminal launch did not reach running session state; falling back to current shell"
        fi
        ;;
    esac
  fi
  garth_zellij_clean_env bash -lc "$launch_script"
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
