#!/bin/bash
# Test for lib/tools/sys/sys_exec.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
source "$BASE_DIR/lib/core/utils.sh"
source "$BASE_DIR/lib/tools/sys/sys_exec.sh"

# 3. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

cd "$TEST_DIR"

# Mocks
export CURRENT_TURN=1
export MAX_TURNS=10
RESP_FILE="response.json"
echo "[]" > "$RESP_FILE"

# Mock UI functions used in sys_exec.sh
get_log_timestamp() { echo "[00:00:00]"; }
get_log_duration() { echo "[00:00:00]"; }

echo "Running sys_exec tests..."

# --- Test Safe Command Auto-Approval ---
echo "Testing auto-approval of safe commands..."
INPUT='{"args": {"command": "ls -la"}}'
# In non-interactive mode (no tty), it would deny if not safe.
# But "ls" is in the safe list.
tool_execute_command "$INPUT" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")
if [[ "$RESULT" == *"Exit Code: 0"* && "$RESULT" == *"Output:"* ]]; then
    pass "Safe command auto-approved and executed"
else
    fail "Safe command failed: $RESULT"
fi

# --- Test Unsafe Command Rejection (Non-Interactive) ---
echo "Testing rejection of unsafe commands (non-interactive)..."
echo "[]" > "$RESP_FILE"
INPUT_UNSAFE='{"args": {"command": "rm -rf /"}}'
# Ensure we are NOT in a TTY (standard for these tests)
tool_execute_command "$INPUT_UNSAFE" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")
if [[ "$RESULT" == *"User denied execution"* ]]; then
    pass "Unsafe command correctly rejected in non-interactive mode"
else
    fail "Unsafe command not rejected: $RESULT"
fi

# --- Test Command Output Capture ---
echo "Testing output capture..."
echo "[]" > "$RESP_FILE"
INPUT_OUT='{"args": {"command": "echo \"Hello World\""}}'
tool_execute_command "$INPUT_OUT" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")
if [[ "$RESULT" == *"Hello World"* ]]; then
    pass "Command output captured correctly"
else
    fail "Command output capture failed: $RESULT"
fi

# --- Test Non-Zero Exit Code ---
echo "Testing exit code capture..."
echo "[]" > "$RESP_FILE"
INPUT_ERR='{"args": {"command": "ls non_existent_file_xyz"}}'
tool_execute_command "$INPUT_ERR" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")
if [[ "$RESULT" == *"Exit Code:"* ]] && [[ "$RESULT" != *"Exit Code: 0"* ]]; then
    pass "Non-zero exit code captured correctly"
else
    fail "Non-zero exit code capture failed: $RESULT"
fi

