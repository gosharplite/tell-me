#!/bin/bash

# Test script for manage_tasks tool in lib/task_manager.sh
# Mocks the necessary environment

# --- Mock Environment ---
BASE_DIR="$(pwd)"
source "lib/utils.sh"
source "lib/task_manager.sh"

# Mock RESP_PARTS_FILE
RESP_PARTS_FILE="./test_resp_parts.json"

# Mock Global 'file' variable to simulate agent environment
export file="./test_output/mock_history.json"
TASKS_FILE="./test_output/mock_history.tasks.json"

# Ensure clean slate
rm -rf "./test_output"
mkdir -p "./test_output"

cleanup() {
    rm -f "$RESP_PARTS_FILE"
    rm -rf "./test_output"
}
trap cleanup EXIT

# --- Helper Function ---
run_tool() {
    local json_args="$1"
    
    # Initialize response file
    echo "[]" > "$RESP_PARTS_FILE"

    # Run the tool
    tool_manage_tasks "$json_args" "$RESP_PARTS_FILE"
    
    # Read result
    if [ -f "$RESP_PARTS_FILE" ]; then
        cat "$RESP_PARTS_FILE"
        rm "$RESP_PARTS_FILE"
    else
        echo "Error: No response file created."
    fi
}

echo "=== Starting Task Manager Tests ==="

# Test 1: Add Task (Should create directory and file)
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

