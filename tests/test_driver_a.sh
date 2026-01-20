#!/bin/bash
# Unit test for a.sh (Driver Logic)
# Tests:
# 1. Happy Path: User Input -> Tool Call -> Tool Execution -> Final Response
# 2. Error Path: User Input -> Unknown Tool -> Error Feedback -> Final Response

set -e

# Setup isolated environment
TEST_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)
cp a.sh "$TEST_DIR/"
mkdir -p "$TEST_DIR/lib"
mkdir -p "$TEST_DIR/bin"

# --- Mocking Libraries ---

# 1. Mock lib/utils.sh (sourced by a.sh)
touch "$TEST_DIR/lib/utils.sh"

# 2. Mock lib/auth.sh
echo 'export TOKEN="mock-token-123"' > "$TEST_DIR/lib/auth.sh"

# 3. Mock lib/tools.json
echo '[]' > "$TEST_DIR/lib/tools.json"

# 4. Mock known tools
cat <<EOF > "$TEST_DIR/lib/scratchpad.sh"
tool_manage_scratchpad() {
    local FC_DATA="\$1"
    local RESP_FILE="\$2"
    echo "DEBUG: tool_manage_scratchpad called" >> "$TEST_DIR/tool_calls.log"
    local RESULT="Scratchpad Content: Plan A"
    jq -n --arg name "manage_scratchpad" --arg content "\$RESULT" \\
        '{functionResponse: {name: \$name, response: {result: \$content}}}' > "\${RESP_FILE}.part"
    jq --slurpfile new "\${RESP_FILE}.part" '. + \$new' "\$RESP_FILE" > "\${RESP_FILE}.tmp" && mv "\${RESP_FILE}.tmp" "\$RESP_FILE"
}
EOF

# Mock other tools to prevent 'No such file' errors
# Note: This list must match the source commands in a.sh
TOOLS="read_file read_image read_url sys_exec ask_user git_diff git_status git_blame git_log git_commit file_search file_edit"
for t in $TOOLS; do
    touch "$TEST_DIR/lib/${t}.sh"
done

# 5. Mock recap.sh
cat <<EOF > "$TEST_DIR/recap.sh"
#!/bin/bash
echo "Mock Recap Output"
EOF
chmod +x "$TEST_DIR/recap.sh"

# --- Shared Env Setup ---
export PATH="$TEST_DIR/bin:$PATH"
export AIURL="http://mock-api"
export AIMODEL="mock-model"
export PERSON="System Instruction"
export USE_SEARCH="false"
export FUNC_ROLE="function"
export file="$TEST_DIR/history.json"

# ==============================================================================
# TEST CASE 1: Happy Path (Known Tool)
# ==============================================================================
echo "--- Test Case 1: Happy Path ---"

# Setup History
echo '{"messages": []}' > "$file"

# Mock Curl for Happy Path
cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
STATE_FILE="$TEST_DIR/curl_state_1"
if [ ! -f "\$STATE_FILE" ]; then echo "1" > "\$STATE_FILE"; fi
STATE=\$(cat "\$STATE_FILE")
echo \$((STATE + 1)) > "\$STATE_FILE"

if [ "\$STATE" -eq "1" ]; then
    # Return Tool Call
    cat "$TEST_DIR/resp_tool_happy.json"
else
    # Return Final Answer
    cat "$TEST_DIR/resp_final_happy.json"
fi
EOF
chmod +x "$TEST_DIR/bin/curl"

# JSON Responses
cat <<EOF > "$TEST_DIR/resp_tool_happy.json"
{
  "candidates": [{
    "content": { "role": "model", "parts": [{ "functionCall": { "name": "manage_scratchpad", "args": { "action": "read" } } }] }
  }]
}
EOF
cat <<EOF > "$TEST_DIR/resp_final_happy.json"
{
  "candidates": [{
    "content": { "role": "model", "parts": [{ "text": "Plan A" }] },
    "usageMetadata": { "totalTokenCount": 100 }
  }]
}
EOF

# Run
cd "$TEST_DIR"
./a.sh "What is the plan?" > output_1.txt 2> error_1.log

# Assertions
if ! grep -q "DEBUG: tool_manage_scratchpad called" tool_calls.log; then
    echo "FAIL: Tool not called in happy path"
    exit 1
fi
echo "PASS: Happy path complete"


# ==============================================================================
# TEST CASE 2: Error Path (Unknown Tool)
# ==============================================================================
echo "--- Test Case 2: Unknown Tool ---"

# Clear logs
rm -f tool_calls.log
# Reset History
echo '{"messages": []}' > "$file"

# Mock Curl for Error Path
cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
STATE_FILE="$TEST_DIR/curl_state_2"
if [ ! -f "\$STATE_FILE" ]; then echo "1" > "\$STATE_FILE"; fi
STATE=\$(cat "\$STATE_FILE")
echo \$((STATE + 1)) > "\$STATE_FILE"

if [ "\$STATE" -eq "1" ]; then
    # Return Unknown Tool Call
    cat "$TEST_DIR/resp_tool_unknown.json"
else
    # Return Final Answer (Model responding to error)
    cat "$TEST_DIR/resp_final_unknown.json"
fi
EOF
chmod +x "$TEST_DIR/bin/curl"

# JSON Responses
cat <<EOF > "$TEST_DIR/resp_tool_unknown.json"
{
  "candidates": [{
    "content": { "role": "model", "parts": [{ "functionCall": { "name": "make_coffee", "args": {} } }] }
  }]
}
EOF
cat <<EOF > "$TEST_DIR/resp_final_unknown.json"
{
  "candidates": [{
    "content": { "role": "model", "parts": [{ "text": "I cannot make coffee." }] },
    "usageMetadata": { "totalTokenCount": 100 }
  }]
}
EOF

# Run
./a.sh "Make coffee" > output_2.txt 2> error_2.log

# Assertions
# 1. Verify NO execution of known tools
if [ -f tool_calls.log ]; then
    echo "FAIL: Unexpected tool execution"
    exit 1
fi

# 2. Verify History contains the Error Feedback
# We expect: User -> Model(make_coffee) -> Function(Error) -> Model(Text)
# jq check: Find a functionResponse containing "not found"
HAS_ERROR=$(jq '.messages[] | select(.role=="function") | .parts[0].functionResponse.response.result | contains("not found")' "$file")

if [ "$HAS_ERROR" == "true" ]; then
    echo "PASS: Error message injected into history"
else
    echo "FAIL: Error message not found in history"
    # Debug info
    echo "Contents of history.json:"
    cat "$file"
    exit 1
fi

# Cleanup
cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"

echo "------------------------------------------------"
echo "All tests passed."

