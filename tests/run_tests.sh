#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. Setup Environment
# Calculate BASE_DIR (Project Root) from tests/ directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERBOSE=false

# Check for verbose flag
if [ "$1" == "-v" ]; then
    VERBOSE=true
fi

echo "Starting All Tests..."
echo "====================="

FAIL_COUNT=0
PASS_COUNT=0
GLOBAL_START=$(date +%s.%N)

# Loop through all test scripts in the tests directory recursively
# Use -print0 and IFS= read -r -d '' to handle spaces and prevent stdin consumption
while IFS= read -r -d '' test_script; do
    TEST_NAME=$(basename "$test_script")
    
    # Skip the runner itself
    if [[ "$test_script" == *"/run_tests.sh" ]]; then continue; fi

    echo -n "Running $TEST_NAME... "
    
    TEST_START=$(date +%s.%N)
    # Run the test script explicitly with bash from the project root
    # IMPORTANT: Redirect stdin from /dev/null to prevent tests from consuming the 'find' stream
    OUTPUT=$(cd "$BASE_DIR" && bash "$test_script" 2>&1 < /dev/null)
    EXIT_CODE=$?
    TEST_END=$(date +%s.%N)
    DURATION=$(awk -v start="$TEST_START" -v end="$TEST_END" 'BEGIN { printf "%.2fs", end - start }')

    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}PASS${NC} ($DURATION)"
        PASS_COUNT=$((PASS_COUNT + 1))
        
        if [ "$VERBOSE" == "true" ]; then
             echo "--- Output [$TEST_NAME] ---"
             echo "$OUTPUT" | sed 's/^/  /'
             echo "---------------------------"
        fi
    else
        echo -e "${RED}FAIL${NC} ($DURATION)"
        echo "---------------------------------------------------"
        echo "$OUTPUT"
        echo "---------------------------------------------------"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done < <(find "$BASE_DIR/tests" -type f -name "*.sh" -print0 | sort -z)

GLOBAL_END=$(date +%s.%N)
TOTAL_DURATION=$(awk -v start="$GLOBAL_START" -v end="$GLOBAL_END" 'BEGIN { printf "%.2fs", end - start }')

echo "====================="
echo "Summary:"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}Failed: $FAIL_COUNT${NC}"
    echo -e "Total Time: $TOTAL_DURATION"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    echo -e "Total Time: $TOTAL_DURATION"
    exit 0
fi

