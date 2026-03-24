# Color Themes — Design Spec
_2026-03-24_

## Overview

Add preset color theme support to `context-bar.sh`. Users set a theme via a config file; the script reads it at startup and applies the corresponding ANSI color codes. No changes to `settings.json` or the installation procedure are required.

---

## Config File

**Path:** Same directory as the installed script — `context-bar.conf` next to `context-bar.sh`.
For the standard install location this resolves to `~/.claude/scripts/context-bar.conf`.

**Format:**
```sh
THEME=catppuccin-mocha
```

- The script dot-sources this file (`. "$CONF_FILE"`) if it exists, using POSIX `.` (not `source`)
- Dot-sourcing executes the entire file as shell code. The config file is a trusted local file written by the user; no sanitization is performed. Users should keep it to a single `THEME=` line. Any other variable assignments in the file will take effect in the script's environment — in particular, do not put `USE_COLOR=`, `RESET=`, or other script-internal variables in the config file.
- `THEME` is treated as a reserved variable name in the script's environment. Do not rely on `THEME` being unset after startup.
- If the file is absent, `THEME` is unset, or the theme name is unrecognized, the script falls back to `teal` (current default behavior — fully backwards compatible)
- If the file has a shell syntax error, the dot-source will fail silently (the shell's error handling suppresses it); `THEME` will be unset and the script falls back to `teal`

---

## Theme System

Each theme defines three color roles, matching the existing variable names in `context-bar.sh`:

| Variable | Role | Examples |
|---|---|---|
| `C_TEAL` | Symbols (`◆ ⎇ ▸ ⊛ ⚡ ⟳ → ⧗`) | Darker, more muted tone |
| `C_BLUE` | Values (model name, numbers, cost) | Brighter, more prominent tone |
| `C_GRAY` | Labels (`of`, `5hr`, `weekly`, separators) | Always a neutral gray — unchanged across all themes |

`C_GRAY` is fixed at `\033[38;5;245m` for all themes and is assigned directly in the startup block, not inside `set_theme()`. Only `C_TEAL` and `C_BLUE` vary per theme.

---

## Bundled Themes

### Basic

| Theme name | C_TEAL (symbols) | C_BLUE (values) |
|---|---|---|
| `teal` | `\033[38;5;66m` | `\033[38;5;74m` |
| `amber` | `\033[38;5;130m` | `\033[38;5;178m` |
| `rose` | `\033[38;5;132m` | `\033[38;5;211m` |
| `green` | `\033[38;5;65m` | `\033[38;5;72m` |
| `purple` | `\033[38;5;98m` | `\033[38;5;141m` |
| `mono` | `\033[38;5;250m` | `\033[38;5;255m` |
| `red` | `\033[38;5;124m` | `\033[38;5;203m` |
| `orange` | `\033[38;5;166m` | `\033[38;5;208m` |
| `yellow` | `\033[38;5;100m` | `\033[38;5;184m` |
| `cyan` | `\033[38;5;30m` | `\033[38;5;44m` |
| `blue` | `\033[38;5;25m` | `\033[38;5;69m` |
| `pink` | `\033[38;5;127m` | `\033[38;5;207m` |
| `lavender` | `\033[38;5;103m` | `\033[38;5;147m` |
| `mint` | `\033[38;5;29m` | `\033[38;5;79m` |

Note: `amber` (130, dark brownish-gold) and `orange` (166, true orange) are intentionally distinct — amber has a warmer, darker symbol tone while orange is brighter and more saturated.

### Special

| Theme name | C_TEAL (symbols) | C_BLUE (values) |
|---|---|---|
| `catppuccin-mocha` | `\033[38;2;203;166;247m` (Mauve #cba6f7) | `\033[38;2;137;180;250m` (Blue #89b4fa) |
| `gruvbox` | `\033[38;2;254;128;25m` (Orange #fe8019) | `\033[38;2;250;189;47m` (Yellow #fabd2f) |

Note: Catppuccin Mocha and Gruvbox use 24-bit (truecolor) ANSI codes (`\033[38;2;R;G;Bm`) to match their exact palette colors. All other themes use 256-color codes. Both are widely supported in modern terminals.

---

## Implementation

### `set_theme()` function in `context-bar.sh`

A new `set_theme()` function replaces the current hardcoded color assignments. It must be defined **before** the color initialization block — place it immediately above the Colors section. Note that `SCRIPT_DIR` must also be moved above the Colors section, since the config-sourcing line depends on it (currently `SCRIPT_DIR` is assigned in the Helpers section which comes after Colors). It is called once during startup, only when `USE_COLOR=1`.

```sh
set_theme() {
    theme="${1:-teal}"
    case "$theme" in
        teal)              C_TEAL='\033[38;5;66m';  C_BLUE='\033[38;5;74m'  ;;
        amber)             C_TEAL='\033[38;5;130m'; C_BLUE='\033[38;5;178m' ;;
        rose)              C_TEAL='\033[38;5;132m'; C_BLUE='\033[38;5;211m' ;;
        green)             C_TEAL='\033[38;5;65m';  C_BLUE='\033[38;5;72m'  ;;
        purple)            C_TEAL='\033[38;5;98m';  C_BLUE='\033[38;5;141m' ;;
        mono)              C_TEAL='\033[38;5;250m'; C_BLUE='\033[38;5;255m' ;;
        red)               C_TEAL='\033[38;5;124m'; C_BLUE='\033[38;5;203m' ;;
        orange)            C_TEAL='\033[38;5;166m'; C_BLUE='\033[38;5;208m' ;;
        yellow)            C_TEAL='\033[38;5;100m'; C_BLUE='\033[38;5;184m' ;;
        cyan)              C_TEAL='\033[38;5;30m';  C_BLUE='\033[38;5;44m'  ;;
        blue)              C_TEAL='\033[38;5;25m';  C_BLUE='\033[38;5;69m'  ;;
        pink)              C_TEAL='\033[38;5;127m'; C_BLUE='\033[38;5;207m' ;;
        lavender)          C_TEAL='\033[38;5;103m'; C_BLUE='\033[38;5;147m' ;;
        mint)              C_TEAL='\033[38;5;29m';  C_BLUE='\033[38;5;79m'  ;;
        catppuccin-mocha)  C_TEAL='\033[38;2;203;166;247m'; C_BLUE='\033[38;2;137;180;250m' ;;
        gruvbox)           C_TEAL='\033[38;2;254;128;25m';  C_BLUE='\033[38;2;250;189;47m'  ;;
        *)                 C_TEAL='\033[38;5;66m';  C_BLUE='\033[38;5;74m'  ;;  # fallback to teal
    esac
}
```

### Startup sequence change

The config file is sourced unconditionally (before the color block executes) so `THEME` is available when `set_theme` is called. `set_theme` is only called when `USE_COLOR=1` — if colors are disabled, the function is never invoked and all color variables remain empty strings (existing behavior unchanged).

Current:
```sh
if [ "$USE_COLOR" = "1" ]; then
    RESET='\033[0m'
    C_TEAL='\033[38;5;66m'
    C_BLUE='\033[38;5;74m'
    C_GRAY='\033[38;5;245m'
fi
```

New (config sourcing goes after `SCRIPT_DIR` is set, before the color block):
```sh
CONF_FILE="${SCRIPT_DIR}/context-bar.conf"
[ -f "$CONF_FILE" ] && . "$CONF_FILE" 2>/dev/null || true

if [ "$USE_COLOR" = "1" ]; then
    RESET='\033[0m'
    C_GRAY='\033[38;5;245m'   # fixed across all themes
    set_theme "${THEME:-teal}"
fi
```

The `2>/dev/null || true` on the source line suppresses errors from malformed config files and ensures the script always continues.

---

## Files Changed

- `context-bar.sh` — add `set_theme()` in Helpers section; update startup block to source config and call `set_theme`
- `README.md` — add "Themes" section with: the config file path, the format (`THEME=name`), and a list of all 16 valid theme names

## Files Added

- None. The config file (`context-bar.conf`) is created by the user, not shipped.

---

## Non-Goals

- No interactive theme picker / setup script
- No per-segment color overrides
- No light-terminal themes (background color not controllable via ANSI)
- No runtime theme switching (requires restarting Claude Code)
