#!/bin/bash
# Test for lib/tools/fs/file_search.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
source "$BASE_DIR/lib/core/utils.sh"
source "$BASE_DIR/lib/tools/fs/file_search.sh"

# 3. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

cd "$TEST_DIR"

# Mocks
export CURRENT_TURN=1
export MAX_TURNS=10
RESP_FILE="response.json"
echo "[]" > "$RESP_FILE"

echo "Testing file_search (grep_definitions, find_file, get_tree, search_files)..."

mkdir -p src
echo "function hello() { return 'world'; }" > src/main.js
echo "def hello(): return 'world'" > src/main.py
echo "Just some text" > src/notes.txt

# --- Test search_files ---
INPUT_SEARCH=$(jq -n '{args: {query: "hello", path: "src"}}')
tool_search_files "$INPUT_SEARCH" "$RESP_FILE"
RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [[ "$RESULT" == *"src/main.js"* && "$RESULT" == *"src/main.py"* ]]; then
    pass "search_files found matches"
else
    fail "search_files failed: $RESULT"
fi

# --- Test grep_definitions ---
INPUT_GREP=$(jq -n '{args: {path: "src"}}')
tool_grep_definitions "$INPUT_GREP" "$RESP_FILE"
RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [[ "$RESULT" == *"src/main.js"* && "$RESULT" == *"function"* ]]; then
    pass "grep_definitions found function"
else
    fail "grep_definitions failed: $RESULT"
fi

# --- Test find_file ---
INPUT_FIND=$(jq -n '{args: {name_pattern: "*.txt", path: "src"}}')
tool_find_file "$INPUT_FIND" "$RESP_FILE"
RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [[ "$RESULT" == *"src/notes.txt"* && "$RESULT" != *"src/main.py"* ]]; then
    pass "find_file found pattern"
else
    fail "find_file failed: $RESULT"
fi

# --- Test get_tree ---
INPUT_TREE=$(jq -n '{args: {path: ".", max_depth: 2}}')
tool_get_tree "$INPUT_TREE" "$RESP_FILE"
RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [[ "$RESULT" == *"src"* && "$RESULT" == *"main.py"* ]]; then
    pass "get_tree listed structure"
else
    fail "get_tree failed: $RESULT"
fi

