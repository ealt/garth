#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_PATH" ]]; do
  LINK_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
  SOURCE_PATH="$(readlink "$SOURCE_PATH")"
  [[ "$SOURCE_PATH" != /* ]] && SOURCE_PATH="$LINK_DIR/$SOURCE_PATH"
done
REPO_ROOT="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"

usage() {
  cat << 'USAGE'
Usage: ./setup.sh

Bootstraps the standalone garth repo setup:
  1) runs `bin/garth setup --yes`
  2) creates/validates repo-local `config.toml`
USAGE
}

log_info() {
  printf 'INFO: %s\n' "$1"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage
        exit 1
        ;;
    esac
  done

  local garth_bin="$REPO_ROOT/bin/garth"
  if [[ ! -x "$garth_bin" ]]; then
    printf 'Error: %s is not executable\n' "$garth_bin" >&2
    exit 1
  fi

  log_info "Running non-interactive garth setup"
  "$garth_bin" setup --yes
}

main "$@"
