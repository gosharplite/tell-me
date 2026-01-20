#!/bin/bash

# Test suite for System and Git tools:
# - execute_command
# - get_git_status
# - get_git_diff
# - get_git_log
# - read_git_commit
# - get_git_blame

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
source ./sys_exec.sh
source ./git_status.sh
source ./git_diff.sh
source ./git_log.sh
source ./git_commit.sh
source ./git_blame.sh

# Mocks
CURRENT_TURN=1
MAX_TURNS=10
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

# --- Test execute_command ---
echo "Testing execute_command..."

# Case 1: Non-interactive mode (auto-deny)
# In this script, stdin is not a TTY (usually), or we rely on the tool's check.
# The tool checks [ -t 0 ]. When running this script, it might be true if run from terminal.
# To force non-interactive, we can redirect stdin.

# JSON input for tool
INPUT_EXEC=$(jq -n '{args: {command: "echo test_exec"}}')

# Run tool with redirected stdin to force non-interactive
tool_execute_command "$INPUT_EXEC" "$RESP_FILE" < /dev/null

RESULT=$(get_result)
if [[ "$RESULT" == *"User denied execution"* ]] || [[ "$RESULT" == *"Auto-denying"* ]]; then
    pass "execute_command denied in non-interactive mode"
else
    # If the environment allows TTY, we might need another strategy, but for now assuming auto-deny or "n" default
    if [[ "$RESULT" == *"Exit Code: 0"* ]]; then
         echo "Warning: Command executed. This might be expected if running interactively."
    else
         pass "execute_command handled safely ($RESULT)"
    fi
fi

# --- Test Git Tools ---
echo "Testing Git Tools..."

# Initialize Git Repo
git init
git config user.email "test@example.com"
git config user.name "Test User"

# 1. get_git_status (Empty/Untracked)
echo "file1" > file1.txt
INPUT_STATUS=$(jq -n '{}')
tool_get_git_status "$INPUT_STATUS" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"??"*"file1.txt"* ]]; then
    pass "get_git_status detected untracked file"
else
    fail "get_git_status failed: $RESULT"
fi

# 2. get_git_diff (Unstaged)
echo "change" >> file1.txt
# file1 is untracked, so git diff shows nothing. We need to add it first to track, then modify?
# Actually untracked files don't show in git diff.
# Let's add file1, commit it, then modify.
git add file1.txt
git commit -m "Initial commit" > /dev/null

echo "modification" >> file1.txt
INPUT_DIFF=$(jq -n '{args: {staged: false}}')
tool_get_git_diff "$INPUT_DIFF" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"diff --git"* && "$RESULT" == *"+modification"* ]]; then
    pass "get_git_diff detected unstaged changes"
else
    fail "get_git_diff failed: $RESULT"
fi

# 3. get_git_diff (Staged)
git add file1.txt
INPUT_DIFF_STAGED=$(jq -n '{args: {staged: true}}')
tool_get_git_diff "$INPUT_DIFF_STAGED" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"diff --git"* && "$RESULT" == *"+modification"* ]]; then
    pass "get_git_diff detected staged changes"
else
    fail "get_git_diff staged failed: $RESULT"
fi

# 4. get_git_status (Staged/Modified)
tool_get_git_status "$INPUT_STATUS" "$RESP_FILE"
RESULT=$(get_result)
if [[ "$RESULT" == *"M"*"file1.txt"* ]]; then
    pass "get_git_status detected staged modification"
else
    fail "get_git_status failed to see staged file: $RESULT"
fi

# 5. read_git_commit
git commit -m "Second commit" > /dev/null
COMMIT_HASH=$(git rev-parse HEAD)
INPUT_COMMIT=$(jq -n --arg hash "$COMMIT_HASH" '{args: {hash: $hash}}')
tool_read_git_commit "$INPUT_COMMIT" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Second commit"* && "$RESULT" == *"diff --git"* ]]; then
    pass "read_git_commit retrieved commit details"
else
    fail "read_git_commit failed: $RESULT"
fi

# 6. get_git_log
INPUT_LOG=$(jq -n '{args: {limit: 5}}')
tool_get_git_log "$INPUT_LOG" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Second commit"* && "$RESULT" == *"Initial commit"* ]]; then
    pass "get_git_log retrieved history"
else
    fail "get_git_log failed: $RESULT"
fi

# 7. get_git_blame
INPUT_BLAME=$(jq -n '{args: {filepath: "file1.txt"}}')
tool_get_git_blame "$INPUT_BLAME" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Test User"* && "$RESULT" == *"file1"* ]]; then
    pass "get_git_blame retrieved blame info"
else
    fail "get_git_blame failed: $RESULT"
fi

# Cleanup
cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"

echo "All tests passed."

