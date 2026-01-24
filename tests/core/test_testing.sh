#!/bin/bash
# Test for lib/testing.sh (run_tests)

# Setup isolated environment
TEST_DIR=$(mktemp -d)
RESP_FILE="$TEST_DIR/resp.json"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Copy lib to use locally if needed, but we source from absolute path or relative to original.
# We will CD into TEST_DIR, so we need to know where lib is.
ORIGINAL_DIR="$(pwd)"
cp -r lib "$TEST_DIR/"

cd "$TEST_DIR"

source "lib/core/utils.sh"
source "lib/tools/dev/testing.sh"

# Mock variables
CURRENT_TURN=1
MAX_TURNS=10

echo "[]" > "$RESP_FILE"
FAILED=0

# Create dummy test script named exactly as the allowed command
cat <<EOF > "run_tests.sh"
#!/bin/bash
echo 'All good'
EOF
chmod +x "run_tests.sh"

# Test 1: Passing Test
echo "Test 1: Passing Test"
# Command must match whitelist exactly: ./run_tests.sh
ARGS=$(jq -n --arg command "./run_tests.sh" '{args: {command: $command}}')
tool_run_tests "$ARGS" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [ "$RESULT" == "PASS" ]; then
    echo "PASS: Correctly identified success"
else
    echo "FAIL: Expected PASS, got '$RESULT'"
    FAILED=1
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

# Return to original dir (though script exit handles it)
cd "$ORIGINAL_DIR"

if [ $FAILED -eq 1 ]; then
    exit 1
fi

