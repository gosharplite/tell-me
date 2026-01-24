#!/bin/bash
# test_loop_termination.sh: Verifies tool calling loop behavior and Final Turn Protection.

set -e

# Setup isolated environment
TEST_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)
cp a.sh "$TEST_DIR/"
mkdir -p "$TEST_DIR/lib/core" "$TEST_DIR/lib/tools/sys" "$TEST_DIR/lib/tools/fs" "$TEST_DIR/lib/tools/git" "$TEST_DIR/lib/tools/media" "$TEST_DIR/lib/tools/dev"
mkdir -p "$TEST_DIR/bin"
mkdir -p "$TEST_DIR/output"

# Create mock config.yaml with low MAX_TURNS
CONFIG_NAME="test-loop.config.yaml"
cat <<EOF > "$TEST_DIR/$CONFIG_NAME"
AIURL: "http://mock-api"
AIMODEL: "mock-model"
PERSON: "System Instruction"
USE_SEARCH: "false"
MAX_TURNS: 1
EOF

# Mock dependencies
cp "$ORIGINAL_DIR/lib/core/utils.sh" "$TEST_DIR/lib/core/utils.sh"
cp "$ORIGINAL_DIR/lib/core/history_manager.sh" "$TEST_DIR/lib/core/history_manager.sh"
echo 'export TOKEN="mock-token"' > "$TEST_DIR/lib/core/auth.sh"
echo '[]' > "$TEST_DIR/lib/tools.json"
cat <<EOF > "$TEST_DIR/recap.sh"
#!/bin/bash
echo "Recap"
EOF
chmod +x "$TEST_DIR/recap.sh"

# Mock tool
cat <<EOF > "$TEST_DIR/lib/tools/sys/scratchpad.sh"
tool_manage_scratchpad() {
    local FC_DATA="\$1"
    local RESP_FILE="\$2"
    jq -n --arg name "manage_scratchpad" --arg content "result" \\
        '{functionResponse: {name: \$name, response: {result: \$content}}}' > "\${RESP_FILE}.part"
    jq --slurpfile new "\${RESP_FILE}.part" '. + \$new' "\$RESP_FILE" > "\${RESP_FILE}.tmp" && mv "\${RESP_FILE}.tmp" "\$RESP_FILE"
}
EOF

# Mock curl to return a function call on the first turn
cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
cat <<INNEREOF
{
  "candidates": [{
    "content": { "role": "model", "parts": [{ "functionCall": { "name": "manage_scratchpad", "args": { "action": "read" } } }] }
  }]
}
INNEREOF
EOF
chmod +x "$TEST_DIR/bin/curl"

export PATH="$TEST_DIR/bin:$PATH"
cd "$TEST_DIR"

echo "--- Running loop termination test (MAX_TURNS=1) ---"
BASE_DIR="$TEST_DIR" ./a.sh "$CONFIG_NAME" "test" > output.txt 2> error.log || true

# Verify that the warning message appears
if grep -q "MAX_TURNS (1) reached after tool execution" output.txt; then
    echo "PASS: Warning detected correctly."
else
    echo "FAIL: Warning message not found."
    echo "Output was:"
    cat output.txt
    exit 1
fi

# Verify history contains both the tool call AND the tool response
HISTORY_FILE="output/test-loop.json"
HAS_CALL=$(jq '.messages[] | select(.parts[0].functionCall.name == "manage_scratchpad")' "$HISTORY_FILE")
HAS_RESP=$(jq '.messages[] | select(.role == "function")' "$HISTORY_FILE")

if [ -n "$HAS_CALL" ] && [ -n "$HAS_RESP" ]; then
    echo "PASS: Tool call and response recorded in history before termination."
else
    echo "FAIL: Missing call or response in history."
    cat "$HISTORY_FILE"
    exit 1
fi

cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"
echo "Done."

