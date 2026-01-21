#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Resolve Script Directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize Temp File Variables
PAYLOAD_FILE=""
RESP_PARTS_FILE=""
RECAP_OUT=""

# Define cleanup function for trap
cleanup() {
    [ -n "$PAYLOAD_FILE" ] && rm -f "$PAYLOAD_FILE"
    [ -n "$RESP_PARTS_FILE" ] && rm -f "$RESP_PARTS_FILE"
    [ -n "$RECAP_OUT" ] && rm -f "$RECAP_OUT"
}
trap cleanup EXIT

# Check Dependencies
for cmd in jq curl gcloud awk python3 patch; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is missing." >&2
        exit 1
    fi
done

source "$BASE_DIR/lib/utils.sh"
# Helper function to append messages to history safely
update_history() {
  update_history_file "$1" "$file"
}

# Ensure critical variables are set
if [ -z "$file" ]; then
    echo "Warning: \$file not set. Defaulting to ./history.json" >&2
    file="./history.json"
fi

if [ -z "$PERSON" ]; then
   PERSON="You are a helpful AI assistant."
fi

# 1. Update Conversation History (User Input)
PROMPT_TEXT="$1"
STDIN_DATA=""

if [ ! -t 0 ]; then
    STDIN_DATA="$(cat)"
fi

if [ -n "$STDIN_DATA" ]; then
    MSG_TEXT="${PROMPT_TEXT}\n\n${STDIN_DATA}"
elif [ -n "$PROMPT_TEXT" ]; then
    MSG_TEXT="$PROMPT_TEXT"
else
    echo "Error: No input provided. Usage: a \"Your message\" or pipe content via stdin" >&2
    exit 1
fi

USER_MSG=$(printf "%s" "$MSG_TEXT" | jq -Rs '{role: "user", parts: [{text: .}]}')
update_history "$USER_MSG"

# 2. Configure Tools & Auth
# --- Tool Definitions ---
# CHANGED: Use tools.json for review version
if [ -f "$BASE_DIR/lib/tools.json" ]; then
    FUNC_DECLARATIONS=$(cat "$BASE_DIR/lib/tools.json")
else
    echo "Error: Tool definitions not found at $BASE_DIR/lib/tools.json" >&2
    exit 1
fi
# Define role for function responses (Gemini expects 'function')
FUNC_ROLE="function"

if [ "$USE_SEARCH" == "true" ]; then
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "googleSearch": {} }, { "functionDeclarations": $funcs }]')
else
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "functionDeclarations": $funcs }]')
fi

# --- Auth Setup ---
source "$BASE_DIR/lib/auth.sh"

# --- Load Tools ---
source "$BASE_DIR/lib/read_file.sh"
source "$BASE_DIR/lib/read_image.sh"
source "$BASE_DIR/lib/read_url.sh"
source "$BASE_DIR/lib/code_analysis.sh"
source "$BASE_DIR/lib/testing.sh"
source "$BASE_DIR/lib/scratchpad.sh"
source "$BASE_DIR/lib/sys_exec.sh"
source "$BASE_DIR/lib/ask_user.sh"
source "$BASE_DIR/lib/git_diff.sh"
source "$BASE_DIR/lib/git_status.sh"
source "$BASE_DIR/lib/git_blame.sh"
source "$BASE_DIR/lib/git_log.sh"
source "$BASE_DIR/lib/git_commit.sh"
source "$BASE_DIR/lib/file_search.sh"
source "$BASE_DIR/lib/file_edit.sh"
source "$BASE_DIR/lib/linter.sh"
# CHANGED: Source task_manager.sh
source "$BASE_DIR/lib/task_manager.sh"

# ==============================================================================
# MAIN INTERACTION LOOP
# Handles multi-turn interactions (Tool Call -> Execution -> Tool Response)
# ==============================================================================

MAX_TURNS=100
CURRENT_TURN=0
FINAL_TEXT_RESPONSE=""

START_TIME=$(date +%s.%N)

