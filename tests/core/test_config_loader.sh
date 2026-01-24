#!/bin/bash
# Test for lib/core/config_loader.sh

# 1. Setup Environment
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 2. Source Dependencies
# config_loader.sh doesn't seem to have explicit hard dependencies, 
# but we'll mock what's needed.
source "$BASE_DIR/lib/core/config_loader.sh"

# 3. Define Assertions
pass() { echo -e "\033[0;32mPASS:\033[0m $1"; }
fail() { echo -e "\033[0;31mFAIL:\033[0m $1"; exit 1; }

cd "$TEST_DIR"

echo "Running config_loader tests..."

# Test 1: Discovery via Argument
echo "MODE: \"test-arg\"" > test_arg.yaml
load_config "test_arg.yaml" "$TEST_DIR"
if [[ "$MODE" == "test-arg" ]]; then
    pass "Discovery via argument"
else
    fail "Discovery via argument failed: MODE=$MODE"
fi

# Test 2: Discovery via Environment Variable
unset MODE
echo "MODE: \"test-env\"" > test_env.yaml
CONFIG_FILE="test_env.yaml" load_config "" "$TEST_DIR"
if [[ "$MODE" == "test-env" ]]; then
    pass "Discovery via CONFIG_FILE env"
else
    fail "Discovery via env failed: MODE=$MODE"
fi

# Test 3: Discovery via local config.yaml
unset MODE
unset CONFIG_FILE
echo "MODE: \"test-local\"" > config.yaml
load_config "" "$TEST_DIR"
if [[ "$MODE" == "test-local" ]]; then
    pass "Discovery via local config.yaml"
else
    fail "Discovery via local failed: MODE=$MODE"
fi
rm config.yaml

# Test 4: Discovery via output/ last assist
unset MODE
unset CONFIG_FILE
mkdir -p output
echo "MODE: \"test-history\"" > output/last-assist-gemini.config.yaml
# Sleep 1s to ensure timestamp logic is testable if needed, 
# but here we just need one file.
load_config "" "$TEST_DIR"
if [[ "$MODE" == "test-history" ]]; then
    pass "Discovery via output/ history"
else
    fail "Discovery via history failed: MODE=$MODE"
fi

# Test 5: Parsing logic with various characters
unset MODE
unset ANOTHER_VAR
cat <<EOF > complex.yaml
MODE: "complex-test"
ANOTHER_VAR: 'value-with-dash'
# Comment line
  SPACED_VAR :  "  extra spaces  "
EOF
load_config "complex.yaml" "$TEST_DIR"
if [[ "$MODE" == "complex-test" && "$ANOTHER_VAR" == "value-with-dash" && "$SPACED_VAR" == "  extra spaces  " ]]; then
    pass "Parsing logic (comments, quotes, spaces)"
else
    fail "Parsing logic failed: MODE=$MODE, ANOTHER_VAR=$ANOTHER_VAR, SPACED_VAR='$SPACED_VAR'"
fi

# Test 6: Error on missing config
rm -rf "$TEST_DIR"/*
unset CONFIG_FILE
if ! load_config "" "$TEST_DIR" 2>/dev/null; then
    pass "Correctly errors on missing config when none available"
else
    fail "Failed to error on missing config"
fi

