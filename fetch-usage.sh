#!/bin/sh

# ── Configuration ──────────────────────────────────────────────────────────────
CACHE_DIR="${HOME}/.cache/claude/statusline"
CACHE_FILE="${CACHE_DIR}/usage.json"
LOCK_FILE="${CACHE_DIR}/usage.lock"
TOKEN_CACHE_FILE="${CACHE_DIR}/token.cache"
CACHE_MAX_AGE=180
LOCK_MAX_AGE=30
TOKEN_CACHE_MAX_AGE=3600
DEFAULT_RATE_LIMIT_BACKOFF=300
USAGE_API_HOST="api.anthropic.com"
USAGE_API_PATH="/api/oauth/usage"
USAGE_API_TIMEOUT=5

# ── Helpers ────────────────────────────────────────────────────────────────────
ensure_cache_dir() {
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
}

now() {
    date +%s
}

file_mtime() {
    file="$1"
    # POSIX-compatible: try GNU stat, then BSD stat, then fall back to 0
    stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0
}

# ── Token retrieval ────────────────────────────────────────────────────────────
get_usage_token() {
    now_ts=$(now)

    # Check token cache
    if [ -f "$TOKEN_CACHE_FILE" ]; then
        cache_age=$(( now_ts - $(file_mtime "$TOKEN_CACHE_FILE") ))
        if [ "$cache_age" -lt "$TOKEN_CACHE_MAX_AGE" ]; then
            cached=$(cat "$TOKEN_CACHE_FILE" 2>/dev/null)
            if [ -n "$cached" ]; then
                echo "$cached"
                return 0
            fi
        fi
    fi

    token=""

    # macOS keychain
    if command -v security > /dev/null 2>&1; then
        keychain_data=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || true
        if [ -n "$keychain_data" ]; then
            token=$(echo "$keychain_data" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null) || true
        fi
    fi

    # Fallback: credentials file
    if [ -z "$token" ]; then
        cred_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
        if [ -f "$cred_file" ]; then
            token=$(jq -r '.claudeAiOauth.accessToken // empty' "$cred_file" 2>/dev/null) || true
        fi
    fi

    if [ -z "$token" ] || [ "$token" = "null" ]; then
        return 1
    fi

    # Cache token
    ensure_cache_dir
    echo "$token" > "$TOKEN_CACHE_FILE" 2>/dev/null || true
    echo "$token"
}

# ── Lock file ──────────────────────────────────────────────────────────────────
read_active_lock() {
    now_ts=$(now)
    [ -f "$LOCK_FILE" ] || return 1

    lock_data=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$lock_data" ]; then
        blocked_until=$(echo "$lock_data" | jq -r '.blockedUntil // empty' 2>/dev/null) || true
        error=$(echo "$lock_data" | jq -r '.error // "timeout"' 2>/dev/null) || true
        if [ -n "$blocked_until" ]; then
            case "$blocked_until" in
                ''|*[!0-9]*) ;;
                *)
                    if [ "$blocked_until" -gt "$now_ts" ]; then
                        echo "${error}:${blocked_until}"
                        return 0
                    fi
                    return 1
                    ;;
            esac
        fi
    fi

    # mtime-based fallback
    lock_mtime=$(file_mtime "$LOCK_FILE")
    blocked_until=$(( lock_mtime + LOCK_MAX_AGE ))
    if [ "$blocked_until" -gt "$now_ts" ]; then
        echo "timeout:${blocked_until}"
        return 0
    fi
    return 1
}

write_lock() {
    blocked_until="$1"
    error="${2:-timeout}"
    ensure_cache_dir
    printf '{"blockedUntil":%s,"error":"%s"}' "$blocked_until" "$error" > "$LOCK_FILE" 2>/dev/null || true
}

# ── Cache ──────────────────────────────────────────────────────────────────────
read_stale_cache() {
    [ -f "$CACHE_FILE" ] || return 1
    cat "$CACHE_FILE" 2>/dev/null
}

create_error_response() {
    printf '{"error":"%s"}' "$1"
}

# ── Retry-After parsing ────────────────────────────────────────────────────────
parse_retry_after() {
    retry_after="$1"
    [ -z "$retry_after" ] && return 1
    case "$retry_after" in
        ''|*[!0-9]*)
            # Try as HTTP date via jq
            retry_at=$(echo "\"$retry_after\"" | jq -r 'try (fromdate - now | floor) catch empty' 2>/dev/null) || return 1
            [ -n "$retry_at" ] && [ "$retry_at" -gt 0 ] && echo "$retry_at" && return 0
            return 1
            ;;
        *)
            [ "$retry_after" -gt 0 ] && echo "$retry_after" && return 0
            return 1
            ;;
    esac
}

