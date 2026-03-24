# Workspace launch helpers (Cursor, browser launch, AeroSpace workspace).

if [[ -n "${GARTH_WORKSPACE_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_WORKSPACE_SH_LOADED=1

garth_cursor_binary_path() {
  local candidates=(
    "/Applications/Cursor.app/Contents/MacOS/Cursor"
    "$HOME/Applications/Cursor.app/Contents/MacOS/Cursor"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

garth_gui_python_shim_dir() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/garth/gui-bin"
}

garth_ensure_gui_python_shim() {
  if [[ ! -x "/opt/homebrew/bin/python3" ]]; then
    return 1
  fi

  local shim_dir
  shim_dir="$(garth_gui_python_shim_dir)"
  mkdir -p "$shim_dir"
  chmod 700 "$shim_dir" 2>/dev/null || true

  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] ln -sf /opt/homebrew/bin/python3 $shim_dir/python"
    return 0
  fi

  ln -sf "/opt/homebrew/bin/python3" "$shim_dir/python" 2>/dev/null || return 1
  chmod 755 "$shim_dir/python" 2>/dev/null || true
  return 0
}

garth_ensure_macos_gui_path() {
  if ! garth_is_macos; then
    return 0
  fi
  if [[ "${GARTH_SKIP_GUI_PATH_SET:-false}" == "true" ]]; then
    return 0
  fi
  if [[ ! -x "/bin/launchctl" ]]; then
    return 0
  fi

  local desired_path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  local desired_python=""
  if [[ ! -x "/opt/homebrew/bin/python3" ]]; then
    desired_path="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  else
    desired_python="/opt/homebrew/bin/python3"
    if garth_ensure_gui_python_shim; then
      desired_path="$(garth_gui_python_shim_dir):${desired_path}"
    fi
  fi

  local current_path
  current_path=$(/bin/launchctl getenv PATH 2>/dev/null || true)
  local current_python
  current_python=$(/bin/launchctl getenv PYTHON3 2>/dev/null || true)

  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] /bin/launchctl setenv PATH $desired_path"
    if [[ -n "$desired_python" ]]; then
      echo "[dry-run] /bin/launchctl setenv PYTHON $desired_python"
      echo "[dry-run] /bin/launchctl setenv PYTHON3 $desired_python"
    fi
    return 0
  fi

  if [[ "$current_path" != "$desired_path" ]]; then
    if ! /bin/launchctl setenv PATH "$desired_path" >/dev/null 2>&1; then
      garth_log_warn "Unable to set launchctl PATH for GUI apps"
      return 1
    fi
  fi

  if [[ -n "$desired_python" && "$current_python" != "$desired_python" ]]; then
    /bin/launchctl setenv PYTHON "$desired_python" >/dev/null 2>&1 || true
    /bin/launchctl setenv PYTHON3 "$desired_python" >/dev/null 2>&1 || true
  fi
  return 0
}

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

  garth_ensure_macos_gui_path >/dev/null 2>&1 || true

  local cursor_bin
  if cursor_bin=$(garth_cursor_binary_path); then
    local launch_path="$PATH"
    local launch_python=""
    local shim_dir=""
    if [[ "$launch_path" != *"/opt/homebrew/bin"* && -x "/opt/homebrew/bin/python3" ]]; then
      launch_path="/opt/homebrew/bin:$launch_path"
      launch_python="/opt/homebrew/bin/python3"
    elif [[ -x "/opt/homebrew/bin/python3" ]]; then
      launch_python="/opt/homebrew/bin/python3"
    fi
    if shim_dir=$(garth_gui_python_shim_dir 2>/dev/null) && [[ -x "$shim_dir/python" ]]; then
      case ":$launch_path:" in
        *":$shim_dir:"*) ;;
        *) launch_path="$shim_dir:$launch_path" ;;
      esac
    fi
    if [[ -n "$launch_python" ]]; then
      env PATH="$launch_path" PYTHON="$launch_python" PYTHON3="$launch_python" "$cursor_bin" "$dir" >/dev/null 2>&1 &
    else
      env PATH="$launch_path" "$cursor_bin" "$dir" >/dev/null 2>&1 &
    fi
    disown || true
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

container=""
if command -v docker >/dev/null 2>&1; then
  container="$(docker ps \
    --filter "label=garth.session=$best_session" \
    --filter "label=garth.agent=shell" \
    --format '{{.Names}}' 2>/dev/null | head -n 1 || true)"
fi

