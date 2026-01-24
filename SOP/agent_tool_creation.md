# Standard Operating Procedure (SOP): Creating Agent Tools for "tell-me"

This SOP outlines the process for adding new agentic capabilities (tools) to the `tell-me` project.

---

### 1. Define the Tool Interface
Identify the functionality you want to add and define how the AI will interact with it.
- **Name**: A clear, snake_case name (e.g., `calculate_hash`).
- **Description**: A concise explanation of what the tool does and when the AI should use it.
- **Parameters**: A list of arguments the tool accepts, including their types (STRING, INTEGER, etc.) and descriptions.

### 2. Update Tool Definitions
Add the tool's schema to the centralized definitions file so the Gemini model becomes aware of it.
- **File**: `lib/tools.json`
- **Action**: Append a new JSON object to the array. **Ensure valid JSON syntax (commas between objects).**
- **Example**:
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

### 3. Implement the Tool Logic
Create the Bash function that executes the actual operation.
- **Location**: Create a new script (e.g., `lib/hash_tool.sh`) or add to an existing relevant file in `lib/`.
- **Function Name**: Must be prefixed with `tool_` followed by the name defined in step 2 (e.g., `tool_calculate_hash`).
- **Function Signature**: `tool_name "$FC_DATA" "$RESP_PARTS_FILE"`
  - `$1` (`FC_DATA`): The raw JSON tool call from the API.
  - `$2` (`RESP_PARTS_FILE`): The temp file where the result must be appended.

#### Implementation Template:
```bash
tool_calculate_hash() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    # 1. Extract Arguments
    local FILEPATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

    # 2. Logic & Execution
    # Tip: Use python3 -c "..." for complex math or data processing.
    if [[ -f "$FILEPATH" ]]; then
        local HASH=$(sha256sum "$FILEPATH" | awk '{print $1}')
        local RESULT="SHA256: $HASH"
    else
        local RESULT="Error: File not found."
    fi

    # 3. Format and Save Response
    # Always use 'jq' to build the JSON response to handle special characters safely.
    jq -n --arg name "calculate_hash" --arg res "$RESULT" \
        '{functionResponse: {name: $name, response: {result: $res}}}' > "${RESP_PARTS_FILE}.part"
    
    # 4. Append to the shared response array (Atomic Update)
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" \
        && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
```

### 4. Integration
The tool will be automatically loaded because `a.sh` sources all `.sh` files in the `lib/` directory during startup.
- **Available Globals**: Your tool can access global variables like `$file` (history path), `$AIMODEL`, `$MODE`, and `$BASE_DIR`.

### 5. Verification & Testing
1. **Syntax Check**: Run `bash -n lib/your_new_script.sh`.
2. **Functional Test**: Start a session (`ait`) and prompt the AI to use the tool:
   - *User: "What is the hash of the README.md file?"*
3. **Check Logs**: Ensure the tool call appears correctly in the terminal output and the sidecar `.log` file.
4. **Regression**: (Optional) Add a dedicated test case in the `tests/` directory to ensure future changes don't break the tool.

---

### 💡 Best Practices
- **Handle Errors Gracefully**: Always return a JSON response, even on failure (e.g., `{"result": "Error: ..."}`).
- **Python for Complexity**: If the logic involves floating-point math or complex string manipulation, wrap it in a `python3 -c` block.
- **Log Visibility**: Use `echo -e` within the tool to provide immediate visual feedback to the user if the tool performs a slow or critical operation.

