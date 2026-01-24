#!/bin/bash
# Test for lib/tools/media/read_image.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
source "$BASE_DIR/lib/core/utils.sh"
source "$BASE_DIR/lib/tools/media/read_image.sh"

# 3. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

cd "$TEST_DIR"

# Mocks
export CURRENT_TURN=1
export MAX_TURNS=10
RESP_FILE="response.json"
echo "[]" > "$RESP_FILE"

echo "Testing read_image..."

# Create a tiny valid PNG (1x1 transparent pixel)
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" | base64 -d > test_image.png

# Case 1: Valid Image
INPUT_IMG=$(jq -n '{args: {filepath: "test_image.png"}}')
tool_read_image "$INPUT_IMG" "$RESP_FILE"
RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [[ "$RESULT" == *"Image read successfully"* ]]; then
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
RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [[ "$RESULT" == *"Error: File is not a supported image"* ]]; then
    pass "read_image rejected text file"
else
    fail "read_image failed to reject text file: $RESULT"
fi