if [[ -n "$container" ]]; then
  workdir="$(docker inspect --format '{{.Config.WorkingDir}}' "$container" 2>/dev/null || true)"
  if [[ -z "$workdir" ]]; then
    workdir="/"
  fi
  escaped_workdir="$(printf '%q' "$workdir")"
  exec docker exec -it "$container" bash -lc "cd ${escaped_workdir}; exec bash"
fi

cd "$repo_root"
exec "${SHELL:-/bin/bash}" -l
SCRIPT
  chmod +x "$bridge_script"

  garth_python - << 'PY' "$settings_file"
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
terminal_env_key = "terminal.integrated.env.osx"
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

# Pin a concrete interpreter so Cursor doesn't fall back to macOS system Python.
python_candidates = [
    Path("/opt/homebrew/bin/python3"),
    Path("/usr/local/bin/python3"),
]
python_path = next((str(p) for p in python_candidates if p.exists()), sys.executable)
if not python_path:
    python_path = "python3"

data["python.defaultInterpreterPath"] = python_path
data["python.pythonPath"] = python_path
# Avoid extension-level "install python" probes on macOS stubs.
data["python.disableInstallationCheck"] = True
# Cursor's pyright fork defaults to fromEnvironment and may invoke bare 'python'.
data["cursorpyright.importStrategy"] = "useBundled"

terminal_env = data.get(terminal_env_key)
if not isinstance(terminal_env, dict):
    terminal_env = {}

python_bin_dir = str(Path(python_path).parent) if "/" in python_path else ""
path_expr = terminal_env.get("PATH")
if python_bin_dir:
    if isinstance(path_expr, str) and path_expr:
        if python_bin_dir not in path_expr.split(":"):
            terminal_env["PATH"] = f"{python_bin_dir}:{path_expr}"
    else:
        terminal_env["PATH"] = f"{python_bin_dir}:${{env:PATH}}"
    terminal_env["PYTHON"] = python_path
    terminal_env["PYTHON3"] = python_path

data[terminal_env_key] = terminal_env

# Clean up stale invalid top-level editor settings if present.
if "reportUnnecessaryEllipsis" in data:
    del data["reportUnnecessaryEllipsis"]

settings_path.write_text(json.dumps(data, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY
}

garth_browser_profile_path() {
  local profiles_root="$1"
  local profile_name="$2"
  local expanded_root="${profiles_root/#\~/$HOME}"
  printf '%s\n' "$expanded_root/$profile_name"
}

garth_find_browser_binary() {
  local preferred="$1"
  shift

  if [[ -n "$preferred" ]] && command -v "$preferred" >/dev/null 2>&1; then
    printf '%s\n' "$preferred"
    return 0
  fi

  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

garth_launch_browser_command() {
  local command_name="$1"
  shift

  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "[dry-run] $command_name $*"
    return 0
  fi

  "$command_name" "$@" >/dev/null 2>&1 &
  disown || true
}

garth_launch_browser() {
  local engine="$1"
  local app="$2"
  local binary="$3"
  local profiles_root="$4"
  local profile_name="$5"
  local url="$6"

  case "$engine" in
    chromium)
      garth_launch_chromium_browser "$app" "$binary" "$profiles_root" "$profile_name" "$url"
      ;;
    firefox)
      garth_launch_firefox_browser "$app" "$binary" "$profiles_root" "$profile_name" "$url"
      ;;
    open)
      garth_launch_url_only_browser "$app" "$url"
      ;;
    none)
      return 0
      ;;
    *)
      garth_log_warn "Unsupported browser engine: $engine"
      return 0
      ;;
  esac
}

