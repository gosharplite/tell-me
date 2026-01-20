#!/bin/bash

# Test script for lib/file_edit.sh
# Covers: update_file, replace_text, insert_text, apply_patch

mkdir -p output/test_files
export CURRENT_TURN=0
export MAX_TURNS=10
RESP_FILE="./output/test_edit_resp.json"

# Source dependencies
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
    
    # Test overwrite and backup
    local NEW_CONTENT="Hello Universe"
    ARGS=$(jq -n --arg fp "$TEST_FILE" --arg c "$NEW_CONTENT" '{"args": {"filepath": $fp, "content": $c}}')
    
    tool_update_file "$ARGS" "$RESP_FILE"
    
    if [ "$(cat "$TEST_FILE")" == "$NEW_CONTENT" ]; then
         echo "PASS: File overwritten"
    else
         echo "FAIL: File overwrite failed"
         return 1
    fi
    
    if [ $BACKUP_CALLED -gt 0 ]; then
        echo "PASS: Backup function called"
    else
        echo "FAIL: Backup function not called"
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
         cat "$TEST_FILE"
         return 1
    fi
    
    # Test missing text
    ARGS=$(jq -n --arg fp "$TEST_FILE" --arg o "NonExistent" --arg n "New" '{"args": {"filepath": $fp, "old_text": $o, "new_text": $n}}')
    echo "[]" > "$RESP_FILE"
    tool_replace_text "$ARGS" "$RESP_FILE"
    
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    if [[ "$RES" == *"Error: old_text not found"* ]]; then
        echo "PASS: Correctly failed on missing text"
    else
        echo "FAIL: Did not report error for missing text. Got: $RES"
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

    # Insert After Line 1
    local ARGS=$(jq -n --arg fp "$TEST_FILE" --arg t "A.5" --arg ln "1" --arg p "after" '{"args": {"filepath": $fp, "text": $t, "line_number": $ln, "placement": $p}}')
    
    echo "[]" > "$RESP_FILE"
    tool_insert_text "$ARGS" "$RESP_FILE"
    
    local LINE2=$(sed -n '2p' "$TEST_FILE" | tr -d '\n')
    if [[ "$LINE2" == "A.5" ]]; then
        echo "PASS: Insert After worked"
    else
        echo "FAIL: Insert After failed. Line 2 is '$LINE2'"
        cat "$TEST_FILE"
        return 1
    fi
    
    # Insert Before Line 1
    ARGS=$(jq -n --arg fp "$TEST_FILE" --arg t "Start" --arg ln "1" --arg p "before" '{"args": {"filepath": $fp, "text": $t, "line_number": $ln, "placement": $p}}')
    
    echo "[]" > "$RESP_FILE"
    tool_insert_text "$ARGS" "$RESP_FILE"
    
    local LINE1=$(sed -n '1p' "$TEST_FILE" | tr -d '\n')
    if [[ "$LINE1" == "Start" ]]; then
         echo "PASS: Insert Before worked"
    else
         echo "FAIL: Insert Before failed. Line 1 is '$LINE1'"
         cat "$TEST_FILE"
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
    
    # Create a unified diff
    # NOTE: The patch command usually expects relative paths or -p1 strips segments.
    # The tool uses -p1. So we need the patch header to look like a/path b/path.
    # But our TEST_FILE is ./output/...
    # Let's try to construct a valid patch.
    
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
        echo "--- Expected: Patched Content"
        echo "--- Got:"
        cat "$TEST_FILE"
        echo "--- Response:"
        jq -r '.[0].functionResponse.response.result' "$RESP_FILE"
        return 1
    fi
}

# Run tests
FAILED=0
test_update_file || FAILED=1
test_replace_text || FAILED=1
test_insert_text || FAILED=1
test_apply_patch || FAILED=1

# Cleanup
rm -rf output/test_files "$RESP_FILE"

if [ $FAILED -eq 0 ]; then
    echo "------------------------------------------------"
    echo "All file_edit tests passed."
    exit 0
else
    echo "------------------------------------------------"
    echo "Some file_edit tests failed."
    exit 1
fi