# Multi-Browser Support for Garth

## Context

Garth currently hardcodes Google Chrome as the only browser option. The `[chrome]`
config section, `GARTH_CHROME_*` env vars, and `garth_launch_chrome_profile()`
function are all Chrome-specific. Users who prefer Firefox, Edge, Brave, or other
browsers have no config path — they must skip browser launch entirely.

This change replaces the Chrome-specific integration with a generic engine-based
browser abstraction: **chromium** (any `--user-data-dir` browser), **firefox**
(any `-profile` browser), **open** (URL-only, no profile isolation), and **none**
(disabled). The user specifies the macOS app name and optional Linux binary.

## Breaking Changes

This is a **hard break** for existing configs and env vars:
- `[chrome]` config section is rejected with a clear migration error
- `GARTH_SKIP_CHROME` env var is rejected at startup with migration message
- `GARTH_CHROME_*` env vars are no longer emitted
- `garth_launch_chrome_profile()` function is removed

Users must migrate `[chrome]` to `[browser]` with `engine = "chromium"`.
README includes an upgrade migration note.

## Config Design

Replace `[chrome]` with `[browser]`:

```toml
[browser]
engine = "chromium"          # chromium | firefox | open | none
app = "Google Chrome"        # macOS app name for `open -na`
binary = ""                  # Linux binary (auto-detected if empty)
profiles_dir = "~/Library/Application Support/Chrome-ProjectProfiles"
```

**Note:** The old `profile_directory` field is dropped. It was emitted by the
config parser but never consumed by any shell code — dead code. If needed in the
future, it can be added back with proper per-engine semantics.

### `profiles_dir` behavior (both platforms)

| `profiles_dir` | macOS | Linux |
|---|---|---|
| non-empty | Launch with profile isolation (`--user-data-dir` / `-profile`) | Same — direct binary with profile flag |
| `""` (empty) | Open URL in default browser profile (no isolation) | Same — `$binary "$url"` with no profile flag |

## Files to Modify

### 1. `lib/config-parser.py` — Config validation & env emission

**Constants (top of file):**
- Remove `"chrome"` from `ALLOWED_TOP`, add `"browser"`
- Remove `ALLOWED_CHROME`
- Add `ALLOWED_BROWSER = {"engine", "app", "binary", "profiles_dir"}`
- Add `BROWSER_ENGINES = {"chromium", "firefox", "open", "none"}`
- Add `ENGINE_DEFAULTS` dict mapping engine to default app/binary/profiles_dir:
  ```python
  ENGINE_DEFAULTS = {
      "chromium": {"app": "Google Chrome", "binary": "", "profiles_dir": "~/Library/Application Support/Chrome-ProjectProfiles"},
      "firefox":  {"app": "Firefox", "binary": "", "profiles_dir": "~/Library/Application Support/Firefox-ProjectProfiles"},
      "open":     {"app": "", "binary": "", "profiles_dir": ""},
      "none":     {"app": "", "binary": "", "profiles_dir": ""},
  }
  ```

**`normalize_config()` (replace lines 258-275):**
- If `"chrome"` key exists in raw config: `out.error("[chrome] is no longer supported; migrate to [browser] with engine = \"chromium\". See config.example.toml")`
- Parse `[browser]` section (default to empty dict if absent)
- Validate `engine` is in `BROWSER_ENGINES` (default: `"chromium"`)
- Default `app`, `binary`, `profiles_dir` from `ENGINE_DEFAULTS[engine]` when not provided
- Validate all fields are strings
- Warn if `engine` is `"open"` or `"none"` and `profiles_dir` is non-empty
- Store as `norm["browser"]`

**`emit_env()` (replace lines 503-504):**
```python
put("GARTH_BROWSER_ENGINE", browser["engine"])
put("GARTH_BROWSER_APP", browser["app"])
put("GARTH_BROWSER_BINARY", browser["binary"])
put("GARTH_BROWSER_PROFILES_DIR", browser["profiles_dir"])
```

No legacy `GARTH_CHROME_*` emission, no `profile_directory` (hard break, field dropped).

### 2. `lib/workspace.sh` — Browser launch functions

**Replace `garth_launch_chrome_profile()` (lines 291-344) with:**

