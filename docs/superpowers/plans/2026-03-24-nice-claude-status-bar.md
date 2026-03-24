# nice-claude-status-bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two POSIX shell scripts that display a three-line Claude Code status bar showing model, git branch, session duration, context usage, cost, and subscription quota.

**Architecture:** `fetch-usage.sh` is a standalone subprocess that fetches and caches subscription quota data from the Anthropic OAuth API. `context-bar.sh` reads Claude Code's stdin JSON, calls `fetch-usage.sh`, parses the current session JSONL, and assembles up to three lines of output. Each segment is a shell function for testability.

**Tech Stack:** POSIX sh, jq 1.6+, curl, git (optional)

---

## File Map

| File | Role |
|---|---|
| `fetch-usage.sh` | OAuth token retrieval, API call, file cache, lock file |
| `context-bar.sh` | Stdin parsing, segment functions, line assembly, color |
| `tests/test.sh` | Test runner — pipes fixtures, asserts stdout |
| `tests/fixtures/stdin-full.json` | Full Claude Code stdin blob |
| `tests/fixtures/stdin-minimal.json` | Stdin with null/missing optional fields |
| `tests/fixtures/session.jsonl` | Sample JSONL with realistic usage data |
| `tests/fixtures/usage-response.json` | Mock fetch-usage.sh output |
| `README.md` | Setup, settings.json snippet, extension guide |
| `.gitignore` | Ignore OS files and cache dir |

---

## Task 1: Repo skeleton + test fixtures

**Files:**
- Create: `.gitignore`
- Create: `tests/test.sh`
- Create: `tests/fixtures/stdin-full.json`
- Create: `tests/fixtures/stdin-minimal.json`
- Create: `tests/fixtures/session.jsonl`
- Create: `tests/fixtures/usage-response.json`

- [ ] **Step 1: Create .gitignore**

```
.DS_Store
*.swp
~/.cache/claude/
```

Save to `.gitignore`.

- [ ] **Step 2: Create stdin-full.json fixture**

```json
{
  "model": {
    "id": "claude-sonnet-4-6",
    "display_name": "Claude Sonnet 4.6"
  },
  "cwd": "/Users/testuser/myproject",
  "context_window": {
    "context_window_size": 200000,
    "current_usage": {
      "input_tokens": 12000,
      "cache_creation_input_tokens": 50000,
      "cache_read_input_tokens": 22000
    }
  }
}
```

Save to `tests/fixtures/stdin-full.json`.

- [ ] **Step 3: Create stdin-minimal.json fixture**

```json
{
  "model": {
    "id": "claude-sonnet-4-6",
    "display_name": null
  },
  "cwd": "/Users/testuser/myproject",
  "context_window": {
    "context_window_size": null,
    "current_usage": null
  }
}
```

Save to `tests/fixtures/stdin-minimal.json`.

- [ ] **Step 4: Create session.jsonl fixture**

Each line is a JSON object. These represent two assistant turns (second entry in each pair has output_tokens=0, first has actual value — matching the deduplication rule).

```jsonl
{"type":"assistant","timestamp":"2026-03-24T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":500,"cache_creation_input_tokens":2000,"cache_read_input_tokens":0,"output_tokens":150}}}
{"type":"assistant","timestamp":"2026-03-24T10:00:00.100Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":500,"cache_creation_input_tokens":2000,"cache_read_input_tokens":0,"output_tokens":0}}}
{"type":"assistant","timestamp":"2026-03-24T10:05:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":600,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":200}}}
{"type":"assistant","timestamp":"2026-03-24T10:05:00.100Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":600,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":0}}}
```

Save to `tests/fixtures/session.jsonl`.

Expected cost from this fixture (sonnet-4 rates):
- Turn 1: (500 * 3 + 2000 * 3.75 + 0 * 0.30 + 150 * 15) / 1000000
  = (1500 + 7500 + 0 + 2250) / 1000000 = 11250 / 1000000 = $0.01125
- Turn 2: (600 * 3 + 0 * 3.75 + 8000 * 0.30 + 200 * 15) / 1000000
  = (1800 + 0 + 2400 + 3000) / 1000000 = 7200 / 1000000 = $0.0072
- Total: $0.01125 + $0.0072 = $0.01845 → formatted as `~$0.018`

