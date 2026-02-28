# Workspace launch helpers (Cursor, Chrome profile, AeroSpace workspace).

if [[ -n "${GARTH_WORKSPACE_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_WORKSPACE_SH_LOADED=1

garth_launch_cursor() {
  local dir="$1"

  if ! garth_is_macos; then
    garth_log_warn "Cursor auto-launch skipped (non-macOS)"
    return 0
  fi

  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] open -a Cursor $dir"
    return 0
  fi

  open -a "Cursor" "$dir" >/dev/null 2>&1 || garth_log_warn "Failed to open Cursor"
}

garth_launch_chrome_profile() {
  local profiles_root="$1"
  local profile_name="$2"
  local url="$3"

  local expanded_root="${profiles_root/#\~/$HOME}"

  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] open -na Google Chrome --args --user-data-dir=$expanded_root/$profile_name $url"
    return 0
  fi

  mkdir -p "$expanded_root/$profile_name"

  if ! garth_is_macos; then
    garth_log_warn "Chrome profile launch skipped (non-macOS)"
    return 0
  fi

  open -na "Google Chrome" --args "--user-data-dir=$expanded_root/$profile_name" "$url" >/dev/null 2>&1 || \
    garth_log_warn "Failed to launch Chrome with profile"
}

garth_aerospace_list_workspaces() {
  local output=""
  if output=$(aerospace list-workspaces --all 2>/dev/null); then
    printf '%s\n' "$output"
    return 0
  fi
  if output=$(aerospace list-workspaces 2>/dev/null); then
    printf '%s\n' "$output"
    return 0
  fi
  return 1
}

garth_aerospace_is_ready() {
  aerospace list-workspaces --all >/dev/null 2>&1 || \
    aerospace list-workspaces >/dev/null 2>&1
}

garth_aerospace_ensure_running() {
  if garth_aerospace_is_ready; then
    return 0
  fi

  if ! garth_is_macos; then
    return 1
  fi

  garth_log_info "AeroSpace is installed but not running; starting AeroSpace.app"
  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] open -ga AeroSpace"
    return 0
  fi

  if ! open -ga "AeroSpace" >/dev/null 2>&1; then
    garth_log_warn "Unable to start AeroSpace.app automatically"
    garth_log_warn "Start it manually with: open -a AeroSpace"
    return 1
  fi

  local i
  for ((i = 0; i < 20; i++)); do
    if garth_aerospace_is_ready; then
      return 0
    fi
    sleep 0.2
  done

  garth_log_warn "AeroSpace did not become ready in time"
  garth_log_warn "Start it manually with: open -a AeroSpace"
  return 1
}

garth_aerospace_next_workspace() {
  local output max_value
  output=$(garth_aerospace_list_workspaces 2>/dev/null || true)
  max_value=$(printf '%s\n' "$output" | tr -cs '0-9' '\n' | awk 'NF { if ($1 > m) m = $1 } END { if (m == "") m = 0; print m }')
  echo $((max_value + 1))
}

garth_move_windows_to_workspace() {
  local workspace="$1"

  [[ -n "$workspace" ]] || return 0

  if ! command -v aerospace >/dev/null 2>&1; then
    if garth_is_macos; then
      garth_log_warn "AeroSpace is not installed; workspace placement is disabled."
      if command -v brew >/dev/null 2>&1; then
        garth_log_warn "Install with: brew tap nikitabobko/tap && brew install --cask aerospace"
      fi
    elif [[ "$workspace" != "auto" ]]; then
      garth_log_warn "AeroSpace not installed; --workspace ignored"
    fi
    return 0
  fi

  if ! garth_aerospace_ensure_running; then
    garth_log_warn "AeroSpace unavailable; workspace placement skipped"
    return 0
  fi

  if [[ "$workspace" == "auto" ]]; then
    workspace=$(garth_aerospace_next_workspace)
    if [[ -z "$workspace" ]]; then
      garth_log_warn "Unable to determine next AeroSpace workspace; --workspace auto ignored"
      return 0
    fi
    garth_log_info "Auto-selected AeroSpace workspace: $workspace"
  fi

  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] aerospace move-node-to-workspace $workspace"
    echo "[dry-run] aerospace workspace $workspace"
    return 0
  fi

  aerospace move-node-to-workspace "$workspace" >/dev/null 2>&1 || \
    garth_log_warn "Unable to move windows to AeroSpace workspace $workspace"
  aerospace workspace "$workspace" >/dev/null 2>&1 || \
    garth_log_warn "Unable to focus AeroSpace workspace $workspace"
}
