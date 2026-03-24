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

# Task 7: session duration — skips silently when no JSONL found
actual=$(printf '{"model":{"id":"claude-sonnet-4-6","display_name":null},"cwd":"/nonexistent/path","context_window":null}' \
    | sh "$SCRIPTS/context-bar.sh" --test-segment duration)
assert_eq "duration: empty when no JSONL" "" "$actual"

# Task 8: context segment — computes pct and context_k correctly
# tokens_used = 12000 + 50000 + 22000 = 84000; pct = 84000*100/200000 = 42; 200k
actual=$(cat "$FIXTURES/stdin-full.json" \
    | sh "$SCRIPTS/context-bar.sh" --test-segment context)
assert_eq "context: correct pct and k display" "▸ 42% of 200k" "$actual"

# Task 8: context segment — defaults context_window_size to 200000 when null
actual=$(cat "$FIXTURES/stdin-minimal.json" \
    | sh "$SCRIPTS/context-bar.sh" --test-segment context)
assert_eq "context: null usage shows 0% of 200k" "▸ 0% of 200k" "$actual"

# Task 9: cost segment — correct cost from fixture JSONL
FAKE_SLUG="-Users-testuser-myproject"
FAKE_DIR="$(mktemp -d)"
mkdir -p "$FAKE_DIR/.claude/projects/$FAKE_SLUG"
cp "$FIXTURES/session.jsonl" "$FAKE_DIR/.claude/projects/$FAKE_SLUG/session.jsonl"
actual=$(cat "$FIXTURES/stdin-full.json" \
    | HOME="$FAKE_DIR" sh "$SCRIPTS/context-bar.sh" --test-segment cost)
assert_eq "cost: correct cost from JSONL" "⊛ ~\$0.018" "$actual"
rm -rf "$FAKE_DIR"

# Task 10: subscription — skips when fetch-usage returns error
actual=$(cat "$FIXTURES/stdin-full.json" \
    | FETCH_USAGE_OVERRIDE='{"error":"no-credentials"}' \
      sh "$SCRIPTS/context-bar.sh" --test-segment subscription)
assert_eq "subscription: empty when fetch-usage returns error" "" "$actual"

# Task 11: full output — line 1 contains model and symbol
FAKE_DIR3="$(mktemp -d)"
FAKE_SLUG3="-Users-testuser-myproject"
mkdir -p "$FAKE_DIR3/.claude/projects/$FAKE_SLUG3"
cp "$FIXTURES/session.jsonl" "$FAKE_DIR3/.claude/projects/$FAKE_SLUG3/session.jsonl"
actual_line1=$(cat "$FIXTURES/stdin-full.json" \
    | HOME="$FAKE_DIR3" FETCH_USAGE_OVERRIDE='{"error":"no-credentials"}' \
      sh "$SCRIPTS/context-bar.sh" | head -1)
case "$actual_line1" in
    *"◆"*"Sonnet 4.6"*) echo "PASS: full output: line 1 contains model"; PASS=$((PASS+1)) ;;
    *) echo "FAIL: full output: line 1 contains model"; echo "  Actual: [$actual_line1]"; FAIL=$((FAIL+1)) ;;
esac
rm -rf "$FAKE_DIR3"

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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