while [ $CURRENT_TURN -lt $MAX_TURNS ]; do
    CURRENT_TURN=$((CURRENT_TURN + 1))

    # 3. Build API Payload (reads current history from file)
    APIDATA=$(jq -n \
      --arg person "$PERSON" \
      --argjson tools "$TOOLS_JSON" \
      --slurpfile history "$file" \
      '{
        contents: $history[0].messages,
        tools: $tools,
        generationConfig: { 
            temperature: 1.0 
            # thinkingConfig removed for compatibility

        },
        safetySettings: [
          { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" }
        ]
      } + 
      (if $person != "" then { systemInstruction: { role: "system", parts: [{text: $person}] } } else {} end)'
    )

    PAYLOAD_FILE=$(mktemp) || exit 1
    echo "$APIDATA" > "$PAYLOAD_FILE"

    # 4. Call API with Retry Logic
    RETRY_COUNT=0
    MAX_RETRIES=3
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RESPONSE_JSON=$(curl -s "${AIURL}/${AIMODEL}:generateContent" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d @"$PAYLOAD_FILE")
        
        # Check for Rate Limit (429) or Server Errors (500, 503)
        # Note: curl output is JSON, we look for error code/status inside the JSON if HTTP 200 returned a soft error.
        
        SHOULD_RETRY="no"
        if echo "$RESPONSE_JSON" | jq -e '.error.code == 429 or .error.code == 500 or .error.code == 503 or .error.status == "RESOURCE_EXHAUSTED" or (.error.message | contains("Resource exhausted"))' > /dev/null 2>&1; then
            SHOULD_RETRY="yes"
        fi

        if [ "$SHOULD_RETRY" == "yes" ]; then
             RETRY_COUNT=$((RETRY_COUNT + 1))
             if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                 echo -e "\033[0;33m[System] API Error (Rate Limit/Server). Retrying in 5s... ($RETRY_COUNT/$MAX_RETRIES)\033[0m"
                 sleep 5
                 continue
             else
                 echo -e "\033[31mError: API retry limit exhausted after $MAX_RETRIES retries.\033[0m"
                 # Cleanup happens via trap
                 exit 1
             fi
        else
             # Not a retryable error, break the retry loop
             break
        fi
    done

    # Basic Validation
    if echo "$RESPONSE_JSON" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "\033[31mAPI Error:\033[0m $(echo "$RESPONSE_JSON" | jq -r '.error.message')"
        exit 1
    fi

    CANDIDATE=$(echo "$RESPONSE_JSON" | jq -c '.candidates[0].content')

    if [ "$CANDIDATE" == "null" ] || [ -z "$CANDIDATE" ]; then
        echo -e "\033[31mError: API returned no content (Check Safety Settings or Input).\033[0m"
        exit 1
    fi
    
    # 5. Check for Function Call(s)
    # Gemini may return multiple function calls in one turn (parallel calling).
    # We must identify if ANY part is a function call.
    HAS_FUNC=$(echo "$CANDIDATE" | jq -e '.parts[] | has("functionCall")' >/dev/null 2>&1 && echo "yes" || echo "no")

    if [ "$HAS_FUNC" == "yes" ]; then
        # --- Handle Tool Execution (Parallel Compatible) ---
        
        # 1. Update History with the Model's Request (The Function Call)
        update_history "$CANDIDATE"

        # 2. Iterate over parts to execute calls and build responses
        RESP_PARTS_FILE=$(mktemp)
        echo "[]" > "$RESP_PARTS_FILE"
        
        PART_COUNT=$(echo "$CANDIDATE" | jq '.parts | length')

        for (( i=0; i<$PART_COUNT; i++ )); do
            FC_DATA=$(echo "$CANDIDATE" | jq -c ".parts[$i].functionCall // empty")
            
            if [ -n "$FC_DATA" ]; then
                F_NAME=$(echo "$FC_DATA" | jq -r '.name')
                CMD_NAME="tool_${F_NAME}"

                if declare -f "$CMD_NAME" > /dev/null; then
                    "$CMD_NAME" "$FC_DATA" "$RESP_PARTS_FILE"
                else
                    # Handle unknown tool
                    ERR_MSG="Error: Tool '$F_NAME' not found or not supported."
                    echo -e "\033[0;31m[System] $ERR_MSG\033[0m"
                    
                    # Send error back to model so it can correct itself
                    jq -n --arg name "$F_NAME" --arg content "$ERR_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                fi
            fi
        done

        # 3. Construct Full Tool Response
        TOOL_RESPONSE=$(jq -n --arg role "$FUNC_ROLE" --slurpfile parts "$RESP_PARTS_FILE" '{ role: $role, parts: $parts[0] }')
        rm "$RESP_PARTS_FILE"
        
        # 4. Update History with Tool Result
        update_history "$TOOL_RESPONSE"

        # Loop continues to send this result back to the model...
        continue

    else
        # --- Handle Text Response (Final Answer) ---
        FINAL_TEXT_RESPONSE="$RESPONSE_JSON"
        update_history "$CANDIDATE"
        break
    fi
