#!/bin/bash
# test_metrics.sh: Unit test for lib/core/metrics.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock dependencies
source "$BASE_DIR/lib/core/metrics.sh"

# 2. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

LOG_FILE="$TEST_DIR/session.log"

# ==============================================================================
# TEST CASE 1: log_usage (Standard Gemini 1.5 Payload)
# ==============================================================================
echo "--- Test Case 1: log_usage (Standard) ---"

RESP_STD='{
  "usageMetadata": {
    "promptTokenCount": 100,
    "candidatesTokenCount": 50,
    "totalTokenCount": 150
  }
}'

log_usage "$RESP_STD" "1.5" "0" "$LOG_FILE" > /dev/null

if grep -q "H: 0 M: 100 C: 50 T: 150 N: 150(100%) S: 0 Th: 0 \[1.50s\]" "$LOG_FILE"; then
    pass "Standard usage correctly logged"
else
    fail "Log entry mismatch for standard payload: $(cat "$LOG_FILE")"
fi

# ==============================================================================
# TEST CASE 2: log_usage (Cached Tokens & Thinking)
# ==============================================================================
echo "--- Test Case 2: log_usage (Cached & Thinking) ---"

RESP_THINK='{
  "usageMetadata": {
    "cachedContentTokenCount": 1000,
    "promptTokenCount": 1200,
    "candidatesTokenCount": 200,
    "totalTokenCount": 1400,
    "candidatesTokenCountDetails": {
      "thinkingTokenCount": 50
    }
  }
}'

log_usage "$RESP_THINK" "5.0" "1" "$LOG_FILE" > /dev/null

# H: 1000, M: 200 (1200-1000), C: 200, T: 1400, N: 450 (200+200+50), S: 1, Th: 50
if grep -q "H: 1000 M: 200 C: 200 T: 1400 N: 450(32%) S: 1 Th: 50 \[5.00s\]" "$LOG_FILE"; then
    pass "Cached tokens and Thinking tokens correctly logged"
else
    fail "Log entry mismatch for cached/thinking payload: $(tail -n 1 "$LOG_FILE")"
fi

# ==============================================================================
# TEST CASE 3: display_session_totals
# ==============================================================================
echo "--- Test Case 3: display_session_totals ---"
OUTPUT=$(display_session_totals "$LOG_FILE")

# The log file now has 2 entries.
# Entry 1: H=0, M=100, C=50, T=150, S=0
# Entry 2: H=1000, M=200, C=200, T=1400, S=1
# Totals: H=1000, M=300, C=250, T=1550, S=1

# Strip ANSI codes for easier grepping
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')

if echo "$CLEAN_OUTPUT" | grep -q "Hit: 1000 | Miss: 300 | Comp: 250 | Total: 1550 | Search: 1"; then
    pass "Session totals correctly aggregated"
else
    fail "Aggregation mismatch in output: $CLEAN_OUTPUT"
fi

echo "Done."

