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
  basename "$repo_root"
}

garth_git_remote_url() {
  local repo_root="$1"
  local remote="${2:-origin}"
  git -C "$repo_root" remote get-url "$remote"
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
  local branch_slug
  branch_slug=$(garth_slugify_branch "$branch")
  local session="garth-${repo_name}-${branch_slug}"
  # Keep names manageable for zellij/docker.
  echo "${session:0:80}"
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
  git -C "$repo_root" worktree add "$path" -b "$branch" "$from_ref"
  echo "$path"
}

garth_git_list_worktrees() {
  local repo_root="$1"
  git -C "$repo_root" worktree list --porcelain
}