done

END_TIME=$(date +%s.%N)
DURATION=$(awk -v start="$START_TIME" -v end="$END_TIME" 'BEGIN { print end - start }')

if [ -z "$FINAL_TEXT_RESPONSE" ]; then
    echo -e "\033[31mError: Maximum conversation turns ($MAX_TURNS) exceeded without a final response.\033[0m"
    exit 1
fi

# 6. Render Output
# Use the final JSON response for Recap and Stats
# Note: Recap reads from the *file* history, but we want to render the last message.
RECAP_OUT=$(mktemp)
if [ -z "$RECAP_OUT" ]; then
    RECAP_OUT="${TMPDIR:-/tmp}/tellme_recap_${RANDOM}.txt"
fi

if [ -f "$BASE_DIR/recap.sh" ] && [ -x "$BASE_DIR/recap.sh" ]; then
    "$BASE_DIR/recap.sh" -l > "$RECAP_OUT"
else
    # Fallback: just cat the final response text if recap is missing
    echo "$FINAL_TEXT_RESPONSE" | jq -r '.candidates[0].content.parts[].text // empty' > "$RECAP_OUT"
fi

LINE_COUNT=$(wc -l < "$RECAP_OUT")

if [ "$LINE_COUNT" -gt 20 ]; then
    head -n 10 "$RECAP_OUT"
    echo -e "\n\033[1;30m... (Content Snipped) ...\033[0m\n"
    tail -n 5 "$RECAP_OUT"
else
    cat "$RECAP_OUT"
fi
# rm -f "$RECAP_OUT" # Handled by trap

# 7. Grounding Detection
SEARCH_COUNT=$(echo "$FINAL_TEXT_RESPONSE" | jq -r '(.candidates[0].groundingMetadata.webSearchQueries // []) | length')
if [ "$SEARCH_COUNT" -gt 0 ]; then
    echo -e "\033[0;33m[Grounding] Performed $SEARCH_COUNT Google Search(es):\033[0m"
    echo "$FINAL_TEXT_RESPONSE" | jq -r '.candidates[0].groundingMetadata.webSearchQueries[]' | while read -r query; do
            echo -e "  \033[0;33m> \"$query\"\033[0m"
    done
fi

printf "\033[0;35m[Response Time] %.2f seconds\033[0m\n" "$DURATION"

# 8. Stats & Metrics
read -r HIT PROMPT_TOTAL COMPLETION TOTAL <<< $(echo "$FINAL_TEXT_RESPONSE" | jq -r '
  .usageMetadata | 
  (.cachedContentTokenCount // 0), 
  (.promptTokenCount // 0), 
  (.candidatesTokenCount // .completionTokenCount // 0), 
  (.totalTokenCount // 0)
' | xargs)

MISS=$(( PROMPT_TOTAL - HIT ))
NEWTOKEN=$(( MISS + COMPLETION ))

if [ "$TOTAL" -gt 0 ]; then PERCENT=$(( ($NEWTOKEN * 100) / $TOTAL )); else PERCENT=0; fi

LOG_FILE="${file}.log"
STATS_MSG=$(printf "[%s] H: %d M: %d C: %d T: %d N: %d(%d%%) S: %d [%.2fs]" \
  "$(date +%H:%M:%S)" "$HIT" "$MISS" "$COMPLETION" "$TOTAL" "$NEWTOKEN" "$PERCENT" "$SEARCH_COUNT" "$DURATION")
echo "$STATS_MSG" >> "$LOG_FILE"

if [ -f "$LOG_FILE" ]; then
    echo -e "\033[0;36m--- Usage History ---\033[0m"
    tail -n 3 "$LOG_FILE"
    echo ""
    awk '{ gsub(/\./, ""); h+=$3; m+=$5; c+=$7; t+=$9; s+=$13 } END { printf "\033[0;34m[Session Total]\033[0m Hit: %d | Miss: %d | Comp: %d | \033[1mTotal: %d\033[0m | Search: %d\n", h, m, c, t, s }' "$LOG_FILE"
fi


