#!/bin/bash
# Test for lib/tools/sys/read_url.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
source "$BASE_DIR/lib/core/utils.sh"
source "$BASE_DIR/lib/tools/sys/read_url.sh"

# 3. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

cd "$TEST_DIR"

# Mocks
export CURRENT_TURN=1
export MAX_TURNS=10
RESP_FILE="response.json"
echo "[]" > "$RESP_FILE"

# Mock curl for URL fetching
mkdir -p ./bin
cat << EOF > ./bin/curl
#!/bin/bash
echo "Mocked Web Content Body"
EOF
chmod +x ./bin/curl
export PATH="$PWD/bin:$PATH"

echo "Testing read_url..."

INPUT_URL=$(jq -n '{args: {url: "http://example.com"}}')
tool_read_url "$INPUT_URL" "$RESP_FILE"
RESULT=$(jq -r '.[-1].functionResponse.response.result' "$RESP_FILE")

if [[ "$RESULT" == *"Mocked Web Content Body"* ]]; then
    pass "read_url retrieved mocked content"
else
    fail "read_url failed: $RESULT"
fi