- [ ] **Step 5: Create usage-response.json fixture**

```json
{
  "sessionUsage": 61,
  "sessionResetAt": "2026-03-24T15:00:00Z",
  "weeklyUsage": 38,
  "weeklyResetAt": "2026-03-28T00:00:00Z"
}
```

Save to `tests/fixtures/usage-response.json`.

- [ ] **Step 6: Create test runner skeleton**

```sh
#!/bin/sh
set -e

FIXTURES="$(dirname "$0")/fixtures"
SCRIPTS="$(dirname "$0")/.."
PASS=0
FAIL=0

assert_eq() {
    label="$1"
    expected="$2"
    actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  Expected: [$expected]"
        echo "  Actual:   [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

# Tests added in subsequent tasks

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

Save to `tests/test.sh` and make executable: `chmod +x tests/test.sh`.

- [ ] **Step 7: Run test runner to verify it works**

```bash
cd /path/to/nice-claude-status-bar && sh tests/test.sh
```

Expected output:
```
Results: 0 passed, 0 failed
```

(No tests yet — just verifying the harness runs without error.)

- [ ] **Step 8: Initial commit**

```bash
git init
git add .gitignore tests/
git commit -m "chore: repo skeleton with test fixtures and harness"
```

---

## Task 2: fetch-usage.sh — token retrieval

**Files:**
- Create: `fetch-usage.sh`

- [ ] **Step 1: Write failing test for token retrieval**

Add to `tests/test.sh`:

```sh
# Task 2: token retrieval — test that get_usage_token exits non-zero when no credentials exist
actual=$(HOME=/nonexistent CLAUDE_CONFIG_DIR=/nonexistent sh -c '. '"$SCRIPTS"'/fetch-usage.sh; get_usage_token' 2>/dev/null; echo $?)
assert_eq "get_usage_token: returns non-zero when no credentials" "1" "$actual"
```

Run: `sh tests/test.sh`
Expected: FAIL (fetch-usage.sh does not exist yet)

- [ ] **Step 2: Create fetch-usage.sh with token retrieval**

```sh
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
```

Save to `fetch-usage.sh`.

- [ ] **Step 3: Run test to verify it passes**

```bash
sh tests/test.sh
```

Expected:
```
PASS: get_usage_token: returns non-zero when no credentials
Results: 1 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add fetch-usage.sh tests/test.sh
git commit -m "feat: fetch-usage.sh token retrieval with keychain + credentials fallback"
```

---

## Task 3: fetch-usage.sh — caching and locking

**Files:**
- Modify: `fetch-usage.sh`
- Modify: `tests/test.sh`

- [ ] **Step 1: Write failing tests for cache and lock functions**

Add to `tests/test.sh`:

```sh
# Task 3: cache — stale cache returns non-zero from read_stale_cache when missing
actual=$(CACHE_DIR=/nonexistent sh -c '. '"$SCRIPTS"'/fetch-usage.sh; read_stale_cache' 2>/dev/null; echo $?)
assert_eq "read_stale_cache: returns non-zero when cache missing" "1" "$actual"

