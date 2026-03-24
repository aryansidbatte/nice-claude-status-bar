#!/bin/sh

# ── Args ───────────────────────────────────────────────────────────────────────
USE_COLOR=0
TEST_SEGMENT=""
TEST_SEGMENT_NEXT=0
for arg in "$@"; do
    if [ "$TEST_SEGMENT_NEXT" = "1" ]; then
        TEST_SEGMENT="$arg"
        TEST_SEGMENT_NEXT=0
    else
        case "$arg" in
            --color) USE_COLOR=1 ;;
            --test-segment) TEST_SEGMENT_NEXT=1 ;;
        esac
    fi
done

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

# ── Stdin ──────────────────────────────────────────────────────────────────────
INPUT=$(cat)

# ── Helpers ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
FETCH_USAGE="${SCRIPT_DIR}/fetch-usage.sh"

slug_from_cwd() {
    printf '%s' "$1" | tr '/' '-'
}

find_session_jsonl() {
    cwd="$1"
    slug=$(slug_from_cwd "$cwd")
    dir="${HOME}/.claude/projects/${slug}"
    [ -d "$dir" ] || return 1
    latest=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
    [ -n "$latest" ] && echo "$latest"
}

# ── Segment: Model ─────────────────────────────────────────────────────────────
segment_model() {
    display=$(echo "$INPUT" | jq -r '.model.display_name // empty' 2>/dev/null) || display=""

    if [ -n "$display" ]; then
        model="${display#Claude }"
    else
        model_id=$(echo "$INPUT" | jq -r '.model.id // empty' 2>/dev/null) || model_id=""
        if [ -z "$model_id" ] || [ "$model_id" = "null" ]; then
            return
        fi
        model=$(echo "$model_id" | jq -Rr '
            ltrimstr("claude-") |
            split("-") |
            .[0] |= (.[0:1] | ascii_upcase) + .[1:] |
            .[0] + " " + (.[1:] | join("."))
        ' 2>/dev/null) || return
    fi

    [ -z "$model" ] && return
    printf '%b%s%b %b%s%b' "$C_TEAL" "◆" "$RESET" "$C_BLUE" "$model" "$RESET"
}

# ── Segment: Git ───────────────────────────────────────────────────────────────
segment_git() {
    cwd=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
    [ -z "$cwd" ] && return
    command -v git > /dev/null 2>&1 || return

    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null) || return
    [ -z "$branch" ] && return

    # Ahead/behind (silently skip if no upstream)
    ahead_behind=$(git -C "$cwd" rev-list --count --left-right "@{upstream}...HEAD" 2>/dev/null) || ahead_behind=""
    behind=0
    ahead=0
    if [ -n "$ahead_behind" ]; then
        behind=$(echo "$ahead_behind" | cut -f1)
        ahead=$(echo "$ahead_behind" | cut -f2)
    fi

    # Dirty check
    dirty=$(git -C "$cwd" status --porcelain 2>/dev/null) || dirty=""

    # Assemble branch display
    display="$branch"
    [ "$ahead" -gt 0 ] 2>/dev/null && display="${display} ↑${ahead}"
    [ "$behind" -gt 0 ] 2>/dev/null && display="${display} ↓${behind}"
    [ -n "$dirty" ] && display="${display} ●"

    printf '%b%s%b  %b%s%b' "$C_TEAL" "⎇" "$RESET" "$C_BLUE" "$display" "$RESET"
}

# ── Test harness dispatch ──────────────────────────────────────────────────────
if [ -n "$TEST_SEGMENT" ]; then
    "segment_${TEST_SEGMENT}"
    exit 0
fi
