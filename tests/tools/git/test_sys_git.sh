#!/bin/bash

# Test suite for System and Git tools:
# - execute_command
# - get_git_status
# - get_git_diff
# - get_git_log
# - get_git_commit
# - get_git_blame

# Exit on error
set -e

# Setup temp environment
TEST_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)

# --- OPTIMIZATION: Mock date to avoid process overhead ---
mkdir -p "$TEST_DIR/bin"
cat <<EOF > "$TEST_DIR/bin/date"
#!/bin/bash
echo "12:00:00"
EOF
chmod +x "$TEST_DIR/bin/date"
export PATH="$TEST_DIR/bin:$PATH"

cp -r lib "$TEST_DIR/"
cp lib/tools.json "$TEST_DIR/"

cd "$TEST_DIR"

# Source dependencies
source lib/core/utils.sh
source lib/tools/sys/sys_exec.sh
source lib/tools/git/git_status.sh
source lib/tools/git/git_diff.sh
source lib/tools/git/git_log.sh
source lib/tools/git/git_commit.sh
source lib/tools/git/git_blame.sh

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

# --- Test execute_command ---
echo "Testing execute_command..."

# Case 1: Whitelisted command (should succeed automatically)
# Optimization: Hardcoded JSON
INPUT_SAFE='{"args": {"command": "echo safe_check"}}'
tool_execute_command "$INPUT_SAFE" "$RESP_FILE" < /dev/null
RESULT=$(get_result)

if [[ "$RESULT" == *"Exit Code: 0"* && "$RESULT" == *"safe_check"* ]]; then
    pass "execute_command allowed whitelisted command (echo)"
else
    fail "execute_command failed to allow whitelisted command: $RESULT"
fi

# Case 1b: Diff command (Newly whitelisted)
echo "A" > fileA
echo "B" > fileB
INPUT_DIFF='{"args": {"command": "diff fileA fileB"}}'

set +e
tool_execute_command "$INPUT_DIFF" "$RESP_FILE" < /dev/null
RET_CODE=$?
set -e

if [ $RET_CODE -ne 0 ]; then
    fail "tool_execute_command crashed or returned non-zero code ($RET_CODE)"
fi

RESULT=$(get_result)
if [[ "$RESULT" == *"Exit Code: 1"* && "$RESULT" == *"< A"* ]]; then
    pass "execute_command allowed whitelisted command (diff)"
else
    fail "execute_command failed to allow whitelisted command (diff): $RESULT"
fi


# Case 2: Non-whitelisted command (should be denied in non-interactive)
INPUT_UNSAFE='{"args": {"command": "touch unsafe_file"}}'
tool_execute_command "$INPUT_UNSAFE" "$RESP_FILE" < /dev/null
RESULT=$(get_result)

# Case 3: Chained malicious command
INPUT_CHAINED='{"args": {"command": "ls -la; touch malicious_file"}}'
tool_execute_command "$INPUT_CHAINED" "$RESP_FILE" < /dev/null
RESULT=$(get_result)

if [[ "$RESULT" == *"User denied execution"* ]] || [[ "$RESULT" == *"Auto-denying"* ]]; then
    pass "execute_command denied chained malicious command (ls; touch)"
else
    fail "execute_command incorrectly allowed chained malicious command: $RESULT"
fi

if [[ "$RESULT" == *"User denied execution"* ]] || [[ "$RESULT" == *"Auto-denying"* ]]; then
    pass "execute_command denied unsafe command in non-interactive mode"
else
    fail "execute_command incorrectly allowed unsafe command: $RESULT"
fi

# --- Test Git Tools ---
echo "Testing Git Tools..."

# Initialize Git Repo (Slow, but necessary)
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

# 1. get_git_status (Empty/Untracked)
echo "file1" > file1.txt
INPUT_STATUS='{}'
tool_get_git_status "$INPUT_STATUS" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"??"*"file1.txt"* ]]; then
    pass "get_git_status detected untracked file"
else
    fail "get_git_status failed: $RESULT"
fi

# 2. get_git_diff (Unstaged)
echo "change" >> file1.txt
git add file1.txt
git commit -m "Initial commit" -q

echo "modification" >> file1.txt
INPUT_DIFF='{"args": {"staged": false}}'
tool_get_git_diff "$INPUT_DIFF" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"diff --git"* && "$RESULT" == *"+modification"* ]]; then
    pass "get_git_diff detected unstaged changes"
else
    fail "get_git_diff failed: $RESULT"
fi

# 3. get_git_diff (Staged)
git add file1.txt
INPUT_DIFF_STAGED='{"args": {"staged": true}}'
tool_get_git_diff "$INPUT_DIFF_STAGED" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"diff --git"* && "$RESULT" == *"+modification"* ]]; then
    pass "get_git_diff detected staged changes"
else
    fail "get_git_diff staged failed: $RESULT"
fi

# 5. get_git_commit
git commit -m "Second commit" -q
COMMIT_HASH=$(git rev-parse HEAD)
INPUT_COMMIT="{\"args\": {\"hash\": \"$COMMIT_HASH\"}}"
tool_get_git_commit "$INPUT_COMMIT" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Second commit"* && "$RESULT" == *"diff --git"* ]]; then
    pass "get_git_commit retrieved commit details"
else
    fail "get_git_commit failed: $RESULT"
fi

# 6. get_git_log
INPUT_LOG='{"args": {"limit": 5}}'
tool_get_git_log "$INPUT_LOG" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Second commit"* && "$RESULT" == *"Initial commit"* ]]; then
    pass "get_git_log retrieved history"
else
    fail "get_git_log failed: $RESULT"
fi

# 7. get_git_blame
INPUT_BLAME='{"args": {"filepath": "file1.txt"}}'
tool_get_git_blame "$INPUT_BLAME" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"file1.txt"* || "$RESULT" == *"file1"* ]]; then
    pass "get_git_blame retrieved blame info"
else
    fail "get_git_blame failed: $RESULT"
fi

# Cleanup
cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"

echo "All tests passed."