- `garth_launch_browser()` — main dispatcher:
  ```
  garth_launch_browser(engine, app, binary, profiles_root, profile_name, url)
  ```
  Dispatches to engine-specific function based on `engine` arg. Returns 0 for
  `none`. Logs and returns 0 on all failures (non-fatal, matching current behavior).

- `garth_launch_chromium_browser(app, binary, profiles_root, profile_name, url)`:
  - **macOS with profiles_root**: `open -na "$app" --args "--user-data-dir=$expanded_root/$profile_name" "$url"`
  - **macOS without profiles_root (app is "Google Chrome")**: existing AppleScript
    new-window path (preserve backward compat for Chrome specifically)
  - **macOS without profiles_root (other app)**: `open -a "$app" "$url"`
  - **Linux with profiles_root**: resolve binary via `command -v` (try `$binary`,
    then common names like `google-chrome-stable`, `google-chrome`); invoke with
    `--user-data-dir=` flag; background with `>/dev/null 2>&1 &`
  - **Linux without profiles_root**: resolve binary, invoke with just `"$url"`
    (default profile, no isolation)
  - **Neither macOS nor Linux binary found**: log warning, return 0

- `garth_launch_firefox_browser(app, binary, profiles_root, profile_name, url)`:
  - **macOS with profiles_root**: `open -na "$app" --args -profile "$expanded_root/$profile_name" "$url"`
  - **macOS without profiles_root**: `open -a "$app" "$url"`
  - **Linux with profiles_root**: resolve binary (`$binary`, then `firefox`,
    `firefox-esr`); `mkdir -p` profile dir; invoke with `-profile "$path" "$url"`;
    background
  - **Linux without profiles_root**: resolve binary, invoke with just `"$url"`
    (default profile, no isolation)

- `garth_launch_url_only_browser(app, url)`:
  - **macOS**: `open -a "$app" "$url"` (or just `open "$url"` if app is empty)
  - **Linux**: `xdg-open "$url"` if available, else warning

- Remove `garth_launch_chrome_profile()` entirely (hard break).

**Linux binary auto-detection helper:**
```bash
garth_find_browser_binary() {
  local preferred="$1"
  shift
  # remaining args are fallback candidates
  if [[ -n "$preferred" ]] && command -v "$preferred" >/dev/null 2>&1; then
    echo "$preferred"; return 0
  fi
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"; return 0
    fi
  done
  return 1
}
```

Default Linux candidates per engine:
- chromium: `google-chrome-stable`, `google-chrome`, `chromium-browser`, `chromium`
- firefox: `firefox`, `firefox-esr`

### 3. `bin/garth` — CLI launch sequence

**Add preflight check for deprecated env vars** at the top of
`garth_launch_workspace()` (line ~500), which is the shared entry point for
`new`, `up`, and `open` subcommands — so all browser-launching paths are covered:
```bash
if [[ -n "${GARTH_SKIP_CHROME+x}" ]]; then
  garth_die "GARTH_SKIP_CHROME is no longer supported; use GARTH_SKIP_BROWSER=true instead"
fi
if [[ -n "${GARTH_CHROME_PROFILES_DIR+x}" ]]; then
  garth_die "GARTH_CHROME_PROFILES_DIR is no longer supported; set browser.profiles_dir in config.toml instead"
fi
```
This must be in `bin/garth` because the config parser cannot detect shell env
vars — it only validates TOML. Placed in the shared function so users see the
error regardless of which subcommand they invoke.

**Lines 835-839 — Replace Chrome skip/launch block:**
```bash
if [[ "${GARTH_SKIP_BROWSER:-false}" == "true" ]]; then
  garth_log_warn "GARTH_SKIP_BROWSER=true; skipping browser launch"
else
  garth_launch_browser \
    "${GARTH_BROWSER_ENGINE:-chromium}" \
    "${GARTH_BROWSER_APP:-Google Chrome}" \
    "${GARTH_BROWSER_BINARY:-}" \
    "${GARTH_BROWSER_PROFILES_DIR:-}" \
    "$profile_name" \
    "$github_url"
fi
```

**Line 826** — Update GUI skip message from "Chrome" to "browser".

**Remove** all references to `GARTH_SKIP_CHROME` and `GARTH_CHROME_PROFILES_DIR`.

