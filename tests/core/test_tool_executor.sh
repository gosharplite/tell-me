#!/bin/bash
# Test for lib/core/tool_executor.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
source "$BASE_DIR/lib/core/tool_executor.sh"

# 3. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

cd "$TEST_DIR"

# Mocks
log_tool_call() { echo "LOG: $2 $1" > /dev/null; }

# Mock tool functions
tool_test_one() {
    local data="$1"
    local resp_file="$2"
    jq -n --arg name "test_one" '{functionResponse: {name: $name, response: {result: "Success 1"}}}' > "${resp_file}.part"
    jq --slurpfile new "${resp_file}.part" '. + $new' "$resp_file" > "${resp_file}.tmp" && mv "${resp_file}.tmp" "$resp_file"
}

tool_test_two() {
    local data="$1"
    local resp_file="$2"
    jq -n --arg name "test_two" '{functionResponse: {name: $name, response: {result: "Success 2"}}}' > "${resp_file}.part"
    jq --slurpfile new "${resp_file}.part" '. + $new' "$resp_file" > "${resp_file}.tmp" && mv "${resp_file}.tmp" "$resp_file"
}

echo "Running tool_executor tests..."

# --- Test Single Tool Call ---
RESP_FILE="response.json"
echo "[]" > "$RESP_FILE"

CANDIDATE='{"parts": [{"functionCall": {"name": "test_one", "args": {}}}]}'
execute_tools "$CANDIDATE" "$RESP_FILE"

COUNT=$(jq 'length' "$RESP_FILE")
NAME=$(jq -r '.[0].functionResponse.name' "$RESP_FILE")

if [ "$COUNT" -eq 1 ] && [ "$NAME" == "test_one" ]; then
    pass "Single tool call executed"
else
    fail "Single tool call failed: count=$COUNT, name=$NAME"
fi

# --- Test Multiple Tool Calls ---
echo "[]" > "$RESP_FILE"
CANDIDATE='{"parts": [{"functionCall": {"name": "test_one", "args": {}}}, {"functionCall": {"name": "test_two", "args": {}}}]}'
execute_tools "$CANDIDATE" "$RESP_FILE"

COUNT=$(jq 'length' "$RESP_FILE")
NAME2=$(jq -r '.[1].functionResponse.name' "$RESP_FILE")

if [ "$COUNT" -eq 2 ] && [ "$NAME2" == "test_two" ]; then
    pass "Multiple tool calls executed"
else
    fail "Multiple tool calls failed: count=$COUNT, name2=$NAME2"
fi

# --- Test Missing Tool ---
echo "[]" > "$RESP_FILE"
CANDIDATE='{"parts": [{"functionCall": {"name": "non_existent", "args": {}}}]}'
execute_tools "$CANDIDATE" "$RESP_FILE" 2>/dev/null

RESULT=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
if [[ "$RESULT" == *"Error: Tool not found"* ]]; then
    pass "Correctly handles non-existent tool"
else
    fail "Non-existent tool error missing: $RESULT"
fi

