#!/bin/bash

# Test script for lib/tools/sys/ask_user.sh

# Setup isolated environment
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

# Source dependencies
# We need to source utils.sh because ask_user.sh might use it
# But ask_user.sh sources utils.sh internally? No, usually tools expect utils to be sourced.
# Let's check imports. `lib/tools/sys/ask_user.sh` might rely on `tool_ask_user`.
# We source from the real lib directory.
source lib/core/utils.sh
source lib/tools/sys/ask_user.sh

test_normal_usage() {
    echo "------------------------------------------------"
    echo "Running test_normal_usage..."
    local ARGS='{"args": {"question": "How are you?"}}'
    
    echo "[]" > "$RESP_FILE"
    
    tool_ask_user "$ARGS" "$RESP_FILE"
    
    if grep -q "Test Answer" "$RESP_FILE"; then
        echo "PASS: Output contains user answer"
    else
        echo "FAIL: Output missing user answer"
        cat "$RESP_FILE"
        return 1
    fi
    
    if jq . "$RESP_FILE" >/dev/null 2>&1; then
         echo "PASS: Valid JSON"
    else
         echo "FAIL: Invalid JSON"
         cat "$RESP_FILE"
         return 1
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
        echo "PASS: Warning message present"
    else
        echo "FAIL: Warning message missing"
        cat "$RESP_FILE"
        return 1
    fi
    
    if grep -q "Test Answer" "$RESP_FILE"; then
        echo "PASS: User answer still present"
    else
        echo "FAIL: User answer missing in warning mode"
        return 1
    fi
}

FAILED=0
test_normal_usage || FAILED=1
test_warning_usage || FAILED=1

if [ $FAILED -eq 0 ]; then
    echo "------------------------------------------------"
    echo "All tests passed successfully."
    exit 0
else
    echo "------------------------------------------------"
    echo "Some tests failed."
    exit 1
fi