# Task 3: lock — read_active_lock returns non-zero when no lock file
actual=$(CACHE_DIR=/nonexistent sh -c '. '"$SCRIPTS"'/fetch-usage.sh; read_active_lock' 2>/dev/null; echo $?)
assert_eq "read_active_lock: returns non-zero when no lock file" "1" "$actual"
```

Run: `sh tests/test.sh`
Expected: 1 passed, 2 failed

- [ ] **Step 2: Add caching and locking functions to fetch-usage.sh**

Append after the `get_usage_token` function:

```sh
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
```

- [ ] **Step 3: Run tests**

```bash
sh tests/test.sh
```

Expected:
```
PASS: get_usage_token: returns non-zero when no credentials
PASS: read_stale_cache: returns non-zero when cache missing
PASS: read_active_lock: returns non-zero when no lock file
Results: 3 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add fetch-usage.sh tests/test.sh
git commit -m "feat: fetch-usage.sh caching and lock file logic"
```

---

## Task 4: fetch-usage.sh — API call, response parsing, main function

**Files:**
- Modify: `fetch-usage.sh`
- Modify: `tests/test.sh`

- [ ] **Step 1: Write failing test for response parsing**

Add to `tests/test.sh`:

```sh
# Task 4: parse_api_response — extracts sessionUsage and weeklyUsage
raw='{"five_hour":{"utilization":61,"resets_at":"2026-03-24T15:00:00Z"},"seven_day":{"utilization":38,"resets_at":"2026-03-28T00:00:00Z"},"extra_usage":{"is_enabled":false,"monthly_limit":0,"used_credits":0,"utilization":0}}'
actual=$(echo "$raw" | sh -c '. '"$SCRIPTS"'/fetch-usage.sh; parse_api_response "'"$raw"'"' 2>/dev/null | jq -r '.sessionUsage')
assert_eq "parse_api_response: extracts sessionUsage" "61" "$actual"
```

Run: `sh tests/test.sh`
Expected: 3 passed, 1 failed

- [ ] **Step 2: Add API call + response parsing + main function**

Append to `fetch-usage.sh`:

```sh
# ── Retry-After parsing ────────────────────────────────────────────────────────
parse_retry_after() {
    retry_after="$1"
    [ -z "$retry_after" ] && return 1
    case "$retry_after" in
        ''|*[!0-9]*)
            # Try as HTTP date via jq
            retry_at=$(echo "\"$retry_after\"" | jq -r 'try fromdate | . - now | floor' 2>/dev/null) || return 1
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
```

- [ ] **Step 3: Run tests**

```bash
sh tests/test.sh
```

Expected:
```
PASS: get_usage_token: returns non-zero when no credentials
PASS: read_stale_cache: returns non-zero when cache missing
PASS: read_active_lock: returns non-zero when no lock file
PASS: parse_api_response: extracts sessionUsage
Results: 4 passed, 0 failed
```

- [ ] **Step 4: Make fetch-usage.sh executable and commit**

```bash
chmod +x fetch-usage.sh
git add fetch-usage.sh tests/test.sh
git commit -m "feat: fetch-usage.sh API call, response parsing, and main function"
```

---

## Task 5: context-bar.sh — scaffolding, helpers, model segment

**Files:**
- Create: `context-bar.sh`
- Modify: `tests/test.sh`

- [ ] **Step 1: Write failing tests for model segment**

Add to `tests/test.sh`:

```sh
# Task 5: model segment — display_name strips Claude prefix
actual=$(cat "$FIXTURES/stdin-full.json" | sh -c '. '"$SCRIPTS"'/context-bar.sh --test-segment model')
assert_eq "model: strips Claude prefix from display_name" "Sonnet 4.6" "$actual"

# Task 5: model segment — falls back to model.id transformation
actual=$(cat "$FIXTURES/stdin-minimal.json" | sh -c '. '"$SCRIPTS"'/context-bar.sh --test-segment model')
assert_eq "model: falls back to model.id transformation" "Sonnet 4.6" "$actual"

# Task 5: model segment — null both fields returns empty
actual=$(printf '{"model":{"id":null,"display_name":null},"cwd":"/tmp","context_window":null}' | sh -c '. '"$SCRIPTS"'/context-bar.sh --test-segment model')
assert_eq "model: null fields returns empty" "" "$actual"
```

Run: `sh tests/test.sh`
Expected: 4 passed, 3 failed

- [ ] **Step 2: Create context-bar.sh with scaffolding and model segment**

```sh
#!/bin/sh

# ── Args ───────────────────────────────────────────────────────────────────────
USE_COLOR=0
TEST_SEGMENT=""
for arg in "$@"; do
    case "$arg" in
        --color) USE_COLOR=1 ;;
        --test-segment) TEST_SEGMENT_NEXT=1 ;;
        *) [ -n "$TEST_SEGMENT_NEXT" ] && TEST_SEGMENT="$arg" && TEST_SEGMENT_NEXT="" ;;
    esac
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
    # Replace every / with - (POSIX tr)
    printf '%s' "$1" | tr '/' '-'
}

find_session_jsonl() {
    cwd="$1"
    slug=$(slug_from_cwd "$cwd")
    dir="${HOME}/.claude/projects/${slug}"
    [ -d "$dir" ] || return 1
    # Most recently modified .jsonl file
    latest=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
    [ -n "$latest" ] && echo "$latest"
}

