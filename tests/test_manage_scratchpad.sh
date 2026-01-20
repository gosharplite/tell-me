#!/bin/bash

# Test script for lib/scratchpad.sh

# Setup environment
mkdir -p output
export CURRENT_TURN=0
export MAX_TURNS=10
RESP_FILE="./output/test_resp.json"
echo "[]" > "$RESP_FILE"

# Mock the 'file' global variable which determines the scratchpad path
export file="./output/session.yaml"
SCRATCHPAD_PATH="./output/session.scratchpad.md"

# Source the function under test
source lib/scratchpad.sh

# Cleanup before starting
rm -f "$SCRATCHPAD_PATH"

test_write() {
    echo "------------------------------------------------"
    echo "Running test_write..."
    local ARGS='{"args": {"action": "write", "content": "Initial Content"}}'
    
    echo "[]" > "$RESP_FILE"
    tool_manage_scratchpad "$ARGS" "$RESP_FILE"
    
    if grep -q "Scratchpad overwritten" "$RESP_FILE"; then
         echo "PASS: Response indicates success"
    else
         echo "FAIL: Response missing success message"
         cat "$RESP_FILE"
         return 1
    fi
    
    if [ "$(cat "$SCRATCHPAD_PATH")" == "Initial Content" ]; then
        echo "PASS: Content written correctly"
    else
        echo "FAIL: Content mismatch"
        cat "$SCRATCHPAD_PATH"
        return 1
    fi
}

test_read() {
    echo "------------------------------------------------"
    echo "Running test_read..."
    local ARGS='{"args": {"action": "read"}}'
    
    echo "[]" > "$RESP_FILE"
    tool_manage_scratchpad "$ARGS" "$RESP_FILE"
    
    local JSON_RESULT=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    if [ "$JSON_RESULT" == "Initial Content" ]; then
        echo "PASS: Read correct content"
    else
        echo "FAIL: Read failed or mismatch. Got: '$JSON_RESULT'"
        return 1
    fi
}

test_append() {
    echo "------------------------------------------------"
    echo "Running test_append..."
    local ARGS='{"args": {"action": "append", "content": " - Appended Line"}}'
    
    echo "[]" > "$RESP_FILE"
    tool_manage_scratchpad "$ARGS" "$RESP_FILE"
    
    local EXPECTED="Initial Content

 - Appended Line"
 
    if [ "$(cat "$SCRATCHPAD_PATH")" == "$EXPECTED" ]; then
        echo "PASS: Content appended correctly"
    else
        echo "FAIL: Append mismatch"
        echo "Expected:"
        echo "$EXPECTED"
        echo "Got:"
        cat "$SCRATCHPAD_PATH"
        return 1
    fi
}

test_clear() {
    echo "------------------------------------------------"
    echo "Running test_clear..."
    local ARGS='{"args": {"action": "clear"}}'
    
    echo "[]" > "$RESP_FILE"
    tool_manage_scratchpad "$ARGS" "$RESP_FILE"
    
    if [ -s "$SCRATCHPAD_PATH" ] && [ "$(cat "$SCRATCHPAD_PATH" | tr -d '[:space:]')" == "" ]; then
        echo "PASS: Scratchpad cleared (empty or just newline)"
    else
        echo "FAIL: Scratchpad not cleared"
        ls -l "$SCRATCHPAD_PATH"
        cat "$SCRATCHPAD_PATH"
        return 1
    fi
}

test_read_empty() {
    echo "------------------------------------------------"
    echo "Running test_read_empty..."
    local ARGS='{"args": {"action": "read"}}'
    
    echo "[]" > "$RESP_FILE"
    tool_manage_scratchpad "$ARGS" "$RESP_FILE"
    
    local JSON_RESULT=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    if [[ "$JSON_RESULT" == *"[Scratchpad is empty]"* ]]; then
        echo "PASS: Detected empty scratchpad"
    else
        echo "FAIL: Did not detect empty scratchpad. Got: $JSON_RESULT"
        return 1
    fi
}

# Run tests
FAILED=0
test_write || FAILED=1
test_read || FAILED=1
test_append || FAILED=1
test_clear || FAILED=1
test_read_empty || FAILED=1

# Cleanup
rm -f "$RESP_FILE" "$SCRATCHPAD_PATH"

if [ $FAILED -eq 0 ]; then
    echo "------------------------------------------------"
    echo "All manage_scratchpad tests passed."
    exit 0
else
    echo "------------------------------------------------"
    echo "Some manage_scratchpad tests failed."
    exit 1
fi