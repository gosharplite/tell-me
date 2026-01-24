#!/bin/bash
# test_api_client.sh: Unit test for lib/core/api_client.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock dependencies
mkdir -p "$TEST_DIR/bin"
cp "$BASE_DIR/lib/core/"*.sh "$TEST_DIR/"
export PATH="$TEST_DIR/bin:$PATH"

# Source the module under test
source "$TEST_DIR/api_client.sh"

# 2. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

# Mock payload
PAYLOAD="$TEST_DIR/payload.json"
echo '{"test": "data"}' > "$PAYLOAD"

# ==============================================================================
# TEST CASE 1: Happy Path
# ==============================================================================
echo "--- Test Case 1: Happy Path ---"

cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
echo '{"candidates": [{"content": {"parts": [{"text": "Hello"}]}}]}'
EOF
chmod +x "$TEST_DIR/bin/curl"

RESPONSE=$(call_gemini_api "http://mock" "model" "token" "$PAYLOAD")
if echo "$RESPONSE" | jq -e '.candidates[0].content.parts[0].text == "Hello"' >/dev/null; then
    pass "Successful API response captured"
else
    fail "Unexpected API response: $RESPONSE"
fi

# ==============================================================================
# TEST CASE 2: Retry Path (429 -> Success)
# ==============================================================================
echo "--- Test Case 2: Retry Path (429 -> Success) ---"

STATE_FILE="$TEST_DIR/curl_state"
echo "0" > "$STATE_FILE"

cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
COUNT=\$(cat "$STATE_FILE")
echo \$((COUNT + 1)) > "$STATE_FILE"

if [ "\$COUNT" -eq 0 ]; then
    echo '{"error": {"code": 429, "message": "Rate limited"}}'
else
    echo '{"candidates": [{"content": {"parts": [{"text": "Success after retry"}]}}]}'
fi
EOF
chmod +x "$TEST_DIR/bin/curl"

# Mock sleep to speed up test
sleep() { :; }
export -f sleep

RESPONSE=$(call_gemini_api "http://mock" "model" "token" "$PAYLOAD" 3)
if echo "$RESPONSE" | jq -e '.candidates[0].content.parts[0].text == "Success after retry"' >/dev/null; then
    pass "Recovered from 429 error after retry"
else
    fail "Failed to recover from retryable error: $RESPONSE"
fi

# ==============================================================================
# TEST CASE 3: Exhausted Retries
# ==============================================================================
echo "--- Test Case 3: Exhausted Retries ---"

cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
echo '{"error": {"code": 500, "message": "Internal Server Error"}}'
EOF
chmod +x "$TEST_DIR/bin/curl"

set +e
call_gemini_api "http://mock" "model" "token" "$PAYLOAD" 2 > "$TEST_DIR/out" 2> "$TEST_DIR/err"
RESULT=$?
set -e

if [ $RESULT -ne 0 ] && grep -q "retry limit exhausted" "$TEST_DIR/err"; then
    pass "Correctly failed after exhausting retries"
else
    fail "Did not fail correctly on persistent 500 error"
fi

# ==============================================================================
# TEST CASE 4: Non-Retryable Error (400)
# ==============================================================================
echo "--- Test Case 4: Non-Retryable Error (400) ---"

cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
echo '{"error": {"code": 400, "message": "Invalid argument"}}'
EOF
chmod +x "$TEST_DIR/bin/curl"

set +e
call_gemini_api "http://mock" "model" "token" "$PAYLOAD" 3 > "$TEST_DIR/out" 2> "$TEST_DIR/err"
RESULT=$?
set -e

if [ $RESULT -ne 0 ] && grep -q "Invalid argument" "$TEST_DIR/err"; then
    pass "Correctly aborted on non-retryable 400 error"
else
    fail "Aborted incorrectly or missed error message"
fi

echo "Done."

