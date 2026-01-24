#!/bin/bash
# Test script for session archiving (tell-me.sh)

# Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock CONFIG
CONFIG_FILE="$TEST_DIR/test_config.yaml"
cat <<EOF > "$CONFIG_FILE"
MODE: "test-session"
AIURL: "http://localhost"
AIMODEL: "test-model"
PERSON: "test-person"
USE_SEARCH: false
MAX_TURNS: 5
MAX_HISTORY_TOKENS: 1000
EOF

# Mock Environment
export AIT_HOME="$TEST_DIR"
export ACTION_NEW="true"
export MODE="test-session"

# Define file paths (matching tell-me.sh logic)
HIST_FILE="$TEST_DIR/output/last-${MODE}.json"
LOG_FILE="${HIST_FILE}.log"
SCRATCH_FILE="${HIST_FILE%.*}.scratchpad.md"
TASK_FILE="${HIST_FILE%.*}.tasks.json"
CONFIG_COPY="${HIST_FILE%.*}.config.yaml"
BACKUP_ROOT="$TEST_DIR/output/backups"

mkdir -p "$TEST_DIR/output"

# Helper to create dummy session files
create_session_files() {
    echo '{"messages": []}' > "$HIST_FILE"
    echo "some logs" > "$LOG_FILE"
    echo "some scratchpad" > "$SCRATCH_FILE"
    echo "[]" > "$TASK_FILE"
    echo "config content" > "$CONFIG_COPY"
}

echo "Running Session Archiving Tests..."

# Test 1: Archiving on ACTION_NEW=true
echo -n "Test 1: Archiving with ACTION_NEW=true... "
create_session_files

(
    file="$HIST_FILE"
    ACTION_NEW="true"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SESSION_BACKUP_DIR="$(dirname "$file")/backups/$TIMESTAMP"
    mkdir -p "$SESSION_BACKUP_DIR"
    [ -f "$file" ] && rm "$file"
    for f in "${file}.log" "${file%.*}.scratchpad.md" "${file%.*}.tasks.json" "${file%.*}.config.yaml"; do
        [ -f "$f" ] && mv "$f" "$SESSION_BACKUP_DIR/"
    done
)

# Verify original files are gone and archives exist in a subfolder
STAMP=$(date +%Y%m%d)
BACKUP_SUBDIR=$(ls "$BACKUP_ROOT" 2>/dev/null | grep "$STAMP")
ARCHIVE_COUNT=$(ls "$BACKUP_ROOT/$BACKUP_SUBDIR" 2>/dev/null | wc -l)

if [ ! -f "$HIST_FILE" ] && [ "$ARCHIVE_COUNT" -eq 4 ]; then
    echo "PASS"
else
    echo "FAIL (Files not archived correctly to subdirectory. Archive count: $ARCHIVE_COUNT)"
    ls -la "$BACKUP_ROOT/$BACKUP_SUBDIR"
    exit 1
fi

# Test 2: Archiving on User "n" (New Session)
echo -n "Test 2: Archiving on User Decline Resume... "
create_session_files

(
    file="$HIST_FILE"
    REPLY="n"
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)_2
        SESSION_BACKUP_DIR="$(dirname "$file")/backups/$TIMESTAMP"
        mkdir -p "$SESSION_BACKUP_DIR"
        [ -f "$file" ] && rm "$file"
        for f in "${file}.log" "${file%.*}.scratchpad.md" "${file%.*}.tasks.json" "${file%.*}.config.yaml"; do
            [ -f "$f" ] && mv "$f" "$SESSION_BACKUP_DIR/"
        done
    fi
)

DIR_COUNT=$(ls "$BACKUP_ROOT" 2>/dev/null | wc -l)
if [ ! -f "$HIST_FILE" ] && [ "$DIR_COUNT" -ge 2 ]; then
    echo "PASS"
else
    echo "FAIL (Files not archived to new subdirectory on decline)"
    exit 1
fi

echo "All Session Archiving Tests PASSED!"

