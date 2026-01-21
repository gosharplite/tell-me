# Function to generate images using Gemini 3 Pro Image model
# Usage: tool_create_image '{ "args": { "prompt": "...", "aspect_ratio": "16:9" } }' "output_file"

tool_create_image() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    
    # Extract Arguments
    local PROMPT=$(echo "$FC_DATA" | jq -r '.args.prompt')
    local ASPECT_RATIO=$(echo "$FC_DATA" | jq -r '.args.aspect_ratio // "1:1"')
    
    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Generating Image: \"${PROMPT:0:50}...\" ($ASPECT_RATIO)\033[0m"

    local RESULT_MSG=""
    local IMG_DIR="assets/generated"
    mkdir -p "$IMG_DIR"
    
    # Construct Filename
    local SAFE_TITLE=$(echo "$PROMPT" | tr -dc 'a-zA-Z0-9' | head -c 20)
    [ -z "$SAFE_TITLE" ] && SAFE_TITLE="image"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local OUT_FILE="${IMG_DIR}/${TIMESTAMP}_${SAFE_TITLE}.png"
    
    # Construct Payload
    # We append aspect ratio to prompt to guide the model, as schema varies.
    # We strictly request responseModalities: ["IMAGE"]
    local MODIFIED_PROMPT="$PROMPT\n(Aspect Ratio: $ASPECT_RATIO)"
    
    local PAYLOAD_FILE=$(mktemp)
    
    jq -n \
      --arg prompt "$MODIFIED_PROMPT" \
      '{
        contents: [{ role: "user", parts: [{ text: $prompt }] }],
        generationConfig: {
            responseModalities: ["IMAGE"],
            temperature: 0.4
        }
      }' > "$PAYLOAD_FILE"

    # API Call
    # We use the specific image model.
    local IMAGE_MODEL="gemini-3-pro-image-preview"
    # Fallback/Check if AIMODEL is set to something else? 
    # The tool forces the image model.
    
    local API_ENDPOINT="${AIURL}/${IMAGE_MODEL}:generateContent"
    
    local START_TIME=$(date +%s.%N)
    
    local RESPONSE_JSON=$(curl -s "$API_ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TOKEN" \
      -d @"$PAYLOAD_FILE")
      
    rm "$PAYLOAD_FILE"
    
    # Error Handling
    if echo "$RESPONSE_JSON" | jq -e '.error' > /dev/null 2>&1; then
        local ERR_MSG=$(echo "$RESPONSE_JSON" | jq -r '.error.message')
        RESULT_MSG="Error generating image: $ERR_MSG"
        local DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Failed] API Error: $ERR_MSG\033[0m"
    else
        # Extract Image Data
        # Expecting: candidates[0].content.parts[0].inlineData.data
        local B64_DATA=$(echo "$RESPONSE_JSON" | jq -r '.candidates[0].content.parts[0].inlineData.data // empty')
        
        if [ -n "$B64_DATA" ] && [ "$B64_DATA" != "null" ]; then
            # Decode and Save
            if echo "$B64_DATA" | base64 -d > "$OUT_FILE" 2>/dev/null; then
                RESULT_MSG="Image generated successfully. Saved to: $OUT_FILE"
                local FILE_SIZE=$(du -h "$OUT_FILE" | cut -f1)
                local DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;32m[Tool Success] Saved $OUT_FILE ($FILE_SIZE)\033[0m"
                display_media_file "$OUT_FILE"
            else
                RESULT_MSG="Error: Failed to decode base64 image data."
                local DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;31m[Tool Failed] Base64 decode error.\033[0m"
            fi
        else
            # Check if it returned text instead (refusal)
            local TEXT_RESP=$(echo "$RESPONSE_JSON" | jq -r '.candidates[0].content.parts[0].text // empty')
            if [ -n "$TEXT_RESP" ]; then
                RESULT_MSG="Model refused or returned text: $TEXT_RESP"
                local DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;33m[Tool Warning] Model returned text instead of image.\033[0m"
            else
                RESULT_MSG="Error: No image data found in response."
                local DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;31m[Tool Failed] Empty response content.\033[0m"
            fi
        fi
    fi

    # Return Result to Model (Text only, no Base64)
    jq -n --arg name "create_image" --arg content "$RESULT_MSG" \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
        
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

