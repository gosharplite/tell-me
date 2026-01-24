#!/bin/bash
# Test for lib/tools/dev/testing.sh (run_tests)

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
TEST_DIR=$(mktemp -d)
RESP_FILE="$TEST_DIR/resp.json"
echo "[]" > "$RESP_FILE"

# Mock Environment
export CURRENT_TURN=1
export MAX_TURNS=10

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Copy lib to use locally if needed
cp -r "$BASE_DIR/lib" "$TEST_DIR/"

cd "$TEST_DIR"

# 2. Source Dependencies
source "$TEST_DIR/lib/core/utils.sh"
source "$TEST_DIR/lib/tools/dev/testing.sh"

pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

echo "Running Testing Tool Tests..."

# Create dummy test script named exactly as the allowed command
cat <<EOF > "run_tests.sh"
#!/bin/bash
echo 'All good'
EOF
chmod +x "run_tests.sh"

# Test 1: Passing Test
echo "Test 1: Passing Test"
ARGS=$(jq -n --arg command "./run_tests.sh" '{args: {command: $command}}')
tool_run_tests "$ARGS" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [ "$RESULT" == "PASS" ]; then
    pass "Correctly identified success"
else
    fail "Expected PASS, got '$RESULT'"
fi

# Test 2: Failing Test
cat <<EOF > "run_tests.sh"
#!/bin/bash
echo 'Bad error' >&2
exit 1
EOF
chmod +x "run_tests.sh"

echo "Test 2: Failing Test"
ARGS=$(jq -n --arg command "./run_tests.sh" '{args: {command: $command}}')
tool_run_tests "$ARGS" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if echo "$RESULT" | grep -q "FAIL"; then
    pass "Correctly identified failure"
else
    fail "Expected FAIL, got '$RESULT'"
fi

if echo "$RESULT" | grep -q "Bad error"; then
    pass "Captured stderr"
else
    fail "Missing stderr output"
fi

echo "------------------------------------------------"
echo "All tests passed successfully."
exit 0

