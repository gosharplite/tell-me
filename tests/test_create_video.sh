#!/bin/bash
# Test script for lib/create_video.sh
# Covers: tool_create_video (Success, Error, Polling, Custom Duration)

export CURRENT_TURN=0
export MAX_TURNS=10
export AIURL="https://mock-api.com/models"
export TOKEN="mock-token"
RESP_FILE="./output/test_video_resp.json"
STATE_FILE="./output/test_video_state"
mkdir -p output

source lib/utils.sh
source lib/create_video.sh

# Mock curl with state persistence
TEST_MODE="none"
URL_LOG="./output/curl_urls.log"

curl() {
    # Log all arguments to capture URL regardless of flag position
    echo "$@" >> "$URL_LOG"

    # Read and increment counter atomically-ish
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
             # 1. Init Response
             jq -n '{ name: "projects/123/locations/us-central1/publishers/google/models/veo-3.1-generate-preview/operations/999" }'
        elif [ $CNT -eq 2 ]; then
             # 2. Poll Response (Running)
             jq -n '{ done: false, name: "projects/123/locations/us-central1/publishers/google/models/veo-3.1-generate-preview/operations/999" }'
        else
             # 3. Poll Response (Done with Base64)
             jq -n '{ done: true, response: { generatedSamples: [{ video: { bytesBase64Encoded: "AAAA" } }] } }'
        fi
    elif [ "$TEST_MODE" == "error_init" ]; then
        jq -n '{ error: { message: "Quota exceeded" } }'
    fi
}

# Mock gcloud
gcloud() {
    echo "mock-project"
    return 0
}

# Override sleep to be instant
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
    
    local GEN_FILE=$(ls -t assets/generated/*.mp4 2>/dev/null | head -n 1)
    if [ -f "$GEN_FILE" ]; then
         echo "PASS: Video file created: $GEN_FILE"
         rm "$GEN_FILE"
    else
         echo "FAIL: No mp4 found."
         return 1
    fi
}

test_create_video_duration() {
    echo "------------------------------------------------"
    echo "Running test_create_video_duration..."
    TEST_MODE="success_duration"
    echo "0" > "$STATE_FILE"
    : > "$URL_LOG"
    
    local PROMPT="Short clip"
    # Pass integer 3
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
    
    local PROMPT="Fast car"
    local ARGS='{"args":{"prompt":"Fast car", "fast_generation": true}}'
    
    echo "[]" > "$RESP_FILE"
    
    tool_create_video "$ARGS" "$RESP_FILE"
    
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    if [[ "$RES" == *"Video generated successfully"* ]]; then
         # Check if correct model was used in URL
         if grep -q "veo-3.0-fast-generate-001" "$URL_LOG"; then
             echo "PASS: Fast model requested"
         else
             echo "FAIL: Fast model NOT requested. URLs logged:"
             cat "$URL_LOG"
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

rm -f "$RESP_FILE" "$STATE_FILE" "$URL_LOG"

if [ $FAILED -eq 0 ]; then
    echo "All create_video tests passed."
    exit 0
else
    echo "Some create_video tests failed."
    exit 1
fi
