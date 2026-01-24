#!/bin/bash

# Test script for validate_syntax tool in lib/linter.sh

# Setup isolated environment
TEST_DIR=$(mktemp -d)
RESP_PARTS_FILE="$TEST_DIR/test_resp_parts.json"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Copy lib to use locally
cp -r lib "$TEST_DIR/"
cd "$TEST_DIR"

source "lib/core/utils.sh"
source "lib/linter.sh"

# --- Helper Function ---
run_tool() {
    local filepath="$1"
    
    echo "[]" > "$RESP_PARTS_FILE"
    local args_json=$(jq -n --arg fp "$filepath" '{args: {filepath: $fp}}')
    
    tool_validate_syntax "$args_json" "$RESP_PARTS_FILE"
    
    if [ -f "$RESP_PARTS_FILE" ]; then
        cat "$RESP_PARTS_FILE"
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
echo 'if [ 1 -eq 1 ]; then echo "oops"' > test_invalid.sh 
OUTPUT=$(run_tool "test_invalid.sh")
echo "$OUTPUT" | grep -q "FAIL: Syntax errors found" && echo "PASS" || echo "FAIL"

# Test 3: Valid Python
echo -e "\n--- Test 3: Valid Python ---"
echo 'print("Hello")' > test_valid.py
OUTPUT=$(run_tool "test_valid.py")
echo "$OUTPUT" | grep -q "PASS: Syntax is valid" && echo "PASS" || echo "FAIL"

# Test 4: Invalid Python
echo -e "\n--- Test 4: Invalid Python ---"
echo 'print("Hello"' > test_invalid.py 
OUTPUT=$(run_tool "test_invalid.py")
echo "$OUTPUT" | grep -q "FAIL: Syntax errors found" && echo "PASS" || echo "FAIL"

# Test 5: Valid JSON
echo -e "\n--- Test 5: Valid JSON ---"
echo '{"key": "value"}' > test_valid.json
OUTPUT=$(run_tool "test_valid.json")
echo "$OUTPUT" | grep -q "PASS: Syntax is valid" && echo "PASS" || echo "FAIL"

# Test 6: Invalid JSON
echo -e "\n--- Test 6: Invalid JSON ---"
echo '{"key": "value"' > test_invalid.json
OUTPUT=$(run_tool "test_invalid.json")
echo "$OUTPUT" | grep -q "FAIL: Syntax errors found" && echo "PASS" || echo "FAIL"

echo -e "\n=== Tests Complete ==="
