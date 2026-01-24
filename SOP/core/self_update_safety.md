# Standard Operating Procedure (SOP): Self-Updating Core Scripts

### Objective
To safely modify the core execution scripts (`a.sh`, `tell-me.sh`, `recap.sh`) while they are actively running the assistant session, preventing execution errors or script corruption.

---

### Prerequisites
- Bash shell (supports atomic `mv` operations).
- Standard utility `bash -n` for syntax validation.

---

### Step-by-Step Instructions

#### 1. Backup and Draft
Before making any changes to a core script:
- Create a backup of the current script: `cp a.sh a.sh.bak`.
- Write the intended changes to a temporary file (e.g., `a.sh.tmp`) instead of overwriting the original.

#### 2. Syntax Validation
Never swap a core script without verification:
- Run `bash -n <script_name>.tmp`.
- If the command returns an error, fix the temporary file and re-validate. Do NOT proceed to the swap phase.

#### 3. Atomic Replacement
Use the atomic nature of the `mv` command to replace the script:
- Run `mv <script_name>.tmp <script_name>`.
- This ensures that the running process (which already holds a file descriptor) completes its task undisturbed, while all subsequent calls load the new version.

#### 4. Post-Update Communication
Inform the user of the update:
- State clearly which script was updated.
- Note that changes will take effect upon the **next** user command (or next tool turn if the script is re-sourced).

---

### Code Templates

#### Safe Update Pattern (Bash):
```bash
# Example for updating a.sh
cp a.sh a.sh.bak
# ... logic to generate new_content ...
echo "$new_content" > a.sh.tmp
if bash -n a.sh.tmp; then
    mv a.sh.tmp a.sh
    echo "Update successful."
else
    echo "Syntax error detected! Aborting swap."
    rm a.sh.tmp
fi
```

---

### Best Practices
- **Library Focus**: Whenever possible, move logic into the `lib/` directory. Modifying library files is inherently safer as they are sourced at the start of the script's execution.
- **Rollback Readiness**: Keep the `.bak` file until the user confirms the system is still functional.
- **Minimalism**: Keep the core loop in `a.sh` as slim as possible to reduce the frequency of needed updates to the execution heart.

