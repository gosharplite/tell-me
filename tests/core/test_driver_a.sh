#!/bin/bash
# Unit test for a.sh (Driver Logic)
# Extreme-Optimization Version

set -e

# Setup isolated environment
TEST_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)

# --- ISOLATION: Prevent slow backup pruning in utils.sh ---
export TMPDIR="$TEST_DIR/tmp"
mkdir -p "$TMPDIR"

cp a.sh "$TEST_DIR/"
mkdir -p "$TEST_DIR/lib/core"
mkdir -p "$TEST_DIR/lib/tools/sys"
mkdir -p "$TEST_DIR/bin"
mkdir -p "$TEST_DIR/output"

# Create mock config.yaml
CONFIG_NAME="test-session.config.yaml"
cat <<EOF > "$TEST_DIR/$CONFIG_NAME"
AIURL: "http://mock-api"
AIMODEL: "mock-model"
PERSON: "System Instruction"
USE_SEARCH: "false"
MAX_TURNS: 5
EOF

# --- Mocking Libraries ---
cp "$ORIGINAL_DIR/lib/core/"*.sh "$TEST_DIR/lib/core/"
echo 'export TOKEN="mock-token-123"' > "$TEST_DIR/lib/core/auth.sh"
echo '[]' > "$TEST_DIR/lib/tools.json"

cat <<EOF > "$TEST_DIR/lib/tools/sys/scratchpad.sh"
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

# --- SURGICAL OPTIMIZATION: Speed up sourcing loop in a.sh ---
sed -i 's/while IFS= read -r -d '"''"' lib; do/for lib in lib\/core\/*.sh lib\/tools\/sys\/scratchpad.sh; do/' "$TEST_DIR/a.sh"
sed -i 's/done < <(find "$BASE_DIR\/lib" -maxdepth 3 -name "\*.sh" -print0)/done/' "$TEST_DIR/a.sh"

cat <<EOF > "$TEST_DIR/recap.sh"
#!/bin/bash
echo "Mock Recap Output"
EOF
chmod +x "$TEST_DIR/recap.sh"

# --- Mocking external processes to save spawn time ---
# Optimized python3 mock
cat <<EOF > "$TEST_DIR/bin/python3"
#!/bin/bash
if [[ "\$*" == *"import sys, shlex"* ]]; then
    echo "AIURL='http://mock-api'"
    echo "AIMODEL='mock-model'"
    echo "PERSON='System Instruction'"
    echo "USE_SEARCH='false'"
    echo "MAX_TURNS='5'"
    exit 0
fi
exit 0
EOF
chmod +x "$TEST_DIR/bin/python3"

# Mock date to avoid process overhead and slow syscalls
cat <<EOF > "$TEST_DIR/bin/date"
#!/bin/bash
if [[ "\$1" == "+%s.%N" ]]; then
    echo "1700000000.000000000"
elif [[ "\$1" == "+%H:%M:%S" ]]; then
    echo "12:00:00"
else
    /usr/bin/date "\$@"
fi
EOF
chmod +x "$TEST_DIR/bin/date"

export PATH="$TEST_DIR/bin:$PATH"
export AIURL="http://mock-api"
export AIMODEL="mock-model"
export PERSON="System Instruction"
export USE_SEARCH="false"
export FUNC_ROLE="function"

# The history file
HISTORY_FILE="$TEST_DIR/output/test-session.json"

# ==============================================================================
# TEST CASE 1: Happy Path (Known Tool)
# ==============================================================================
echo "--- Test Case 1: Happy Path ---"

mkdir -p "$TEST_DIR/output"
echo '{"messages": []}' > "$HISTORY_FILE"

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

# Inject mock curl for Case 1
cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
STATE_FILE="$TEST_DIR/curl_state_1"
[ -f "\$STATE_FILE" ] || echo "1" > "\$STATE_FILE"
STATE=\$(cat "\$STATE_FILE")
echo \$((STATE + 1)) > "\$STATE_FILE"
if [ "\$STATE" -eq "1" ]; then cat "$TEST_DIR/resp_tool_happy.json"
else cat "$TEST_DIR/resp_final_happy.json"; fi
EOF
chmod +x "$TEST_DIR/bin/curl"

cd "$TEST_DIR"
BASE_DIR="$TEST_DIR" ./a.sh "$CONFIG_NAME" "What is the plan?" > output_1.txt 2> error_1.log

if ! grep -q "DEBUG: tool_manage_scratchpad called" tool_calls.log; then
    echo "FAIL: Tool not called in happy path"
    exit 1
fi
echo "PASS: Happy path complete"

# ==============================================================================
# TEST CASE 2: Error Path (Unknown Tool)
# ==============================================================================
echo "--- Test Case 2: Unknown Tool ---"

rm -f tool_calls.log
echo '{"messages": []}' > "$HISTORY_FILE"

cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
STATE_FILE="$TEST_DIR/curl_state_2"
[ -f "\$STATE_FILE" ] || echo "1" > "\$STATE_FILE"
STATE=\$(cat "\$STATE_FILE")
echo \$((STATE + 1)) > "\$STATE_FILE"
if [ "\$STATE" -eq "1" ]; then cat "$TEST_DIR/resp_tool_unknown.json"
else cat "$TEST_DIR/resp_final_unknown.json"; fi
EOF
chmod +x "$TEST_DIR/bin/curl"

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

BASE_DIR="$TEST_DIR" ./a.sh "$CONFIG_NAME" "Make coffee" > output_2.txt 2> error_2.log

if [ -f tool_calls.log ]; then
    echo "FAIL: Unexpected tool execution"
    exit 1
fi

HAS_ERROR=$(jq '.messages[] | select(.role=="function") | .parts[0].functionResponse.response.result | contains("not found")' "$HISTORY_FILE")

if [ "$HAS_ERROR" == "true" ]; then
    echo "PASS: Error message injected into history"
else
    echo "FAIL: Error message not found in history"
    exit 1
fi

cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"
echo "------------------------------------------------"
echo "All tests passed."

