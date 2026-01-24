#!/bin/bash
# Test for Resilience (History Pruning and Rollback)

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock TMPDIR for backups
export TMPDIR="$TEST_DIR"

# 2. Source Dependencies
source "$BASE_DIR/lib/core/utils.sh"
source "$BASE_DIR/lib/core/history_manager.sh"
source "$BASE_DIR/lib/core/payload_manager.sh"

pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

test_advance_warning() {
    echo "Testing Advance Warning (80% Capacity)..."
    local HIST_FILE="$TEST_DIR/history_warn.json"
    local LOG_FILE="${HIST_FILE}.log"
    local LIMIT=10000
    
    # 1. Create history with some messages
    echo '{"messages": [{"role": "user", "parts": [{"text": "Hello"}]}]}' > "$HIST_FILE"
    
    # 2. Mock log indicating 8500 tokens (85% > 80% limit)
    echo "[00:00:00] H: 0 M: 8500 C: 0 T: 8500 N: 8500 S: 0 Th: 0 [1.0s]" > "$LOG_FILE"
    
    prune_history_if_needed "$HIST_FILE" "$LIMIT"
    
    if jq -e '.messages[-1].parts[0].text | contains("reaching the limit")' "$HIST_FILE" >/dev/null; then
        pass "Advance warning injected"
    else
        fail "Advance warning missing"
    fi
}

test_pruning() {
    echo "Testing Pruning (95% Capacity)..."
    local HIST_FILE="$TEST_DIR/history_prune.json"
    local LOG_FILE="${HIST_FILE}.log"
    local LIMIT=10000
    
    # 1. Create history with 25 messages
    jq -n '{messages: [range(25) | {role: "user", parts: [{text: "msg \(.)"}]}]}' > "$HIST_FILE"
    
    # 2. Mock log indicating 9500 tokens (95% > 90% limit)
    echo "[00:00:00] H: 0 M: 9500 C: 0 T: 9500 N: 9500 S: 0 Th: 0 [1.0s]" > "$LOG_FILE"
    
    prune_history_if_needed "$HIST_FILE" "$LIMIT"
    
    local COUNT=$(jq '.messages | length' "$HIST_FILE")
    # Initial 25 -> Prune 1/5 (5) -> Should be around 21 messages (including the notice)
    if [ "$COUNT" -lt 25 ]; then
        pass "History pruned (New count: $COUNT)"
        if jq -e '.messages[0].parts[0].text | contains("pruned to save space")' "$HIST_FILE" >/dev/null; then
            pass "Memory loss notice present"
        else
            fail "Memory loss notice missing"
        fi
    else
        fail "History not pruned (Count: $COUNT)"
    fi
}

test_rollback() {
    echo "Testing Rollback (Payload Overflow)..."
    local HIST_FILE="$TEST_DIR/history_rollback.json"
    local PAYLOAD_FILE="$TEST_DIR/payload.json"
    local LIMIT=1000
    
    # 1. Create a "Good" state and backup it
    echo '{"messages": [{"role": "user", "parts": [{"text": "Good State"}]}]}' > "$HIST_FILE"
    backup_file "$HIST_FILE"
    
    # 2. Create a "Bad" state (too large)
    echo '{"messages": [{"role": "user", "parts": [{"text": "Very long message..."}]}]}' > "$HIST_FILE"
    
    # Create a dummy payload file whose size / 3.5 > LIMIT
    # 4000 bytes / 3.5 =~ 1142 tokens > 1000
    head -c 4000 /dev/zero > "$PAYLOAD_FILE"
    
    # Execute check (expecting failure and rollback)
    estimate_and_check_payload "$PAYLOAD_FILE" "$HIST_FILE" "$LIMIT" 2>/dev/null
    RET=$?
    
    if [ $RET -ne 0 ]; then
        pass "Payload check correctly failed"
    else
        fail "Payload check should have failed"
    fi
    
    if grep -q "Good State" "$HIST_FILE"; then
        pass "History rolled back to last known good state"
    else
        fail "History rollback failed"
        cat "$HIST_FILE"
    fi
}

echo "Running Resilience Tests..."
test_advance_warning
test_pruning
test_rollback

echo "------------------------------------------------"
echo "All tests passed successfully."
exit 0

