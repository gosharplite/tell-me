#!/bin/bash
# Unit test for a.sh (Driver Logic)
# Hyper-Optimization Version: FULL MOCKING

set -e

# Setup isolated environment
TEST_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)

# --- ISOLATION ---
export TMPDIR="$TEST_DIR/tmp"
mkdir -p "$TMPDIR"
mkdir -p "$TEST_DIR/lib/core"
mkdir -p "$TEST_DIR/lib/tools/sys"
mkdir -p "$TEST_DIR/bin"
mkdir -p "$TEST_DIR/output"

# Copy a.sh
cp a.sh "$TEST_DIR/"

# Create mock config.yaml
CONFIG_NAME="test-session.config.yaml"
touch "$TEST_DIR/$CONFIG_NAME"

# --- AGGRESSIVE MOCKING OF ALL LIBRARIES ---

# 1. Config Loader
cat <<'EOF' > "$TEST_DIR/lib/core/config_loader.sh"
load_config() {
    export AIURL="http://mock-api"
    export AIMODEL="mock-model"
    export PERSON="System Instruction"
    export USE_SEARCH="false"
    export MAX_TURNS=5
    export THINKING_BUDGET=0
    export CONFIG_FILE="$1"
    return 0
}
get_thinking_config() { echo "LOW 4000"; }
EOF

# 2. History Manager (Use EOF for expansion)
cat <<EOF > "$TEST_DIR/lib/core/history_manager.sh"
update_history_file() {
    echo "HISTORY_UPDATE: \$1" >> "$TEST_DIR/history_calls.log"
}
prune_history_if_needed() { :; }
EOF

# 3. Utils (Use EOF for expansion)
cat <<EOF > "$TEST_DIR/lib/core/utils.sh"
get_log_timestamp() { echo "[TIME]"; }
log_usage() { :; }
display_session_totals() { :; }
log_tool_call() { echo "TOOL_CALL_LOGged" >> "$TEST_DIR/tool_calls.log"; }
estimate_and_check_payload() { echo "100"; }
EOF

# 4. Session Manager (Use EOF for expansion)
cat <<EOF > "$TEST_DIR/lib/core/session_manager.sh"
setup_session() {
    echo "$TEST_DIR/output/test-session"
}
EOF

# 5. Auth
echo 'export TOKEN="mock-token-123"' > "$TEST_DIR/lib/core/auth.sh"

# 6. Input Handler
cat <<'EOF' > "$TEST_DIR/lib/core/input_handler.sh"
process_user_input() {
    echo "$1"
}
EOF

# 7. API Client (Use EOF for expansion)
cat <<EOF > "$TEST_DIR/lib/core/api_client.sh"
call_gemini_api() {
    local STATE_FILE="$TEST_DIR/api_state"
    if [ ! -f "\$STATE_FILE" ]; then
        echo "2" > "\$STATE_FILE"
        cat "$TEST_DIR/resp_tool_happy.json" 2>/dev/null || cat "$TEST_DIR/resp_tool_unknown.json"
    else
        cat "$TEST_DIR/resp_final_happy.json" 2>/dev/null || cat "$TEST_DIR/resp_final_unknown.json"
    fi
}
EOF

# 8. Tool Executor (Use EOF for expansion)
cat <<EOF > "$TEST_DIR/lib/core/tool_executor.sh"
execute_tools() {
    echo "DEBUG: execute_tools called" >> "$TEST_DIR/tool_calls.log"
    echo '{"functionResponse": {"name": "mock_tool", "response": {"result": "Success"}}}' > "\$2"
}
EOF

# 9. Payload Manager
cat <<'EOF' > "$TEST_DIR/lib/core/payload_manager.sh"
build_payload() {
    echo "{}"
}
estimate_and_check_payload() {
    echo "100"
}
EOF

# --- Mocking Tools.json ---
echo '[]' > "$TEST_DIR/lib/tools.json"

# --- Patching a.sh ---
sed -i 's/while IFS= read -r -d '"''"' lib; do/for lib in lib\/core\/*.sh; do/' "$TEST_DIR/a.sh"
sed -i 's/done < <(find "$BASE_DIR\/lib" -maxdepth 3 -name "\*.sh" -print0)/done/' "$TEST_DIR/a.sh"

# Recap Mock
cat <<EOF > "$TEST_DIR/recap.sh"
#!/bin/bash
:
EOF
chmod +x "$TEST_DIR/recap.sh"

# --- External Binaries Mocks ---
for cmd in curl gcloud patch awk; do
    echo "#!/bin/bash" > "$TEST_DIR/bin/$cmd"
    echo "exit 0" >> "$TEST_DIR/bin/$cmd"
    chmod +x "$TEST_DIR/bin/$cmd"
done

ln -s "$(which jq)" "$TEST_DIR/bin/jq"

echo "#!/bin/bash" > "$TEST_DIR/bin/python3"
echo "exit 0" >> "$TEST_DIR/bin/python3"
chmod +x "$TEST_DIR/bin/python3"

cat <<EOF > "$TEST_DIR/bin/date"
#!/bin/bash
if [[ "\$1" == "+%s.%N" ]]; then
    echo "1000.000"
else
    echo "mock-date"
fi
EOF
chmod +x "$TEST_DIR/bin/date"

export PATH="$TEST_DIR/bin:$PATH"

# ==============================================================================
# TEST CASE 1: Happy Path
# ==============================================================================
echo "--- Test Case 1: Happy Path ---"

cat <<EOF > "$TEST_DIR/resp_tool_happy.json"
{
  "candidates": [{
    "content": { "role": "model", "parts": [{ "functionCall": { "name": "mock_tool", "args": {} } }] }
  }]
}
EOF
cat <<EOF > "$TEST_DIR/resp_final_happy.json"
{
  "candidates": [{
    "content": { "role": "model", "parts": [{ "text": "Done." }] }
  }]
}
EOF

cd "$TEST_DIR"
BASE_DIR="$TEST_DIR" ./a.sh "$CONFIG_NAME" "Do something" > output_1.txt 2> error_1.log || true

if ! grep -q "DEBUG: execute_tools called" tool_calls.log; then
    echo "FAIL: execute_tools not called"
    echo "--- stdout ---"
    cat output_1.txt
    echo "--- stderr ---"
    cat error_1.log
    exit 1
fi

echo "PASS: Happy path"

# ==============================================================================
# TEST CASE 2: No Tool
# ==============================================================================
echo "--- Test Case 2: No Tool ---"
rm -f tool_calls.log api_state
cat <<EOF > "$TEST_DIR/resp_tool_happy.json"
{
  "candidates": [{
    "content": { "role": "model", "parts": [{ "text": "Just text." }] }
  }]
}
EOF

BASE_DIR="$TEST_DIR" ./a.sh "$CONFIG_NAME" "Hello" > output_2.txt 2> error_2.log || true

if [ -f tool_calls.log ]; then
    echo "FAIL: execute_tools called unexpectedly"
    exit 1
fi
echo "PASS: No tool path"

cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"
echo "All tests passed."

