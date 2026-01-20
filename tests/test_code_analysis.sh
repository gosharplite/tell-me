#!/bin/bash
# Test for lib/code_analysis.sh (get_file_skeleton)

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BASE_DIR/lib/utils.sh"
source "$BASE_DIR/lib/code_analysis.sh"

# Mock variables
CURRENT_TURN=1
MAX_TURNS=10

# Create temp files in current dir to satisfy check_path_safety
TEST_PY="./test_temp_${RANDOM}.py"
cat <<EOF > "$TEST_PY"
import os

def my_func(a, b):
    """Calculates stuff."""
    return a + b

class MyClass:
    """A class docstring."""
    def method_one(self):
        pass
EOF

RESP_FILE=$(mktemp)
echo "[]" > "$RESP_FILE"

# Test 1: Python Skeleton
echo "Test 1: Python Skeleton"
ARGS=$(jq -n --arg filepath "$TEST_PY" '{args: {filepath: $filepath}}')
tool_get_file_skeleton "$ARGS" "$RESP_FILE"

# The result is appended to the array, so we want the last element's result
RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

FAILED=0

if echo "$RESULT" | grep -q "FunctionDef: my_func"; then
    echo "PASS: Found function definition"
else
    echo "FAIL: Missing function definition"
    echo "Result: $RESULT"
    FAILED=1
fi

if echo "$RESULT" | grep -q "Calculates stuff"; then
    echo "PASS: Found docstring"
else
    echo "FAIL: Missing docstring"
    FAILED=1
fi

if echo "$RESULT" | grep -q "ClassDef: MyClass"; then
    echo "PASS: Found class definition"
else
    echo "FAIL: Missing class definition"
    FAILED=1
fi

rm "$TEST_PY" "$RESP_FILE"

if [ $FAILED -eq 1 ]; then
    exit 1
fi

# Test 2: Shell Skeleton
TEST_SH="./test_temp_${RANDOM}.sh"
cat <<EOF > "$TEST_SH"
#!/bin/bash
function my_shell_func() {
    echo "hi"
}
simple_func() {
    echo "yo"
}
EOF

RESP_FILE=$(mktemp)
echo "[]" > "$RESP_FILE"

echo "Test 2: Shell Skeleton"
ARGS=$(jq -n --arg filepath "$TEST_SH" '{args: {filepath: $filepath}}')
tool_get_file_skeleton "$ARGS" "$RESP_FILE"

RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if echo "$RESULT" | grep -q "my_shell_func"; then
    echo "PASS: Found shell function"
else
    echo "FAIL: Missing shell function"
    echo "Result: $RESULT"
    FAILED=1
fi

rm "$TEST_SH" "$RESP_FILE"

if [ $FAILED -eq 1 ]; then
    exit 1
fi

