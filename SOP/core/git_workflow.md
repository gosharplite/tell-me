# Standard Operating Procedure (SOP): Git Workflow (Commit and Push)

### Objective
To ensure that all changes to the `tell-me` repository are verified, logically grouped, and documented with clear, descriptive commit messages.

---

### Prerequisites
- All functional changes must be verified (e.g., via `./tests/run_tests.sh`).
- No sensitive information (API keys, secrets) should be staged.
- **Git Hooks**: Ensure project hooks are installed via `./tests/infra/setup-git-hooks.sh` to automate these checks.

---

### Step-by-Step Instructions

#### 1. Pre-Commit Verification
Before staging any files:
- Run the full test suite: `./tests/run_tests.sh`.
- **Automated Check**: The pre-commit hook will automatically run syntax validation (`bash -n`) and the test suite. If the hook fails, the commit will be blocked.
- Ensure all tests pass. Do NOT commit if tests are failing unless the commit is specifically meant to document a broken state (rare).
- Review current changes: `git status` and `git diff`.

#### 2. Staging Changes
- Stage files logically: `git add <files>`.
- Avoid `git add .` if you have unrelated experimental changes in the workspace.
- Group related changes (e.g., a lib refactor and its corresponding test fixes) into a single commit.

#### 3. Composing the Commit Message
Follow the "Summary + Details" format:
- **Summary Line**: A concise (max 50 chars) description starting with a type prefix:
    - `Feat:` (New feature)
    - `Fix:` (Bug fix)
    - `Refactor:` (Code restructuring)
    - `Docs:` (Documentation only)
    - `Test:` (Adding/fixing tests)
    - `Chore:` (Maintenance/SOP updates)
- **Detailed Body**: A blank line followed by bullet points explaining the "what" and "why."

#### 4. Final Review and Push
- Review the staged changes one last time: `git diff --staged`.
- Commit: `git commit -m "Summary line..."`.
- Push to the remote: `git push origin <branch_name>`.

---

### ⚠️ AI Agent Implementation Guide
When an AI assistant performs a commit, it must:
1.  **Explicitly check test status** before recommending a commit.
2.  **Generate a structured message** based on the actual tasks completed during the session.
3.  **Confirm the branch name** using `git branch --show-current`.

---

### Code Templates

#### Recommended Commit Pattern:
```bash
git add .
git commit -m "Refactor: Structure lib directory and update core/SOPs

- Categorized library scripts into functional subdirectories.
- Updated a.sh to recursively source libraries.
- Revised SOPs to include AI agent safety protocols.
- Verified PASS on all 19 tests."
git push origin $(git branch --show-current)
```

---

### Best Practices
- **Atomic Commits**: Each commit should represent a single logical change.
- **Push Often**: Push at the end of a successful task or session to prevent data loss.
- **Never Push Broken Code**: The `dev` and `main` branches should always be in a passing state.
- **Secret Scanning**: Double-check that no `.json` key files or `.config.yaml` with sensitive data are accidentally staged.

