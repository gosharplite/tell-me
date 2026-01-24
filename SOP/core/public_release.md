# Standard Operating Procedure (SOP): Public Release Process

### Objective
This SOP defines the requirements and steps for publishing a new public release of the `tell-me` project, ensuring code quality, security compliance, and comprehensive documentation.

---

### Prerequisites
- All tests must pass: `./run_tests.sh`.
- The `README.md` must be updated with the latest features and tools.
- A clean Git state (no uncommitted or untracked experimental files).
- Access to the repository with permission to push tags.

---

### Step-by-Step Instructions

#### 1. Security & Privacy Audit
Before any public release, perform a mandatory security scan:
- **Secret Scanning**: Ensure no Service Account JSON keys (`*.json`), API keys, or `.env` files are in the repository. Use `git grep` for common patterns like `"private_key"` or `"api_key"`.
- **Ignore Check**: Verify `.gitignore` covers `output/`, `*.log`, and `last-*.json` history files.
- **Privacy**: Ensure no personal data or proprietary internal URLs are hardcoded in the YAML configs or scripts.

#### 2. Documentation & Compliance Review
- **License**: Verify `LICENSE` (MIT) is present in the root.
- **SPDX Headers**: Ensure all core scripts (`.sh`) and YAML files contain the standard SPDX-License-Identifier header.
    - **⚠️ CRITICAL**: Modifications to core scripts (`a.sh`, `tell-me.sh`, etc.) **MUST** follow the atomic swap procedure in `SOP/core/self_update_safety.md`. Do not use in-place editing tools.
- **SOP Sync**: Verify that the `SOP/` directory reflects the current system architecture.
- **Version Bump**: Update any version strings (if applicable) in `tell-me.sh` or the welcome header.

#### 3. Final Functional Verification
Run the full suite in a clean environment:
```bash
./run_tests.sh
./tests/infra/check_coverage.sh
```
*Note: The Git pre-commit hook (installed via `./tests/infra/setup-git-hooks.sh`) provides a final safety gate during the merge to `main`. The coverage report ensures all core modules are officially supported by tests.*

#### 4. Changelog Update
Create or update a `CHANGELOG.md` or the "Latest Changes" section of the README:
- Categorize changes into: `Added`, `Changed`, `Fixed`, `Removed`.
- Link to major feature additions (e.g., "Refactored test structure for better modularity").

#### 5. Git Tagging and Pushing
Follow Semantic Versioning (vMAJOR.MINOR.PATCH):
1.  **Switch to Main Branch**: `git checkout main`.
2.  **Merge Dev**: `git merge dev`.
3.  **Tag the release**:
    ```bash
    git tag -a v1.0.0 -m "Release version 1.0.0 - [Brief summary]"
    ```
4.  **Push**:
    ```bash
    git push origin main --tags
    ```

---

### Release Checklist
- [ ] Security audit completed (no secrets found).
- [ ] `./run_tests.sh` returns **PASS**.
- [ ] `README.md` includes all new tools and configuration options.
- [ ] `SOP/` directory is updated to reflect structural changes.
- [ ] Branch `dev` is successfully merged into `main`.
- [ ] Git tag is applied and pushed.

---

### Best Practices
- **Release Often**: Small, frequent releases are easier to audit and test.
- **Draft Releases**: Use GitHub's "Draft Release" feature to stage the release notes before making them public.
- **Clean Output**: Ensure `dump.sh` does not include the `output/` folder or sensitive data when shared as an example.
- **Zero-Dependency Goal**: Maintain the project's philosophy of relying only on standard system tools (`bash`, `curl`, `jq`, `yq`).

