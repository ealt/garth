#!/usr/bin/env bash
set -euo pipefail

REPO="ealt/garth"
DEFAULT_PREFIX="$HOME/.local/share/garth"
DEFAULT_BIN_DIR="$HOME/.local/bin"

usage() {
  cat << 'USAGE'
Usage: install.sh [options]

Install garth from a GitHub release tarball.

Options:
  --prefix DIR     Installation directory (default: ~/.local/share/garth)
  --bin-dir DIR    Symlink directory (default: ~/.local/bin)
  --version X.Y.Z  Install a specific version (default: latest)
  --uninstall      Remove a previous installation
  -h, --help       Show this help
USAGE
}

die() { printf '\033[0;31mError: %s\033[0m\n' "$1" >&2; exit 1; }
info() { printf '\033[0;34m%s\033[0m\n' "$1"; }
ok() { printf '\033[0;32m%s\033[0m\n' "$1"; }

check_deps() {
  local missing=()
  for cmd in curl tar; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if ((${#missing[@]} > 0)); then
    die "Missing required commands: ${missing[*]}"
  fi
}

detect_os() {
  local os
  os="$(uname -s)"
  case "$os" in
    Darwin|Linux) echo "$os" ;;
    *) die "Unsupported OS: $os (only Darwin and Linux are supported)" ;;
  esac
}

get_latest_version() {
  local url="https://api.github.com/repos/${REPO}/releases/latest"
  local tag
  tag="$(curl -fsSL "$url" | grep -o '"tag_name":\s*"[^"]*"' | grep -o 'v[^"]*')" \
    || die "Failed to fetch latest release from GitHub"
  echo "${tag#v}"
}

do_install() {
  local prefix="$1" bin_dir="$2" version="$3"
  local tarball_url="https://github.com/${REPO}/releases/download/v${version}/garth-${version}.tar.gz"

  info "Installing garth v${version}..."

  # Download and extract
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  info "Downloading ${tarball_url}..."
  curl -fsSL "$tarball_url" -o "$tmpdir/garth.tar.gz" \
    || die "Failed to download release tarball (v${version} may not exist)"

  # Clean previous install at prefix (preserve nothing — config is in XDG)
  if [[ -d "$prefix" ]]; then
    rm -rf "$prefix"
  fi
  mkdir -p "$prefix"

  tar -xzf "$tmpdir/garth.tar.gz" --strip-components=1 -C "$prefix" \
    || die "Failed to extract tarball"

  # Symlink into bin dir
  mkdir -p "$bin_dir"
  ln -sf "$prefix/bin/garth" "$bin_dir/garth"

  ok "garth v${version} installed to ${prefix}"
  echo ""
  echo "Next steps:"
  echo "  1. Ensure ${bin_dir} is in your PATH"
  echo "  2. Run: garth setup"
}

do_uninstall() {
  local prefix="$1" bin_dir="$2"

  if [[ -L "$bin_dir/garth" ]]; then
    rm -f "$bin_dir/garth"
    info "Removed symlink ${bin_dir}/garth"
  fi

  if [[ -d "$prefix" ]]; then
    rm -rf "$prefix"
    info "Removed ${prefix}"
  fi

  ok "garth uninstalled"
}

main() {
  local prefix="$DEFAULT_PREFIX"
  local bin_dir="$DEFAULT_BIN_DIR"
  local version=""
  local uninstall=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix)
        [[ -n "${2:-}" ]] || die "--prefix requires an argument"
        prefix="$2"; shift 2 ;;
      --bin-dir)
        [[ -n "${2:-}" ]] || die "--bin-dir requires an argument"
        bin_dir="$2"; shift 2 ;;
      --version)
        [[ -n "${2:-}" ]] || die "--version requires an argument"
        version="$2"; shift 2 ;;
      --uninstall)
        uninstall=true; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        die "Unknown option: $1" ;;
    esac
  done

  if "$uninstall"; then
    do_uninstall "$prefix" "$bin_dir"
    return
  fi

  check_deps
  detect_os >/dev/null

  if [[ -z "$version" ]]; then
    info "Fetching latest version..."
    version="$(get_latest_version)"
  fi

  do_install "$prefix" "$bin_dir" "$version"
}

main "$@"
