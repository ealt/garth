# Git-related helpers for garth.

if [[ -n "${GARTH_GIT_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_GIT_SH_LOADED=1

garth_git_repo_root() {
  local dir="$1"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null
}

garth_git_current_branch() {
  local repo_root="$1"
  git -C "$repo_root" rev-parse --abbrev-ref HEAD
}

garth_git_repo_name() {
  local repo_root="$1"
  local common_git_dir=""
  common_git_dir=$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$common_git_dir" ]]; then
    common_git_dir=$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null || true)
    if [[ -n "$common_git_dir" ]]; then
      common_git_dir=$(garth_abs_path "$repo_root/$common_git_dir")
    fi
  fi

  if [[ -n "$common_git_dir" ]]; then
    basename "$(dirname "$common_git_dir")"
    return 0
  fi

  basename "$repo_root"
}

garth_git_remote_url() {
  local repo_root="$1"
  local remote="${2:-origin}"
  git -C "$repo_root" remote get-url "$remote"
}

garth_git_default_branch() {
  local repo_root="$1"

  if [[ -n "${GARTH_DEFAULTS_DEFAULT_BRANCH:-}" ]]; then
    echo "$GARTH_DEFAULTS_DEFAULT_BRANCH"
    return 0
  fi

  local ref
  ref=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
  if [[ "$ref" == refs/remotes/origin/* ]]; then
    echo "${ref#refs/remotes/origin/}"
    return 0
  fi

  if git -C "$repo_root" show-ref --verify --quiet refs/heads/main || \
     git -C "$repo_root" show-ref --verify --quiet refs/remotes/origin/main; then
    echo "main"
    return 0
  fi

  if git -C "$repo_root" show-ref --verify --quiet refs/heads/master || \
     git -C "$repo_root" show-ref --verify --quiet refs/remotes/origin/master; then
    echo "master"
    return 0
  fi

  garth_git_current_branch "$repo_root"
}

garth_git_fetch_and_resolve_default_base() {
  local repo_root="$1"
  local default_branch
  default_branch=$(garth_git_default_branch "$repo_root")

  if ! git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
    echo "$default_branch"
    return 0
  fi

  git -C "$repo_root" fetch origin --quiet 2>/dev/null || true

  if git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
    echo "origin/$default_branch"
  else
    echo "$default_branch"
  fi
}

# Supports:
#   git@github.com:owner/repo.git
#   https://github.com/owner/repo.git
#   ssh://git@github.com/owner/repo.git
garth_git_owner_repo_from_remote() {
  local remote_url="$1"
  local owner_repo=""

  case "$remote_url" in
    git@github.com:*)
      owner_repo="${remote_url#git@github.com:}"
      ;;
    https://github.com/*)
      owner_repo="${remote_url#https://github.com/}"
      ;;
    http://github.com/*)
      owner_repo="${remote_url#http://github.com/}"
      ;;
    ssh://git@github.com/*)
      owner_repo="${remote_url#ssh://git@github.com/}"
      ;;
  esac

  [[ -n "$owner_repo" ]] || return 1
  owner_repo="${owner_repo%.git}"
  [[ "$owner_repo" =~ ^[^/]+/[^/]+$ ]] || return 1
  echo "$owner_repo"
}

garth_git_https_url_from_remote() {
  local remote_url="$1"
  local owner_repo
  owner_repo=$(garth_git_owner_repo_from_remote "$remote_url") || return 1
  echo "https://github.com/$owner_repo"
}

garth_git_session_name() {
  local repo_name="$1"
  local branch="$2"
  local max_len="${3:-}"
  if [[ -z "$max_len" ]]; then
    # macOS sun_path is 104 bytes.  Zellij places sockets at
    # $TMPDIR/zellij-$UID/$VERSION/$SESSION.  Reserve room for that prefix
    # plus a -NN suffix from garth_unique_session_name.
    local prefix="${TMPDIR:-/tmp}/zellij-$(id -u)/0.00.0/"
    local suffix_reserve=3  # e.g. "-15"
    max_len=$(( 103 - ${#prefix} - suffix_reserve ))  # 103 = 104 - null
    # Floor at a reasonable minimum
    (( max_len < 20 )) && max_len=20
  fi
  local branch_slug
  branch_slug=$(garth_slugify_branch "$branch")
  local session="garth-${repo_name}-${branch_slug}"
  if [[ ${#session} -le $max_len ]]; then
    echo "$session"
  else
    local hash
    hash=$(garth_hash_short "$session")
    echo "${session:0:$((max_len - 7))}-${hash:0:6}"
  fi
}

garth_hash_short() {
  local value="$1"
  if command -v shasum >/dev/null 2>&1; then
    echo "$value" | shasum | cut -c1-8
  else
    echo "$value" | sha256sum | cut -c1-8
  fi
}

garth_git_worktree_path() {
  local repo_root="$1"
  local branch="$2"
  local slug
  slug=$(garth_slugify_branch "$branch")

  local path="$repo_root/wt/$slug"
  if [[ -e "$path" ]]; then
    local suffix
    suffix=$(garth_hash_short "$branch")
    path="${path}-${suffix}"
  fi
  echo "$path"
}

garth_git_create_worktree() {
  local repo_root="$1"
  local branch="$2"
  local from_ref="$3"

  local path
  path=$(garth_git_worktree_path "$repo_root" "$branch")
  mkdir -p "$(dirname "$path")"

  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
    garth_die "Branch already exists locally: $branch" 1
  fi

  if [[ "$GARTH_DRY_RUN" == "true" ]]; then
    echo "$path"
    return 0
  fi

  git -C "$repo_root" fetch origin >/dev/null 2>&1 || true
  git -C "$repo_root" worktree add "$path" -b "$branch" "$from_ref" >/dev/null
  git -C "$path" config push.default current
  echo "$path"
}

garth_git_list_worktrees() {
  local repo_root="$1"
  git -C "$repo_root" worktree list --porcelain
}

garth_git_find_worktree_for_branch() {
  local repo_root="$1"
  local branch="$2"
  local line current_worktree current_branch

  current_worktree=""
  current_branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        current_worktree="${line#worktree }"
        current_branch=""
        ;;
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        if [[ "$current_branch" == "$branch" && -n "$current_worktree" ]]; then
          echo "$current_worktree"
          return 0
        fi
        ;;
      "")
        current_worktree=""
        current_branch=""
        ;;
    esac
  done < <(garth_git_list_worktrees "$repo_root")

  return 1
}
