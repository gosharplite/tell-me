# Standard Operating Procedure (SOP): Library Organization and Refactoring

### Objective
To maintain a clean, structured, and scalable `lib/` directory by categorizing scripts into functional subdirectories and ensuring system-wide compatibility.

---

### Prerequisites
- Core execution script (`a.sh`) must support recursive sourcing.
- Access to the `run_tests.sh` script for verification.

---

### Step-by-Step Instructions

#### 1. Categorization
Identify the appropriate functional directory for the script:
- **`lib/core/`**: Scripts required for the assistant's basic operation (auth, history, utils).
- **`lib/tools/fs/`**: File system manipulation.
- **`lib/tools/git/`**: Version control integration.
- **`lib/tools/media/`**: Multimedia generation and analysis.
- **`lib/tools/dev/`**: Development, linting, and code analysis.
- **`lib/tools/sys/`**: System execution and session memory.

#### 2. Relocation
Move the script and update its internal references:
- Move the file: `mv lib/old_script.sh lib/tools/sys/`
- Update "Requires" comments at the top of the file to reflect new paths for dependencies (e.g., `# Requires: lib/core/utils.sh`).

#### 3. Core Sourcing Check
- Verify `a.sh` uses a recursive sourcing loop (typically using `find -maxdepth 3 -name "*.sh"`).
- Ensure core files sourced explicitly at the top of `a.sh` (like `utils.sh` or `history_manager.sh`) are excluded from the loop to prevent double-sourcing.

#### 4. Test Suite Alignment and Mirroring
Reorganization *will* break existing tests and requires structural updates:
- **Mirroring**: Move the corresponding test files in `tests/` to subdirectories that match the new `lib/` structure (e.g., if a tool moves to `lib/tools/fs/`, its test should move to `tests/tools/fs/`).
- **Path Updates**: Update all `source` paths in relevant `tests/*.sh` files.
- **Base Directory**: Recalculate `BASE_DIR` in test scripts to account for the new nesting depth (e.g., change `../` to `../../`).
- **Logic Updates**: Update any `cp` or `mkdir` logic in tests that mock the library environment.
- **Verification**: Run the full suite: `./run_tests.sh`.

---

### Code Templates

#### Recursive Sourcing Pattern (in a.sh):
```bash
# Source all library files recursively from lib/core and lib/tools
while IFS= read -r -d '' lib; do
    # Skip files already sourced explicitly
    case "$(basename "$lib")" in
        history_manager.sh|utils.sh|auth.sh) continue ;;
    esac
    source "$lib"
done < <(find "$BASE_DIR/lib" -maxdepth 3 -name "*.sh" -print0)
```

---

### Verification & Testing
1.  **Structure Check**: Run `find lib -maxdepth 3` and `find tests -maxdepth 3` to verify both directories are mirrored correctly.
2.  **Logic Check**: Start a session with `ait` and verify that basic tools (like `read_file` or `manage_tasks`) are responsive.
3.  **Full Regression**: Run `./run_tests.sh`. A successful refactor must result in **PASS** for all tests.

---

### Best Practices
- **Mirroring**: Always keep the `tests/` folder structure in sync with `lib/` as per `SOP/core/testing_standards.md`.
- **Depth Limit**: Keep the hierarchy shallow (maximum 3 levels) to maintain visibility.
- **Naming Consistency**: Keep filenames lowercase with underscores.
- **Atomic Commits**: Commit the library moves, the directory mirroring in tests, and the corresponding path fixes in a single logical block.

