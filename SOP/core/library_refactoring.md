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

#### 4. Test Suite Alignment
Reorganization *will* break existing tests. You must:
- Update all `source` paths in relevant `tests/*.sh` files.
- Update any `cp` or `mkdir` logic in tests that mock the library environment.
- Run the full suite: `./run_tests.sh`.

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
1.  **Structure Check**: Run `find lib -maxdepth 3` to verify files are in the correct subfolders.
2.  **Logic Check**: Start a session with `ait` and verify that basic tools (like `read_file` or `manage_tasks`) are responsive.
3.  **Full Regression**: Run `./run_tests.sh`. A successful refactor must result in **PASS** for all tests.

---

### Best Practices
- **Depth Limit**: Keep the hierarchy shallow (maximum 3 levels) to maintain visibility.
- **Naming Consistency**: Keep filenames lowercase with underscores.
- **Atomic Commits**: Commit the directory move and the corresponding test fixes in a single logical block to keep the repository in a "green" state.

