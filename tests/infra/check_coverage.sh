#!/bin/bash
# check_coverage.sh: Analyzes the mapping between library files and test files.

# 1. Setup Environment - Adjusted to find root from tests/infra/
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}          tell-me Test Coverage Analysis          ${NC}"
echo -e "${BLUE}==================================================${NC}"

LIBS=$(find "$BASE_DIR/lib" -name "*.sh" | sort)
TOTAL_LIBS=$(echo "$LIBS" | wc -l)
COVERED_COUNT=0

printf "%-40s | %-10s\n" "Library File" "Status"
echo "------------------------------------------------------------"

for lib in $LIBS; do
    # Get relative path from lib root
    # e.g., /path/to/lib/core/utils.sh -> core/utils.sh
    REL_PATH=${lib#$BASE_DIR/lib/}
    DIR_NAME=$(dirname "$REL_PATH")
    BASE_NAME=$(basename "$REL_PATH")
    TEST_FILE="$BASE_DIR/tests/${DIR_NAME}/test_${BASE_NAME}"
    
    # Handle status
    if [ -f "$TEST_FILE" ]; then
        STATUS="${GREEN}COVERED${NC}"
        COVERED_COUNT=$((COVERED_COUNT + 1))
    else
        # Check if it's covered by an integration test (heuristic)
        if [[ "$DIR_NAME" == "tools/git" ]] && [ -f "$BASE_DIR/tests/tools/git/test_sys_git.sh" ]; then
             STATUS="${YELLOW}INTEGRATION${NC}"
             COVERED_COUNT=$((COVERED_COUNT + 1))
        elif [[ "$BASE_NAME" == "file_edit.sh" || "$BASE_NAME" == "read_file.sh" ]] && [ -f "$BASE_DIR/tests/tools/fs/test_file_ops.sh" ]; then
             STATUS="${YELLOW}INTEGRATION${NC}"
             COVERED_COUNT=$((COVERED_COUNT + 1))
        else
             STATUS="${RED}MISSING${NC}"
        fi
    fi
    # Use relative path for display
    printf "%-40s | %b\n" "lib/$REL_PATH" "$STATUS"
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

