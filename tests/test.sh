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

# Tests added in subsequent tasks

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
