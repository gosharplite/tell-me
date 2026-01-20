#!/bin/bash

# Test script for validate_syntax tool in lib/linter.sh
# Mocks the necessary environment and tests various file types

# --- Mock Environment ---
BASE_DIR="$(pwd)"
source "lib/utils.sh"
source "lib/linter.sh"

# Mock RESP_PARTS_FILE
RESP_PARTS_FILE="./test_resp_parts.json"

cleanup() {
    rm -f "$RESP_PARTS_FILE"
    rm -f test_valid.sh test_invalid.sh test_valid.py test_invalid.py test_valid.json test_invalid.json
}
trap cleanup EXIT

# --- Helper Function ---
run_tool() {
    local filepath="$1"
    
    # Initialize response file
    echo "[]" > "$RESP_PARTS_FILE"

    # Construct JSON argument
    local args_json
    args_json=$(jq -n --arg fp "$filepath" '{args: {filepath: $fp}}')
    
    # Run the tool
    tool_validate_syntax "$args_json" "$RESP_PARTS_FILE"
    
    # Read result
    if [ -f "$RESP_PARTS_FILE" ]; then
        # The output is a JSON array of response objects. We want to check the content.
        cat "$RESP_PARTS_FILE"
        rm "$RESP_PARTS_FILE"
    else
        echo "Error: No response file created."
    fi
}

echo "=== Starting Linter Tests ==="

# Test 1: Valid Bash
echo -e "\n--- Test 1: Valid Bash ---"
echo 'if [ 1 -eq 1 ]; then echo "ok"; fi' > test_valid.sh
OUTPUT=$(run_tool "test_valid.sh")
echo "$OUTPUT" | grep -q "PASS: Syntax is valid" && echo "PASS" || echo "FAIL"

# Test 2: Invalid Bash
echo -e "\n--- Test 2: Invalid Bash ---"
echo 'if [ 1 -eq 1 ]; then echo "oops"' > test_invalid.sh # Missing fi
OUTPUT=$(run_tool "test_invalid.sh")
echo "$OUTPUT" | grep -q "FAIL: Syntax errors found" && echo "PASS" || echo "FAIL"

# Test 3: Valid Python
echo -e "\n--- Test 3: Valid Python ---"
echo 'print("Hello")' > test_valid.py
OUTPUT=$(run_tool "test_valid.py")
echo "$OUTPUT" | grep -q "PASS: Syntax is valid" && echo "PASS" || echo "FAIL"

# Test 4: Invalid Python
echo -e "\n--- Test 4: Invalid Python ---"
echo 'print("Hello"' > test_invalid.py # Missing closing paren
OUTPUT=$(run_tool "test_invalid.py")
echo "$OUTPUT" | grep -q "FAIL: Syntax errors found" && echo "PASS" || echo "FAIL"

# Test 5: Valid JSON
echo -e "\n--- Test 5: Valid JSON ---"
echo '{"key": "value"}' > test_valid.json
OUTPUT=$(run_tool "test_valid.json")
echo "$OUTPUT" | grep -q "PASS: Syntax is valid" && echo "PASS" || echo "FAIL"

# Test 6: Invalid JSON
echo -e "\n--- Test 6: Invalid JSON ---"
echo '{"key": "value"' > test_invalid.json # Missing closing brace
OUTPUT=$(run_tool "test_invalid.json")
echo "$OUTPUT" | grep -q "FAIL: Syntax errors found" && echo "PASS" || echo "FAIL"

echo -e "\n=== Tests Complete ==="

