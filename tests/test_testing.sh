#!/bin/bash
# Test for lib/testing.sh (run_tests)

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BASE_DIR/lib/utils.sh"
source "$BASE_DIR/lib/testing.sh"

# Mock variables
CURRENT_TURN=1
MAX_TURNS=10

RESP_FILE=$(mktemp)
echo "[]" > "$RESP_FILE"
FAILED=0

# Test 1: Passing Test
echo "Test 1: Passing Test"
ARGS=$(jq -n --arg command "echo 'All good'" '{args: {command: $command}}')
tool_run_tests "$ARGS" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [ "$RESULT" == "PASS" ]; then
    echo "PASS: Correctly identified success"
else
    echo "FAIL: Expected PASS, got '$RESULT'"
    FAILED=1
fi

# Test 2: Failing Test
echo "Test 2: Failing Test"
ARGS=$(jq -n --arg command "echo 'Bad error' >&2; exit 1" '{args: {command: $command}}')
tool_run_tests "$ARGS" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if echo "$RESULT" | grep -q "FAIL"; then
    echo "PASS: Correctly identified failure"
else
    echo "FAIL: Expected FAIL, got '$RESULT'"
    FAILED=1
fi

if echo "$RESULT" | grep -q "Bad error"; then
    echo "PASS: Captured stderr"
else
    echo "FAIL: Missing stderr output"
    FAILED=1
fi

rm "$RESP_FILE"

if [ $FAILED -eq 1 ]; then
    exit 1
fi

