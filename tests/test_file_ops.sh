#!/bin/bash

# Test suite for File Operations tools:
# - rollback_file
# - move_file
# - delete_file
# - list_files
# - get_file_info
# - read_file

# Exit on error
set -e

# Setup temp environment
TEST_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)
cp lib/*.sh "$TEST_DIR/"
cp lib/tools.json "$TEST_DIR/"

cd "$TEST_DIR"

# Source dependencies
source ./utils.sh
source ./file_edit.sh
source ./file_search.sh
source ./read_file.sh

# Mocks
export CURRENT_TURN=1
export MAX_TURNS=10
RESP_FILE="response.json"
echo "[]" > "$RESP_FILE"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS:${NC} $1"; }
fail() { echo -e "${RED}FAIL:${NC} $1"; exit 1; }

# Helper to read result from response.json
get_result() {
    jq -r '.[-1].functionResponse.response.result' "$RESP_FILE"
}

# --- Test rollback_file ---
echo "Testing rollback_file..."

# To test rollback, we need `backup_file` and `restore_backup` to be defined.
# They are typically in `utils.sh` or `scratchpad.sh` but `file_edit.sh` sources nothing.
# Let's check `lib/file_edit.sh` calls `backup_file` if defined.
# We need to mock these functions.

BACKUP_DIR=".backups"
mkdir -p "$BACKUP_DIR"

backup_file() {
    cp "$1" "$BACKUP_DIR/$(basename "$1").bak"
}

restore_backup() {
    local FILE="$1"
    local BAK="$BACKUP_DIR/$(basename "$FILE").bak"
    if [ -f "$BAK" ]; then
        cp "$BAK" "$FILE"
        return 0
    else
        return 1
    fi
}
export -f backup_file
export -f restore_backup

# Create file and backup
echo "Original Content" > test_rollback.txt
backup_file "test_rollback.txt"
echo "New Content" > test_rollback.txt

INPUT_ROLLBACK=$(jq -n '{args: {filepath: "test_rollback.txt"}}')
tool_rollback_file "$INPUT_ROLLBACK" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Success: Reverted"* ]] && grep -q "Original Content" test_rollback.txt; then
    pass "rollback_file reverted content"
else
    fail "rollback_file failed: $RESULT"
fi


# --- Test move_file ---
echo "Testing move_file..."

echo "Move Me" > src_file.txt
INPUT_MOVE=$(jq -n '{args: {source_path: "src_file.txt", dest_path: "dst_file.txt"}}')
tool_move_file "$INPUT_MOVE" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Success: Moved"* ]] && [ -f "dst_file.txt" ] && [ ! -f "src_file.txt" ]; then
    pass "move_file moved file"
else
    fail "move_file failed: $RESULT"
fi

# Security check for move
INPUT_MOVE_UNSAFE=$(jq -n '{args: {source_path: "/etc/passwd", dest_path: "passwd.txt"}}')
tool_move_file "$INPUT_MOVE_UNSAFE" "$RESP_FILE"
RESULT=$(get_result)
if [[ "$RESULT" == *"Security violation"* ]]; then
    pass "move_file blocked unsafe path"
else
    fail "move_file failed security check: $RESULT"
fi


# --- Test delete_file ---
echo "Testing delete_file..."

echo "Delete Me" > del_file.txt
INPUT_DEL=$(jq -n '{args: {filepath: "del_file.txt"}}')
tool_delete_file "$INPUT_DEL" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Success: Deleted"* ]] && [ ! -f "del_file.txt" ]; then
    pass "delete_file deleted file"
else
    fail "delete_file failed: $RESULT"
fi

# Safety check (delete CWD)
INPUT_DEL_CWD=$(jq -n '{args: {filepath: "."}}')
tool_delete_file "$INPUT_DEL_CWD" "$RESP_FILE"
RESULT=$(get_result)
if [[ "$RESULT" == *"Error: Cannot delete current working directory"* ]]; then
     pass "delete_file blocked CWD deletion"
else
     fail "delete_file failed CWD safety: $RESULT"
fi

# --- Test list_files ---
echo "Testing list_files..."
mkdir -p subdir
touch subdir/a.txt subdir/b.txt

INPUT_LIST=$(jq -n '{args: {path: "subdir"}}')
tool_list_files "$INPUT_LIST" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"a.txt"* && "$RESULT" == *"b.txt"* ]]; then
    pass "list_files listed contents"
else
    fail "list_files failed: $RESULT"
fi


# --- Test get_file_info ---
echo "Testing get_file_info..."

echo "Info" > info.txt
INPUT_INFO=$(jq -n '{args: {filepath: "info.txt"}}')
tool_get_file_info "$INPUT_INFO" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Path: info.txt"* && "$RESULT" == *"Type:"* ]]; then
    pass "get_file_info returned metadata"
else
    fail "get_file_info failed: $RESULT"
fi


# --- Test read_file ---
echo "Testing read_file..."

# Generate file with 10 lines
seq 1 10 > numbers.txt

# Case 1: Read all (or start to end)
INPUT_READ=$(jq -n '{args: {filepath: "numbers.txt"}}')
tool_read_file "$INPUT_READ" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"1"* && "$RESULT" == *"10"* ]]; then
    pass "read_file read all lines"
else
    fail "read_file failed full read: $RESULT"
fi

# Case 2: Read range
INPUT_READ_RANGE=$(jq -n '{args: {filepath: "numbers.txt", start_line: 4, end_line: 6}}')
tool_read_file "$INPUT_READ_RANGE" "$RESP_FILE"
RESULT=$(get_result)

# Expected: 4\n5\n6
LINES=$(echo "$RESULT" | wc -l)
if [[ "$RESULT" == *"4"* && "$RESULT" == *"6"* ]] && [[ "$RESULT" != *"3"* ]] && [[ "$RESULT" != *"7"* ]]; then
    pass "read_file read range correctly"
else
    fail "read_file failed range: $RESULT"
fi

# Cleanup
cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"

echo "All tests passed."

