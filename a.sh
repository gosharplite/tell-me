#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Resolve Script Directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check Dependencies
for cmd in jq curl gcloud awk; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is missing." >&2
        exit 1
    fi
done

# Helper function to append messages to history safely
update_history() {
  local json_content="$1"
  local item_file=$(mktemp)
  printf "%s" "$json_content" > "$item_file"
  
  if [ -s "$file" ] && jq empty "$file" > /dev/null 2>&1; then
    if ! jq --slurpfile item "$item_file" '.messages += $item' "$file" > "${file}.tmp"; then
        echo "Error: Failed to process history file." >&2
        rm "$item_file"
        exit 1
    fi
    mv "${file}.tmp" "$file"
  else
    jq -n --slurpfile item "$item_file" '{messages: $item}' > "$file"
  fi
  rm "$item_file"
}

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
    MSG_TEXT="$DATA"
    echo "Usage: a \"Your message\" or pipe content via stdin" >&2
    exit 1
fi

USER_MSG=$(printf "%s" "$MSG_TEXT" | jq -Rs '{role: "user", parts: [{text: .}]}')
update_history "$USER_MSG"

# 2. Configure Tools & Auth
# --- Tool Definitions ---
read -r -d '' FUNC_DECLARATIONS <<EOM
[
  {
    "name": "update_file",
    "description": "Overwrites a specific file with new content. Use this to save code or text to a file.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "filepath": {
          "type": "STRING",
          "description": "The path to the file to write (e.g., ./README.md)"
        },
        "content": {
          "type": "STRING",
          "description": "The full text content to write into the file"
        }
      },
      "required": ["filepath", "content"]
    }
  },
  {
    "name": "list_files",
    "description": "Lists files and directories in the specified path. Use this to explore the file system structure.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "path": {
          "type": "STRING",
          "description": "The directory path to list (defaults to current directory '.')",
          "default": "."
        }
      },
      "required": ["path"]
    }
  },
  {
    "name": "read_file",
    "description": "Reads the content of a specific file. Use this to inspect code or configs before editing them.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "filepath": {
          "type": "STRING",
          "description": "The path to the file to read (e.g., ./src/main.py)"
        }
      },
      "required": ["filepath"]
    }
  }
]
EOM

if [ "$USE_SEARCH" == "true" ]; then
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "googleSearch": {} }, { "functionDeclarations": $funcs }]')
else
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "functionDeclarations": $funcs }]')
fi

# --- Auth Setup ---
if [[ "$AIURL" == *"aiplatform.googleapis.com"* ]]; then
    TARGET_SCOPE="https://www.googleapis.com/auth/cloud-platform"
    CACHE_SUFFIX="vertex"
else
    TARGET_SCOPE="https://www.googleapis.com/auth/generative-language"
    CACHE_SUFFIX="studio"
fi

TOKEN_CACHE="${TMPDIR:-/tmp}/gemini_token_${CACHE_SUFFIX}.txt"

get_file_mtime() {
    if [[ "$OSTYPE" == "darwin"* ]]; then stat -f %m "$1"; else stat -c %Y "$1"; fi
}

if [ -f "$TOKEN_CACHE" ]; then
    NOW=$(date +%s)
    LAST_MOD=$(get_file_mtime "$TOKEN_CACHE")
    if [ $((NOW - LAST_MOD)) -lt 3300 ]; then TOKEN=$(cat "$TOKEN_CACHE"); fi
fi

if [ -z "$TOKEN" ]; then
    if [ -n "$KEY_FILE" ] && [ -f "$KEY_FILE" ]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$KEY_FILE"
        TOKEN=$(gcloud auth application-default print-access-token --scopes="${TARGET_SCOPE}")
    else
        TOKEN=$(gcloud auth print-access-token --scopes="${TARGET_SCOPE}")
    fi
    echo "$TOKEN" > "$TOKEN_CACHE"
fi

