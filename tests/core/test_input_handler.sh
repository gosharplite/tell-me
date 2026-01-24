#!/bin/bash
# Test for lib/core/input_handler.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
source "$BASE_DIR/lib/core/input_handler.sh"

# 3. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

cd "$TEST_DIR"

echo "Running input_handler tests..."

# Test 1: Simple text prompt
RESULT=$(process_user_input "Hello World")
EXPECTED_TEXT=$(echo "$RESULT" | jq -r '.parts[0].text')
if [[ "$EXPECTED_TEXT" == "Hello World" ]]; then
    pass "Text prompt processing"
else
    fail "Text prompt failed: $EXPECTED_TEXT"
fi

# Test 2: STDIN data (piped)
# We mock STDIN using a subshell or file redirection
RESULT=$(echo "System Logs" | process_user_input "Check these")
EXPECTED_TEXT=$(echo "$RESULT" | jq -r '.parts[0].text')
# The input_handler adds \n\n between prompt and stdin
if [[ "$EXPECTED_TEXT" == "Check these\n\nSystem Logs" ]]; then
    pass "STDIN data processing"
else
    fail "STDIN data failed: $EXPECTED_TEXT"
fi

# Test 3: JSON Structure verification
ROLE=$(echo "$RESULT" | jq -r '.role')
if [[ "$ROLE" == "user" ]]; then
    pass "JSON role correct"
else
    fail "JSON role incorrect: $ROLE"
fi

# Test 4: Error on empty input
if ! process_user_input "" 2>/dev/null; then
    pass "Error on empty input"
else
    fail "Failed to error on empty input"
fi

