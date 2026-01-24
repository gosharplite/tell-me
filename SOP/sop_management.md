# Standard Operating Procedure (SOP): Creating and Managing SOPs

This SOP defines the standard structure and process for documentating procedures within the `tell-me` project to ensure clarity, consistency, and maintainability.

---

### 1. Structure of an SOP

#### File Criticality Levels
To ensure stability, files are categorized by risk:
- **Core Scripts** (`a.sh`, `tell-me.sh`, `recap.sh`, `aa.sh`, `hack.sh`, `dump.sh`): **HIGH RISK**. Modifications require atomic swap and syntax validation as per `SOP/core/self_update_safety.md`.
- **Library Scripts** (`lib/**/*.sh`): **MEDIUM RISK**. Sourced at startup. Verify syntax before committing.
- **Configurations/Tools** (`yaml/*.yaml`, `lib/tools.json`): **LOW RISK**. Ensure valid JSON/YAML syntax.

Every SOP should follow a consistent Markdown structure:

- **Title**: A clear, descriptive title prefixed with "Standard Operating Procedure (SOP):".
- **Objective**: A brief statement explaining what the SOP covers and its purpose.
- **Prerequisites**: Any tools, files, or permissions required before starting.
- **Step-by-Step Instructions**: Numbered sections detailing the process.
- **Code Templates**: Reusable code blocks or boilerplate for implementation.
- **Verification/Testing**: How to confirm the procedure was successful.
- **Best Practices**: Tips for edge cases, error handling, or efficiency.

### 2. The Creation Process

#### Step 1: Identify the Need
- Create an SOP for any task that is complex (3+ steps), recurring, or critical to system stability (e.g., adding tools, refactoring history, deployment).

#### Step 2: Research & Draft
- Explore the existing codebase to identify the "source of truth."
- Perform the task manually once to verify all steps.
- Draft the content following the structure in Section 1.

#### Step 3: Localization
- **File Path**: Save the file in the `SOP/` directory or an appropriate sub-folder (e.g., `SOP/tools/`).
- **Naming Convention**: Use lowercase with underscores (e.g., `SOP/tools/new_tool_guide.md`).

#### Step 4: Verification
- Follow your own draft as if you were a new user.
- Fix any ambiguities or missing steps discovered during the walkthrough.

### 3. Maintenance & Revision
- **Evolution**: When a codebase change breaks a documented procedure, the corresponding SOP **must** be updated immediately.
- **Versioning**: Use Git commit messages to track the "why" behind SOP revisions.
- **Consistency**: Periodically review all files in the `SOP/` tree to ensure they don't contradict each other.

---

### 4. Implementation Checklist
- [ ] Is the title clear?
- [ ] Does this impact **Core Scripts**? (If yes, follow `SOP/core/self_update_safety.md` and ensure **execute permissions** are preserved)
- [ ] Are all dependencies listed?
- [ ] Is the logic broken down into digestible numbered steps?
- [ ] Are there example code blocks?
- [ ] Is the file saved in `SOP/` or a sub-folder?
- [ ] Has the file been committed to the repository?

