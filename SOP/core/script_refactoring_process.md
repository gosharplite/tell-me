# Standard Operating Procedure (SOP): Monolithic Script Refactoring Process

### Objective
To safely and systematically decompose monolithic scripts (like `a.sh`) into modular, testable library files. This process improves maintainability, reduces the risk of corruption during self-updates, and enables granular unit testing.

---

### Prerequisites
- Bash shell.
- Access to the `lib/core/` directory.
- `bash -n` for syntax validation.
- Knowledge of the **Atomic Swap Procedure** (`SOP/core/self_update_safety.md`).

---

### Step-by-Step Instructions

#### 1. Identification Phase
Analyze the target script to identify logic blocks suitable for extraction. Prioritize:
- **Pure Functions**: Logic that takes inputs and returns outputs (e.g., YAML parsing, token estimation).
- **External Interfaces**: Code handling API requests, retries, and HTTP headers.
- **UI & Logging**: Code responsible for terminal output formatting and ANSI color management.
- **Session State**: Initialization of folders, history files, and environment variables.

#### 2. Library Module Creation
For each identified block:
- Create a new file in `lib/core/` (e.g., `lib/core/metrics.sh`).
- Wrap the logic in a descriptive function (e.g., `calculate_usage()`).
- **Isolation**: Use `local` for all variables inside the function to prevent accidental pollution of the orchestrator’s global namespace.
- **Dependencies**: Ensure the new function can access required global variables (like `$BASE_DIR` or `$file`) or pass them as arguments.

#### 3. Orchestrator Integration
Update the main script (e.g., `a.sh`):
- Add a `source` command for the new library at the top.
- Add the new filename to the **Recursive Sourcing Exclusion List** in the main loop to prevent double-sourcing.
- Replace the original multi-line logic block with a single call to the new function.

#### 4. The Atomic Deployment Protocol
[... unchanged ...]

#### 5. Test Context Alignment
Refactoring often changes the "source-of-truth" for dependencies. You must:
- **Audit Mocks**: Check `tests/` for any scripts that manually copy or mock the refactored files.
- **Update Setup Logic**: Ensure test setup scripts (using `cp` or `mktemp`) are updated to include the new library modules.
- **Dynamic Copying**: Transition tests from copying specific files (e.g., `cp lib/core/utils.sh`) to dynamic wildcards (e.g., `cp lib/core/*.sh`) to future-proof the test suite.

#### 6. Verification & Metrics
- **Syntax Check**: Ensure all new library files are valid (`bash -n lib/core/*.sh`).
- **Complexity Check**: Run `wc -l <script>` to confirm the reduction in monolithic size.
- **Functional Test**: Execute a standard assistant turn to ensure the "plumbing" is correct.
- **Regression**: Run `./run_tests.sh`. All tests **MUST** pass before committing.

---

### Code Templates

#### Before Refactoring (Inlined Logic):
```bash
# Complex logic inside a loop
while true; do
  # 20 lines of curl and retry logic
  RESPONSE=$(curl ... )
  if [[ $? -ne 0 ]]; then ... retry ... fi
done
```

#### After Refactoring (Modular Call):
```bash
# lib/core/api_client.sh
call_api() {
  local url="$1"
  # ... logic ...
}

# a.sh
while true; do
  RESPONSE=$(call_api "$URL") || exit 1
done
```

---

### Best Practices
- **Step-by-Step**: Refactor one logic block at a time. Never attempt a "big bang" refactor of an entire script in one turn.
- **Variable Scoping**: Always use `local` for internal counters (`i`, `j`, `count`) and temporary strings within library functions.
- **Error Propagation**: Ensure library functions return non-zero exit codes on failure so the orchestrator can react (e.g., `|| exit 1`).
- **Minimalist Orchestrator**: Aim to keep the main orchestrator script under 200 lines. If it grows larger, identify new candidates for extraction.
- **Documentation**: Update `SOP/core/library_refactoring.md` whenever a new core module is added.

