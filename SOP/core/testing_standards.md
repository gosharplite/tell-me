# Standard Operating Procedure (SOP): Testing Standards and Organization

### Objective
To ensure that the `tell-me` test suite remains modular, isolated, and mirrors the project's library architecture for ease of maintenance and scalability.

---

### Prerequisites
- Bash shell.
- Access to the `tests/` directory and the `run_tests.sh` script.
- `jq` for JSON manipulation within tests.

---

### Step-by-Step Instructions

#### 1. Directory Mapping (Mirroring)
New tests must be placed in a subdirectory that mirrors the location of the logic being tested:
- **`tests/core/`**: Tests for authentication, history management, configuration parsing, and core loop drivers.
- **`tests/tools/fs/`**: Tests for file system tools (`read`, `write`, `patch`, etc.).
- **`tests/tools/git/`**: Tests for Git-related toolsets.
- **`tests/tools/media/`**: Tests for image and video generation tools.
- **`tests/tools/dev/`**: Tests for code analysis, linting, and development helpers.
- **`tests/tools/sys/`**: Tests for system execution, tasks, and scratchpad memory.

#### 2. Naming Conventions
- All test files must use the prefix `test_` and the extension `.sh` (e.g., `test_file_ops.sh`).
- Files must be marked as executable: `chmod +x tests/.../test_*.sh`.

#### 3. Environment Isolation
Tests should not modify the user's actual environment or history. Every test script should:
1.  **Create a temporary workspace**: Use `mktemp -d`.
2.  **Use Traps**: Ensure the temporary directory is deleted on exit: `trap 'rm -rf "$TEST_DIR"' EXIT`.
3.  **Mock Dependencies**: Copy necessary `lib/` files or `tools.json` into the temporary workspace to simulate a clean state.
4.  **Localize Paths**: Define `BASE_DIR` relative to the script's location to correctly source library files (e.g., `BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"`).

#### 4. Test Execution
- Tests are executed via the root `./run_tests.sh` script.
- The runner automatically discovers tests recursively using `find tests -type f -name "*.sh"`.
- Tests must return exit code `0` for success and non-zero for failure.

---

### Code Templates

#### New Test Boilerplate:
```bash
#!/bin/bash
# Test for [Feature Name]

# 1. Setup Environment
# Adjust depth based on nesting (e.g., ../../ for tests/tools/fs/)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
source "$BASE_DIR/lib/core/utils.sh"
# Source the specific module under test
source "$BASE_DIR/lib/tools/fs/example.sh"

# 3. Setup Mocks
RESP_FILE="$TEST_DIR/response.json"
echo "[]" > "$RESP_FILE"

# 4. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

# 5. Logic Execution
echo "Running [Feature] Tests..."
# ... test logic here ...

# 6. Verification
if [[ "$RESULT" == "Expected" ]]; then
    pass "Behavior confirmed"
else
    fail "Unexpected result: $RESULT"
fi
```

---

### Verification & Testing
1.  **Syntax Check**: Run `bash -n tests/.../test_name.sh`.
2.  **Execution**: Run `./run_tests.sh` from the project root.
3.  **Summary Check**: Ensure your new test is listed in the output and marked as **PASS**.

---

### Best Practices
- **Atomic Tests**: Test one specific function or tool per assertion if possible.
- **Quiet by Default**: Tests should only output "PASS" or "FAIL" unless run with the `-v` (verbose) flag in the runner.
- **No Side Effects**: Never write to the project's real `output/` or `yaml/` directories during a test.
- **Mock External APIs**: For tools that call external services (like Gemini or Search), mock the `curl` response or the tool's inner logic to verify the *handling* of data without incurring costs.

