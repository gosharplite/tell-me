#!/bin/bash
# Test for lib/core/api_client.sh (Retry Logic)

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock curl
mkdir -p "$TEST_DIR/bin"
cat <<'EOF' > "$TEST_DIR/bin/curl"
#!/bin/bash
# Check how many times we've been called by creating a state file
COUNT_FILE="../curl_count.txt"
[ ! -f "$COUNT_FILE" ] && echo 0 > "$COUNT_FILE"
COUNT=$(cat "$COUNT_FILE")
echo $((COUNT + 1)) > "$COUNT_FILE"

# Logic: Return 429 once, then success
if [ "$COUNT" -eq 0 ]; then
    echo '{"error": {"code": 429, "message": "Too Many Requests"}}'
else
    echo '{"candidates": [{"content": {"parts": [{"text": "Success"}]}}]}'
fi
EOF
chmod +x "$TEST_DIR/bin/curl"
export PATH="$TEST_DIR/bin:$PATH"

# Mock sleep to speed up tests
sleep() {
    echo "Skipping sleep $1"
}
export -f sleep

# 2. Source Dependencies
source "$BASE_DIR/lib/core/api_client.sh"

pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

test_retry_logic() {
    echo "Testing API Retry Logic (429 -> Success)..."
    
    # Create dummy payload
    local PAYLOAD="$TEST_DIR/payload.json"
    echo "{}" > "$PAYLOAD"
    
    # Reset count
    echo 0 > "$TEST_DIR/curl_count.txt"
    
    # Call client
    RESPONSE=$(call_gemini_api "http://mock" "model" "token" "$PAYLOAD")
    
    if echo "$RESPONSE" | grep -q "Success"; then
        pass "API client recovered after retry"
    else
        fail "API client failed to recover: $RESPONSE"
    fi
}

test_retry_exhaustion() {
    echo "Testing API Retry Exhaustion..."
    
    # Mock curl to always fail
    cat <<'EOF' > "$TEST_DIR/bin/curl"
#!/bin/bash
echo '{"error": {"code": 500, "message": "Persistent Server Error"}}'
EOF
    
    local PAYLOAD="$TEST_DIR/payload.json"
    echo "{}" > "$PAYLOAD"
    
    # Call client with low retry limit
    call_gemini_api "http://mock" "model" "token" "$PAYLOAD" 2 > /dev/null
    RET=$?
    
    if [ $RET -ne 0 ]; then
        pass "API client correctly reported exhaustion"
    else
        fail "API client should have failed"
    fi
}

echo "Running API Client Tests..."
test_retry_logic
test_retry_exhaustion

echo "------------------------------------------------"
echo "All tests passed successfully."
exit 0

