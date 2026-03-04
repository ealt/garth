# Session state helpers.

if [[ -n "${GARTH_SESSION_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_SESSION_SH_LOADED=1

ensure_state_root() {
  mkdir -p "$GARTH_STATE_ROOT/sessions"
  chmod 700 "$GARTH_STATE_ROOT" "$GARTH_STATE_ROOT/sessions"
}

session_dir_for() {
  local session="$1"
  echo "$GARTH_STATE_ROOT/sessions/$session"
}

write_state_value() {
  local session_dir="$1"
  local key="$2"
  local value="$3"
  printf '%s\n' "$value" > "$session_dir/$key"
}

read_state_value() {
  local session_dir="$1"
  local key="$2"
  if [[ -f "$session_dir/$key" ]]; then
    cat "$session_dir/$key"
  fi
}

garth_session_list_dirs() {
  local dir
  for dir in "$GARTH_STATE_ROOT"/sessions/*; do
    [[ -d "$dir" ]] || continue
    echo "$dir"
  done
}

garth_session_id_for_dir() {
  local session_dir="$1"
  local id
  id=$(read_state_value "$session_dir" "id")
  if [[ -z "$id" ]]; then
    # Legacy fallback for pre-ID state dirs.
    id=$(basename "$session_dir")
  fi
  echo "$id"
}

garth_session_name_for_dir() {
  local session_dir="$1"
  local name
  name=$(read_state_value "$session_dir" "session")
  if [[ -z "$name" ]]; then
    name=$(basename "$session_dir")
  fi
  echo "$name"
}

garth_session_generate_id() {
  local id dir existing
  while true; do
    if command -v hexdump >/dev/null 2>&1; then
      id=$(hexdump -n 3 -e '/1 "%02x"' /dev/urandom 2>/dev/null || true)
    elif command -v od >/dev/null 2>&1; then
      id=$(od -An -N3 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    elif command -v openssl >/dev/null 2>&1; then
      id=$(openssl rand -hex 3 2>/dev/null || true)
    else
      id=$(date +%s%N | shasum | cut -c1-6)
    fi
    [[ "$id" =~ ^[a-f0-9]{6}$ ]] || continue
    existing=""
    while IFS= read -r dir; do
      [[ -n "$dir" ]] || continue
      if [[ "$(garth_session_id_for_dir "$dir")" == "$id" ]]; then
        existing="1"
        break
      fi
    done < <(garth_session_list_dirs)
    if [[ -z "$existing" ]]; then
      echo "$id"
      return 0
    fi
  done
}

garth_find_sessions_for_branch() {
  local repo_root="$1"
  local branch="$2"
  local dir
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    if [[ "$(read_state_value "$dir" "repo_root")" == "$repo_root" && "$(read_state_value "$dir" "branch")" == "$branch" ]]; then
      echo "$dir"
    fi
  done < <(garth_session_list_dirs)
}

garth_find_sessions_by_id_prefix() {
  local prefix="$1"
  local dir id
  local -a exact_matches=()
  local -a prefix_matches=()
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    id=$(garth_session_id_for_dir "$dir")
    if [[ "$id" == "$prefix"* ]]; then
      prefix_matches+=("$dir")
      if [[ "$id" == "$prefix" ]]; then
        exact_matches+=("$dir")
      fi
    fi
  done < <(garth_session_list_dirs)

  if [[ ${#exact_matches[@]} -gt 0 ]]; then
    printf '%s\n' "${exact_matches[@]}"
  else
    printf '%s\n' "${prefix_matches[@]}"
  fi
}
