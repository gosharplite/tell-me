#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Starting All Tests..."
echo "====================="

FAIL_COUNT=0
PASS_COUNT=0

# Loop through all test scripts in the tests directory
for test_script in tests/*.sh; do
    # Skip this script itself if it were in the tests dir (it's currently not, but good practice)
    if [ "$(basename "$test_script")" == "run_all_tests.sh" ]; then
        continue
    fi

    echo -n "Running $(basename "$test_script")... "
    
    # Run the test script and capture exit code
    # We suppress stdout to keep the summary clean, but show stderr
    OUTPUT=$("$test_script" 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo "---------------------------------------------------"
        echo "$OUTPUT"
        echo "---------------------------------------------------"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo "====================="
echo "Summary:"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}Failed: $FAIL_COUNT${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi

