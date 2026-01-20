#!/bin/bash

# Setup
TEST_DIR="tests/temp_analysis"
mkdir -p "$TEST_DIR"

# Mock Environment
export CURRENT_TURN=0
export MAX_TURNS=10

# Create dummy Python file
cat << 'EOF' > "$TEST_DIR/complex.py"
def simple():
    print("Hello")

def complex_func(x):
    if x > 0:
        if x > 10:
            print("Large")
        else:
            print("Medium")
    else:
        for i in range(5):
            print(i)
    return x

class MyClass:
    def method(self):
        pass

# Usage
simple()
complex_func(5)
EOF

# Create dummy Bash file
cat << 'EOF' > "$TEST_DIR/script.sh"
#!/bin/bash

function my_func() {
    if [ "$1" == "test" ]; then
        echo "Test"
    fi
}

# Usage
my_func "test"
echo "Done"
EOF

# Load library
source ./lib/utils.sh
source ./lib/code_analysis.sh

# Helper to run tool
run_tool() {
    local FUNC=$1
    local JSON_INPUT=$2
    local OUT_FILE=$(mktemp)
    echo "[]" > "$OUT_FILE" # Initialize as array
    
    $FUNC "$JSON_INPUT" "$OUT_FILE"
    
    echo "Response:"
    cat "$OUT_FILE" | jq -r '.[0].functionResponse.response.result'
    rm "$OUT_FILE"
}

echo "--- Test 1: Calculate Complexity (Python) ---"
INPUT=$(jq -n --arg filepath "$TEST_DIR/complex.py" '{args: {filepath: $filepath}}')
run_tool "tool_calculate_complexity" "$INPUT"
echo ""

echo "--- Test 2: Calculate Complexity (Bash) ---"
INPUT=$(jq -n --arg filepath "$TEST_DIR/script.sh" '{args: {filepath: $filepath}}')
run_tool "tool_calculate_complexity" "$INPUT"
echo ""

echo "--- Test 3: Find Usages (Python) ---"
INPUT=$(jq -n --arg query "complex_func" --arg path "$TEST_DIR" '{args: {query: $query, path: $path}}')
run_tool "tool_find_usages" "$INPUT"
echo ""

echo "--- Test 4: Find Usages (Bash) ---"
INPUT=$(jq -n --arg query "my_func" --arg path "$TEST_DIR" '{args: {query: $query, path: $path}}')
run_tool "tool_find_usages" "$INPUT"
echo ""

# Cleanup
rm -rf "$TEST_DIR"

