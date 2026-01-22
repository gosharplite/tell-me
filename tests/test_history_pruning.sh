#!/bin/bash
# Test script for history pruning logic

# Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BASE_DIR/lib/utils.sh"
source "$BASE_DIR/lib/history_manager.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

HIST_FILE="$TEST_DIR/test_hist.json"
LOG_FILE="${HIST_FILE}.log"

# Helper to create a fake history with a specific number of turns
create_fake_history() {
    local turns=$1
    echo '{"messages": []}' > "$HIST_FILE"
    for (( i=0; i<turns; i++ )); do
        update_history_file "{\"role\": \"user\", \"parts\": [{\"text\": \"user message $i\"}]}" "$HIST_FILE"
        update_history_file "{\"role\": \"model\", \"parts\": [{\"text\": \"model response $i\"}]}" "$HIST_FILE"
    done
}

# Helper to mock a log entry
mock_log_usage() {
    local total=$1
    echo "[00:00:00] H: 0 M: $((total-100)) C: 100 T: $total N: $total(100%) S: 0 [1.0s]" >> "$LOG_FILE"
}

echo "Running History Pruning Tests..."

# Test 1: Under Limit (No Action)
echo -n "Test 1: Under limit... "
create_fake_history 10
mock_log_usage 50000
prune_history_if_needed "$HIST_FILE" 100000
MSG_COUNT=$(jq '.messages | length' "$HIST_FILE")
if [ "$MSG_COUNT" -eq 20 ]; then
    echo "PASS"
else
    echo "FAIL (Expected 20, got $MSG_COUNT)"
    exit 1
fi

# Test 2: Warning Threshold (85%+)
echo -n "Test 2: Warning at 90%... "
mock_log_usage 90000
prune_history_if_needed "$HIST_FILE" 100000
# Check if last message is a system notice
LAST_MSG=$(jq -r '.messages[-1].parts[0].text' "$HIST_FILE")
if [[ "$LAST_MSG" == *"[SYSTEM NOTICE] Context is reaching the limit"* ]]; then
    echo "PASS"
else
    echo "FAIL (No warning found)"
    exit 1
fi

# Test 3: Over Limit (Pruning)
echo -n "Test 3: Over limit (Pruning)... "
# Reset history to a large count
create_fake_history 50 # 100 messages
mock_log_usage 110000
prune_history_if_needed "$HIST_FILE" 100000

# Verify pruning happened
NEW_COUNT=$(jq '.messages | length' "$HIST_FILE")
if [ "$NEW_COUNT" -lt 100 ]; then
    # Verify notice was injected at the start
    FIRST_MSG=$(jq -r '.messages[0].parts[0].text' "$HIST_FILE")
    if [[ "$FIRST_MSG" == *"[SYSTEM NOTICE] Older conversation history has been pruned"* ]]; then
        # Verify boundary (next message should be a user message)
        SECOND_ROLE=$(jq -r '.messages[1].role' "$HIST_FILE")
        if [ "$SECOND_ROLE" == "user" ]; then
            echo "PASS ($NEW_COUNT messages remaining)"
        else
            echo "FAIL (Boundary mismatch: Role is $SECOND_ROLE)"
            exit 1
        fi
    else
        echo "FAIL (Notice not found at start)"
        exit 1
    fi
else
    echo "FAIL (No pruning occurred: $NEW_COUNT messages)"
    exit 1
fi

echo "All History Pruning Tests PASSED!"

