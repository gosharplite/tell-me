#!/bin/bash
# Test for lib/core/ui_utils.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock get_log_timestamp (usually in utils.sh)
get_log_timestamp() {
    echo "[TS]"
}

# 2. Source Dependencies
source "$BASE_DIR/lib/core/ui_utils.sh"

pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

test_log_tool_call() {
    echo "Testing log_tool_call..."
    
    # Test case 1: read_file
    local FC_JSON='{"name": "read_file", "args": {"filepath": "config.yaml"}}'
    local TURN="[T:1/10]"
    
    OUTPUT=$(log_tool_call "$FC_JSON" "$TURN")
    
    # Strip ANSI escape codes
    CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
    
    if [[ "$CLEAN_OUTPUT" == *"[TS] [T:1/10] Reading config.yaml (read_file)"* ]]; then
        pass "read_file log correct"
    else
        fail "read_file log incorrect: $CLEAN_OUTPUT"
    fi
    
    # Test case 2: update_file
    FC_JSON='{"name": "update_file", "args": {"filepath": "main.py"}}'
    OUTPUT=$(log_tool_call "$FC_JSON" "$TURN")
    CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
    
    if [[ "$CLEAN_OUTPUT" == *"[TS] [T:1/10] Updating main.py (update_file)"* ]]; then
        pass "update_file log correct"
    else
        fail "update_file log incorrect: $CLEAN_OUTPUT"
    fi
    
    # Test case 3: unknown tool
    FC_JSON='{"name": "secret_scan", "args": {}}'
    OUTPUT=$(log_tool_call "$FC_JSON" "$TURN")
    CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
    
    if [[ "$CLEAN_OUTPUT" == *"[TS] [T:1/10] Calling secret_scan"* ]]; then
        pass "unknown tool log correct"
    else
        fail "unknown tool log incorrect: $CLEAN_OUTPUT"
    fi
}

echo "Running UI Utils Tests..."
test_log_tool_call

echo "------------------------------------------------"
echo "All tests passed successfully."
exit 0