# ── Segment: Model ─────────────────────────────────────────────────────────────
segment_model() {
    display=$(echo "$INPUT" | jq -r '.model.display_name // empty' 2>/dev/null) || display=""

    if [ -n "$display" ]; then
        # Strip "Claude " prefix
        model="${display#Claude }"
    else
        model_id=$(echo "$INPUT" | jq -r '.model.id // empty' 2>/dev/null) || model_id=""
        [ -z "$model_id" ] || [ "$model_id" = "null" ] && return

        # Strip claude- prefix, title-case family, dot-join version
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
```

Save to `context-bar.sh`.

- [ ] **Step 3: Add --test-segment dispatch at bottom of context-bar.sh**

```sh
# ── Test harness dispatch ──────────────────────────────────────────────────────
if [ -n "$TEST_SEGMENT" ]; then
    "segment_${TEST_SEGMENT}"
    exit 0
fi
```

- [ ] **Step 4: Run tests**

```bash
sh tests/test.sh
```

Expected:
```
PASS: model: strips Claude prefix from display_name
PASS: model: falls back to model.id transformation
PASS: model: null fields returns empty
Results: 7 passed, 0 failed
```

Note: color codes appear in actual output when `--color` is not passed they are empty strings, so the assert checks plain text. This is correct.

- [ ] **Step 5: Make executable and commit**

```bash
chmod +x context-bar.sh
git add context-bar.sh tests/test.sh
git commit -m "feat: context-bar.sh scaffolding and model segment"
```

---

## Task 6: context-bar.sh — git segment

**Files:**
- Modify: `context-bar.sh`
- Modify: `tests/test.sh`

- [ ] **Step 1: Write failing tests for git segment**

Add to `tests/test.sh`:

```sh
# Task 6: git segment — skip when cwd is not a git repo
actual=$(printf '{"model":{"id":"claude-sonnet-4-6","display_name":null},"cwd":"/tmp","context_window":null}' \
    | sh "$SCRIPTS/context-bar.sh" --test-segment git)
assert_eq "git: empty output when not a git repo" "" "$actual"

# Task 6: git segment — skip when cwd is empty
actual=$(printf '{"model":{"id":"claude-sonnet-4-6","display_name":null},"cwd":"","context_window":null}' \
    | sh "$SCRIPTS/context-bar.sh" --test-segment git)
assert_eq "git: empty output when cwd is empty" "" "$actual"
```

Run: `sh tests/test.sh`
Expected: 7 passed, 2 failed

- [ ] **Step 2: Add git segment to context-bar.sh (before test dispatch)**

```sh
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

    # Assemble
    display="$branch"
    [ "$ahead" -gt 0 ] 2>/dev/null && display="${display} ↑${ahead}"
    [ "$behind" -gt 0 ] 2>/dev/null && display="${display} ↓${behind}"
    [ -n "$dirty" ] && display="${display} ●"

    printf '%b%s%b  %b%s%b' "$C_TEAL" "⎇" "$RESET" "$C_BLUE" "$display" "$RESET"
}
```

- [ ] **Step 3: Run tests**

```bash
sh tests/test.sh
```

Expected:
```
PASS: git: empty output when not a git repo
PASS: git: empty output when cwd is empty
Results: 9 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add context-bar.sh tests/test.sh
git commit -m "feat: context-bar.sh git segment with branch, ahead/behind, dirty indicator"
```

---

## Task 7: context-bar.sh — session duration segment

**Files:**
- Modify: `context-bar.sh`
- Modify: `tests/test.sh`

- [ ] **Step 1: Write failing tests for duration segment**

Add to `tests/test.sh`:

```sh
# Task 7: session duration — skips silently when no JSONL found
actual=$(printf '{"model":{"id":"claude-sonnet-4-6","display_name":null},"cwd":"/nonexistent/path","context_window":null}' \
    | sh "$SCRIPTS/context-bar.sh" --test-segment duration)
