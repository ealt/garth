# 1Password secret retrieval helpers.

if [[ -n "${GARTH_SECRETS_SH_LOADED:-}" ]]; then
  return 0
fi
GARTH_SECRETS_SH_LOADED=1
: "${GARTH_OP_SESSION_READY:=false}"
: "${GARTH_OP_AUTO_SIGNIN:=true}"

garth_op_auto_signin_enabled() {
  [[ "${GARTH_OP_AUTO_SIGNIN:-true}" == "true" ]]
}

# Resolve the 1Password account shorthand from op account list.
# Used for non-TTY signin where --account is required.
garth_op_resolve_account() {
  local account=""
  account=$(op account list --format json 2>/dev/null | \
    garth_python -c "import json,sys;a=json.load(sys.stdin);print(a[0]['url'].split('.')[0] if a else '')" 2>/dev/null) || true
  [[ -n "$account" ]] && printf '%s' "$account"
}

# Attempt op signin, using --account in non-TTY contexts where bare
# "op signin" silently no-ops.
garth_op_try_signin() {
  if ! garth_op_auto_signin_enabled; then
    return 1
  fi
  if [[ -t 0 || -t 1 || -t 2 ]]; then
    eval "$(op signin)" && op whoami >/dev/null 2>&1 && return 0
    return 1
  fi
  # Non-TTY: bare "op signin" silently no-ops; use --account to trigger
  # system-auth (biometric) through the 1Password daemon instead.
  local account
  account=$(garth_op_resolve_account) || return 1
  [[ -n "$account" ]] || return 1
  op signin --account "$account" >/dev/null 2>&1 && op whoami >/dev/null 2>&1 && return 0
  return 1
}

garth_require_op() {
  if [[ "$GARTH_OP_SESSION_READY" == "true" ]]; then
    return 0
  fi
  garth_require_cmd op
  if op whoami >/dev/null 2>&1; then
    GARTH_OP_SESSION_READY=true
    export GARTH_OP_SESSION_READY
    return 0
  fi
  garth_log_info "1Password CLI is not signed in; attempting sign-in" >&2
  if garth_op_try_signin; then
    GARTH_OP_SESSION_READY=true
    export GARTH_OP_SESSION_READY
    garth_log_success "1Password CLI sign-in complete" >&2
    return 0
  fi
  if ! garth_op_auto_signin_enabled; then
    garth_die "1Password CLI is not signed in and auto sign-in is disabled. Run: eval \"\$(op signin)\"" 2
  fi
  garth_die "1Password CLI is not signed in. Run: eval \"\$(op signin)\"" 2
}

garth_secret_read() {
  local ref="$1"
  local err_file
  local value=""
  garth_require_op
  err_file=$(mktemp "${TMPDIR:-/tmp}/garth-op-read.XXXXXX") || return 1
  garth_register_cleanup_path "$err_file"

  if value=$(op read "$ref" 2>"$err_file"); then
    printf '%s' "$value"
    rm -f "$err_file"
    return 0
  fi

  if grep -qi "not currently signed in" "$err_file" && garth_op_auto_signin_enabled; then
    GARTH_OP_SESSION_READY=false
    export GARTH_OP_SESSION_READY
    garth_log_info "1Password session refresh required; attempting sign-in" >&2
    if garth_op_try_signin && value=$(op read "$ref" 2>/dev/null); then
      GARTH_OP_SESSION_READY=true
      export GARTH_OP_SESSION_READY
      garth_log_success "1Password CLI session refresh complete" >&2
      printf '%s' "$value"
      rm -f "$err_file"
      return 0
    fi
  fi

  cat "$err_file" >&2
  rm -f "$err_file"
  return 1
}

garth_ensure_secret_access() {
  local probe_ref="$1"
  garth_require_op

  local err_file
  err_file=$(mktemp "${TMPDIR:-/tmp}/garth-op-probe.XXXXXX") || return 1
  garth_register_cleanup_path "$err_file"

  if op read "$probe_ref" >/dev/null 2>"$err_file"; then
    rm -f "$err_file"
    return 0
  fi

  if grep -qi "not currently signed in" "$err_file" && garth_op_auto_signin_enabled; then
    GARTH_OP_SESSION_READY=false
    export GARTH_OP_SESSION_READY
    garth_log_info "1Password session refresh required; attempting sign-in" >&2
    if garth_op_try_signin && op read "$probe_ref" >/dev/null 2>&1; then
      GARTH_OP_SESSION_READY=true
      export GARTH_OP_SESSION_READY
      garth_log_success "1Password CLI session refresh complete" >&2
      rm -f "$err_file"
      return 0
    fi
  fi

  cat "$err_file" >&2
  rm -f "$err_file"
  return 1
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
