#!/bin/bash

# Test script for manage_tasks tool in lib/task_manager.sh

# Setup isolated environment
TEST_DIR=$(mktemp -d)
RESP_PARTS_FILE="$TEST_DIR/test_resp_parts.json"
TASKS_DIR="$TEST_DIR/test_output"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Mock Environment
BASE_DIR="$(pwd)"
source "lib/utils.sh"
source "lib/task_manager.sh"

# Mock Global 'file' variable to simulate agent environment
export file="$TASKS_DIR/mock_history.json"
TASKS_FILE="$TASKS_DIR/mock_history.tasks.json"

mkdir -p "$TASKS_DIR"

# --- Helper Function ---
run_tool() {
    local json_args="$1"
    
    echo "[]" > "$RESP_PARTS_FILE"

    tool_manage_tasks "$json_args" "$RESP_PARTS_FILE"
    
    if [ -f "$RESP_PARTS_FILE" ]; then
        cat "$RESP_PARTS_FILE"
        rm "$RESP_PARTS_FILE"
    else
        echo "Error: No response file created."
    fi
}

echo "=== Starting Task Manager Tests ==="

# Test 1: Add Task
echo -e "\n--- Test 1: Add Task ---"
ARGS=$(jq -n '{args: {action: "add", content: "Buy milk"}}')
OUTPUT=$(run_tool "$ARGS")
echo "$OUTPUT" | grep -q "Task added with ID: 1" && echo "PASS" || echo "FAIL"

if [ -f "$TASKS_FILE" ]; then
    echo "File created at $TASKS_FILE: PASS"
else
    echo "File NOT created at $TASKS_FILE: FAIL"
fi

# Test 2: List Tasks
echo -e "\n--- Test 2: List Tasks ---"
ARGS=$(jq -n '{args: {action: "list"}}')
OUTPUT=$(run_tool "$ARGS")
echo "$OUTPUT" | grep -q "Buy milk" && echo "PASS" || echo "FAIL"

# Test 3: Update Task
echo -e "\n--- Test 3: Update Task ---"
ARGS=$(jq -n '{args: {action: "update", task_id: 1, status: "completed"}}')
OUTPUT=$(run_tool "$ARGS")
echo "$OUTPUT" | grep -q "Task 1 updated" && echo "PASS" || echo "FAIL"

# Verify update
ARGS=$(jq -n '{args: {action: "list"}}')
OUTPUT=$(run_tool "$ARGS")
echo "$OUTPUT" | grep -q "[completed]" && echo "PASS" || echo "FAIL"

# Test 4: Delete Task
echo -e "\n--- Test 4: Delete Task ---"
ARGS=$(jq -n '{args: {action: "delete", task_id: 1}}')
OUTPUT=$(run_tool "$ARGS")
echo "$OUTPUT" | grep -q "Task 1 deleted" && echo "PASS" || echo "FAIL"

# Test 5: Clear Tasks
echo -e "\n--- Test 5: Clear Tasks ---"
# Add one first
ARGS=$(jq -n '{args: {action: "add", content: "Temp"}}')
run_tool "$ARGS" > /dev/null

ARGS=$(jq -n '{args: {action: "clear"}}')
OUTPUT=$(run_tool "$ARGS")
echo "$OUTPUT" | grep -q "All tasks cleared" && echo "PASS" || echo "FAIL"

echo -e "\n=== Tests Complete ==="

# Test 6: Global Scope
echo -e "\n--- Test 6: Global Scope ---"
export AIT_HOME="$TEST_DIR"
GLOBAL_TASKS_FILE="$TEST_DIR/output/global-tasks.json"
mkdir -p "$TEST_DIR/output"

ARGS=$(jq -n '{args: {action: "add", content: "Global task", scope: "global"}}')
OUTPUT=$(run_tool "$ARGS")

if [ -f "$GLOBAL_TASKS_FILE" ] && grep -q "Global task" "$GLOBAL_TASKS_FILE"; then
    echo "PASS: Global tasks file created and task added"
else
    echo "FAIL: Global tasks file check failed"
fi

