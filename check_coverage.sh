#!/bin/bash
# check_coverage.sh: Analyzes the mapping between library files and test files.

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}          tell-me Test Coverage Analysis          ${NC}"
echo -e "${BLUE}==================================================${NC}"

LIBS=$(find lib -name "*.sh" | sort)
TOTAL_LIBS=$(echo "$LIBS" | wc -l)
COVERED_COUNT=0

printf "%-40s | %-10s\n" "Library File" "Status"
echo "------------------------------------------------------------"

for lib in $LIBS; do
    # Calculate the expected test name
    # e.g., lib/core/utils.sh -> tests/core/test_utils.sh
    # e.g., lib/tools/fs/read_file.sh -> tests/tools/fs/test_read_file.sh
    
    REL_PATH=${lib#lib/}
    DIR_NAME=$(dirname "$REL_PATH")
    BASE_NAME=$(basename "$REL_PATH")
    TEST_FILE="tests/${DIR_NAME}/test_${BASE_NAME}"
    
    # Handle edge cases (e.g. tools that are grouped)
    if [ -f "$TEST_FILE" ]; then
        STATUS="${GREEN}COVERED${NC}"
        COVERED_COUNT=$((COVERED_COUNT + 1))
    else
        # Check if it's covered by an integration test (heuristic)
        if [[ "$DIR_NAME" == "tools/git" ]] && [ -f "tests/tools/git/test_sys_git.sh" ]; then
             STATUS="${YELLOW}INTEGRATION${NC}"
             COVERED_COUNT=$((COVERED_COUNT + 1))
        elif [[ "$BASE_NAME" == "file_edit.sh" || "$BASE_NAME" == "read_file.sh" ]] && [ -f "tests/tools/fs/test_file_ops.sh" ]; then
             STATUS="${YELLOW}INTEGRATION${NC}"
             COVERED_COUNT=$((COVERED_COUNT + 1))
        else
             STATUS="${RED}MISSING${NC}"
        fi
    fi
    printf "%-40s | %b\n" "$lib" "$STATUS"
done

echo "------------------------------------------------------------"
PERCENTAGE=$(( (COVERED_COUNT * 100) / TOTAL_LIBS ))

if [ "$PERCENTAGE" -eq 100 ]; then
    COLOR=$GREEN
else
    COLOR=$YELLOW
fi

echo -e "Total Library Files: $TOTAL_LIBS"
echo -e "Covered/Mapped:      $COVERED_COUNT"
echo -e "Project Coverage:    ${COLOR}${PERCENTAGE}%${NC}"
echo -e "${BLUE}==================================================${NC}"