# ==============================================================================
# MAIN INTERACTION LOOP
# Handles multi-turn interactions (Tool Call -> Execution -> Tool Response)
# ==============================================================================

MAX_TURNS=5
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

    # 4. Call API
    RESPONSE_JSON=$(curl -s "${AIURL}/${AIMODEL}:generateContent" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TOKEN" \
      -d @"$PAYLOAD_FILE")
    
    rm "$PAYLOAD_FILE"

    # Basic Validation
    if echo "$RESPONSE_JSON" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "\033[31mAPI Error:\033[0m $(echo "$RESPONSE_JSON" | jq -r '.error.message')"
        exit 1
    fi

    CANDIDATE=$(echo "$RESPONSE_JSON" | jq -c '.candidates[0].content')
    
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
                
                if [ "$F_NAME" == "update_file" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
                    FC_CONTENT=$(echo "$FC_DATA" | jq -r '.args.content')

                    echo -e "\033[0;36m[Tool Request] Writing to file: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        mkdir -p "$(dirname "$FC_PATH")"
                        printf "%s" "$FC_CONTENT" > "$FC_PATH"
                        if [ $? -eq 0 ]; then
                            RESULT_MSG="File updated successfully."
                            echo -e "\033[0;32m[Tool Success] File updated.\033[0m"
                        else
                            RESULT_MSG="Error: Failed to write file."
                            echo -e "\033[0;31m[Tool Failed] Could not write file.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Write path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Write denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "update_file" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "list_files" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')

                    echo -e "\033[0;36m[Tool Request] Listing: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD (Reuse existing logic)
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -e "$FC_PATH" ]; then
                            # Run ls -F (adds / to dirs, * to executables)
                            RESULT_MSG=$(ls -F "$FC_PATH" 2>&1)
                            echo -e "\033[0;32m[Tool Success] Directory listed.\033[0m"
                        else
                            RESULT_MSG="Error: Path does not exist."
                            echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] List denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "list_files" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                
                elif [ "$F_NAME" == "read_file" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

                    echo -e "\033[0;36m[Tool Request] Reading: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -f "$FC_PATH" ]; then
                            # Read file content
                            # Limit size to prevent token explosion (e.g., 500 lines)
                            LINE_COUNT=$(wc -l < "$FC_PATH")
                            if [ "$LINE_COUNT" -gt 500 ]; then
                                RESULT_MSG=$(head -n 500 "$FC_PATH")
                                RESULT_MSG="${RESULT_MSG}\n\n... (File truncated at 500 lines) ..."
                            else
                                RESULT_MSG=$(cat "$FC_PATH")
                            fi
                            echo -e "\033[0;32m[Tool Success] File read.\033[0m"
                        else
                            RESULT_MSG="Error: File not found."
                            echo -e "\033[0;31m[Tool Failed] File not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Read denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "read_file" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                fi
            fi
        done

        # 3. Construct Full Tool Response
        TOOL_RESPONSE=$(jq -n --slurpfile parts "$RESP_PARTS_FILE" '{ role: "function", parts: $parts[0] }')
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

# 6. Render Output
# Use the final JSON response for Recap and Stats
# Note: Recap reads from the *file* history, but we want to render the last message.
RECAP_OUT=$(mktemp)
"$BASE_DIR/recap.sh" -l > "$RECAP_OUT"
LINE_COUNT=$(wc -l < "$RECAP_OUT")

if [ "$LINE_COUNT" -gt 20 ]; then
    head -n 10 "$RECAP_OUT"
    echo -e "\n\033[1;30m... (Content Snipped) ...\033[0m\n"
    tail -n 5 "$RECAP_OUT"
else
    cat "$RECAP_OUT"
fi
rm "$RECAP_OUT"

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

# Backup History
if [ -f "${file}" ]; then
    TIMESTAMP=$(date -u "+%y%m%d-%H")$(printf "%02d" $(( (10#$(date -u "+%M") / 10) * 10 )) )
    cp "$file" "${file%.*}-${TIMESTAMP}-trace.${file##*.}"
fi