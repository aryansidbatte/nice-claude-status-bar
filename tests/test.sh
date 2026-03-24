#!/bin/sh

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

# Task 2: token retrieval — test that get_usage_token exits non-zero when no credentials exist
actual=$(HOME=/nonexistent CLAUDE_CONFIG_DIR=/nonexistent sh -c '. '"$SCRIPTS"'/fetch-usage.sh; get_usage_token' 2>/dev/null; echo $?)
assert_eq "get_usage_token: returns non-zero when no credentials" "1" "$actual"

# Task 3: cache — stale cache returns non-zero from read_stale_cache when missing
actual=$(HOME=/nonexistent sh -c '. '"$SCRIPTS"'/fetch-usage.sh; read_stale_cache' 2>/dev/null; echo $?)
assert_eq "read_stale_cache: returns non-zero when cache missing" "1" "$actual"

# Task 3: lock — read_active_lock returns non-zero when no lock file
actual=$(HOME=/nonexistent sh -c '. '"$SCRIPTS"'/fetch-usage.sh; read_active_lock' 2>/dev/null; echo $?)
assert_eq "read_active_lock: returns non-zero when no lock file" "1" "$actual"

# Task 4: parse_api_response — extracts sessionUsage and weeklyUsage
raw='{"five_hour":{"utilization":61,"resets_at":"2026-03-24T15:00:00Z"},"seven_day":{"utilization":38,"resets_at":"2026-03-28T00:00:00Z"},"extra_usage":{"is_enabled":false,"monthly_limit":0,"used_credits":0,"utilization":0}}'
actual=$(HOME=/nonexistent RAW_DATA="$raw" sh -c '. '"$SCRIPTS"'/fetch-usage.sh; parse_api_response "$RAW_DATA"' 2>/dev/null | jq -r '.sessionUsage')
assert_eq "parse_api_response: extracts sessionUsage" "61" "$actual"

# Task 5: model segment — display_name strips Claude prefix
actual=$(cat "$FIXTURES/stdin-full.json" | sh "$SCRIPTS/context-bar.sh" --test-segment model)
assert_eq "model: strips Claude prefix from display_name" "◆ Sonnet 4.6" "$actual"

# Task 5: model segment — falls back to model.id transformation
actual=$(cat "$FIXTURES/stdin-minimal.json" | sh "$SCRIPTS/context-bar.sh" --test-segment model)
assert_eq "model: falls back to model.id transformation" "◆ Sonnet 4.6" "$actual"

# Task 5: model segment — null both fields returns empty
actual=$(printf '{"model":{"id":null,"display_name":null},"cwd":"/tmp","context_window":null}' | sh "$SCRIPTS/context-bar.sh" --test-segment model)
assert_eq "model: null fields returns empty" "" "$actual"

# Task 6: git segment — skip when cwd is not a git repo
actual=$(printf '{"model":{"id":"claude-sonnet-4-6","display_name":null},"cwd":"/tmp","context_window":null}' \
    | sh "$SCRIPTS/context-bar.sh" --test-segment git)
assert_eq "git: empty output when not a git repo" "" "$actual"

# Task 6: git segment — skip when cwd is empty
actual=$(printf '{"model":{"id":"claude-sonnet-4-6","display_name":null},"cwd":"","context_window":null}' \
    | sh "$SCRIPTS/context-bar.sh" --test-segment git)
assert_eq "git: empty output when cwd is empty" "" "$actual"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
