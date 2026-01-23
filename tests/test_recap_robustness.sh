#!/bin/bash
# Test for recap.sh robustness against null/empty parts (Regression for commit a19f3ba)

TEST_DIR=$(mktemp -d)
HISTORY_FILE="$TEST_DIR/null_history.json"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 1. Create a history file with missing parts and null content
cat <<EOF > "$HISTORY_FILE"
{
  "messages": [
    { "role": "user", "parts": [{ "text": "Hello" }] },
    { "role": "model" },
    { "role": "user", "parts": [{ "text": "Next" }] },
    { "role": "model", "parts": null }
  ]
}
EOF

echo "--- Testing Recap Robustness (Raw Mode) ---"
# We expect it not to crash and not to output "null" where text should be
OUTPUT=$(export file="$HISTORY_FILE"; ./recap.sh -r)

if echo "$OUTPUT" | grep -q "null"; then
    echo "FAIL: Output contains 'null' string"
    echo "$OUTPUT"
    exit 1
fi

if ! echo "$OUTPUT" | grep -q "<Empty Message>"; then
    echo "FAIL: Missing '<Empty Message>' placeholder for null parts"
    echo "$OUTPUT"
    exit 1
fi

echo "PASS: Recap handled null messages gracefully"

echo -e "\n--- Testing Recap Robustness (Markdown Mode) ---"
# Note: glow might not be installed in all test environments, so we test the markdown generator part
# By forcing --markdown which outputs raw markdown without calling glow
OUTPUT=$(export file="$HISTORY_FILE"; ./recap.sh --markdown)

if echo "$OUTPUT" | grep -q "null"; then
    echo "FAIL: Markdown output contains 'null' string"
    echo "$OUTPUT"
    exit 1
fi

if ! echo "$OUTPUT" | grep -q "\*\[Empty Message\]\*"; then
    echo "FAIL: Missing '*[Empty Message]*' placeholder in Markdown"
    echo "$OUTPUT"
    exit 1
fi

echo "PASS: Markdown recap handled null messages gracefully"

