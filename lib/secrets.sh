# 1Password secret retrieval helpers.

if [[ -n "${GARTH_SECRETS_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_SECRETS_SH_LOADED=1

garth_require_op() {
  garth_require_cmd op
  if ! op whoami >/dev/null 2>&1; then
    if [[ -t 0 && -t 1 ]]; then
      garth_log_info "1Password CLI is not signed in; running 'eval \"\$(op signin)\"'"
      if eval "$(op signin)" && op whoami >/dev/null 2>&1; then
        garth_log_success "1Password CLI sign-in complete"
        return 0
      fi
      garth_die "1Password CLI sign-in failed. Run: eval \"\$(op signin)\"" 2
    fi
    garth_die "1Password CLI is not signed in. Run: eval \"\$(op signin)\"" 2
  fi
}

garth_secret_read() {
  local ref="$1"
  garth_require_op
  op read "$ref"
}

garth_secret_write_file() {
  local ref="$1"
  local out_file="$2"

  local value
  value=$(garth_secret_read "$ref") || return 1

  umask 077
  printf '%s\n' "$value" > "$out_file"
  chmod 600 "$out_file"
}
