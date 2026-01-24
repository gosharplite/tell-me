#!/bin/bash
# Test for lib/core/session_manager.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
source "$BASE_DIR/lib/core/session_manager.sh"

# Mock backup_file as it is used in session_manager.sh
backup_file() { echo "MOCK BACKUP: $1" > /dev/null; }

# 3. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

cd "$TEST_DIR"

echo "Running session_manager tests..."

# Test 1: Thinking level mapping
while read -r budget level; do
    RESULT=$(get_thinking_config "$budget")
    if [[ "$RESULT" == "$level $budget" ]]; then
        pass "Thinking config: $budget -> $level"
    else
        fail "Thinking config failed: $budget -> expected $level, got $RESULT"
    fi
done <<EOF
1000 MINIMAL
2000 LOW
4000 LOW
5000 MEDIUM
8000 MEDIUM
9000 HIGH
EOF

# Test 2: Session Setup
# Create a fake config file
CONFIG_FILE="$TEST_DIR/test-session.config.yaml"
touch "$CONFIG_FILE"

HIST_FILE=$(setup_session "$CONFIG_FILE" "$TEST_DIR")

if [[ "$HIST_FILE" == "$TEST_DIR/output/test-session.json" ]]; then
    pass "History file path correct"
else
    fail "History file path incorrect: $HIST_FILE"
fi

if [[ -f "$HIST_FILE" ]]; then
    MESSAGES=$(jq '.messages | length' "$HIST_FILE")
    if [[ "$MESSAGES" == "0" ]]; then
        pass "History file initialized with empty messages"
    else
        fail "History file initialized incorrectly"
    fi
else
    fail "History file not created"
fi

# Test 3: Session Setup with existing history
echo '{"messages": [{"role": "user"}]}' > "$HIST_FILE"
setup_session "$CONFIG_FILE" "$TEST_DIR" > /dev/null
MESSAGES=$(jq '.messages | length' "$HIST_FILE")
if [[ "$MESSAGES" == "1" ]]; then
    pass "Existing history preserved"
else
    fail "Existing history lost or corrupted: $MESSAGES"
fi

