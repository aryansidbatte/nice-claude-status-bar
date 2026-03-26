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

# ── Config ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
CONF_FILE="${SCRIPT_DIR}/context-bar.conf"
if [ -f "$CONF_FILE" ]; then . "$CONF_FILE" 2>/dev/null; fi

# ── Theme ──────────────────────────────────────────────────────────────────────
set_theme() {
    case "${1:-teal}" in
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

# ── Stdin ──────────────────────────────────────────────────────────────────────
INPUT=$(cat)

# ── Helpers ────────────────────────────────────────────────────────────────────
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
    # Normalize timestamp: strip fractional seconds and convert +00:00 to Z
    duration=$(jq -n --arg ts "$first_ts" '
        ($ts | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | try fromdate catch null) as $start |
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

# ── Segment: Subscription Usage ───────────────────────────────────────────────
segment_subscription() {
    # Allow test override via env var
    if [ -n "$FETCH_USAGE_OVERRIDE" ]; then
        usage_data="$FETCH_USAGE_OVERRIDE"
    elif [ -x "$FETCH_USAGE" ]; then
        usage_data=$("$FETCH_USAGE" 2>/dev/null) || usage_data=""
    else
        return
    fi

    [ -z "$usage_data" ] && return

    has_error=$(echo "$usage_data" | jq -r '.error // empty' 2>/dev/null) || has_error="error"
    [ -n "$has_error" ] && return

    # Parse fields
    session_pct=$(echo "$usage_data" | jq -r '.sessionUsage // empty | if . then floor | tostring else empty end' 2>/dev/null) || session_pct=""
    session_reset=$(echo "$usage_data" | jq -r '.sessionResetAt // empty' 2>/dev/null) || session_reset=""
    weekly_pct=$(echo "$usage_data" | jq -r '.weeklyUsage // empty | if . then floor | tostring else empty end' 2>/dev/null) || weekly_pct=""
    weekly_reset=$(echo "$usage_data" | jq -r '.weeklyResetAt // empty' 2>/dev/null) || weekly_reset=""

    [ -z "$session_pct" ] && return

    # Session reset countdown
    countdown=""
    if [ -n "$session_reset" ]; then
        diff=$(jq -rn --arg ts "$session_reset" '
            $ts | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") |
            try (fromdate - now | floor) catch empty
        ' 2>/dev/null) || diff=""
        if [ -n "$diff" ]; then
            if [ "$diff" -le 0 ] && [ "$diff" -gt -300 ]; then
                countdown="resetting"
            elif [ "$diff" -le -300 ]; then
                countdown=""
            elif [ "$diff" -ge 3600 ]; then
                h=$(( diff / 3600 ))
                m=$(( (diff % 3600) / 60 ))
                countdown="${h}h ${m}m"
            else
                m=$(( diff / 60 ))
                countdown="${m}m"
            fi
        fi
    fi

    # 5hr segment
    if [ -n "$countdown" ]; then
        line3="${C_TEAL}⚡${RESET}${C_BLUE}${session_pct}%${RESET}${C_GRAY} 5hr (${countdown})${RESET}"
    else
        line3="${C_TEAL}⚡${RESET}${C_BLUE}${session_pct}%${RESET}${C_GRAY} 5hr${RESET}"
    fi

    # Weekly + pacing
    if [ -n "$weekly_pct" ]; then
        line3="${line3}${C_GRAY}  ·  ${RESET}${C_TEAL}⟳${RESET} ${C_BLUE}${weekly_pct}%${RESET}${C_GRAY} weekly${RESET}"

        # Pacing
        if [ -n "$weekly_reset" ]; then
            pacing=$(jq -rn --arg ts "$weekly_reset" --argjson wpct "$weekly_pct" '
                ($ts | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | try fromdate catch null) as $reset_epoch |
                if $reset_epoch == null then empty
                elif $reset_epoch <= now then empty
                else
                    (($reset_epoch - now) / 86400) as $days |
                    (if $days < 0.1 then 0.1 else $days end) as $days |
                    ((100 - $wpct) / $days * 10 | round) / 10 |
                    tostring + "%"
                end
            ' 2>/dev/null) || pacing=""
            [ -n "$pacing" ] && line3="${line3}${C_GRAY}  ·  ${RESET}${C_TEAL}→${RESET} ${C_BLUE}${pacing}${RESET}${C_GRAY}/day${RESET}"
        fi
    fi

    printf '%b' "$line3"
}

# ── Line assembly ──────────────────────────────────────────────────────────────
assemble_output() {
    SEP="${C_GRAY}  |  ${RESET}"

    # Line 1: model | git | duration
    line1=""
    seg=$(segment_model); [ -n "$seg" ] && line1="$seg"
    seg=$(segment_git);   [ -n "$seg" ] && { [ -n "$line1" ] && line1="${line1}${SEP}${seg}" || line1="$seg"; }
    seg=$(segment_duration); [ -n "$seg" ] && { [ -n "$line1" ] && line1="${line1}${SEP}${seg}" || line1="$seg"; }

    # Line 2: context | cost
    line2=""
    seg=$(segment_context); [ -n "$seg" ] && line2="$seg"
    seg=$(segment_cost);    [ -n "$seg" ] && { [ -n "$line2" ] && line2="${line2}${SEP}${seg}" || line2="$seg"; }

    # Line 3: subscription
    line3=$(segment_subscription)

    # Print non-empty lines
    out=""
    [ -n "$line1" ] && out="$line1"
    if [ -n "$line2" ]; then
        [ -n "$out" ] && out="${out}
${line2}" || out="$line2"
    fi
    if [ -n "$line3" ]; then
        [ -n "$out" ] && out="${out}
${line3}" || out="$line3"
    fi

    printf '%b' "$out"
}

# ── Entry point ────────────────────────────────────────────────────────────────
if [ -n "$TEST_SEGMENT" ]; then
    "segment_${TEST_SEGMENT}"
    exit 0
fi

assemble_output
