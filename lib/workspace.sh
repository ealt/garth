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

garth_configure_cursor_terminal_bridge() {
  local repo_dir="$1"
  local sandbox="$2"

  if ! garth_is_macos; then
    return 0
  fi

  # Only force Cursor terminal profile in docker sandbox mode.
  if [[ "$sandbox" != "docker" ]]; then
    return 0
  fi

  local vscode_dir="$repo_dir/.vscode"
  local bridge_script="$vscode_dir/garth-sandbox-shell.sh"
  local settings_file="$vscode_dir/settings.json"

  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] configure Cursor terminal bridge in $vscode_dir"
    return 0
  fi

  mkdir -p "$vscode_dir"

  cat > "$bridge_script" << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/garth/sessions"

best_session=""
best_epoch=0

if [[ -d "$state_root" ]]; then
  while IFS= read -r session_dir; do
    [[ -n "$session_dir" ]] || continue
    [[ -f "$session_dir/active" ]] || continue
    this_repo="$(cat "$session_dir/repo_root" 2>/dev/null || true)"
    [[ "$this_repo" == "$repo_root" ]] || continue
    epoch="$(cat "$session_dir/started_epoch" 2>/dev/null || echo 0)"
    if [[ "$epoch" =~ ^[0-9]+$ ]] && (( epoch >= best_epoch )); then
      best_epoch="$epoch"
      best_session="$(basename "$session_dir")"
    fi
  done < <(find "$state_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
fi

if [[ -z "$best_session" ]]; then
  echo "[garth] No active garth session found for this repo." >&2
  echo "[garth] Run: garth boot \"$repo_root\"" >&2
  exec bash
fi

container="${best_session}-shell"
container="$(echo "$container" | sed -E 's/[^A-Za-z0-9_.-]/-/g')"
container="${container:0:80}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[garth] docker is not installed." >&2
  exec bash
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
  echo "[garth] Sandbox shell container is not running: $container" >&2
  echo "[garth] Run: garth boot \"$repo_root\"" >&2
  exec bash
fi

exec docker exec -it "$container" bash -lc 'cd /work; exec bash'
SCRIPT
  chmod +x "$bridge_script"

  python3 - << 'PY' "$settings_file"
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
data = {}
if settings_path.exists():
    try:
        data = json.loads(settings_path.read_text(encoding="utf-8"))
    except Exception:
        data = {}
if not isinstance(data, dict):
    data = {}

profiles_key = "terminal.integrated.profiles.osx"
default_key = "terminal.integrated.defaultProfile.osx"
profile_name = "Garth Sandbox"

profiles = data.get(profiles_key)
if not isinstance(profiles, dict):
    profiles = {}

profiles[profile_name] = {
    "path": "/bin/bash",
    "args": ["-lc", "${workspaceFolder}/.vscode/garth-sandbox-shell.sh"],
    "overrideName": True,
}

data[profiles_key] = profiles
data[default_key] = profile_name

settings_path.write_text(json.dumps(data, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY
}

garth_launch_chrome_profile() {
  local profiles_root="$1"
  local profile_name="$2"
  local url="$3"

  if [[ -z "$profiles_root" ]]; then
    if [[ "$GARTH_DRY_RUN" == "true" ]]; then
      echo "[dry-run] osascript Google Chrome new window -> $url"
      return 0
    fi

    if ! garth_is_macos; then
      garth_log_warn "Chrome launch skipped (non-macOS)"
      return 0
    fi

    open -g -a "Google Chrome" >/dev/null 2>&1 || true

    local escaped_url="$url"
    escaped_url="${escaped_url//\\/\\\\}"
    escaped_url="${escaped_url//\"/\\\"}"
    if osascript \
      -e "tell application \"Google Chrome\" to activate" \
      -e "tell application \"Google Chrome\" to set _w to make new window" \
      -e "tell application \"Google Chrome\" to set URL of active tab of _w to \"$escaped_url\"" \
      >/dev/null 2>&1; then
      return 0
    fi

    if open -a "Google Chrome" "$url" >/dev/null 2>&1; then
      return 0
    fi

    garth_log_warn "Failed to launch Chrome new window"
    return 0
  fi

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
