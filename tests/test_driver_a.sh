#!/bin/bash
# Unit test for a.sh (Driver Logic)
# Tests the main interaction loop: User Input -> Tool Call -> Tool Execution -> Final Response

set -e

# Setup isolated environment
TEST_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)
cp a.sh "$TEST_DIR/"
mkdir -p "$TEST_DIR/lib"
mkdir -p "$TEST_DIR/bin"

# --- Mocking Libraries ---

# 1. Mock lib/utils.sh (sourced by a.sh)
# a.sh uses `source "$BASE_DIR/lib/utils.sh"`
touch "$TEST_DIR/lib/utils.sh"

# 2. Mock lib/auth.sh
echo 'export TOKEN="mock-token-123"' > "$TEST_DIR/lib/auth.sh"

# 3. Mock lib/tools.json
echo '[]' > "$TEST_DIR/lib/tools.json"

# 4. Mock a specific tool library (scratchpad) to verify tool dispatch
# We verify that a.sh calls tool_manage_scratchpad when the API requests it.
cat <<EOF > "$TEST_DIR/lib/scratchpad.sh"
tool_manage_scratchpad() {
    local FC_DATA="\$1"
    local RESP_FILE="\$2"
    echo "DEBUG: tool_manage_scratchpad called" >> "$TEST_DIR/tool_calls.log"
    
    # Verify we received correct data
    local ACTION=\$(echo "\$FC_DATA" | jq -r '.args.action')
    if [ "\$ACTION" == "read" ]; then
         echo "DEBUG: Action validated" >> "$TEST_DIR/tool_calls.log"
    fi

    # Write tool response
    local RESULT="Scratchpad Content: Plan A"
    jq -n --arg name "manage_scratchpad" --arg content "\$RESULT" \\
        '{functionResponse: {name: \$name, response: {result: \$content}}}' > "\${RESP_FILE}.part"
    
    # Append to response file (mimic tool behavior)
    jq --slurpfile new "\${RESP_FILE}.part" '. + \$new' "\$RESP_FILE" > "\${RESP_FILE}.tmp" && mv "\${RESP_FILE}.tmp" "\$RESP_FILE"
}
EOF

# 5. Mock other tools to prevent 'No such file' errors during sourcing
TOOLS="read_file read_image read_url sys_exec ask_user git_diff git_status git_blame git_log git_commit file_search file_edit"
for t in $TOOLS; do
    touch "$TEST_DIR/lib/${t}.sh"
done

# 6. Mock recap.sh (called at the end)
cat <<EOF > "$TEST_DIR/recap.sh"
#!/bin/bash
echo "Mock Recap Output: Final Answer"
EOF
chmod +x "$TEST_DIR/recap.sh"

# --- Mocking External Binaries ---

# Mock curl to simulate Gemini API responses
# It needs to return a Sequence of responses:
# 1. First call: Return a "Function Call" (manage_scratchpad)
# 2. Second call: Return a "Final Text Answer" (after tool output is submitted)
cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
# Mock Curl

# Read iteration state
STATE_FILE="$TEST_DIR/curl_state"
if [ ! -f "\$STATE_FILE" ]; then echo "1" > "\$STATE_FILE"; fi
STATE=\$(cat "\$STATE_FILE")

# Increment state for next call
echo \$((STATE + 1)) > "\$STATE_FILE"

if [ "\$STATE" -eq "1" ]; then
    # Return Tool Call
    cat "$TEST_DIR/resp_tool.json"
else
    # Return Final Answer
    cat "$TEST_DIR/resp_final.json"
fi
EOF
chmod +x "$TEST_DIR/bin/curl"

# --- Create Mock API Responses ---

# Response 1: Model asks to read scratchpad
cat <<EOF > "$TEST_DIR/resp_tool.json"
{
  "candidates": [
    {
      "content": {
        "role": "model",
        "parts": [
          {
            "functionCall": {
              "name": "manage_scratchpad",
              "args": { "action": "read" }
            }
          }
        ]
      },
      "finishReason": "STOP",
      "usageMetadata": { "totalTokenCount": 100 }
    }
  ]
}
EOF

# Response 2: Model gives final answer
cat <<EOF > "$TEST_DIR/resp_final.json"
{
  "candidates": [
    {
      "content": {
        "role": "model",
        "parts": [
          {
            "text": "The plan is Plan A."
          }
        ]
      },
      "finishReason": "STOP",
      "groundingMetadata": {
        "webSearchQueries": ["query1"]
      },
      "usageMetadata": { 
          "cachedContentTokenCount": 0,
          "promptTokenCount": 150,
          "candidatesTokenCount": 20,
          "totalTokenCount": 170
      }
    }
  ]
}
EOF

# --- Environment Setup ---
export PATH="$TEST_DIR/bin:$PATH"
export AIURL="http://mock-api"
export AIMODEL="mock-model"
export PERSON="System Instruction"
export USE_SEARCH="false"
export FUNC_ROLE="function" # Required by a.sh to construct tool response
export file="$TEST_DIR/history.json" # The history file

# Initialize empty history
echo '{"messages": []}' > "$file"

# --- Run Test ---
cd "$TEST_DIR"

echo "------------------------------------------------"
echo "Running a.sh (Tool Loop Integration Test)..."

./a.sh "What is the plan?" > output.txt 2> error.log

EXIT_CODE=$?

# --- Assertions ---

FAILED=0

if [ $EXIT_CODE -ne 0 ]; then
    echo "FAIL: a.sh exited with error code $EXIT_CODE"
    cat error.log
    FAILED=1
fi

# 1. Check if Tool was called
if grep -q "DEBUG: tool_manage_scratchpad called" tool_calls.log; then
    echo "PASS: Tool dispatched correctly"
else
    echo "FAIL: Tool was not called"
    FAILED=1
fi

# 2. Check if History was updated correctly
# We expect 4 messages:
# 1. User: "What is the plan?"
# 2. Model: FunctionCall(manage_scratchpad)
# 3. Function: Result("Plan A")
# 4. Model: Text("The plan is Plan A.")

MSG_COUNT=$(jq '.messages | length' "$file")
if [ "$MSG_COUNT" -eq 4 ]; then
    echo "PASS: History contains 4 turns"
else
    echo "FAIL: History has $MSG_COUNT turns (Expected 4)"
    cat "$file"
    FAILED=1
fi

# 3. Check if Function Response has correct role
ROLE_3=$(jq -r '.messages[2].role' "$file")
if [ "$ROLE_3" == "function" ]; then
     echo "PASS: Tool response role is 'function'"
else
     echo "FAIL: Tool response role is '$ROLE_3'"
     FAILED=1
fi

# 4. Check Output
if grep -q "Mock Recap Output" output.txt; then
    echo "PASS: Output rendered via recap"
else
    echo "FAIL: Output missing"
    cat output.txt
    FAILED=1
fi

# 5. Check Grounding Log
if grep -q "Grounding" output.txt && grep -q "query1" output.txt; then
    echo "PASS: Grounding info displayed"
else
    echo "FAIL: Grounding info missing"
    FAILED=1
fi

# Cleanup
cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"

if [ $FAILED -eq 0 ]; then
    echo "------------------------------------------------"
    echo "All a.sh driver tests passed."
    exit 0
else
    echo "------------------------------------------------"
    echo "Tests failed."
    exit 1
fi

