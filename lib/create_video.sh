# Function to generate videos using Veo 3.0 model
# Usage: tool_create_video '{ "args": { "prompt": "...", "resolution": "720p", "aspect_ratio": "16:9", "duration_seconds": 8 } }' "output_file"

tool_create_video() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    
    # Extract Arguments
    local PROMPT=$(echo "$FC_DATA" | jq -r '.args.prompt')
    local RESOLUTION=$(echo "$FC_DATA" | jq -r '.args.resolution // "720p"') # 720p, 1080p
    local ASPECT_RATIO=$(echo "$FC_DATA" | jq -r '.args.aspect_ratio // "16:9"')
    local DURATION=$(echo "$FC_DATA" | jq -r '.args.duration_seconds // 4')
    local FAST_GEN=$(echo "$FC_DATA" | jq -r '.args.fast_generation // false')

    # Validate Duration (Veo supports 4, 6, 8)
    if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -le 0 ]; then
        DURATION=8
    elif [ "$DURATION" -lt 4 ]; then
        DURATION=4
    elif [ "$DURATION" -gt 8 ]; then
        DURATION=8
    fi
    if [ "$DURATION" -eq 5 ]; then DURATION=6; fi
    if [ "$DURATION" -eq 7 ]; then DURATION=8; fi
    
    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Generating Video: \"${PROMPT:0:50}...\" ($RESOLUTION, $ASPECT_RATIO, ${DURATION}s, Fast: $FAST_GEN)\033[0m"

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
      --argjson duration "$DURATION" \
      '{
        instances: [{ prompt: $prompt }],
        parameters: {
            sampleCount: 1,
            resolution: $resolution,
            aspectRatio: $aspectRatio,
            durationSeconds: $duration
        }
      }' > "$PAYLOAD_FILE"

    # API Endpoint - Use Veo 3.0 models
    local VIDEO_MODEL="veo-3.0-generate-001"
    if [ "$FAST_GEN" == "true" ]; then
        VIDEO_MODEL="veo-3.0-fast-generate-001"
    fi
    
    local REGIONAL_HOST="us-central1-aiplatform.googleapis.com"
    local PROJECT_ID=$(echo "$AIURL" | sed -n 's|.*/projects/\([^/]*\)/.*|\1|p')
    if [ -z "$PROJECT_ID" ]; then PROJECT_ID=$(gcloud config get-value project 2>/dev/null); fi
    
    local BETA_BASE_URL="https://${REGIONAL_HOST}/v1beta1/projects/${PROJECT_ID}/locations/us-central1/publishers/google/models/${VIDEO_MODEL}"
    local V1_BASE_URL="https://${REGIONAL_HOST}/v1/projects/${PROJECT_ID}/locations/us-central1/publishers/google/models/${VIDEO_MODEL}"
    
    local PREDICT_ENDPOINT="${BETA_BASE_URL}:predictLongRunning"
    local FETCH_ENDPOINT="${V1_BASE_URL}:fetchPredictOperation"
    
    # 1. Initiate Generation
    echo -e "${TS} \033[0;33m[Tool info] Submitting job to $VIDEO_MODEL (us-central1)...\033[0m"
    local START_TIME=$(date +%s.%N)
    local USER_PROJECT=$(gcloud config get-value project 2>/dev/null)

    local INIT_RESPONSE=$(curl -s "$PREDICT_ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TOKEN" \
      -H "x-goog-user-project: $USER_PROJECT" \
      -d @"$PAYLOAD_FILE")
      
    rm "$PAYLOAD_FILE"
    
    if ! echo "$INIT_RESPONSE" | jq -e . > /dev/null 2>&1; then
         RESULT_MSG="Error: Invalid JSON response from API during init."
         echo -e "\033[0;31m[Tool Failed] API returned non-JSON: ${INIT_RESPONSE:0:100}...\033[0m"
    elif echo "$INIT_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        local ERR_MSG=$(echo "$INIT_RESPONSE" | jq -r '.error.message')
        RESULT_MSG="Error starting video generation: $ERR_MSG"
        echo -e "\033[0;31m[Tool Failed] API Error: $ERR_MSG\033[0m"
    else
        local OP_NAME=$(echo "$INIT_RESPONSE" | jq -r '.name // empty')
        
        if [ -z "$OP_NAME" ]; then
             RESULT_MSG="Error: No operation name returned."
        else
            echo -e "\033[0;33m[Tool info] Job started: $OP_NAME. Polling...\033[0m"
            
            # 2. Poll Status (Using fetchPredictOperation)
            local DONE="false"
            local ATTEMPTS=0
            local MAX_ATTEMPTS=60 
            local POLL_PAYLOAD=$(mktemp)
            jq -n --arg name "$OP_NAME" '{operationName: $name}' > "$POLL_PAYLOAD"
            
            local POLL_RESP=""
            while [ "$DONE" != "true" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
                sleep 5
                ((ATTEMPTS++))
                
                POLL_RESP=$(curl -s -X POST "$FETCH_ENDPOINT" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $TOKEN" \
                    -H "x-goog-user-project: $USER_PROJECT" \
                    -d @"$POLL_PAYLOAD")
                
                if ! echo "$POLL_RESP" | jq -e . > /dev/null 2>&1; then
                    echo -ne "\r\033[0;31m[Tool Warning] Polling failed (Invalid JSON)...\033[0m"
                    continue
                fi

                DONE=$(echo "$POLL_RESP" | jq -r '.done // "false"')
                
                if echo "$POLL_RESP" | jq -e '.error' > /dev/null 2>&1; then
                    RESULT_MSG="Error during polling: $(echo "$POLL_RESP" | jq -r '.error.message')"
                    DONE="error"
                    break
                fi
                echo -ne "\r\033[0;33m[Tool info] Polling ($ATTEMPTS/$MAX_ATTEMPTS)...\033[0m"
            done
            echo ""
            rm "$POLL_PAYLOAD"
            
            if [ "$DONE" == "true" ]; then
                if echo "$POLL_RESP" | jq -e '.response.error' > /dev/null 2>&1; then
                     RESULT_MSG="Video generation failed: $(echo "$POLL_RESP" | jq -r '.response.error.message')"
                     echo -e "\033[0;31m[Tool Failed] $RESULT_MSG\033[0m"
                else
                    # Extract Video Data
                    local B64=$(echo "$POLL_RESP" | jq -r '.response.videos[0].bytesBase64Encoded // .response.generatedSamples[0].video.bytesBase64Encoded // empty')
                    local GCS_URI=$(echo "$POLL_RESP" | jq -r '.response.videos[0].gcsUri // .response.videos[0].uri // .response.generatedSamples[0].video.uri // empty')
                    
                    if [ -n "$B64" ] && [ "$B64" != "null" ]; then
                        echo "$B64" | base64 -d > "$OUT_FILE"
                        RESULT_MSG="Video generated successfully. Saved to: $OUT_FILE"
                        local FILE_SIZE=$(du -h "$OUT_FILE" | cut -f1)
                        echo -e "\033[0;32m[Tool Success] Saved $OUT_FILE ($FILE_SIZE)\033[0m"
                        display_media_file "$OUT_FILE"
                    elif [ -n "$GCS_URI" ] && [ "$GCS_URI" != "null" ]; then
                         if command -v gcloud &> /dev/null; then
                             echo -e "\033[0;33m[Tool info] Downloading from $GCS_URI...\033[0m"
                             gcloud storage cp "$GCS_URI" "$OUT_FILE" 2>/dev/null
                             if [ $? -eq 0 ]; then
                                 RESULT_MSG="Video generated successfully. Saved to: $OUT_FILE"
                                 local FILE_SIZE=$(du -h "$OUT_FILE" | cut -f1)
                                 echo -e "\033[0;32m[Tool Success] Saved $OUT_FILE ($FILE_SIZE)\033[0m"
                                 display_media_file "$OUT_FILE"
                             else
                                 RESULT_MSG="Video generated at $GCS_URI but failed to download."
                                 echo -e "\033[0;31m[Tool Failed] Download failed.\033[0m"
                             fi
                         else
                             RESULT_MSG="Video generated at $GCS_URI. Please download manually (gcloud not found)."
                         fi
                    else
                        local FILTERED=$(echo "$POLL_RESP" | jq -r '.response.raiMediaFilteredCount // 0')
                        if [ "$FILTERED" -gt 0 ]; then
                             RESULT_MSG="Video generation blocked by safety filters (Count: $FILTERED)."
                             echo -e "\033[0;33m[Tool Warning] Safety Filter Triggered\033[0m"
                        else
                             RESULT_MSG="Error: Operation completed but no video data found."
                             echo -e "\033[0;31m[Tool Failed] No video data. (See console for details)\033[0m"
                        fi
                    fi
                fi
            elif [ "$DONE" == "error" ]; then
                :
            else
                RESULT_MSG="Error: Timeout waiting for video generation."
                echo -e "\033[0;31m[Tool Failed] Timeout.\033[0m"
            fi
        fi
    fi

    jq -n --arg name "create_video" --arg content "$RESULT_MSG" \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

