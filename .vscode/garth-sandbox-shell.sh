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
