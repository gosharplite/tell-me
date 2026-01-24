#!/bin/bash
# test_rollback.sh: Verify that a.sh rolls back history if MAX_HISTORY_TOKENS is exceeded.

set -e

# Setup isolated environment
TEST_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)
cp a.sh "$TEST_DIR/"
mkdir -p "$TEST_DIR/lib/core" "$TEST_DIR/lib/tools/sys" "$TEST_DIR/lib/tools/fs" "$TEST_DIR/lib/tools/git" "$TEST_DIR/lib/tools/media" "$TEST_DIR/lib/tools/dev"
mkdir -p "$TEST_DIR/bin"
mkdir -p "$TEST_DIR/output"

# Set a custom BACKUP_DIR for the test
export TMPDIR="$TEST_DIR"
export BACKUP_DIR="$TEST_DIR/tellme_backups"
mkdir -p "$BACKUP_DIR"

# Copy libraries
cp "$ORIGINAL_DIR/lib/core/utils.sh" "$TEST_DIR/lib/core/utils.sh"
cp "$ORIGINAL_DIR/lib/core/history_manager.sh" "$TEST_DIR/lib/core/history_manager.sh"

echo 'export TOKEN="mock-token"' > "$TEST_DIR/lib/core/auth.sh"
echo '[]' > "$TEST_DIR/lib/tools.json"

# Mock tool
cat <<EOF > "$TEST_DIR/lib/large_tool.sh"
tool_get_large_data() {
    local FC_DATA="\$1"
    local RESP_FILE="\$2"
    local BIG_DATA=\$(printf 'A%.0s' {1..8000})
    jq -n --arg name "get_large_data" --arg content "\$BIG_DATA" \\
        '{functionResponse: {name: \$name, response: {result: \$content}}}' > "\${RESP_FILE}.part"
    jq --slurpfile new "\${RESP_FILE}.part" '. + \$new' "\$RESP_FILE" > "\${RESP_FILE}.tmp" && mv "\${RESP_FILE}.tmp" "\$RESP_FILE"
}
EOF

# Stub other tools
TOOLS="manage_scratchpad manage_tasks read_file read_image read_url sys_exec ask_user git_diff git_status git_blame git_log git_commit file_search file_edit"
for t in $TOOLS; do touch "$TEST_DIR/lib/${t}.sh"; done

echo '#!/bin/bash' > "$TEST_DIR/recap.sh"
chmod +x "$TEST_DIR/recap.sh"

export PATH="$TEST_DIR/bin:$PATH"
export AIURL="http://mock-api"
export AIMODEL="mock-model"
export PERSON="System Instruction"
export USE_SEARCH="false"
export FUNC_ROLE="function"

# ==============================================================================
# TEST 1: Rollback on Tool Result Overflow
# ==============================================================================
echo "--- Testing Rollback on Tool Result Overflow ---"

CONFIG_1="test1.config.yaml"
cat <<EOF > "$TEST_DIR/$CONFIG_1"
MAX_HISTORY_TOKENS: 2000
EOF

HISTORY_1="$TEST_DIR/output/test1.json"
echo '{"messages": []}' > "$HISTORY_1"

echo '{"candidates": [{"content": {"role": "model", "parts": [{"functionCall": {"name": "get_large_data", "args": {}}}]}}]}' > "$TEST_DIR/resp_tool.json"

cat <<EOF > "$TEST_DIR/bin/curl"
#!/bin/bash
cat "$TEST_DIR/resp_tool.json"
EOF
chmod +x "$TEST_DIR/bin/curl"

cd "$TEST_DIR"
set +e
BASE_DIR="$TEST_DIR" ./a.sh "$CONFIG_1" "Get some data" > output_1.log 2>&1
EXIT_CODE=$?
set -e

MSG_COUNT=$(jq '.messages | length' "$HISTORY_1")
if [ "$MSG_COUNT" -eq 1 ]; then
    echo "PASS: History rolled back to User Prompt only"
else
    echo "FAIL: History not rolled back correctly (Contains $MSG_COUNT messages)"
    cat "$HISTORY_1"
    exit 1
fi

# ==============================================================================
# TEST 2: Rollback on Large User Prompt
# ==============================================================================
echo "--- Testing Rollback on Large User Prompt ---"

CONFIG_2="test2.config.yaml"
cat <<EOF > "$TEST_DIR/$CONFIG_2"
MAX_HISTORY_TOKENS: 2000
EOF

HISTORY_2="$TEST_DIR/output/test2.json"
echo '{"messages": []}' > "$HISTORY_2"

LARGE_PROMPT=$(printf 'P%.0s' {1..8000})

set +e
BASE_DIR="$TEST_DIR" ./a.sh "$CONFIG_2" "$LARGE_PROMPT" > output_2.log 2>&1
EXIT_CODE=$?
set -e

MSG_COUNT=$(jq '.messages | length' "$HISTORY_2")
if [ "$MSG_COUNT" -eq 0 ]; then
    echo "PASS: History rolled back to empty state for large prompt"
else
    echo "FAIL: History not empty (Contains $MSG_COUNT messages)"
    exit 1
fi

cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"
echo "------------------------------------------------"
echo "Rollback Tests PASSED."

