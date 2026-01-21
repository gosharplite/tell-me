# Function to generate videos using Veo 3.1 model
# Usage: tool_create_video '{ "args": { "prompt": "...", "resolution": "720p", "aspect_ratio": "16:9" } }' "output_file"

tool_create_video() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    
    # Extract Arguments
    local PROMPT=$(echo "$FC_DATA" | jq -r '.args.prompt')
    local RESOLUTION=$(echo "$FC_DATA" | jq -r '.args.resolution // "720p"') # 720p, 1080p
    local ASPECT_RATIO=$(echo "$FC_DATA" | jq -r '.args.aspect_ratio // "16:9"')
    
    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Generating Video: \"${PROMPT:0:50}...\" ($RESOLUTION, $ASPECT_RATIO)\033[0m"

    local RESULT_MSG=""
    local VIDEO_DIR="assets/generated"
    mkdir -p "$VIDEO_DIR"
    
    # Construct Filename
    local SAFE_TITLE=$(echo "$PROMPT" | tr -dc 'a-zA-Z0-9' | head -c 20)
    [ -z "$SAFE_TITLE" ] && SAFE_TITLE="video"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local OUT_FILE="${VIDEO_DIR}/${TIMESTAMP}_${SAFE_TITLE}.mp4"
    
    # Construct Payload
    local PAYLOAD_FILE=$(mktemp)
    
    jq -n \
      --arg prompt "$PROMPT" \
      --arg resolution "$RESOLUTION" \
      --arg aspectRatio "$ASPECT_RATIO" \
      '{
        instances: [{ prompt: $prompt }],
        parameters: {
            sampleCount: 1,
            resolution: $resolution,
            aspectRatio: $aspectRatio,
            durationSeconds: 8
        }
      }' > "$PAYLOAD_FILE"

    # API Endpoint
    local VIDEO_MODEL="veo-3.1-generate-preview"
    local PREDICT_ENDPOINT="${AIURL}/${VIDEO_MODEL}:predictLongRunning"
    
    # 1. Initiate Generation
    echo -e "${TS} \033[0;33m[Tool info] Submitting job to $VIDEO_MODEL...\033[0m"
    local START_TIME=$(date +%s.%N)
    
    local INIT_RESPONSE=$(curl -s "$PREDICT_ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TOKEN" \
      -H "x-goog-user-project: $(gcloud config get-value project 2>/dev/null)" \
      -d @"$PAYLOAD_FILE")
      
    rm "$PAYLOAD_FILE"
    
    # Check for immediate error
    if echo "$INIT_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        local ERR_MSG=$(echo "$INIT_RESPONSE" | jq -r '.error.message')
        RESULT_MSG="Error starting video generation: $ERR_MSG"
        local DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Failed] API Error: $ERR_MSG\033[0m"
    else
        # Extract Operation Name
        local OP_NAME=$(echo "$INIT_RESPONSE" | jq -r '.name // empty')
        
        if [ -z "$OP_NAME" ]; then
             RESULT_MSG="Error: No operation name returned."
             echo -e "\033[0;31m[Tool Failed] Invalid response: $INIT_RESPONSE\033[0m"
        else
            echo -e "\033[0;33m[Tool info] Job started: $OP_NAME. Polling...\033[0m"
            
            # 2. Poll Status
            local DONE="false"
            local ATTEMPTS=0
            local MAX_ATTEMPTS=60 # 60 * 5s = 5 minutes max (Veo takes ~1-2 mins usually)
            
            while [ "$DONE" != "true" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
                sleep 5
                ((ATTEMPTS++))
                
                # Check Operation Status
                # URL: https://generativelanguage.googleapis.com/v1beta/{OP_NAME}
                # But AIURL might be .../models. 
                # If OP_NAME is "models/veo.../operations/...", we need BASE_URL/OP_NAME
                # AIURL is usually BASE_URL/models. We need BASE_URL.
                local BASE_URL=$(echo "$AIURL" | sed 's|/models$||')
                local OP_URL="${BASE_URL}/${OP_NAME}"
                
                local POLL_RESP=$(curl -s "$OP_URL" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $TOKEN")
                
                DONE=$(echo "$POLL_RESP" | jq -r '.done // "false"')
                
                if echo "$POLL_RESP" | jq -e '.error' > /dev/null 2>&1; then
                    local ERR=$(echo "$POLL_RESP" | jq -r '.error.message')
                    RESULT_MSG="Error during polling: $ERR"
                    DONE="error"
                    break
                fi
                
                echo -ne "\r\033[0;33m[Tool info] Polling ($ATTEMPTS/$MAX_ATTEMPTS)...\033[0m"
            done
            echo ""
            
            if [ "$DONE" == "true" ]; then
                # 3. Retrieve Result
                # Check for nested error in operation result
                if echo "$POLL_RESP" | jq -e '.response.error' > /dev/null 2>&1; then
                     RESULT_MSG="Video generation failed: $(echo "$POLL_RESP" | jq -r '.response.error.message')"
                     echo -e "\033[0;31m[Tool Failed] $RESULT_MSG\033[0m"
                else
                    # Extract Video Data
                    # Expecting: response.generatedSamples[0].video.uri OR bytesBase64Encoded
                    local URI=$(echo "$POLL_RESP" | jq -r '.response.generatedSamples[0].video.uri // empty')
                    local B64=$(echo "$POLL_RESP" | jq -r '.response.generatedSamples[0].video.bytesBase64Encoded // empty')
                    
                    if [ -n "$B64" ] && [ "$B64" != "null" ]; then
                        echo "$B64" | base64 -d > "$OUT_FILE"
                        RESULT_MSG="Video generated successfully. Saved to: $OUT_FILE"
                        local FILE_SIZE=$(du -h "$OUT_FILE" | cut -f1)
                        local DUR=$(get_log_duration)
                        echo -e "${DUR} \033[0;32m[Tool Success] Saved $OUT_FILE ($FILE_SIZE)\033[0m"
                    elif [ -n "$URI" ] && [ "$URI" != "null" ]; then
                         # Handle URI (likely gs://)
                         if [[ "$URI" == gs://* ]]; then
                            echo -e "\033[0;33m[Tool info] Downloading from $URI...\033[0m"
                            if command -v gcloud &> /dev/null; then
                                gcloud storage cp "$URI" "$OUT_FILE" 2>/dev/null
                                if [ $? -eq 0 ]; then
                                    RESULT_MSG="Video generated successfully. Saved to: $OUT_FILE"
                                    local FILE_SIZE=$(du -h "$OUT_FILE" | cut -f1)
                                    local DUR=$(get_log_duration)
                                    echo -e "${DUR} \033[0;32m[Tool Success] Saved $OUT_FILE ($FILE_SIZE)\033[0m"
                                else
                                    RESULT_MSG="Video generated at $URI but failed to download (check permissions)."
                                    echo -e "\033[0;31m[Tool Failed] Download failed.\033[0m"
                                fi
                            else
                                RESULT_MSG="Video generated at $URI. Please download manually (gcloud not found)."
                                echo -e "\033[0;33m[Tool Warning] gcloud missing.\033[0m"
                            fi
                         else
                             # Try HTTP download if not gs://
                             curl -s "$URI" -o "$OUT_FILE"
                             RESULT_MSG="Video generated successfully. Saved to: $OUT_FILE"
                             local DUR=$(get_log_duration)
                             echo -e "${DUR} \033[0;32m[Tool Success] Saved $OUT_FILE\033[0m"
                         fi
                    else
                        RESULT_MSG="Error: Operation completed but no video data found."
                        echo -e "\033[0;31m[Tool Failed] No video data in response.\033[0m"
                    fi
                fi
            elif [ "$DONE" == "error" ]; then
                # Already handled above
                :
            else
                RESULT_MSG="Error: Timeout waiting for video generation."
                echo -e "\033[0;31m[Tool Failed] Timeout.\033[0m"
            fi
        fi
    fi

    # Return Result
    jq -n --arg name "create_video" --arg content "$RESULT_MSG" \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
        
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

