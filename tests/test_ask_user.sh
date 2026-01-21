#!/bin/bash

# Test script for lib/ask_user.sh

# Setup environment
mkdir -p output
export CURRENT_TURN=0
export MAX_TURNS=10
RESP_FILE="./output/test_resp.json"
echo "[]" > "$RESP_FILE"

# Mock the read builtin
# This prevents the script from pausing for user input
read() {
    # The last argument is the variable name to populate
    local var_name="${!#}"
    
    # Simulate user input
    # We can customize this based on the prompt if needed
    local prompt_val="Test Answer"
    
    # Assign the value to the variable name in the caller's scope
    eval "$var_name='$prompt_val'"
source lib/utils.sh
}

# Source the function under test
# We do this AFTER mocking read so the function uses our mock?
# Actually, function definition order matters. If source defines tool_ask_user,
# and tool_ask_user calls 'read', bash looks up 'read' at runtime.
# So if we define 'read' function here, it should shadow the builtin.
source lib/ask_user.sh

test_normal_usage() {
    echo "------------------------------------------------"
    echo "Running test_normal_usage..."
    local ARGS='{"args": {"question": "How are you?"}}'
    
    # Reset output
    echo "[]" > "$RESP_FILE"
    
    # Call function
    tool_ask_user "$ARGS" "$RESP_FILE"
    
    # Check result content
    if grep -q "Test Answer" "$RESP_FILE"; then
        echo "PASS: Output contains user answer"
    else
        echo "FAIL: Output missing user answer"
        cat "$RESP_FILE"
        return 1
    fi
    
    # Validate JSON structure
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
    # Set condition for warning
    export CURRENT_TURN=9
    export MAX_TURNS=10
    local ARGS='{"args": {"question": "Last turn?"}}'
    
    # Reset output
    echo "[]" > "$RESP_FILE"
    
    tool_ask_user "$ARGS" "$RESP_FILE"
    
    # Check for warning text
    if grep -q "SYSTEM WARNING" "$RESP_FILE"; then
        echo "PASS: Warning message present"
    else
        echo "FAIL: Warning message missing"
        cat "$RESP_FILE"
        return 1
    fi
    
    # Check for original answer too
    if grep -q "Test Answer" "$RESP_FILE"; then
        echo "PASS: User answer still present"
    else
        echo "FAIL: User answer missing in warning mode"
        return 1
    fi
}

# Run tests
FAILED=0
test_normal_usage || FAILED=1
test_warning_usage || FAILED=1

# Cleanup
rm -f "$RESP_FILE"

if [ $FAILED -eq 0 ]; then
    echo "------------------------------------------------"
    echo "All tests passed successfully."
    exit 0
else
    echo "------------------------------------------------"
    echo "Some tests failed."
    exit 1
fi