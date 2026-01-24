#!/bin/bash

# Test script for lib/create_image.sh

# Setup isolated environment
TEST_DIR=$(mktemp -d)
RESP_FILE="$TEST_DIR/test_image_resp.json"

# Copy lib to TEST_DIR to ensure assets/generated is created relative to CWD inside TEST_DIR
cp -r lib "$TEST_DIR/"
cd "$TEST_DIR"

cleanup() {
    cd ..
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

export CURRENT_TURN=0
export MAX_TURNS=10
export AIURL="https://mock-api.com"
export TOKEN="mock-token"

source lib/core/utils.sh
source lib/tools/media/create_image.sh

# Mock curl
CURL_RESPONSE_BODY=""
curl() {
    echo "$CURL_RESPONSE_BODY"
}

# ---------------------------------------------------------
# Test Create Image - Success
# ---------------------------------------------------------
test_create_image_success() {
    echo "------------------------------------------------"
    echo "Running test_create_image_success..."

    local PROMPT="A test image"
    local ARGS=$(jq -n --arg p "$PROMPT" --arg ar "16:9" '{"args": {"prompt": $p, "aspect_ratio": $ar}}')
    
    local B64_DATA="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNiAAAAAgABX5p8QAAAAABJRU5ErkJggg=="
    
    CURL_RESPONSE_BODY=$(jq -n --arg b64 "$B64_DATA" '{
        candidates: [{
            content: {
                parts: [{
                    inlineData: {
                        mimeType: "image/png",
                        data: $b64
                    }
                }]
            }
        }]
    }')
    
    echo "[]" > "$RESP_FILE"
    
    tool_create_image "$ARGS" "$RESP_FILE"
    
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    
    if [[ "$RES" == *"Image generated successfully"* ]]; then
        echo "PASS: Tool reported success"
    else
        echo "FAIL: Tool did not report success. Got: $RES"
        return 1
    fi
    
    local GEN_FILE=$(ls -t assets/generated/*.png | head -n 1)
    if [ -f "$GEN_FILE" ]; then
        echo "PASS: Image file created: $GEN_FILE"
        if [ -s "$GEN_FILE" ]; then
             echo "PASS: File is not empty"
        else
             echo "FAIL: File is empty"
             return 1
        fi
    else
        echo "FAIL: No image file found in assets/generated/"
        return 1
    fi
}

# ---------------------------------------------------------
# Test Create Image - API Error
# ---------------------------------------------------------
test_create_image_error() {
    echo "------------------------------------------------"
    echo "Running test_create_image_error..."

    local PROMPT="A failure case"
    local ARGS=$(jq -n --arg p "$PROMPT" '{"args": {"prompt": $p}}')
    
    CURL_RESPONSE_BODY=$(jq -n '{
        error: {
            code: 400,
            message: "Invalid prompt"
        }
    }')
    
    echo "[]" > "$RESP_FILE"
    
    tool_create_image "$ARGS" "$RESP_FILE"
    
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    
    if [[ "$RES" == *"Error generating image: Invalid prompt"* ]]; then
        echo "PASS: Tool correctly reported API error"
    else
        echo "FAIL: Tool did not report correct error. Got: $RES"
        return 1
    fi
}

# ---------------------------------------------------------
# Test Create Image - Refusal (Text Response)
# ---------------------------------------------------------
test_create_image_refusal() {
    echo "------------------------------------------------"
    echo "Running test_create_image_refusal..."

    local PROMPT="Draw something bad"
    local ARGS=$(jq -n --arg p "$PROMPT" '{"args": {"prompt": $p}}')
    
    CURL_RESPONSE_BODY=$(jq -n '{
        candidates: [{
            content: {
                parts: [{
                    text: "I cannot generate that image."
                }]
            }
        }]
    }')
    
    echo "[]" > "$RESP_FILE"
    
    tool_create_image "$ARGS" "$RESP_FILE"
    
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    
    if [[ "$RES" == *"Model refused or returned text: I cannot generate that image."* ]]; then
        echo "PASS: Tool correctly handled text refusal"
    else
        echo "FAIL: Tool did not handle text refusal correctly. Got: $RES"
        return 1
    fi
}

FAILED=0
test_create_image_success || FAILED=1
test_create_image_error || FAILED=1
test_create_image_refusal || FAILED=1

if [ $FAILED -eq 0 ]; then
    echo "------------------------------------------------"
    echo "All create_image tests passed."
    exit 0
else
    echo "------------------------------------------------"
    echo "Some create_image tests failed."
    exit 1
fi
