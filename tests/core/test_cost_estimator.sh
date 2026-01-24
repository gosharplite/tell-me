#!/bin/bash
# Test for lib/core/cost_estimator.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
RESP_FILE="$TEST_DIR/resp.json"
echo "[]" > "$RESP_FILE"
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock Dependencies
source "$BASE_DIR/lib/core/utils.sh"
source "$BASE_DIR/lib/core/cost_estimator.sh"

pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

test_cost_calculation() {
    echo "Testing Cost Calculation (Gemini 3 Pro)..."
    export AIMODEL="gemini-3-pro-preview"
    export MODE="test-mode"
    export file="$TEST_DIR/test-session"
    
    # Mock Log: [Time] H: 100 M: 1000 C: 50 T: 1150 N: 1050 S: 1 Th: 500 [1.0s]
    # Rates for Pro < 200k: H=0.20, M=2.00, C+Th=12.00 per 1e6
    # 100 * 0.20 / 1e6 = 0.00002
    # 1000 * 2.00 / 1e6 = 0.002
    # (50+500) * 12.00 / 1e6 = 550 * 12 / 1e6 = 0.0066
    # S = 1 * 0.014 = 0.014
    # Total = 0.00002 + 0.002 + 0.0066 + 0.014 = 0.02262
    
    echo "[00:00:00] H: 100 M: 1000 C: 50 T: 1150 N: 1050 S: 1 Th: 500 [1.0s]" > "${file}.log"
    
    echo "[]" > "$RESP_FILE"
    tool_estimate_cost "{}" "$RESP_FILE"
    
    RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")
    
    if [[ "$RESULT" == *"\$0.0226"* ]]; then
        pass "Cost calculated correctly ($RESULT)"
    else
        fail "Cost calculation incorrect: $RESULT"
    fi
}

test_fallback_rates() {
    echo "Testing Fallback Rates (Gemini 1.5 Pro)..."
    export AIMODEL="gemini-1.5-pro"
    export file="$TEST_DIR/test-fallback"
    
    # Rates for 1.5 Pro < 128k: H=0.3125, M=1.25, C=3.75 per 1e6
    # H=1000, M=10000, C=1000, S=0, Th=0
    # 1000 * 0.3125 / 1e6 = 0.0003125
    # 10000 * 1.25 / 1e6 = 0.0125
    # 1000 * 3.75 / 1e6 = 0.00375
    # Total = 0.0165625 -> $0.0166
    
    echo "[00:00:00] H: 1000 M: 10000 C: 1000 T: 12000 N: 11000 S: 0 Th: 0 [1.0s]" > "${file}.log"
    
    echo "[]" > "$RESP_FILE"
    tool_estimate_cost "{}" "$RESP_FILE"
    
    RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")
    
    if [[ "$RESULT" == *"\$0.0166"* ]]; then
        pass "Fallback cost calculated correctly ($RESULT)"
    else
        fail "Fallback cost calculation incorrect: $RESULT"
    fi
}

echo "Running Cost Estimator Tests..."
test_cost_calculation
test_fallback_rates

echo "------------------------------------------------"
echo "All tests passed successfully."
exit 0

