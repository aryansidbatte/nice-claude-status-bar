# Color Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 16 preset color themes to `context-bar.sh`, selectable via a `context-bar.conf` file in the same directory as the script.

**Architecture:** `context-bar.sh` sources `context-bar.conf` (if present) at startup to read a `THEME` variable, then calls a new `set_theme()` function that sets `C_TEAL` and `C_BLUE` ANSI codes. `SCRIPT_DIR` must move above the Colors section so the conf path is available when needed. `C_GRAY` remains hardcoded and is not part of `set_theme()`.

**Tech Stack:** POSIX sh, ANSI 256-color codes, ANSI 24-bit (truecolor) codes for Catppuccin Mocha and Gruvbox.

---

## File Map

| File | Change |
|---|---|
| `context-bar.sh` | Move `SCRIPT_DIR` above Colors section; add conf sourcing; add `set_theme()`; update Colors block |
| `tests/test.sh` | Add 4 new theme tests: amber, unknown-fallback, no-conf, catppuccin-mocha |
| `README.md` | Add "Themes" section after Installation |

---

## Task 1: Write failing theme tests

**Files:**
- Modify: `tests/test.sh`

- [ ] **Step 1: Add theme tests to the end of `tests/test.sh`, before the final `echo` and results block**

The tests write a temporary `context-bar.conf` into the scripts dir (repo root), run a colored segment, then delete it. They inspect raw ANSI output using `printf` to build the expected escape sequence for comparison.

Append these lines to `tests/test.sh`, immediately before the final `echo ""` line:

```sh
# ── Theme tests ────────────────────────────────────────────────────────────────
# Test: amber theme applies correct C_TEAL to colored output
echo "THEME=amber" > "$SCRIPTS/context-bar.conf"
amber_teal=$(printf '\033[38;5;130m')
actual=$(cat "$FIXTURES/stdin-full.json" | sh "$SCRIPTS/context-bar.sh" --color --test-segment model)
rm -f "$SCRIPTS/context-bar.conf"
case "$actual" in
    *"${amber_teal}"*) echo "PASS: theme: amber C_TEAL applied"; PASS=$((PASS+1)) ;;
    *) echo "FAIL: theme: amber C_TEAL applied"; echo "  Actual: [$actual]"; FAIL=$((FAIL+1)) ;;
esac

# Test: unknown theme name falls back to teal C_TEAL
echo "THEME=nonexistent" > "$SCRIPTS/context-bar.conf"
teal_teal=$(printf '\033[38;5;66m')
actual=$(cat "$FIXTURES/stdin-full.json" | sh "$SCRIPTS/context-bar.sh" --color --test-segment model)
rm -f "$SCRIPTS/context-bar.conf"
case "$actual" in
    *"${teal_teal}"*) echo "PASS: theme: unknown theme falls back to teal"; PASS=$((PASS+1)) ;;
    *) echo "FAIL: theme: unknown theme falls back to teal"; echo "  Actual: [$actual]"; FAIL=$((FAIL+1)) ;;
esac

# Test: no conf file uses teal (conf was deleted above — this runs without one)
actual=$(cat "$FIXTURES/stdin-full.json" | sh "$SCRIPTS/context-bar.sh" --color --test-segment model)
case "$actual" in
    *"${teal_teal}"*) echo "PASS: theme: no conf file defaults to teal"; PASS=$((PASS+1)) ;;
    *) echo "FAIL: theme: no conf file defaults to teal"; echo "  Actual: [$actual]"; FAIL=$((FAIL+1)) ;;
esac

# Test: catppuccin-mocha applies truecolor C_TEAL
echo "THEME=catppuccin-mocha" > "$SCRIPTS/context-bar.conf"
mocha_teal=$(printf '\033[38;2;203;166;247m')
actual=$(cat "$FIXTURES/stdin-full.json" | sh "$SCRIPTS/context-bar.sh" --color --test-segment model)
rm -f "$SCRIPTS/context-bar.conf"
case "$actual" in
    *"${mocha_teal}"*) echo "PASS: theme: catppuccin-mocha truecolor C_TEAL applied"; PASS=$((PASS+1)) ;;
    *) echo "FAIL: theme: catppuccin-mocha truecolor C_TEAL applied"; echo "  Actual: [$actual]"; FAIL=$((FAIL+1)) ;;
esac
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
sh tests/test.sh
```

