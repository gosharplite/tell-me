# Standard Operating Procedure (SOP): Self-Updating Core Scripts

### Objective
To safely modify the core execution scripts (`a.sh`, `tell-me.sh`, `recap.sh`, `aa.sh`, `hack.sh`, `dump.sh`) while they are actively running the assistant session, preventing execution errors or script corruption.

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

#### 2. Syntax Validation and Permissions
Never swap a core script without verification:
- Run `bash -n <script_name>.tmp`.
- **Restore Permissions**: Ensure the temporary file has execute permissions: `chmod +x <script_name>.tmp`.
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

### ⚠️ AI Agent Implementation Guide
When an AI assistant (like Gemini) is performing the update, it **MUST NOT** use in-place editing tools (`apply_patch`, `replace_text`, `insert_text`, `append_file`) on core scripts. Instead, follow this exact sequence:

1.  **Read**: Use `read_file` to capture the current content.
2.  **Local Edit**: Prepare the full new content in the thinking process.
3.  **Validate & Atomic Swap**: Use `execute_command` to run a single safe sequence:
    ```bash
    cat <<'EOF' > <script>.tmp
    [FULL CONTENT HERE]
    EOF
    bash -n <script>.tmp && chmod +x <script>.tmp && mv <script>.tmp <script>
    ```
4.  **Verification**: Confirm the file was updated, is valid, and has execute permissions.

---

### Code Templates

#### Safe Update Pattern (Bash):
```bash
# Example for updating a.sh
cp a.sh a.sh.bak
# ... logic to generate new_content ...
echo "$new_content" > a.sh.tmp
if bash -n a.sh.tmp; then
    chmod +x a.sh.tmp
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
- **Atomic Tool Choice**: Prefer `update_file` over partial edits for core files, as it ensures the entire file state is known and controlled.
- **Permission Preservation**: Always verify that the final file is executable (`[ -x <file> ]`) after a swap.