assert_eq "duration: empty when no JSONL" "" "$actual"
```

Run: `sh tests/test.sh`
Expected: 9 passed, 1 failed

- [ ] **Step 2: Add duration segment to context-bar.sh**

```sh
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
```

- [ ] **Step 3: Run tests**

```bash
sh tests/test.sh
```

Expected:
```
PASS: duration: empty when no JSONL
Results: 10 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add context-bar.sh tests/test.sh
git commit -m "feat: context-bar.sh session duration segment"
```

---

## Task 8: context-bar.sh — context window segment

**Files:**
- Modify: `context-bar.sh`
- Modify: `tests/test.sh`

- [ ] **Step 1: Write failing tests for context segment**

Add to `tests/test.sh`:

```sh
# Task 8: context segment — computes pct and context_k correctly
actual=$(cat "$FIXTURES/stdin-full.json" \
    | sh "$SCRIPTS/context-bar.sh" --test-segment context)
# tokens_used = 12000 + 50000 + 22000 = 84000; pct = 84000*100/200000 = 42; 200k
assert_eq "context: correct pct and k display" "▸ 42% of 200k" "$actual"

# Task 8: context segment — defaults context_window_size to 200000 when null
actual=$(cat "$FIXTURES/stdin-minimal.json" \
    | sh "$SCRIPTS/context-bar.sh" --test-segment context)
# all token fields null → 0 tokens → 0%
assert_eq "context: null usage shows 0% of 200k" "▸ 0% of 200k" "$actual"
```

Run: `sh tests/test.sh`
Expected: 10 passed, 2 failed

- [ ] **Step 2: Add context segment to context-bar.sh**

```sh
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
```

- [ ] **Step 3: Run tests**

```bash
sh tests/test.sh
```

Expected:
```
PASS: context: correct pct and k display
PASS: context: null usage shows 0% of 200k
Results: 12 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add context-bar.sh tests/test.sh
git commit -m "feat: context-bar.sh context window segment"
```

---

## Task 9: context-bar.sh — session cost segment

**Files:**
- Modify: `context-bar.sh`
- Modify: `tests/test.sh`

- [ ] **Step 1: Write failing test for cost segment**

Add to `tests/test.sh`:

```sh
# Task 9: cost segment — correct cost from fixture JSONL
# Set up: put fixture JSONL where the slug resolver will find it
FAKE_SLUG="-Users-testuser-myproject"
FAKE_DIR="$(mktemp -d)"
mkdir -p "$FAKE_DIR/.claude/projects/$FAKE_SLUG"
cp "$FIXTURES/session.jsonl" "$FAKE_DIR/.claude/projects/$FAKE_SLUG/session.jsonl"
actual=$(HOME="$FAKE_DIR" cat "$FIXTURES/stdin-full.json" \
    | sh "$SCRIPTS/context-bar.sh" --test-segment cost)
# Expected cost: $0.018 (see fixture notes in Task 1 Step 4)
assert_eq "cost: correct cost from JSONL" "⊛ ~\$0.018" "$actual"
rm -rf "$FAKE_DIR"
```

Run: `sh tests/test.sh`
Expected: 12 passed, 1 failed

- [ ] **Step 2: Add cost segment to context-bar.sh**

```sh
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
```

- [ ] **Step 3: Run tests**

```bash
sh tests/test.sh
```

Expected:
```
PASS: cost: correct cost from JSONL
Results: 13 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add context-bar.sh tests/test.sh
git commit -m "feat: context-bar.sh session cost segment with JSONL parsing"
```

---

## Task 10: context-bar.sh — subscription segment

**Files:**
- Modify: `context-bar.sh`
- Modify: `tests/test.sh`

- [ ] **Step 1: Write failing test for subscription segment**

Add to `tests/test.sh`:

```sh
# Task 10: subscription — skips when fetch-usage returns error
actual=$(cat "$FIXTURES/stdin-full.json" \
    | FETCH_USAGE_OVERRIDE='{"error":"no-credentials"}' \
      sh "$SCRIPTS/context-bar.sh" --test-segment subscription)