Expected: the 4 new theme tests all FAIL (the feature doesn't exist yet). All pre-existing tests should still PASS.

---

## Task 2: Move SCRIPT_DIR above the Colors section

**Files:**
- Modify: `context-bar.sh`

Currently `SCRIPT_DIR` is assigned at line 35, inside the `# Helpers` block. The Colors section is at lines 19–29. The conf-sourcing line needs `SCRIPT_DIR`, so it must move up.

- [ ] **Step 1: Remove `SCRIPT_DIR` from the Helpers section**

In `context-bar.sh`, delete this line from the `# ── Helpers` section (currently line 35):

```sh
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
```

- [ ] **Step 2: Add `SCRIPT_DIR` and conf sourcing above the Colors section**

Insert the following block between the `# ── Args` block (ends at line 17) and the `# ── Colors` block (starts at line 19):

```sh
# ── Config ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
CONF_FILE="${SCRIPT_DIR}/context-bar.conf"
[ -f "$CONF_FILE" ] && . "$CONF_FILE" 2>/dev/null || true
```

- [ ] **Step 3: Run tests to confirm no regressions**

```bash
sh tests/test.sh
```

Expected: all pre-existing tests PASS. The 4 new theme tests still FAIL (set_theme doesn't exist yet).

---

## Task 3: Add `set_theme()` and update the Colors block

**Files:**
- Modify: `context-bar.sh`

- [ ] **Step 1: Add `set_theme()` immediately before the `# ── Colors` block**

Insert this function between the new `# ── Config` block and `# ── Colors`:

```sh
# ── Theme ──────────────────────────────────────────────────────────────────────
set_theme() {
    theme="${1:-teal}"
    case "$theme" in
        teal)             C_TEAL='\033[38;5;66m';  C_BLUE='\033[38;5;74m'  ;;
        amber)            C_TEAL='\033[38;5;130m'; C_BLUE='\033[38;5;178m' ;;
        rose)             C_TEAL='\033[38;5;132m'; C_BLUE='\033[38;5;211m' ;;
        green)            C_TEAL='\033[38;5;65m';  C_BLUE='\033[38;5;72m'  ;;
        purple)           C_TEAL='\033[38;5;98m';  C_BLUE='\033[38;5;141m' ;;
        mono)             C_TEAL='\033[38;5;250m'; C_BLUE='\033[38;5;255m' ;;
        red)              C_TEAL='\033[38;5;124m'; C_BLUE='\033[38;5;203m' ;;
        orange)           C_TEAL='\033[38;5;166m'; C_BLUE='\033[38;5;208m' ;;
        yellow)           C_TEAL='\033[38;5;100m'; C_BLUE='\033[38;5;184m' ;;
        cyan)             C_TEAL='\033[38;5;30m';  C_BLUE='\033[38;5;44m'  ;;
        blue)             C_TEAL='\033[38;5;25m';  C_BLUE='\033[38;5;69m'  ;;
        pink)             C_TEAL='\033[38;5;127m'; C_BLUE='\033[38;5;207m' ;;
        lavender)         C_TEAL='\033[38;5;103m'; C_BLUE='\033[38;5;147m' ;;
        mint)             C_TEAL='\033[38;5;29m';  C_BLUE='\033[38;5;79m'  ;;
        catppuccin-mocha) C_TEAL='\033[38;2;203;166;247m'; C_BLUE='\033[38;2;137;180;250m' ;;
        gruvbox)          C_TEAL='\033[38;2;254;128;25m';  C_BLUE='\033[38;2;250;189;47m'  ;;
        *)                C_TEAL='\033[38;5;66m';  C_BLUE='\033[38;5;74m'  ;;
    esac
}
```

- [ ] **Step 2: Update the Colors block**

Replace the current `# ── Colors` block:

```sh
# ── Colors ─────────────────────────────────────────────────────────────────────
RESET=''
C_TEAL=''
C_BLUE=''
C_GRAY=''
if [ "$USE_COLOR" = "1" ]; then
    RESET='\033[0m'
    C_TEAL='\033[38;5;66m'
    C_BLUE='\033[38;5;74m'
    C_GRAY='\033[38;5;245m'
fi
```

With:

```sh
# ── Colors ─────────────────────────────────────────────────────────────────────
RESET=''
C_TEAL=''
C_BLUE=''
C_GRAY=''
if [ "$USE_COLOR" = "1" ]; then
    RESET='\033[0m'
    C_GRAY='\033[38;5;245m'
    set_theme "${THEME:-teal}"
fi
```

- [ ] **Step 3: Run tests — all should now pass**

```bash
sh tests/test.sh
```

Expected: all tests PASS including the 4 new theme tests.

- [ ] **Step 4: Commit**

```bash
git add context-bar.sh tests/test.sh
git commit -m "feat: add 16 color themes via context-bar.conf"
```

---

## Task 4: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a Themes section after the Installation section**

Insert the following after the `---` that follows the Installation section (after line 47):

```markdown
## Themes

Set a color theme by creating `~/.claude/scripts/context-bar.conf`:

```sh
THEME=catppuccin-mocha
```

Available themes:

| Theme | Style |
|---|---|
| `teal` | Default — teal symbols, blue values |
| `amber` | Warm gold |
| `rose` | Soft rose/pink |
| `green` | Forest green |
| `purple` | Muted purple |
| `mono` | Near-white monochrome |
| `red` | Red |
| `orange` | True orange |
| `yellow` | Golden yellow |
| `cyan` | Bright cyan |
| `blue` | Cool blue |
| `pink` | Vivid pink |
| `lavender` | Soft lavender |
| `mint` | Mint green |
| `catppuccin-mocha` | Catppuccin Mocha (mauve + blue, truecolor) |
| `gruvbox` | Gruvbox (orange + yellow, truecolor) |

If the file is absent or the theme name is unrecognized, `teal` is used. Labels and separators (`of`, `5hr`, `weekly`, `|`, `·`) are always gray regardless of theme.

---
```

- [ ] **Step 2: Run tests to confirm nothing broke**

```bash
sh tests/test.sh
```

Expected: all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add Themes section to README"
```
