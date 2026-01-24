#!/bin/bash
# Resilience and Security tests for file_edit.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mocking parts of a.sh environment
export CURRENT_TURN=1
export MAX_TURNS=10

# Copy required libs to a mock lib structure
mkdir -p "$TEST_DIR/lib/core"
mkdir -p "$TEST_DIR/lib/tools/fs"
cp "$BASE_DIR/lib/core/utils.sh" "$TEST_DIR/lib/core/"
cp "$BASE_DIR/lib/tools/fs/file_edit.sh" "$TEST_DIR/lib/tools/fs/"

# Now set BASE_DIR for the sourced scripts
export BASE_DIR="$TEST_DIR"

# Source them
source "$TEST_DIR/lib/core/utils.sh"
source "$TEST_DIR/lib/tools/fs/file_edit.sh"

# Use local test dir as TMPDIR for backups
export TMPDIR="$TEST_DIR"
cd "$TEST_DIR"

RESP_FILE="$TEST_DIR/response.json"

pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

# Test 1: Permission Preservation
test_permission_preservation() {
    echo "Testing Permission Preservation..."
    local FILE="$TEST_DIR/perm_test.sh"
    echo "original" > "$FILE"
    chmod 755 "$FILE"
    
    local ARGS=$(jq -n --arg fp "$FILE" --arg c "updated" '{"args": {"filepath": $fp, "content": $c}}')
    echo "[]" > "$RESP_FILE"
    
    tool_update_file "$ARGS" "$RESP_FILE"
    
    if [ "$(cat "$FILE")" != "updated" ]; then fail "Update failed (content mismatch)"; fi

    local NEW_PERMS=$(stat -c %a "$FILE" 2>/dev/null || stat -f %Lp "$FILE")
    if [ "$NEW_PERMS" == "755" ]; then
        pass "Permissions preserved (755)"
    else
        fail "Permissions LOST! Expected 755, got $NEW_PERMS"
    fi
}

# Test 2: Rollback Resilience
test_rollback_resilience() {
    echo "Testing Rollback Resilience..."
    local FILE="$TEST_DIR/rollback_test.txt"
    echo "v1" > "$FILE"
    
    # Trigger backup via tool call
    local ARGS_V2=$(jq -n --arg fp "$FILE" --arg c "v2" '{"args": {"filepath": $fp, "content": $c}}')
    echo "[]" > "$RESP_FILE"
    tool_update_file "$ARGS_V2" "$RESP_FILE"
    
    if [ "$(cat "$FILE")" != "v2" ]; then fail "Update failed"; fi
    
    # Rollback
    local ROLL_ARGS=$(jq -n --arg fp "$FILE" '{"args": {"filepath": $fp}}')
    echo "[]" > "$RESP_FILE"
    tool_rollback_file "$ROLL_ARGS" "$RESP_FILE"
    
    if [ "$(cat "$FILE")" == "v1" ]; then
        pass "Rollback successful"
    else
        fail "Rollback failed! Content: $(cat "$FILE")"
    fi
}

# Test 3: Path Security (CWD enforcement)
test_path_security() {
    echo "Testing Path Security..."
    local OUTSIDE="/tmp/tellme_security_test_$(date +%s)"
    touch "$OUTSIDE"
    
    local ARGS=$(jq -n --arg fp "$OUTSIDE" --arg c "hack" '{"args": {"filepath": $fp, "content": $c}}')
    echo "[]" > "$RESP_FILE"
    
    # This should be blocked by check_path_safety
    tool_update_file "$ARGS" "$RESP_FILE"
    
    if grep -q "original" "$OUTSIDE" 2>/dev/null || [ "$(cat "$OUTSIDE" 2>/dev/null)" == "hack" ]; then
        fail "Security Breach: Wrote outside CWD!"
    else
        pass "Security Blocked outside write"
    fi
    rm -f "$OUTSIDE"
}

echo "Running file_edit Resilience Tests..."
test_permission_preservation
test_rollback_resilience
test_path_security

echo "------------------------------------------------"
echo "Resilience Tests PASSED"