assert_eq "subscription: empty when fetch-usage returns error" "" "$actual"
```

Run: `sh tests/test.sh`
Expected: 13 passed, 1 failed

- [ ] **Step 2: Add FETCH_USAGE_OVERRIDE support and subscription segment**

First, modify the `find_session_jsonl` helper area to support the test override. Add just before the subscription segment:

```sh
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
    session_pct=$(echo "$usage_data" | jq -r '.sessionUsage // empty' 2>/dev/null) || session_pct=""
    session_reset=$(echo "$usage_data" | jq -r '.sessionResetAt // empty' 2>/dev/null) || session_reset=""
    weekly_pct=$(echo "$usage_data" | jq -r '.weeklyUsage // empty' 2>/dev/null) || weekly_pct=""
    weekly_reset=$(echo "$usage_data" | jq -r '.weeklyResetAt // empty' 2>/dev/null) || weekly_reset=""

    [ -z "$session_pct" ] && return

    # Session reset countdown
    countdown=""
    if [ -n "$session_reset" ]; then
        diff=$(echo "$session_reset" | jq -r '
            try (fromdate - now | floor) catch empty
        ' 2>/dev/null) || diff=""
        if [ -n "$diff" ]; then
            if [ "$diff" -le 0 ]; then
                countdown="resetting"
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
        line3="${C_TEAL}⚡${RESET} ${C_BLUE}${session_pct}%${RESET}${C_GRAY} 5hr (${countdown})${RESET}"
    else
        line3="${C_TEAL}⚡${RESET} ${C_BLUE}${session_pct}%${RESET}${C_GRAY} 5hr${RESET}"
    fi

    # Weekly + pacing
    if [ -n "$weekly_pct" ]; then
        line3="${line3}${C_GRAY}  ·  ${RESET}${C_TEAL}⟳${RESET} ${C_BLUE}${weekly_pct}%${RESET}${C_GRAY} weekly${RESET}"

        # Pacing
        if [ -n "$weekly_reset" ]; then
            pacing=$(echo "$weekly_reset" | jq -r --argjson wpct "$weekly_pct" '
                (try fromdate catch null) as $reset_epoch |
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
```

- [ ] **Step 3: Run tests**

```bash
sh tests/test.sh
```

Expected:
```
PASS: subscription: empty when fetch-usage returns error
Results: 14 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add context-bar.sh tests/test.sh
git commit -m "feat: context-bar.sh subscription segment with 5hr, weekly, pacing"
```

---

## Task 11: context-bar.sh — line assembly and final output

**Files:**
- Modify: `context-bar.sh`

- [ ] **Step 1: Write failing test for full output**

Add to `tests/test.sh`:

```sh
# Task 11: full output — three lines, correct structure, segments separated by  |
FAKE_DIR2="$(mktemp -d)"
FAKE_SLUG2="-Users-testuser-myproject"
mkdir -p "$FAKE_DIR2/.claude/projects/$FAKE_SLUG2"
cp "$FIXTURES/session.jsonl" "$FAKE_DIR2/.claude/projects/$FAKE_SLUG2/session.jsonl"
# Line 1 should contain ◆ and the model name (git skipped — /tmp is not a git repo)
actual_line1=$(HOME="$FAKE_DIR2" cat "$FIXTURES/stdin-full.json" \
    | FETCH_USAGE_OVERRIDE='{"error":"no-credentials"}' \
      sh "$SCRIPTS/context-bar.sh" | head -1)
# Line 1: model  |  duration (no git since cwd=/Users/testuser/myproject won't be a git repo)
case "$actual_line1" in
    *"◆"*"Sonnet 4.6"*) echo "PASS: full output: line 1 contains model"; PASS=$((PASS+1)) ;;
    *) echo "FAIL: full output: line 1 contains model"; echo "  Actual: [$actual_line1]"; FAIL=$((FAIL+1)) ;;
esac
rm -rf "$FAKE_DIR2"
```

Run: `sh tests/test.sh`
Expected: 14 passed, 1 failed

- [ ] **Step 2: Add line assembly to context-bar.sh (at the end, before test dispatch)**

```sh
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
```

- [ ] **Step 3: Update test dispatch and add main call**

Replace the test dispatch block and add main execution:

```sh
# ── Entry point ────────────────────────────────────────────────────────────────
if [ -n "$TEST_SEGMENT" ]; then
    "segment_${TEST_SEGMENT}"
    exit 0
fi

assemble_output
```

- [ ] **Step 4: Run tests**

```bash
sh tests/test.sh
```

Expected:
```
PASS: full output: line 1 contains model
Results: 15 passed, 0 failed
```

- [ ] **Step 5: Smoke test with real Claude Code stdin**

Run this in your terminal while Claude Code is active:

```bash
echo '{"model":{"id":"claude-sonnet-4-6","display_name":"Claude Sonnet 4.6"},"cwd":"'"$(pwd)"'","context_window":{"context_window_size":200000,"current_usage":{"input_tokens":5000,"cache_creation_input_tokens":10000,"cache_read_input_tokens":3000}}}' \
  | sh context-bar.sh
