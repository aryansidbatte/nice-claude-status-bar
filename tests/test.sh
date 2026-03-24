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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