### 4. `config.example.toml` — Replace lines 39-44

```toml
[browser]
# Engine type: chromium (--user-data-dir), firefox (-profile), open (URL only), none
engine = "chromium"
# macOS app name used by `open -na`.
#   chromium engine: "Google Chrome", "Brave Browser", "Microsoft Edge", "Chromium"
#   firefox engine:  "Firefox", "Firefox Developer Edition"
#   open engine:     "Safari", "Arc", or any app that accepts a URL argument
app = "Google Chrome"
# Linux binary name. Leave empty to auto-detect from common names.
# Examples: "google-chrome", "brave-browser", "firefox", "microsoft-edge"
binary = ""
# Per-project profile directory root. Set to "" to use default browser profile
# (no isolation). Applies to chromium and firefox engines only.
profiles_dir = "~/Library/Application Support/Chrome-ProjectProfiles"
```

### 5. Tests

**`tests/config_parser_smoke.sh` — Update existing tests:**
- Replace `GARTH_CHROME_PROFILES_DIR` grep with `GARTH_BROWSER_ENGINE=`
- Add test: config with `[chrome]` section produces validation error
- Add test: unknown `engine` value produces validation error
- Add test: `engine = "none"` with non-empty `profiles_dir` produces warning

**`tests/browser_launch_smoke.sh` — New test file:**
- Source `lib/workspace.sh` in a test harness
- Test `garth_find_browser_binary` with mocked PATH
- Test `garth_launch_browser "none" ...` returns 0 immediately
- Test dry-run output for each engine type
- Test `garth_launch_browser` with `engine = "chromium"` and
  `app = "Brave Browser"` produces correct dry-run output

**`tests/cli_open_smoke.sh` — Extend existing CLI tests:**
- Test that `GARTH_SKIP_CHROME` set causes a startup error (preflight in
  `garth_launch_workspace`)
- Test that `GARTH_CHROME_PROFILES_DIR` set causes a startup error (same
  preflight)
- Test that `GARTH_SKIP_BROWSER=true` is respected in dry-run mode
- Test that `GARTH_BROWSER_ENGINE` / `GARTH_BROWSER_APP` are wired through to
  the launch path (dry-run output reflects configured values)

### 6. Documentation

**`README.md`:**
- Replace `[chrome]` section description with `[browser]` and document all fields
- Replace `GARTH_SKIP_CHROME` with `GARTH_SKIP_BROWSER` in env var list
- Update "Chrome" references in feature description to "browser"
- Replace "Chrome note" block with "Browser note" block with engine examples
- Add **Upgrade note** calling out the `[chrome]` → `[browser]` breaking change
  and `GARTH_SKIP_CHROME` → `GARTH_SKIP_BROWSER` rename

**`AGENTS.md`:**
- Update workspace.sh module description (line ~251) to mention multi-browser
- Update config-parser.py section to mention `[browser]` validation

**`CLAUDE.md`:**
- Add `bash tests/browser_launch_smoke.sh` to Quick Commands

## Implementation Order

1. `lib/config-parser.py` — foundation; all other code depends on env vars
2. `config.example.toml` — update in lockstep with parser
3. `lib/workspace.sh` — new browser launch functions
4. `bin/garth` — wire up new dispatcher, env vars, and deprecated-env preflight
5. `tests/config_parser_smoke.sh` + `tests/browser_launch_smoke.sh` + `tests/cli_open_smoke.sh`
6. `README.md`, `AGENTS.md`, `CLAUDE.md`

## Verification

1. `python3 -m py_compile lib/config-parser.py` — syntax check
2. `bash -n bin/garth lib/*.sh` — shell syntax check
3. `bash tests/config_parser_smoke.sh` — config parser tests (updated)
4. `bash tests/browser_launch_smoke.sh` — new browser launch tests
5. `bash tests/cli_open_smoke.sh` — CLI integration tests (extended)
6. Manual: run `lib/config-parser.py env config.example.toml` and verify
   `GARTH_BROWSER_*` vars are emitted (no `GARTH_CHROME_*`)
7. Manual: run `lib/config-parser.py validate` against a config with `[chrome]`
   and verify it produces a clear error
8. Manual: test dry-run browser launch with different engine values
