#!/bin/bash

# Test script for lib/create_image.sh
# Covers: tool_create_image (Success and Failure scenarios)

mkdir -p output/test_assets/generated
# Override internal directory for testing
IMG_DIR="output/test_assets/generated"

export CURRENT_TURN=0
export MAX_TURNS=10
export AIURL="https://mock-api.com"
export TOKEN="mock-token"
RESP_FILE="./output/test_image_resp.json"

# Source dependencies
source lib/utils.sh
# We need to source create_image.sh but we might need to modify it or variables inside it?
# The tool function uses local variables. 
# However, `tool_create_image` hardcodes `assets/generated`.
# To test effectively without writing to the real `assets/` folder, I should probably 
# modify the tool to accept a config or variable, OR just accept that it writes to `assets/generated` and clean it up.
# Wait, `tool_create_image` has `local IMG_DIR="assets/generated"`. I cannot override a local variable from outside easily.
# But I can modify the file temporarily or just let it write to `assets/generated` and delete the test files.
# "assets/generated" is safe enough. I will filter the cleanup by the specific filename pattern I create.

source lib/create_image.sh

# Mock curl
# We use a global variable to determine what curl should return.
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
    
    # Mock a successful JSON response with a 1x1 pixel white PNG base64
    # iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNi\nAAAAAgABX5p8QAAAAABJRU5ErkJggg==
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
    
    # Verify Response
    local RES=$(jq -r '.[0].functionResponse.response.result' "$RESP_FILE")
    echo "Result: $RES"
    
    if [[ "$RES" == *"Image generated successfully"* ]]; then
        echo "PASS: Tool reported success"
    else
        echo "FAIL: Tool did not report success. Got: $RES"
        return 1
    fi
    
    # Verify File Creation
    # The filename is time-based, so we look for the most recent file in assets/generated
    local GEN_FILE=$(ls -t assets/generated/*.png | head -n 1)
    if [ -f "$GEN_FILE" ]; then
        echo "PASS: Image file created: $GEN_FILE"
        # Check size (should be small)
        if [ -s "$GEN_FILE" ]; then
             echo "PASS: File is not empty"
        else
             echo "FAIL: File is empty"
             return 1
        fi
        # Cleanup this specific file
        rm "$GEN_FILE"
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
    echo "Result: $RES"
    
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
    echo "Result: $RES"
    
    if [[ "$RES" == *"Model refused or returned text: I cannot generate that image."* ]]; then
        echo "PASS: Tool correctly handled text refusal"
    else
        echo "FAIL: Tool did not handle text refusal correctly. Got: $RES"
        return 1
    fi
}

# Run tests
FAILED=0
test_create_image_success || FAILED=1
test_create_image_error || FAILED=1
test_create_image_refusal || FAILED=1

# Cleanup
rm -f "$RESP_FILE"
rmdir output/test_assets/generated 2>/dev/null

if [ $FAILED -eq 0 ]; then
    echo "------------------------------------------------"
    echo "All create_image tests passed."
    exit 0
else
    echo "------------------------------------------------"
    echo "Some create_image tests failed."
    exit 1
fi

