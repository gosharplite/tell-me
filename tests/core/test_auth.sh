#!/bin/bash
# Test for lib/core/auth.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock gcloud
mkdir -p "$TEST_DIR/bin"
cat <<'EOF' > "$TEST_DIR/bin/gcloud"
#!/bin/bash
if [[ "$*" == *"print-access-token"* ]]; then
    echo "mock_token_$(echo "$*" | grep -o "scopes=[^ ]*" | cut -d= -f2 | sed 's/\//_/g')"
fi
EOF
chmod +x "$TEST_DIR/bin/gcloud"
export PATH="$TEST_DIR/bin:$PATH"

# Mock TMPDIR for token caching
export TMPDIR="$TEST_DIR"

pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

test_studio_auth() {
    echo "Testing Studio Auth..."
    export AIURL="https://generativelanguage.googleapis.com/v1beta/models"
    unset TOKEN
    rm -f "$TEST_DIR/gemini_token_studio.txt"
    
    source "$BASE_DIR/lib/core/auth.sh"
    
    if [[ "$TOKEN" == *"generative-language"* ]]; then
        pass "Studio token generated with correct scope"
    else
        fail "Studio token scope incorrect: $TOKEN"
    fi
    
    if [ -f "$TEST_DIR/gemini_token_studio.txt" ]; then
        pass "Studio token cached"
    else
        fail "Studio token not cached"
    fi
}

test_vertex_auth() {
    echo "Testing Vertex Auth..."
    export AIURL="https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/l/publishers/google/models"
    unset TOKEN
    rm -f "$TEST_DIR/gemini_token_vertex.txt"
    
    source "$BASE_DIR/lib/core/auth.sh"
    
    if [[ "$TOKEN" == *"cloud-platform"* ]]; then
        pass "Vertex token generated with correct scope"
    else
        fail "Vertex token scope incorrect: $TOKEN"
    fi
}

test_caching() {
    echo "Testing Token Caching..."
    export AIURL="https://generativelanguage.googleapis.com/v1beta/models"
    echo "cached_studio_token" > "$TEST_DIR/gemini_token_studio.txt"
    unset TOKEN
    
    source "$BASE_DIR/lib/core/auth.sh"
    
    if [[ "$TOKEN" == "cached_studio_token" ]]; then
        pass "Token retrieved from cache"
    else
        fail "Token not retrieved from cache: $TOKEN"
    fi
}

echo "Running Auth Tests..."
test_studio_auth
test_vertex_auth
test_caching

echo "------------------------------------------------"
echo "All tests passed successfully."
exit 0

