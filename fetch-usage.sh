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
