#!/bin/bash
# Test script for lib/tools/sys/ask_user.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
TEST_DIR=$(mktemp -d)
RESP_FILE="$TEST_DIR/test_resp.json"
echo "[]" > "$RESP_FILE"

# Mock Environment
export CURRENT_TURN=0
export MAX_TURNS=10

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Mock the read builtin
read() {
    local var_name="${!#}"
    local prompt_val="Test Answer"
    eval "$var_name='$prompt_val'"
}

# 2. Source Dependencies
source "$BASE_DIR/lib/core/utils.sh"
source "$BASE_DIR/lib/tools/sys/ask_user.sh"

pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

test_normal_usage() {
    echo "------------------------------------------------"
    echo "Running test_normal_usage..."
    local ARGS='{"args": {"question": "How are you?"}}'
    
    echo "[]" > "$RESP_FILE"
    
    tool_ask_user "$ARGS" "$RESP_FILE"
    
    if grep -q "Test Answer" "$RESP_FILE"; then
        pass "Output contains user answer"
    else
        fail "Output missing user answer"
    fi
    
    if jq . "$RESP_FILE" >/dev/null 2>&1; then
         pass "Valid JSON"
    else
         fail "Invalid JSON"
    fi
}

test_warning_usage() {
    echo "------------------------------------------------"
    echo "Running test_warning_usage..."
    export CURRENT_TURN=9
    export MAX_TURNS=10
    local ARGS='{"args": {"question": "Last turn?"}}'
    
    echo "[]" > "$RESP_FILE"
    
    tool_ask_user "$ARGS" "$RESP_FILE"
    
    if grep -q "SYSTEM WARNING" "$RESP_FILE"; then
        pass "Warning message present"
    else
        fail "Warning message missing"
    fi
    
    if grep -q "Test Answer" "$RESP_FILE"; then
        pass "User answer still present"
    else
        fail "User answer missing in warning mode"
    fi
}

echo "Running Ask User Tests..."
test_normal_usage
test_warning_usage

echo "------------------------------------------------"
echo "All tests passed successfully."
exit 0

