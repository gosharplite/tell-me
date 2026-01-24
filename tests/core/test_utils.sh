#!/bin/bash
# Test for lib/core/utils.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
source "$BASE_DIR/lib/core/utils.sh"

# 3. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

cd "$TEST_DIR"

echo "Running utils tests..."

# --- Test check_path_safety ---
echo "Testing check_path_safety..."
# Current directory is $TEST_DIR
mkdir -p internal
touch internal/file.txt

if [[ "$(check_path_safety "internal/file.txt")" == "true" ]]; then
    pass "Internal path is safe"
else
    fail "Internal path rejected"
fi

if [[ "$(check_path_safety "../test_utils.sh")" == "false" ]]; then
    pass "Parent path is unsafe"
else
    fail "Parent path accepted"
fi

if [[ "$(check_path_safety "/etc/passwd")" == "false" ]]; then
    pass "Absolute outside path is unsafe"
else
    fail "Absolute outside path accepted"
fi

# --- Test update_history_file ---
echo "Testing update_history_file..."
HIST_FILE="history.json"
echo '{"messages": []}' > "$HIST_FILE"

MSG='{"role": "user", "parts": [{"text": "Hello"}]}'
update_history_file "$MSG" "$HIST_FILE"

COUNT=$(jq '.messages | length' "$HIST_FILE")
if [ "$COUNT" -eq 1 ]; then
    pass "Message appended to history"
else
    fail "Message not appended: count=$COUNT"
fi

# Invalid message (empty parts)
INVALID_MSG='{"role": "user", "parts": []}'
update_history_file "$INVALID_MSG" "$HIST_FILE"
COUNT=$(jq '.messages | length' "$HIST_FILE")
if [ "$COUNT" -eq 1 ]; then
    pass "Empty parts message rejected"
else
    fail "Empty parts message accepted"
fi

# --- Test backup and restore ---
echo "Testing backup/restore..."
# Override BACKUP_DIR for isolation
export BACKUP_DIR="$TEST_DIR/backups"
mkdir -p "$BACKUP_DIR"

echo "Original Content" > target.txt
backup_file "target.txt"

echo "Modified Content" > target.txt
restore_backup "target.txt"

if [[ "$(cat target.txt)" == "Original Content" ]]; then
    pass "Backup and restore successful"
else
    fail "Restore failed: $(cat target.txt)"
fi

# --- Test log utilities ---
echo "Testing log timestamp/duration..."
TS=$(get_log_timestamp)
if [[ "$TS" =~ ^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]$ ]]; then
    pass "Log timestamp format correct"
else
    fail "Log timestamp format incorrect: $TS"
fi

DUR=$(get_log_duration)
if [[ "$DUR" == "$TS" || "$DUR" =~ ^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]$ ]]; then
    pass "Log duration format correct"
else
    fail "Log duration format incorrect: $DUR"
fi

