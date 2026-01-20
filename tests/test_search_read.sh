#!/bin/bash

# Test suite for Search and Read tools:
# - read_image
# - read_url
# - search_files
# - grep_definitions
# - find_file
# - get_tree

# Exit on error
set -e

# Setup temp environment
TEST_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)
cp lib/*.sh "$TEST_DIR/"
cp lib/tools.json "$TEST_DIR/"

cd "$TEST_DIR"

# Source dependencies
source ./utils.sh
source ./read_image.sh
source ./read_url.sh
source ./file_search.sh

# Mocks
export CURRENT_TURN=1
export MAX_TURNS=10
RESP_FILE="response.json"
echo "[]" > "$RESP_FILE"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS:${NC} $1"; }
fail() { echo -e "${RED}FAIL:${NC} $1"; exit 1; }

# Helper to read result from response.json
get_result() {
    jq -r '.[-1].functionResponse.response.result' "$RESP_FILE"
}

# --- Test read_image ---
echo "Testing read_image..."

# Create a tiny valid PNG (1x1 transparent pixel)
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" | base64 -d > test_image.png

# Case 1: Valid Image
INPUT_IMG=$(jq -n '{args: {filepath: "test_image.png"}}')
tool_read_image "$INPUT_IMG" "$RESP_FILE"
RESULT=$(get_result)

# Check if we got "Image loaded successfully" message
if [[ "$RESULT" == *"Image read successfully"* ]]; then
    # Check if the side-channel parts file was created/merged correctly
    # The tool appends to RESP_FILE. We expect an inlineData part before the functionResponse part?
    # Wait, the tool logic:
    # 1. Writes inlineData to temp file.
    # 2. Slurps it into RESP_FILE.
    # 3. Writes functionResponse to temp file.
    # 4. Slurps it into RESP_FILE.
    # So RESP_FILE should contain 2 new objects if it started empty (or we appended).
    # actually RESP_FILE starts with [], and the tool does `. + $new`.
    
    # Let's inspect the LAST element for the result message, which we did.
    # Let's inspect the SECOND TO LAST element for the image data.
    IMG_MIME=$(jq -r '.[-2].inlineData.mimeType' "$RESP_FILE")
    if [[ "$IMG_MIME" == "image/png" ]]; then
         pass "read_image processed png"
    else
         fail "read_image failed mime check: $IMG_MIME"
    fi
else
    fail "read_image failed result message: $RESULT"
fi

# Case 2: Invalid File Type
echo "not an image" > text_file.txt
INPUT_TXT=$(jq -n '{args: {filepath: "text_file.txt"}}')
tool_read_image "$INPUT_TXT" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Error: File is not a supported image"* ]]; then
    pass "read_image rejected text file"
else
    fail "read_image failed to reject text file: $RESULT"
fi

# --- Test read_url ---
echo "Testing read_url..."

# Mock curl for URL fetching
mkdir -p ./bin
cat << EOF > ./bin/curl
#!/bin/bash
echo "Mocked Web Content Body"
EOF
chmod +x ./bin/curl
export PATH="$PWD/bin:$PATH"

INPUT_URL=$(jq -n '{args: {url: "http://example.com"}}')
tool_read_url "$INPUT_URL" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"Mocked Web Content Body"* ]]; then
    pass "read_url retrieved mocked content"
else
    fail "read_url failed: $RESULT"
fi

# Restore PATH
# (Actually fine to leave it, subsequent tests use check_path_safety which uses python3, 
# but our mock passes through if urllib is not present. check_path_safety uses 'import os, sys', so it should pass through.)

# --- Test search_files ---
echo "Testing search_files..."

mkdir -p src
echo "function hello() { return 'world'; }" > src/main.js
echo "def hello(): return 'world'" > src/main.py
echo "Just some text" > src/notes.txt

INPUT_SEARCH=$(jq -n '{args: {query: "hello", path: "src"}}')
tool_search_files "$INPUT_SEARCH" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"src/main.js"* && "$RESULT" == *"src/main.py"* ]]; then
    pass "search_files found matches"
else
    fail "search_files failed: $RESULT"
fi

# --- Test grep_definitions ---
echo "Testing grep_definitions..."

INPUT_GREP=$(jq -n '{args: {path: "src"}}')
tool_grep_definitions "$INPUT_GREP" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"src/main.js"* && "$RESULT" == *"function"* ]]; then
    pass "grep_definitions found function"
else
    fail "grep_definitions failed: $RESULT"
fi

# Case with query filter
INPUT_GREP_Q=$(jq -n '{args: {path: "src", query: "main.py"}}')
tool_grep_definitions "$INPUT_GREP_Q" "$RESP_FILE"
RESULT=$(get_result)
if [[ "$RESULT" == *"src/main.py"* && "$RESULT" != *"src/main.js"* ]]; then
    pass "grep_definitions filtered correctly"
else
    fail "grep_definitions filter failed: $RESULT"
fi

# --- Test find_file ---
echo "Testing find_file..."

INPUT_FIND=$(jq -n '{args: {name_pattern: "*.txt", path: "src"}}')
tool_find_file "$INPUT_FIND" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"src/notes.txt"* && "$RESULT" != *"src/main.py"* ]]; then
    pass "find_file found pattern"
else
    fail "find_file failed: $RESULT"
fi

# --- Test get_tree ---
echo "Testing get_tree..."
# Ensure we have a structure
# src/main.js
# src/main.py
# src/notes.txt
# bin/python3 (from earlier)

INPUT_TREE=$(jq -n '{args: {path: ".", max_depth: 2}}')
tool_get_tree "$INPUT_TREE" "$RESP_FILE"
RESULT=$(get_result)

if [[ "$RESULT" == *"src"* && "$RESULT" == *"main.py"* ]]; then
    pass "get_tree listed structure"
else
    fail "get_tree failed: $RESULT"
fi


# Cleanup
cd "$ORIGINAL_DIR"
rm -rf "$TEST_DIR"

echo "All tests passed."

