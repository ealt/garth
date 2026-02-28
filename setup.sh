#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_PATH" ]]; do
  LINK_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
  SOURCE_PATH="$(readlink "$SOURCE_PATH")"
  [[ "$SOURCE_PATH" != /* ]] && SOURCE_PATH="$LINK_DIR/$SOURCE_PATH"
done
REPO_ROOT="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"

if [[ "$(uname -s)" == "Darwin" && -x "/opt/homebrew/bin/python3" ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

usage() {
  cat << 'USAGE'
Usage: ./setup.sh [--yes]

Bootstraps the standalone garth repo setup:
  1) runs `bin/garth setup` (interactive by default)
  2) creates/validates repo-local `config.toml`

Options:
  --yes, -y   Run non-interactively (`bin/garth setup --yes`)
  --help, -h  Show help
USAGE
}

log_info() {
  printf 'INFO: %s\n' "$1"
}

warn_python3_prereq() {
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  local py_path py_ver
  py_path="$(command -v python3)"
  py_ver="$(python3 --version 2>/dev/null || true)"

  if [[ "$(uname -s)" == "Darwin" && "$py_path" == "/usr/bin/python3" ]]; then
    log_info "Detected macOS system python3 ($py_ver at $py_path)"
    log_info "This can trigger Command Line Tools prompts during setup/use."
    log_info "Recommended: brew install python && put /opt/homebrew/bin before /usr/bin in PATH."
  fi
}

main() {
  local non_interactive=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y)
        non_interactive=true
        shift
        ;;
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

  warn_python3_prereq

  if [[ "$non_interactive" == "true" ]]; then
    log_info "Running non-interactive garth setup"
    "$garth_bin" setup --yes
  else
    log_info "Running interactive garth setup"
    "$garth_bin" setup
  fi
}

main "$@"
