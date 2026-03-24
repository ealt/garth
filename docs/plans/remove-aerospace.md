# Plan: Remove AeroSpace from Garth

## Context

AeroSpace is a macOS tiling window manager that Garth optionally integrates with
to move windows to numbered virtual desktops when launching sessions. The user
wants to remove this integration entirely. The feature is cleanly separated from
other GUI integrations (Cursor, Chrome) so removal is straightforward.

## Changes

### 1. Delete `templates/aerospace.example.toml` and `templates/` directory

Only file in the directory. Remove both.

### 2. `lib/workspace.sh` — remove AeroSpace functions (lines 346-447)

- **Line 1**: Update header comment from `(Cursor, Chrome profile, AeroSpace workspace)` to `(Cursor, Chrome profile)`
- **Delete lines 346-447**: Remove all 5 functions:
  - `garth_aerospace_list_workspaces()`
  - `garth_aerospace_is_ready()`
  - `garth_aerospace_ensure_running()`
  - `garth_aerospace_next_workspace()`
  - `garth_move_windows_to_workspace()`

### 3. `lib/config-parser.py` — remove `workspace` config key entirely

**Breaking change** (intentional — new major version): Users with
`workspace = "auto"` in their `config.toml` will see an "Unknown key:
defaults.workspace" warning after upgrading. They must delete the key.

- **Line 43**: Remove `"workspace"` from `ALLOWED_DEFAULTS`
- **Line 149**: Remove `"workspace": defaults_raw.get("workspace", "auto"),`
- **Lines 169-170**: Remove validation block for `defaults["workspace"]`
- **Line 480**: Remove `put("GARTH_DEFAULTS_WORKSPACE", defaults["workspace"])`

### 4. `config.example.toml` — remove default

- **Line 5**: Remove `workspace = "auto"`

### 5. `bin/garth` — 6 areas to modify

**A. `garth_launch_workspace()` function:**
- **Line 506**: Remove `local workspace=""` declaration
- **Lines 536-539**: Remove `--workspace)` case from arg parser
- **Line 582**: Remove `--workspace <N|auto>` from help text
- **Line 612**: Remove `workspace="${workspace:-$GARTH_DEFAULTS_WORKSPACE}"`
- **Line 826**: Change log from `"skipping workspace/Cursor/Chrome launch steps"` to `"skipping Cursor/Chrome launch steps"`
- **Line 828**: Remove `garth_move_windows_to_workspace "$workspace"`

**B. `cmd_new()` — line 1068:**
- Remove `--workspace` from forwarded-flags case pattern
- **Line 1098**: Remove `--workspace <N|auto>    AeroSpace workspace` from help

**C. `cmd_open()` — line 1218:**
- Remove `--workspace` from forwarded-flags case pattern
- **Line 1256**: Remove `--workspace <N|auto>    AeroSpace workspace` from help

**D. `cmd_up()` — line 1499:**
- Remove `--workspace` from forwarded-flags case pattern
- **Line 1549**: Remove `--workspace <N|auto>    AeroSpace workspace` from help

**E. `garth_setup_aerospace()` — lines 2818-2847:**
- Delete the entire function
- **Line 3120**: Remove `garth_setup_aerospace "$non_interactive"` call

**F. `cmd_doctor()` — lines 3438-3440:**
- Remove `if garth_is_macos; then optional_cmds+=(aerospace) fi`

### 6. `README.md` — remove AeroSpace references

- **Line 130**: Remove AeroSpace workspace integration bullet
- **Line 141**: Remove `templates/` line from directory tree
- **Line 169**: Remove `aerospace` from optional deps list
- **Lines 182-183**: Remove "AeroSpace workspace placement" from description
- **Line 205**: Remove aerospace Homebrew install bullet from setup description
- **Line 227**: Change `skip workspace move + Cursor + Chrome` to `skip Cursor + Chrome`
- **Lines 433-438**: Remove `--workspace` option and workspace note block
- **Line 539**: Remove AeroSpace troubleshooting entry

### 7. `AGENTS.md` — remove AeroSpace references

- **Line 243**: Remove "AeroSpace workspace management" from description
- **Lines 252-253**: Remove aerospace function names from key functions list
- **Lines 498-499**: Remove `templates/` and `aerospace.example.toml` from directory tree

### 8. `docs/plans/garth-plan.md` — clean up planning doc

- **Line 22**: Remove AeroSpace workspace switching bullet
- **Line 37**: Update workspace.sh description
- **Line 48**: Remove aerospace template from tree
- **Line 76**: Remove `--workspace N` from flags
- **Line 104**: Remove aerospace install reference
- **Lines 299-315**: Remove entire "AeroSpace Config" section
- **Lines 351-364**: Remove aerospace from phase references
- **Line 385**: Remove AeroSpace prerequisite

### 9. `docs/plans/ux-documentation-plan.md` — clean up

- **Lines 40, 79, 134**: Remove `--workspace` from help text reproductions

## Files modified (in order)

1. `templates/aerospace.example.toml` — **DELETE**
2. `templates/` — **DELETE** directory
3. `lib/workspace.sh` — remove 5 functions + update header
4. `lib/config-parser.py` — remove `workspace` from schema entirely (4 lines)
5. `config.example.toml` — remove 1 line
6. `bin/garth` — 6 areas, ~20 lines removed
7. `README.md` — ~10 lines removed/edited
8. `AGENTS.md` — 3 areas updated
9. `docs/plans/garth-plan.md` — multiple references removed
10. `docs/plans/ux-documentation-plan.md` — 3 lines removed

## Test changes — `tests/config_parser_smoke.sh`

The existing smoke test exercises `config.example.toml` through both `validate`
(line 7) and `env` (line 8) modes. Since we're removing `workspace` from the
config schema and env emission, we need:

1. **Negative assertion**: After the existing `env` output capture, assert that
   `GARTH_DEFAULTS_WORKSPACE` does NOT appear in `$ENV_OUT`
2. **Existing assertions pass**: No current assertion checks
   `GARTH_DEFAULTS_WORKSPACE`, so removing it from the config + parser won't
   break existing tests — but the negative assertion confirms the removal

## Verification

1. `bash -n bin/garth lib/*.sh` — syntax check all shell files
2. `python3 -m py_compile lib/config-parser.py` — verify config parser compiles
3. `bash tests/config_parser_smoke.sh` — run config parser tests (including new assertions)
4. Run all smoke tests from CLAUDE.md quick commands
5. Grep for any remaining `aerospace` or `WORKSPACE` references to confirm clean removal