garth_launch_chromium_browser() {
  local app="$1"
  local binary="$2"
  local profiles_root="$3"
  local profile_name="$4"
  local url="$5"

  if garth_is_macos; then
    if [[ -n "$profiles_root" ]]; then
      if [[ -z "$app" ]]; then
        garth_log_warn "Chromium browser launch skipped (missing macOS app name)"
        return 0
      fi
      local profile_path
      profile_path=$(garth_browser_profile_path "$profiles_root" "$profile_name")
      if [[ "$GARTH_DRY_RUN" == "true" ]]; then
        echo "[dry-run] open -na $app --args --user-data-dir=$profile_path $url"
        return 0
      fi
      mkdir -p "$profile_path"
      open -na "$app" --args "--user-data-dir=$profile_path" "$url" >/dev/null 2>&1 || \
        garth_log_warn "Failed to launch $app with isolated Chromium profile"
      return 0
    fi

    if [[ "$app" == "Google Chrome" ]]; then
      if [[ "$GARTH_DRY_RUN" == "true" ]]; then
        echo "[dry-run] osascript Google Chrome new window -> $url"
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
    fi

    if [[ "$GARTH_DRY_RUN" == "true" ]]; then
      if [[ -n "$app" ]]; then
        echo "[dry-run] open -a $app $url"
      else
        echo "[dry-run] open $url"
      fi
      return 0
    fi

    if [[ -n "$app" ]]; then
      open -a "$app" "$url" >/dev/null 2>&1 || garth_log_warn "Failed to launch $app"
    else
      open "$url" >/dev/null 2>&1 || garth_log_warn "Failed to open browser URL"
    fi
    return 0
  fi

  local resolved_binary=""
  if ! resolved_binary=$(garth_find_browser_binary "$binary" google-chrome-stable google-chrome chromium-browser chromium); then
    garth_log_warn "Chromium browser launch skipped (no supported Linux binary found)"
    return 0
  fi

  if [[ -n "$profiles_root" ]]; then
    local profile_path
    profile_path=$(garth_browser_profile_path "$profiles_root" "$profile_name")
    if [[ "$GARTH_DRY_RUN" != "true" ]]; then
      mkdir -p "$profile_path"
    fi
    garth_launch_browser_command "$resolved_binary" "--user-data-dir=$profile_path" "$url"
    return 0
  fi

  garth_launch_browser_command "$resolved_binary" "$url"
}

garth_launch_firefox_browser() {
  local app="$1"
  local binary="$2"
  local profiles_root="$3"
  local profile_name="$4"
  local url="$5"

  if garth_is_macos; then
    if [[ -n "$profiles_root" ]]; then
      if [[ -z "$app" ]]; then
        garth_log_warn "Firefox browser launch skipped (missing macOS app name)"
        return 0
      fi
      local profile_path
      profile_path=$(garth_browser_profile_path "$profiles_root" "$profile_name")
      if [[ "$GARTH_DRY_RUN" == "true" ]]; then
        echo "[dry-run] open -na $app --args -profile $profile_path $url"
        return 0
      fi
      mkdir -p "$profile_path"
      open -na "$app" --args -profile "$profile_path" "$url" >/dev/null 2>&1 || \
        garth_log_warn "Failed to launch $app with isolated Firefox profile"
      return 0
    fi

    if [[ "$GARTH_DRY_RUN" == "true" ]]; then
      if [[ -n "$app" ]]; then
        echo "[dry-run] open -a $app $url"
      else
        echo "[dry-run] open $url"
      fi
      return 0
    fi

    if [[ -n "$app" ]]; then
      open -a "$app" "$url" >/dev/null 2>&1 || garth_log_warn "Failed to launch $app"
    else
      open "$url" >/dev/null 2>&1 || garth_log_warn "Failed to open browser URL"
    fi
    return 0
  fi

  local resolved_binary=""
  if ! resolved_binary=$(garth_find_browser_binary "$binary" firefox firefox-esr); then
    garth_log_warn "Firefox browser launch skipped (no supported Linux binary found)"
    return 0
  fi

  if [[ -n "$profiles_root" ]]; then
    local profile_path
    profile_path=$(garth_browser_profile_path "$profiles_root" "$profile_name")
    if [[ "$GARTH_DRY_RUN" != "true" ]]; then
      mkdir -p "$profile_path"
    fi
    garth_launch_browser_command "$resolved_binary" -profile "$profile_path" "$url"
    return 0
  fi

  garth_launch_browser_command "$resolved_binary" "$url"
}

garth_launch_url_only_browser() {
  local app="$1"
  local url="$2"

  if garth_is_macos; then
    if [[ "$GARTH_DRY_RUN" == "true" ]]; then
      if [[ -n "$app" ]]; then
        echo "[dry-run] open -a $app $url"
      else
        echo "[dry-run] open $url"
      fi
      return 0
    fi

    if [[ -n "$app" ]]; then
      open -a "$app" "$url" >/dev/null 2>&1 || garth_log_warn "Failed to launch $app"
    else
      open "$url" >/dev/null 2>&1 || garth_log_warn "Failed to open browser URL"
    fi
    return 0
  fi

  if ! command -v xdg-open >/dev/null 2>&1; then
    garth_log_warn "Browser launch skipped (xdg-open not available)"
    return 0
  fi

  garth_launch_browser_command xdg-open "$url"
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