# ── API call ───────────────────────────────────────────────────────────────────
fetch_from_api() {
    token="$1"
    response_file=$(mktemp)
    headers_file=$(mktemp)

    http_code=$(curl -s -m "$USAGE_API_TIMEOUT" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -w "%{http_code}" \
        -o "$response_file" \
        -D "$headers_file" \
        "https://${USAGE_API_HOST}${USAGE_API_PATH}" 2>/dev/null) || http_code="000"

    result=""
    case "$http_code" in
        200)
            body=$(cat "$response_file" 2>/dev/null)
            [ -n "$body" ] && result="success:$body" || result="error"
            ;;
        429)
            retry_after=$(grep -i "^retry-after:" "$headers_file" 2>/dev/null | sed 's/^[Rr]etry-[Aa]fter: *//;s/\r//')
            retry_seconds=$(parse_retry_after "$retry_after") || retry_seconds=$DEFAULT_RATE_LIMIT_BACKOFF
            result="rate-limited:${retry_seconds}"
            ;;
        *)
            result="error"
            ;;
    esac

    rm -f "$response_file" "$headers_file"
    echo "$result"
}

# ── Response parsing ───────────────────────────────────────────────────────────
parse_api_response() {
    body="$1"
    jq -n --argjson data "$body" '{
        sessionUsage: $data.five_hour.utilization,
        sessionResetAt: $data.five_hour.resets_at,
        weeklyUsage: $data.seven_day.utilization,
        weeklyResetAt: $data.seven_day.resets_at
    }' 2>/dev/null
}

# ── Main ───────────────────────────────────────────────────────────────────────
fetch_usage_data() {
    now_ts=$(now)

    # Serve fresh cache
    if [ -f "$CACHE_FILE" ]; then
        cache_age=$(( now_ts - $(file_mtime "$CACHE_FILE") ))
        if [ "$cache_age" -lt "$CACHE_MAX_AGE" ]; then
            cached=$(cat "$CACHE_FILE" 2>/dev/null)
            if [ -n "$cached" ]; then
                has_error=$(echo "$cached" | jq -r '.error // empty' 2>/dev/null) || true
                [ -z "$has_error" ] && echo "$cached" && return 0
            fi
        fi
    fi

    # Get token
    token=$(get_usage_token) || token=""
    if [ -z "$token" ]; then
        stale=$(read_stale_cache 2>/dev/null) || stale=""
        if [ -n "$stale" ]; then
            has_error=$(echo "$stale" | jq -r '.error // empty' 2>/dev/null) || true
            [ -z "$has_error" ] && echo "$stale" && return 0
        fi
        create_error_response "no-credentials"
        return 1
    fi

    # Check lock
    if lock_info=$(read_active_lock 2>/dev/null); then
        stale=$(read_stale_cache 2>/dev/null) || stale=""
        if [ -n "$stale" ]; then
            has_error=$(echo "$stale" | jq -r '.error // empty' 2>/dev/null) || true
            [ -z "$has_error" ] && echo "$stale" && return 0
        fi
        create_error_response "${lock_info%%:*}"
        return 1
    fi

    # Set lock
    write_lock $(( now_ts + LOCK_MAX_AGE )) "timeout"

    # Fetch
    api_result=$(fetch_from_api "$token")
    result_type="${api_result%%:*}"
    result_value="${api_result#*:}"

    case "$result_type" in
        success)
            usage_data=$(parse_api_response "$result_value") || usage_data=""
            if [ -z "$usage_data" ]; then
                stale=$(read_stale_cache 2>/dev/null) || stale=""
                [ -n "$stale" ] && echo "$stale" && return 0
                create_error_response "parse-error"
                return 1
            fi
            ensure_cache_dir
            echo "$usage_data" > "$CACHE_FILE" 2>/dev/null || true
            echo "$usage_data"
            ;;
        rate-limited)
            write_lock $(( now_ts + result_value )) "rate-limited"
            stale=$(read_stale_cache 2>/dev/null) || stale=""
            if [ -n "$stale" ]; then
                has_error=$(echo "$stale" | jq -r '.error // empty' 2>/dev/null) || true
                [ -z "$has_error" ] && echo "$stale" && return 0
            fi
            create_error_response "rate-limited"
            return 1
            ;;
        *)
            stale=$(read_stale_cache 2>/dev/null) || stale=""
            if [ -n "$stale" ]; then
                has_error=$(echo "$stale" | jq -r '.error // empty' 2>/dev/null) || true
                [ -z "$has_error" ] && echo "$stale" && return 0
            fi
            create_error_response "api-error"
            return 1
            ;;
    esac
}

# Run if executed directly
case "$0" in
    */fetch-usage.sh|fetch-usage.sh) fetch_usage_data ;;
esac
