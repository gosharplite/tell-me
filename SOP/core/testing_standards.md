# Standard Operating Procedure (SOP): Testing Standards and Organization

### Objective
To ensure that the `tell-me` test suite remains modular, isolated, and mirrors the project's library architecture for ease of maintenance and scalability.

---

### Prerequisites
- Bash shell.
- Access to the `tests/` directory and the `tests/run_tests.sh` script.
- `jq` for JSON manipulation within tests.

---

### Step-by-Step Instructions

#### 1. Directory Mapping (Mirroring)
New tests must follow the **Mirroring Principle**: place the test in a subdirectory that matches the location of the logic being tested.
- **`tests/core/`**: Tests for authentication, cost estimation, history management, and core loop drivers.
- **`tests/tools/fs/`**: Tests for file system tools (`read`, `write`, `patch`, etc.).
- **`tests/tools/git/`**: Tests for Git-related toolsets.
- **`tests/tools/media/`**: Tests for image and video generation tools.
- **`tests/tools/dev/`**: Tests for code analysis, linting, and development helpers.
- **`tests/tools/sys/`**: Tests for system execution, tasks, and scratchpad memory.
- **`tests/infra/`**: Setup, automation, and coverage scripts (non-test utilities).

#### 2. Naming Conventions
- All test files must use the prefix `test_` and the extension `.sh` (e.g., `test_file_ops.sh`).
- Infrastructure scripts should use descriptive names without the `test_` prefix (e.g., `setup-git-hooks.sh`).
- Files must be marked as executable: `chmod +x tests/.../*.sh`.

#### 3. Environment Isolation
Every test script should:
1.  **Create a temporary workspace**: Use `mktemp -d`.
2.  **Use Traps**: Ensure the temporary directory is deleted on exit: `trap 'rm -rf "$TEST_DIR"' EXIT`.
3.  **Mock Dependencies (Dynamic)**: Use wildcards to ensure new modules are included: `cp lib/core/*.sh "$TEST_DIR/"`.
4.  **Localize Paths**: Define `BASE_DIR` relative to the script's location.

#### 4. Test Execution & The Runner
- Tests are executed via the `./tests/run_tests.sh` script.
- **Runner Lessons**: 
    - The runner must explicitly `cd` to the project root before executing sub-tests to ensure path consistency.
    - **Stdin Isolation**: The runner must redirect stdin from `/dev/null` (e.g., `bash "$test" < /dev/null`) to prevent sub-tests from consuming the runner's loop stream.
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
2.  **Execution**: Run `./tests/run_tests.sh` from the project root.
3.  **Summary Check**: Ensure your new test is listed in the output and marked as **PASS**.
4.  **Automated Enforcement**: Install the Git pre-commit hook via `./tests/infra/setup-git-hooks.sh`.
5.  **Coverage Analysis**: Run `./tests/infra/check_coverage.sh` to verify structural mapping.

---

### Best Practices
- **Resilience Testing**: Do not just test "Happy Paths". Mock API failures (429, 500) and history overflows to verify system recovery.
- **Quiet by Default**: Tests should only output "PASS" or "FAIL" unless run with `-v`.
- **No Side Effects**: Never write to the project's real `output/` or `yaml/` directories.
- **Mock External APIs**: For tools that call Gemini or Search, mock `curl` to verify handling without costs.

#### 5. Handling Styled Output (ANSI Colors)
If a function returns styled text, assertions should strip these codes:
```bash
# Strip ANSI escape codes
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
```
Assertion checks should be performed on the `$CLEAN_OUTPUT` variable.

