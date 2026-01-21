#!/bin/bash
# Test script for lib/create_video.sh

# Setup isolated environment
TEST_DIR=$(mktemp -d)
RESP_FILE="$TEST_DIR/test_video_resp.json"
STATE_FILE="$TEST_DIR/test_video_state"
URL_LOG="$TEST_DIR/curl_urls.log"

# We also need to mock `assets/generated` output or ensure the tool writes there.
# `create_video.sh` likely uses `assets/generated` relative to CWD.
# We should override this if possible, or run the test from inside `TEST_DIR`.
# Since `create_video.sh` is sourced, we can try to override `GEN_DIR` if it's a variable, 
# but usually it's hardcoded or local.
# Best approach: Copy lib to TEST_DIR, cd into TEST_DIR, and run everything there.

cp -r lib "$TEST_DIR/"
cd "$TEST_DIR"

export CURRENT_TURN=0
export MAX_TURNS=10
export AIURL="https://mock-api.com/models"
export TOKEN="mock-token"

cleanup() {
    cd ..
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

source lib/utils.sh
source lib/create_video.sh

# Mock curl with state persistence
TEST_MODE="none"

curl() {
    # Log all arguments
    echo "$@" >> "$URL_LOG"

    if [ -f "$STATE_FILE" ]; then
        local CNT=$(cat "$STATE_FILE")
        CNT=$((CNT + 1))
        echo "$CNT" > "$STATE_FILE"
    else
        echo "1" > "$STATE_FILE"
        local CNT=1
    fi
    
    if [ "$TEST_MODE" == "success" ] || [ "$TEST_MODE" == "success_duration" ]; then
        if [ $CNT -eq 1 ]; then
             jq -n '{ name: "projects/123/locations/us-central1/publishers/google/models/veo-3.1-generate-preview/operations/999" }'
        elif [ $CNT -eq 2 ]; then
             jq -n '{ done: false, name: "projects/123/locations/us-central1/publishers/google/models/veo-3.1-generate-preview/operations/999" }'
        else
             jq -n '{ done: true, response: { generatedSamples: [{ video: { bytesBase64Encoded: "AAAA" } }] } }'
        fi
    elif [ "$TEST_MODE" == "error_init" ]; then
        jq -n '{ error: { message: "Quota exceeded" } }'
    fi
}

gcloud() {
    echo "mock-project"
    return 0
}

sleep() {
    :
}

test_create_video_success() {
    echo "------------------------------------------------"
    echo "Running test_create_video_success..."
    TEST_MODE="success"
    echo "0" > "$STATE_FILE"
    : > "$URL_LOG"
    
    local PROMPT="A fast car"
    local ARGS=$(jq -n --arg p "$PROMPT" '{"args": {"prompt": $p}}')
    
    echo "[]" > "$RESP_FILE"
    
    tool_create_video "$ARGS" "$RESP_FILE"
    
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    
    if [[ "$RES" == *"Video generated successfully"* ]]; then
        echo "PASS: Tool reported success"
    else
        echo "FAIL: Tool did not report success. Got: $RES"
        return 1
    fi
    
    # Check current directory inside TEST_DIR
    local GEN_FILE=$(ls -t assets/generated/*.mp4 2>/dev/null | head -n 1)
    if [ -f "$GEN_FILE" ]; then
         echo "PASS: Video file created: $GEN_FILE"
    else
         echo "FAIL: No mp4 found in $(pwd)/assets/generated"
         return 1
    fi
}

test_create_video_duration() {
    echo "------------------------------------------------"
    echo "Running test_create_video_duration..."
    TEST_MODE="success_duration"
    echo "0" > "$STATE_FILE"
    : > "$URL_LOG"
    
    local ARGS='{"args":{"prompt":"Short clip", "duration_seconds": 3}}'
    
    echo "[]" > "$RESP_FILE"
    
    tool_create_video "$ARGS" "$RESP_FILE"
    
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    if [[ "$RES" == *"Video generated successfully"* ]]; then
         echo "PASS: Duration request completed"
    else
         echo "FAIL: Duration request failed: $RES"
         return 1
    fi
}

test_create_video_fast() {
    echo "------------------------------------------------"
    echo "Running test_create_video_fast..."
    TEST_MODE="success"
    echo "0" > "$STATE_FILE"
    : > "$URL_LOG"
    
    local ARGS='{"args":{"prompt":"Fast car", "fast_generation": true}}'
    
    echo "[]" > "$RESP_FILE"
    
    tool_create_video "$ARGS" "$RESP_FILE"
    
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    if [[ "$RES" == *"Video generated successfully"* ]]; then
         if grep -q "veo-3.1-fast-generate-preview" "$URL_LOG"; then
             echo "PASS: Fast model requested"
         else
             echo "FAIL: Fast model NOT requested."
             return 1
         fi
    else
        echo "FAIL: Fast request failed: $RES"
        return 1
    fi
}

test_create_video_error() {
    echo "------------------------------------------------"
    echo "Running test_create_video_error..."
    TEST_MODE="error_init"
    echo "0" > "$STATE_FILE"
    : > "$URL_LOG"
    
    local ARGS='{"args":{"prompt":"Fail"}}'
    echo "[]" > "$RESP_FILE"
    
    tool_create_video "$ARGS" "$RESP_FILE"
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    
    if [[ "$RES" == *"Error starting video generation: Quota exceeded"* ]]; then
        echo "PASS: Handled init error"
    else
        echo "FAIL: Init error mismatch. Got: $RES"
        return 1
    fi
}

FAILED=0
test_create_video_success || FAILED=1
test_create_video_duration || FAILED=1
test_create_video_fast || FAILED=1
test_create_video_error || FAILED=1

if [ $FAILED -eq 0 ]; then
    echo "All create_video tests passed."
    exit 0
else
    echo "Some create_video tests failed."
    exit 1
fi
