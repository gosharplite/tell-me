#!/bin/bash
# setup-git-hooks.sh: Installs project-specific Git hooks.

# 1. Setup Environment - Adjusted to find root from tests/infra/
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_DIR="$BASE_DIR/.git/hooks"

if [ ! -d "$HOOK_DIR" ]; then
    echo "Error: .git directory not found at $BASE_DIR. Please ensure this script is in the project's tests/infra/ directory."
    exit 1
fi

# 2. Define Pre-commit Hook Content
cat <<'EOF' > "$HOOK_DIR/pre-commit"
#!/bin/bash
# tell-me pre-commit hook: Verifies tests and syntax before committing.

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[Hook] Running pre-commit validation...${NC}"

# 1. Validate Syntax of changed .sh files
CHANGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$')

if [ -n "$CHANGED_FILES" ]; then
    echo "Checking syntax: $CHANGED_FILES"
    for file in $CHANGED_FILES; do
        if ! bash -n "$file"; then
            echo -e "${RED}Error: Syntax error detected in $file${NC}"
            exit 1
        fi
    done
fi

# 2. Run Test Suite
echo "Running full test suite..."
# Since the hook runs from the project root during git commit, we call ./run_tests.sh directly
if ! ./run_tests.sh; then
    echo -e "${RED}Error: Tests failed. Commit aborted.${NC}"
    exit 1
fi

echo -e "${GREEN}[Hook] Validation passed. Proceeding with commit.${NC}"
exit 0
EOF

# 3. Make hook executable
chmod +x "$HOOK_DIR/pre-commit"

echo -e "\033[0;32mSuccess: Git pre-commit hook installed.\033[0m"
echo "The hook will now automatically verify syntax and run tests before every commit."