# Test 4: Replace Text Permission Preservation
test_replace_permission_preservation() {
    echo "Testing Replace Text Permission Preservation..."
    local FILE="$TEST_DIR/replace_perm_test.sh"
    echo "Line 1" > "$FILE"
    chmod 755 "$FILE"
    
    local ARGS=$(jq -n --arg fp "$FILE" --arg o "Line 1" --arg n "Line 1 mod" '{"args": {"filepath": $fp, "old_text": $o, "new_text": $n}}')
    echo "[]" > "$RESP_FILE"
    
    tool_replace_text "$ARGS" "$RESP_FILE"
    
    local NEW_PERMS=$(stat -c %a "$FILE" 2>/dev/null || stat -f %Lp "$FILE")
    if [ "$NEW_PERMS" == "755" ]; then
        pass "Permissions preserved (755) in replace_text"
    else
        fail "Permissions LOST in replace_text! Expected 755, got $NEW_PERMS"
    fi
}

test_replace_permission_preservation


# Test 5: Insert Text Permission Preservation
test_insert_permission_preservation() {
    echo "Testing Insert Text Permission Preservation..."
    local FILE="$TEST_DIR/insert_perm_test.sh"
    echo "Line 1" > "$FILE"
    chmod 755 "$FILE"
    
    local ARGS=$(jq -n --arg fp "$FILE" --arg t "A.5" --arg ln "1" --arg p "after" '{"args": {"filepath": $fp, "text": $t, "line_number": $ln, "placement": $p}}')
    echo "[]" > "$RESP_FILE"
    
    tool_insert_text "$ARGS" "$RESP_FILE"
    
    local NEW_PERMS=$(stat -c %a "$FILE" 2>/dev/null || stat -f %Lp "$FILE")
    if [ "$NEW_PERMS" == "755" ]; then
        pass "Permissions preserved (755) in insert_text"
    else
        fail "Permissions LOST in insert_text! Expected 755, got $NEW_PERMS"
    fi
}

test_insert_permission_preservation


# Test 6: Apply Patch Permission Preservation
test_patch_permission_preservation() {
    echo "Testing Apply Patch Permission Preservation..."
    local FILE="$TEST_DIR/patch_perm_test.sh"
    echo "Line 1" > "$FILE"
    chmod 755 "$FILE"
    
    local PATCH="--- a/patch_perm_test.sh
+++ b/patch_perm_test.sh
@@ -1 +1 @@
-Line 1
+Line 1 mod
"
    local ARGS=$(jq -n --arg pc "$PATCH" '{"args": {"patch_content": $pc}}')
    echo "[]" > "$RESP_FILE"
    
    tool_apply_patch "$ARGS" "$RESP_FILE"
    
    local NEW_PERMS=$(stat -c %a "$FILE" 2>/dev/null || stat -f %Lp "$FILE")
    if [ "$NEW_PERMS" == "755" ]; then
        pass "Permissions preserved (755) in apply_patch"
    else
        fail "Permissions LOST in apply_patch! Expected 755, got $NEW_PERMS"
    fi
}

test_patch_permission_preservation


# Test 7: Append File Permission Preservation
test_append_permission_preservation() {
    echo "Testing Append File Permission Preservation..."
    local FILE="$TEST_DIR/append_perm_test.sh"
    echo "Line 1" > "$FILE"
    chmod 755 "$FILE"
    
    local ARGS=$(jq -n --arg fp "$FILE" --arg c "Line 2" '{"args": {"filepath": $fp, "content": $c}}')
    echo "[]" > "$RESP_FILE"
    
    tool_append_file "$ARGS" "$RESP_FILE"
    
    local NEW_PERMS=$(stat -c %a "$FILE" 2>/dev/null || stat -f %Lp "$FILE")
    if [ "$NEW_PERMS" == "755" ]; then
        pass "Permissions preserved (755) in append_file"
    else
        fail "Permissions LOST in append_file! Expected 755, got $NEW_PERMS"
    fi
}

test_append_permission_preservation

