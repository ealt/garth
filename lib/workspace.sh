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

garth_move_windows_to_workspace() {
  local workspace="$1"

  [[ -n "$workspace" ]] || return 0

  if ! command -v aerospace >/dev/null 2>&1; then
    garth_log_warn "AeroSpace not installed; --workspace ignored"
    return 0
  fi

  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] aerospace move-node-to-workspace $workspace"
    return 0
  fi

  aerospace move-node-to-workspace "$workspace" >/dev/null 2>&1 || \
    garth_log_warn "Unable to move windows to AeroSpace workspace $workspace"
}
