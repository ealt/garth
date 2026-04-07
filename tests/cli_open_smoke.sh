#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARTH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/garth-cli-open-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

REPO="$TMP_ROOT/repo"
ORIGIN_BARE="$TMP_ROOT/origin.git"
UPSTREAM_BARE="$TMP_ROOT/upstream.git"
STATE_HOME="$TMP_ROOT/state"
BROWSER_BIN_DIR="$TMP_ROOT/browser-bin"
BROWSER_CFG="$TMP_ROOT/browser-config.toml"
mkdir -p "$BROWSER_BIN_DIR"

git init -b main "$REPO" >/dev/null
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test User"
echo "init" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -m "init" >/dev/null

git init --bare "$ORIGIN_BARE" >/dev/null
git init --bare "$UPSTREAM_BARE" >/dev/null
git -C "$REPO" remote add origin "$ORIGIN_BARE"
git -C "$REPO" remote add upstream "$UPSTREAM_BARE"

git -C "$REPO" checkout -b topic >/dev/null
echo "topic" > "$REPO/topic.txt"
git -C "$REPO" add topic.txt
git -C "$REPO" commit -m "topic" >/dev/null
git -C "$REPO" push origin topic >/dev/null
git -C "$REPO" push upstream topic >/dev/null
git -C "$REPO" checkout main >/dev/null
git -C "$REPO" branch -D topic >/dev/null

# Keep refs/remotes from local pushes, but use GitHub-shaped remotes for dry-run launch summary.
git -C "$REPO" remote set-url origin "git@github.com:foo/bar.git"
git -C "$REPO" remote set-url upstream "git@github.com:foo/baz.git"

cat > "$BROWSER_BIN_DIR/chromium-browser" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BROWSER_BIN_DIR/chromium-browser"

GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true XDG_STATE_HOME="$STATE_HOME" \
  "$GARTH_ROOT/bin/garth" open --dir "$REPO" topic --dry-run >/dev/null
[[ "$(git -C "$REPO" for-each-ref --format='%(upstream:short)' refs/heads/topic)" == "origin/topic" ]]
[[ "$(git -C "$REPO" config --get push.default)" == "current" ]]

# Verify push.default=current is backfilled when reusing an existing worktree.
git -C "$REPO" config --unset push.default
GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true XDG_STATE_HOME="$STATE_HOME" \
  "$GARTH_ROOT/bin/garth" open --dir "$REPO" topic --dry-run >/dev/null
[[ "$(git -C "$REPO" config --get push.default)" == "current" ]]

git -C "$REPO" checkout main >/dev/null
echo "dirty" > "$REPO/uncommitted.txt"
set +e
DIRTY_OUT="$(GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true XDG_STATE_HOME="$STATE_HOME" "$GARTH_ROOT/bin/garth" open --dir "$REPO" topic --no-worktree --dry-run 2>&1)"
DIRTY_RC=$?
set -e
[[ $DIRTY_RC -ne 0 ]]
echo "$DIRTY_OUT" | grep -q "Cannot switch branches in-place with uncommitted changes"

# Regression: cmd_up with no forwarded flags must not crash on empty forward array (set -u).
git -C "$REPO" checkout -b topic2 >/dev/null 2>&1
echo "t2" > "$REPO/topic2.txt"
git -C "$REPO" add topic2.txt
git -C "$REPO" commit -m "topic2" >/dev/null
GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true \
  XDG_STATE_HOME="$STATE_HOME" "$GARTH_ROOT/bin/garth" up "$REPO" --branch topic2 --auto --dry-run >/dev/null
GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true \
  XDG_STATE_HOME="$STATE_HOME" "$GARTH_ROOT/bin/garth" up "$REPO" -b topic2 --auto --dry-run >/dev/null

# Open by session ID (exact and prefix) should use stored session state.
SESSION_DIR="$STATE_HOME/garth/sessions/session-open-id"
mkdir -p "$SESSION_DIR"
printf '%s\n' "abc123" > "$SESSION_DIR/id"
printf '%s\n' "garth-repo-topic2" > "$SESSION_DIR/session"
printf '%s\n' "$REPO" > "$SESSION_DIR/repo_root"
printf '%s\n' "$REPO" > "$SESSION_DIR/worktree"
printf '%s\n' "false" > "$SESSION_DIR/worktree_managed"
printf '%s\n' "topic2" > "$SESSION_DIR/branch"

GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true XDG_STATE_HOME="$STATE_HOME" \
  "$GARTH_ROOT/bin/garth" open abc --dry-run >/dev/null

GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true XDG_STATE_HOME="$STATE_HOME" \
  "$GARTH_ROOT/bin/garth" open --dir "$REPO" -b topic2 -w "$REPO" -s garth-repo-topic2 --dry-run >/dev/null

