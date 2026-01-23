#!/bin/bash

# Test script for lib/file_edit.sh

# Setup isolated environment
TEST_DIR=$(mktemp -d)
RESP_FILE="$TEST_DIR/test_edit_resp.json"
mkdir -p "$TEST_DIR/output/test_files"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Copy lib
cp -r lib "$TEST_DIR/"
cd "$TEST_DIR"

export CURRENT_TURN=0
export MAX_TURNS=10

source lib/utils.sh
source lib/file_edit.sh

# Mock backup_file to verify it's called
BACKUP_CALLED=0
backup_file() {
    BACKUP_CALLED=$((BACKUP_CALLED + 1))
    echo "Mock backup of $1"
}

# ---------------------------------------------------------
# Test update_file
# ---------------------------------------------------------
test_update_file() {
    echo "------------------------------------------------"
    echo "Running test_update_file..."
    local TEST_FILE="./output/test_files/update_test.txt"
    local CONTENT="Hello World"
    local ARGS=$(jq -n --arg fp "$TEST_FILE" --arg c "$CONTENT" '{"args": {"filepath": $fp, "content": $c}}')
    
    echo "[]" > "$RESP_FILE"
    BACKUP_CALLED=0
    
    tool_update_file "$ARGS" "$RESP_FILE"
    
    if [ "$(cat "$TEST_FILE")" == "$CONTENT" ]; then
         echo "PASS: File created with content"
    else
         echo "FAIL: File content mismatch"
         return 1
    fi
}

# ---------------------------------------------------------
# Test replace_text
# ---------------------------------------------------------
test_replace_text() {
    echo "------------------------------------------------"
    echo "Running test_replace_text..."
    local TEST_FILE="./output/test_files/replace_test.txt"
    echo "Line 1
Line 2
Line 3" > "$TEST_FILE"
    
    local OLD="Line 2"
    local NEW="Line Two Modified"
    local ARGS=$(jq -n --arg fp "$TEST_FILE" --arg o "$OLD" --arg n "$NEW" '{"args": {"filepath": $fp, "old_text": $o, "new_text": $n}}')
    
    echo "[]" > "$RESP_FILE"
    tool_replace_text "$ARGS" "$RESP_FILE"
    
    if grep -q "$NEW" "$TEST_FILE"; then
         echo "PASS: Text replaced"
    else
         echo "FAIL: Text replacement failed"
         return 1
    fi
}

# ---------------------------------------------------------
# Test insert_text
# ---------------------------------------------------------
test_insert_text() {
    echo "------------------------------------------------"
    echo "Running test_insert_text..."
    local TEST_FILE="./output/test_files/insert_test.txt"
    echo "A
B
C" > "$TEST_FILE"

    local ARGS=$(jq -n --arg fp "$TEST_FILE" --arg t "A.5" --arg ln "1" --arg p "after" '{"args": {"filepath": $fp, "text": $t, "line_number": $ln, "placement": $p}}')
    echo "[]" > "$RESP_FILE"
    tool_insert_text "$ARGS" "$RESP_FILE"
    
    local LINE2=$(sed -n '2p' "$TEST_FILE" | tr -d '\n')
    if [[ "$LINE2" == "A.5" ]]; then
        echo "PASS: Insert worked"
    else
        echo "FAIL: Insert failed"
        return 1
    fi
}

# ---------------------------------------------------------
# Test apply_patch
# ---------------------------------------------------------
test_apply_patch() {
    echo "------------------------------------------------"
    echo "Running test_apply_patch..."
    local TEST_FILE="./output/test_files/patch_test.txt"
    echo "Original Content" > "$TEST_FILE"
    
    local PATCH_CONTENT="--- a/output/test_files/patch_test.txt
+++ b/output/test_files/patch_test.txt
@@ -1 +1 @@
-Original Content
+Patched Content
"
    local ARGS=$(jq -n --arg pc "$PATCH_CONTENT" '{"args": {"patch_content": $pc}}')
    echo "[]" > "$RESP_FILE"
    tool_apply_patch "$ARGS" "$RESP_FILE"
    
    if [ "$(cat "$TEST_FILE")" == "Patched Content" ]; then
        echo "PASS: Patch applied successfully"
    else
        echo "FAIL: Patch failed"
        return 1
    fi
}

# ---------------------------------------------------------
# Test apply_patch No-Reject (Artifact Protection)
# ---------------------------------------------------------
test_apply_patch_no_reject() {
    echo "------------------------------------------------"
    echo "Running test_apply_patch_no_reject..."
    local TEST_FILE="./output/test_files/reject_test.txt"
    echo "This is the original content." > "$TEST_FILE"
    
    local BAD_PATCH="--- a/output/test_files/reject_test.txt
+++ b/output/test_files/reject_test.txt
@@ -1 +1 @@
-Mismatch Content Here
+New Content
"
    local ARGS=$(jq -n --arg pc "$BAD_PATCH" '{"args": {"patch_content": $pc}}')
    echo "[]" > "$RESP_FILE"
    tool_apply_patch "$ARGS" "$RESP_FILE"
    
    if [ -f "${TEST_FILE}.rej" ]; then
        echo "FAIL: Artifact .rej file was created!"
        return 1
    else
        echo "PASS: No .rej file created on failed patch"
    fi
}

# ---------------------------------------------------------
# Test append_file
# ---------------------------------------------------------
test_append_file() {
    echo "------------------------------------------------"
    echo "Running test_append_file..."
    local TEST_FILE="./output/test_files/append_test.txt"
    echo "Initial Content" > "$TEST_FILE"
    
    local CONTENT="Appended Content"
    local ARGS=$(jq -n --arg fp "$TEST_FILE" --arg c "$CONTENT" '{"args": {"filepath": $fp, "content": $c}}')
    echo "[]" > "$RESP_FILE"
    tool_append_file "$ARGS" "$RESP_FILE"
    
    if grep -q "Appended Content" "$TEST_FILE"; then
         echo "PASS: File appended correctly"
    else
         echo "FAIL: File append mismatch"
         return 1
    fi
}

FAILED=0
test_update_file || FAILED=1
test_replace_text || FAILED=1
test_insert_text || FAILED=1
test_apply_patch || FAILED=1
test_apply_patch_no_reject || FAILED=1
test_append_file || FAILED=1

if [ $FAILED -eq 0 ]; then
    echo "------------------------------------------------"
    echo "All file_edit tests passed."
    exit 0
else
    echo "------------------------------------------------"
    echo "Some file_edit tests failed."
    exit 1
fi

