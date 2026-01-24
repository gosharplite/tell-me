#!/bin/bash

# Test script for manage_tasks tool in lib/tools/sys/task_manager.sh

# Setup isolated environment
TEST_DIR=$(mktemp -d)
RESP_PARTS_FILE="$TEST_DIR/test_resp_parts.json"
TASKS_DIR="$TEST_DIR/test_output"

# --- OPTIMIZATION: Mock logging to avoid process overhead ---
get_log_timestamp() { echo "[12:00:00]"; }
get_log_duration() { echo "[12:00:00]"; }

# Mock Environment
BASE_DIR="$(pwd)"
source "lib/core/utils.sh"
source "lib/tools/sys/task_manager.sh"

# Mock Global 'file' variable to simulate agent environment
export file="$TASKS_DIR/mock_history.json"
TASKS_FILE="$TASKS_DIR/mock_history.tasks.json"

mkdir -p "$TASKS_DIR"

# --- Helper Function ---
run_tool() {
    local json_args="$1"
    echo "[]" > "$RESP_PARTS_FILE"
    tool_manage_tasks "$json_args" "$RESP_PARTS_FILE"
}

echo "=== Starting Task Manager Tests ==="

# Test 1: Add Task
echo -e "\n--- Test 1: Add Task ---"
OUTPUT=$(run_tool '{"args": {"action": "add", "content": "Buy milk"}}')
echo "$OUTPUT" | grep -q "Task added with ID: 1" && echo "PASS" || echo "FAIL"

if [ -f "$TASKS_FILE" ]; then
    echo "File created at $TASKS_FILE: PASS"
else
    echo "File NOT created at $TASKS_FILE: FAIL"
fi

# Test 2: List Tasks
echo -e "\n--- Test 2: List Tasks ---"
OUTPUT=$(run_tool '{"args": {"action": "list"}}')
echo "$OUTPUT" | grep -q "Buy milk" && echo "PASS" || echo "FAIL"

# Test 3: Update Task
echo -e "\n--- Test 3: Update Task ---"
OUTPUT=$(run_tool '{"args": {"action": "update", "task_id": 1, "status": "completed"}}')
echo "$OUTPUT" | grep -q "Task 1 updated" && echo "PASS" || echo "FAIL"

# Verify update
OUTPUT=$(run_tool '{"args": {"action": "list"}}')
echo "$OUTPUT" | grep -q "\[completed\]" && echo "PASS" || echo "FAIL"

# Test 4: Delete Task
echo -e "\n--- Test 4: Delete Task ---"
OUTPUT=$(run_tool '{"args": {"action": "delete", "task_id": 1}}')
echo "$OUTPUT" | grep -q "Task 1 deleted" && echo "PASS" || echo "FAIL"

# Test 5: Clear Tasks
echo -e "\n--- Test 5: Clear Tasks ---"
# Add one first
run_tool '{"args": {"action": "add", "content": "Temp"}}' > /dev/null
OUTPUT=$(run_tool '{"args": {"action": "clear"}}')
echo "$OUTPUT" | grep -q "All tasks cleared" && echo "PASS" || echo "FAIL"

echo -e "\n=== Tests Complete ==="

# Test 6: Global Scope
echo -e "\n--- Test 6: Global Scope ---"
export AIT_HOME="$TEST_DIR"
GLOBAL_TASKS_FILE="$TEST_DIR/output/global-tasks.json"
mkdir -p "$TEST_DIR/output"

OUTPUT=$(run_tool '{"args": {"action": "add", "content": "Global task", "scope": "global"}}')

if [ -f "$GLOBAL_TASKS_FILE" ] && grep -q "Global task" "$GLOBAL_TASKS_FILE"; then
    echo "PASS: Global tasks file created and task added"
else
    echo "FAIL: Global tasks file check failed"
fi


# Test 7: Special Characters in Content (Regression for commit a19f3ba)
echo -e "\n--- Test 7: Special Characters in Content ---"
TRICKY_CONTENT='Finish the "Project" & '\''fix'\'' it; (maybe) $100%!'
# We still need jq here for safe escaping
ARGS=$(jq -n --arg content "$TRICKY_CONTENT" '{args: {action: "add", content: $content}}')
OUTPUT=$(run_tool "$ARGS")
TASK_ID=$(echo "$OUTPUT" | grep -o "ID: [0-9]*" | head -n 1 | cut -d' ' -f2)

# Now update it with another tricky string
NEW_TRICKY_CONTENT='Updated "Task" with `backticks` and \backslashes\'
ARGS=$(jq -n --arg id "$TASK_ID" --arg content "$NEW_TRICKY_CONTENT" '{args: {action: "update", task_id: ($id|tonumber), content: $content}}')
OUTPUT=$(run_tool "$ARGS")

# Verify the content is stored correctly without shell mangling
ACTUAL_CONTENT=$(jq -r --arg id "$TASK_ID" ".[] | select(.id == (\$id|tonumber)) | .content" "$TASKS_FILE")
if [ "$ACTUAL_CONTENT" == "$NEW_TRICKY_CONTENT" ]; then
    echo "PASS: Special characters preserved"
else
    echo "FAIL: Content mismatch!"
    echo "Expected: $NEW_TRICKY_CONTENT"
    echo "Actual:   $ACTUAL_CONTENT"
    exit 1
fi