set +e
MISSING_ID_OUT="$(GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true XDG_STATE_HOME="$STATE_HOME" "$GARTH_ROOT/bin/garth" open deadbe --dry-run 2>&1)"
MISSING_ID_RC=$?
set -e
[[ $MISSING_ID_RC -ne 0 ]]
echo "$MISSING_ID_OUT" | grep -q "No session matches ID prefix 'deadbe'"

set +e
INCOMPATIBLE_FLAGS_OUT="$(GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true XDG_STATE_HOME="$STATE_HOME" "$GARTH_ROOT/bin/garth" open abc123 -b topic2 --dry-run 2>&1)"
INCOMPATIBLE_FLAGS_RC=$?
set -e
[[ $INCOMPATIBLE_FLAGS_RC -ne 0 ]]
echo "$INCOMPATIBLE_FLAGS_OUT" | grep -q "require --dir"

# Verify push.default=current is backfilled when resuming a managed worktree by session ID.
TOPIC_WT=$(git -C "$REPO" worktree list --porcelain | grep "^worktree.*wt/topic$" | sed 's/^worktree //')
MANAGED_SESSION_DIR="$STATE_HOME/garth/sessions/session-managed-wt"
mkdir -p "$MANAGED_SESSION_DIR"
printf '%s\n' "def456" > "$MANAGED_SESSION_DIR/id"
printf '%s\n' "garth-repo-topic" > "$MANAGED_SESSION_DIR/session"
printf '%s\n' "$REPO" > "$MANAGED_SESSION_DIR/repo_root"
printf '%s\n' "$TOPIC_WT" > "$MANAGED_SESSION_DIR/worktree"
printf '%s\n' "true" > "$MANAGED_SESSION_DIR/worktree_managed"
printf '%s\n' "topic" > "$MANAGED_SESSION_DIR/branch"
git -C "$REPO" config --unset push.default
GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_GUI=true XDG_STATE_HOME="$STATE_HOME" \
  "$GARTH_ROOT/bin/garth" open def --dry-run >/dev/null
[[ "$(git -C "$REPO" config --get push.default)" == "current" ]]

set +e
DEPRECATED_SKIP_OUT="$(GARTH_SKIP_CHROME=true GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" XDG_STATE_HOME="$STATE_HOME" "$GARTH_ROOT/bin/garth" open --dir "$REPO" topic --dry-run 2>&1)"
DEPRECATED_SKIP_RC=$?
set -e
[[ $DEPRECATED_SKIP_RC -ne 0 ]]
echo "$DEPRECATED_SKIP_OUT" | grep -q "GARTH_SKIP_CHROME is no longer supported"

set +e
DEPRECATED_PROFILE_OUT="$(GARTH_CHROME_PROFILES_DIR=/tmp/browser-profiles GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" XDG_STATE_HOME="$STATE_HOME" "$GARTH_ROOT/bin/garth" open --dir "$REPO" topic --dry-run 2>&1)"
DEPRECATED_PROFILE_RC=$?
set -e
[[ $DEPRECATED_PROFILE_RC -ne 0 ]]
echo "$DEPRECATED_PROFILE_OUT" | grep -q "GARTH_CHROME_PROFILES_DIR is no longer supported"

SKIP_BROWSER_OUT="$(GARTH_CONFIG_PATH="$GARTH_ROOT/config.example.toml" GARTH_SKIP_BROWSER=true GARTH_SKIP_CURSOR=true XDG_STATE_HOME="$STATE_HOME" "$GARTH_ROOT/bin/garth" open --dir "$REPO" topic --dry-run 2>&1)"
echo "$SKIP_BROWSER_OUT" | grep -q "GARTH_SKIP_BROWSER=true; skipping browser launch"

cp "$GARTH_ROOT/config.example.toml" "$BROWSER_CFG"
perl -0pi -e 's/app = "Google Chrome"/app = "Brave Browser"/' "$BROWSER_CFG"
perl -0pi -e 's/binary = ""/binary = "chromium-browser"/' "$BROWSER_CFG"
perl -0pi -e 's#profiles_dir = ".*"#profiles_dir = ""#' "$BROWSER_CFG"

BROWSER_OUT="$(PATH="$BROWSER_BIN_DIR:$PATH" GARTH_CONFIG_PATH="$BROWSER_CFG" GARTH_SKIP_CURSOR=true XDG_STATE_HOME="$STATE_HOME" "$GARTH_ROOT/bin/garth" open --dir "$REPO" topic --dry-run 2>&1)"
if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "$BROWSER_OUT" | grep -q '\[dry-run\] open -a Brave Browser '
else
  echo "$BROWSER_OUT" | grep -q '\[dry-run\] chromium-browser https://github.com/'
fi

echo "cli_open_smoke: ok"
