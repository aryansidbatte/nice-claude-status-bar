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

# ── Segment: Session Duration ──────────────────────────────────────────────────
segment_duration() {
    cwd=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
    [ -z "$cwd" ] && return

    jsonl=$(find_session_jsonl "$cwd") || return
    [ -z "$jsonl" ] && return

    # First timestamp in the file
    first_ts=$(head -1 "$jsonl" 2>/dev/null | jq -r '.timestamp // empty' 2>/dev/null) || return
    [ -z "$first_ts" ] && return

    # Compute duration in seconds using jq fromdate
    duration=$(jq -n --arg ts "$first_ts" '
        ($ts | try fromdate catch null) as $start |
        if $start == null then empty
        else (now - $start | floor)
        end
    ' 2>/dev/null) || return
    [ -z "$duration" ] && return

    hours=$(( duration / 3600 ))
    mins=$(( (duration % 3600) / 60 ))

    if [ "$hours" -gt 0 ]; then
        formatted="${hours}h ${mins}m"
    else
        formatted="${mins}m"
    fi

    printf '%b%s%b %b%s%b' "$C_TEAL" "⧗" "$RESET" "$C_BLUE" "$formatted" "$RESET"
}

# ── Segment: Context Window ────────────────────────────────────────────────────
segment_context() {
    result=$(echo "$INPUT" | jq -r '
        (.context_window.context_window_size // 200000) as $size |
        (if $size == 0 then 200000 else $size end) as $size |
        ((.context_window.current_usage.input_tokens // 0) +
         (.context_window.current_usage.cache_creation_input_tokens // 0) +
         (.context_window.current_usage.cache_read_input_tokens // 0)) as $used |
        ($used * 100 / $size | floor) as $pct |
        ($size / 1000 | floor | tostring + "k") as $k |
        ($pct | tostring) + "% of " + $k
    ' 2>/dev/null) || return
    [ -z "$result" ] && return

    # Split for coloring: "42%" is blue, "of 200k" is gray
    pct_part="${result%% *}"
    rest_part="${result#* }"
    printf '%b%s%b %b%s%b %b%s%b' \
        "$C_TEAL" "▸" "$RESET" \
        "$C_BLUE" "$pct_part" "$RESET" \
        "$C_GRAY" "$rest_part" "$RESET"
}

# ── Segment: Session Cost ──────────────────────────────────────────────────────
segment_cost() {
    cwd=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
    [ -z "$cwd" ] && return

    jsonl=$(find_session_jsonl "$cwd") || return
    [ -z "$jsonl" ] && return

    cost=$(jq -rs '
        map(select(.type == "assistant" and
                    .message.usage != null and
                    (.message.usage.output_tokens // 0) > 0)) |
        map(
            (.message.model // "") as $model |
            (if ($model | test("opus-4"))   then {i:15,   cw:18.75, cr:1.5,  o:75}
             elif ($model | test("haiku-4")) then {i:0.8,  cw:1,     cr:0.08, o:4}
             else                                {i:3,    cw:3.75,  cr:0.3,  o:15}
             end) as $r |
            (.message.usage.input_tokens // 0)                  * $r.i  / 1000000 +
            (.message.usage.cache_creation_input_tokens // 0)   * $r.cw / 1000000 +
            (.message.usage.cache_read_input_tokens // 0)       * $r.cr / 1000000 +
            (.message.usage.output_tokens // 0)                 * $r.o  / 1000000
        ) |
        add // 0
    ' "$jsonl" 2>/dev/null) || return

    # Skip if raw cost is zero
    is_zero=$(echo "$cost" | jq '. == 0' 2>/dev/null) || is_zero="true"
    [ "$is_zero" = "true" ] && return

    # Format to exactly 3 decimal places
    formatted=$(echo "$cost" | jq -r '
        . * 1000 | round as $m |
        ($m / 1000 | tostring) as $s |
        "~$" + if ($s | test("\\.")) then
            $s + "0" * (3 - ($s | split(".")[1] | length))
        else
            $s + ".000"
        end
    ' 2>/dev/null) || return
    [ -z "$formatted" ] && return

    printf '%b%s%b %b%s%b' "$C_TEAL" "⊛" "$RESET" "$C_BLUE" "$formatted" "$RESET"
}

# ── Test harness dispatch ──────────────────────────────────────────────────────
if [ -n "$TEST_SEGMENT" ]; then
    "segment_${TEST_SEGMENT}"
    exit 0
fi