```

Verify three lines appear with correct segments. Verify `sh context-bar.sh --color` adds color codes.

- [ ] **Step 6: Commit**

```bash
git add context-bar.sh tests/test.sh
git commit -m "feat: context-bar.sh line assembly and full output"
```

---

## Task 12: README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

```markdown
# nice-claude-status-bar

A Claude Code status bar that shows model, git branch, session duration, context usage, cost, and subscription quota — updated automatically at the bottom of your terminal.

```
◆ Sonnet 4.6  |  ⎇  main ↑2 ●  |  ⧗ 45m
▸ 42% of 200k  |  ⊛ ~$0.031
⚡ 61% 5hr (2h 14m)  ·  ⟳ 38% weekly  ·  → 17.7%/day
```

## Requirements

- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)
- `curl` — pre-installed on macOS; needed for subscription quota line
- `git` — optional; git segment hidden when not in a repo

## Installation

**1. Copy the scripts to `~/.claude/scripts/`:**

```bash
mkdir -p ~/.claude/scripts
cp context-bar.sh fetch-usage.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/context-bar.sh ~/.claude/scripts/fetch-usage.sh
```

**2. Add to `~/.claude/settings.json`:**

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/context-bar.sh"
  }
}
```

For colors, use:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/context-bar.sh --color"
  }
}
```

**3. Restart Claude Code.** The status bar appears at the bottom of your terminal.

## What each line shows

| Line | Segments | Source |
|---|---|---|
| 1 | Model name, git branch + dirty indicator, session duration | Claude Code stdin + JSONL |
| 2 | Context window usage %, estimated session cost | Claude Code stdin + JSONL |
| 3 | 5hr subscription usage + reset countdown, weekly usage, daily pacing | Anthropic OAuth API |

Segments are silently omitted if data is unavailable (not in a git repo, no credentials, etc.).

## How it works

Claude Code calls `context-bar.sh` via the `statusLine` hook and pipes a JSON blob via stdin. This JSON contains the model, CWD, and context window stats. The script:

1. Parses model name and context data from stdin
2. Runs `git` commands in the CWD for branch info
3. Reads `~/.claude/projects/<slug>/*.jsonl` for session token counts and timestamps
4. Calls `fetch-usage.sh` (cached for 3 minutes) for subscription quota
5. Prints up to three lines

No Claude API calls are made. No tokens are consumed.

## Extending display fields

Each segment is a shell function in `context-bar.sh`:

- `segment_model` — line 1, model name
- `segment_git` — line 1, branch info
- `segment_duration` — line 1, session duration
- `segment_context` — line 2, context %
- `segment_cost` — line 2, estimated cost
- `segment_subscription` — line 3, quota data

To add a new field, write a new `segment_<name>` function that prints to stdout (empty string = omit). Then add it to the `assemble_output` function in the appropriate line.

To add new data sources, edit `fetch-usage.sh` (for API data) or read additional fields from stdin or the JSONL in a new segment function.

## Forked reference

The `forked/` directory contains the original implementation this was built from, preserved unchanged for reference.
```

Save to `README.md`.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README with setup instructions, settings.json snippet, and extension guide"
```

---

## Task 13: Final integration + install

**Files:** none new

- [ ] **Step 1: Run full test suite**

```bash
sh tests/test.sh
```

Expected: all 15 tests pass, 0 failed.

- [ ] **Step 2: Install scripts**

```bash
mkdir -p ~/.claude/scripts
cp context-bar.sh fetch-usage.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/context-bar.sh ~/.claude/scripts/fetch-usage.sh
```

- [ ] **Step 3: Add statusLine to ~/.claude/settings.json**

Open `~/.claude/settings.json` and add the `statusLine` block alongside existing keys:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/context-bar.sh --color"
  }
}
```

- [ ] **Step 4: Verify live in Claude Code**

Restart Claude Code. The status bar should appear at the bottom. Verify:
- Line 1 shows model name and current git branch
- Line 2 shows context % and session cost
- Line 3 shows subscription quota (or is absent if no credentials)

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: complete implementation of nice-claude-status-bar"
```
