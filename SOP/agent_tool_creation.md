# Standard Operating Procedure (SOP): Creating Agent Tools for "tell-me"

### Objective
This SOP defines the process for adding new agentic capabilities (tools) to the `tell-me` project, ensuring they are correctly defined for the AI and robustly implemented in Bash.

---

### Prerequisites
- Access to the `lib/` directory.
- `jq` installed for JSON processing.
- Basic knowledge of the Gemini Tool Use (Function Calling) schema.
- Familiarity with the project's global variables (`$file`, `$AIMODEL`, etc.).

---

### Step-by-Step Instructions

#### 1. Define the Tool Interface
Identify the functionality and define the AI interaction schema:
- **Name**: A clear, snake_case name (e.g., `calculate_hash`).
- **Description**: A concise explanation of the tool's purpose and usage context.
- **Parameters**: A JSON-compatible list of arguments (type, description, required fields).

#### 2. Update Tool Definitions
Register the tool in the centralized schema file:
- **File**: `lib/tools.json`
- **Action**: Append the new JSON definition object to the array.
- **Constraint**: Ensure valid JSON syntax (objects must be comma-separated).

#### 3. Implement the Tool Logic
Create the Bash function to handle the execution:
- **Location**: Create a new file in `lib/` (e.g., `lib/hash_tool.sh`) or append to an existing library.
- **Function Name**: Prefix with `tool_` (e.g., `tool_calculate_hash`).
- **Signature**: `tool_name "$FC_DATA" "$RESP_PARTS_FILE"`

#### 4. Integration
Verify the tool is sourced:
- The `a.sh` script automatically sources all `*.sh` files in `lib/`. No manual registration is required if the file is named correctly.

---

### Code Templates

#### Tool Definition (lib/tools.json):
```json
{
  "name": "calculate_hash",
  "description": "Calculates the SHA-256 hash of a file.",
  "parameters": {
    "type": "OBJECT",
    "properties": {
      "filepath": { "type": "STRING", "description": "Path to the file." }
    },
    "required": ["filepath"]
  }
}
```

#### Implementation Boilerplate:
```bash
tool_calculate_hash() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    # 1. Extract Arguments
    local FILEPATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

    # 2. Logic (Use python3 for complex processing)
    if [[ -f "$FILEPATH" ]]; then
        local RESULT=$(sha256sum "$FILEPATH" | awk '{print $1}')
    else
        local RESULT="Error: File not found."
    fi

    # 3. Save Response (Atomic Update)
    jq -n --arg name "calculate_hash" --arg res "$RESULT" \
        '{functionResponse: {name: $name, response: {result: $res}}}' > "${RESP_PARTS_FILE}.part"
    
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" \
        && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
```

---

### Verification & Testing
1. **Linter**: Run `bash -n lib/your_script.sh` to check for syntax errors.
2. **Integration Test**: Start a session (`ait`) and ask the AI to perform the task.
3. **Log Review**: Check the sidecar `.log` file to ensure the `functionCall` and `functionResponse` were logged correctly.
4. **Tool Metadata**: Verify the tool appears in the prompt by checking the payload log in the terminal.

---

### Best Practices
- **Atomic Operations**: Always use temporary files (`.part`, `.tmp`) when updating the shared response array to prevent race conditions.
- **Input Validation**: Check for file existence or empty arguments before executing logic.
- **Error Feedback**: If a tool fails, return an informative error message in the JSON `result` field so the AI can explain the failure to the user.
- **UI Feedback**: Use `echo -e` for long-running tools to keep the user informed during execution.

