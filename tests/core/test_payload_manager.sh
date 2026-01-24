#!/bin/bash
# test_payload_manager.sh: Unit test for lib/core/payload_manager.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock dependencies
source "$BASE_DIR/lib/core/history_manager.sh"
source "$BASE_DIR/lib/core/payload_manager.sh"

# 2. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

# Mock history file
HISTORY="$TEST_DIR/history.json"
echo '{"messages": [{"role": "user", "parts": [{"text": "Hello"}]}]}' > "$HISTORY"

TOOLS='[]'

# ==============================================================================
# TEST CASE 1: Basic Payload Construction
# ==============================================================================
echo "--- Test Case 1: Basic Payload Construction ---"

PAYLOAD=$(build_payload "$HISTORY" "$TOOLS" "System instruction" "gemini-1.5-pro" "HIGH" "4000")

if echo "$PAYLOAD" | jq -e '.systemInstruction.parts[0].text == "System instruction"' >/dev/null && \
   echo "$PAYLOAD" | jq -e '.contents[0].parts[0].text == "Hello"' >/dev/null; then
    pass "Payload contains correct system and user content"
else
    fail "Payload structure invalid: $PAYLOAD"
fi

# ==============================================================================
# TEST CASE 2: Thinking Configuration (Gemini 3)
# ==============================================================================
echo "--- Test Case 2: Thinking Configuration (Gemini 3) ---"

PAYLOAD_G3=$(build_payload "$HISTORY" "$TOOLS" "" "gemini-3-pro-preview" "MEDIUM" "8000")

if echo "$PAYLOAD_G3" | jq -e '.generationConfig.thinkingConfig.thinkingLevel == "MEDIUM"' >/dev/null; then
    pass "Gemini 3 thinkingConfig correctly applied"
else
    fail "Gemini 3 thinkingConfig missing or incorrect: $PAYLOAD_G3"
fi

# ==============================================================================
# TEST CASE 3: Payload Estimation (Safe)
# ==============================================================================
echo "--- Test Case 3: Payload Estimation (Safe) ---"

# Mock backup_file (part of history_manager.sh)
backup_file() { :; }
export -f backup_file

TEMP_PAYLOAD="$TEST_DIR/payload.tmp"
echo "$PAYLOAD" > "$TEMP_PAYLOAD"

EST=$(estimate_and_check_payload "$TEMP_PAYLOAD" "$HISTORY" 5000)

if [[ "$EST" =~ ^[0-9]+$ ]] && [ "$EST" -gt 0 ]; then
    pass "Payload estimation returned valid numeric value: $EST"
else
    fail "Estimation failed to return a valid number: $EST"
fi

# ==============================================================================
# TEST CASE 4: Payload Overflow and Rollback
# ==============================================================================
echo "--- Test Case 4: Payload Overflow and Rollback ---"

# Mock restore_backup
restore_backup() { echo "MOCK_ROLLBACK" > "$1"; }
export -f restore_backup

# Small limit to trigger overflow
set +e
estimate_and_check_payload "$TEMP_PAYLOAD" "$HISTORY" 10 > "$TEST_DIR/out" 2> "$TEST_DIR/err"
RESULT=$?
set -e

if [ $RESULT -ne 0 ] && grep -q "exceeds limit" "$TEST_DIR/err"; then
    if [ "$(cat "$HISTORY")" == "MOCK_ROLLBACK" ]; then
        pass "Correctly handled overflow and triggered rollback"
    else
        fail "Rollback was not triggered on the history file"
    fi
else
    fail "Failed to detect payload overflow"
fi

echo "Done."

