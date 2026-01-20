#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Resolve Script Directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Helper: Shadow Backup Logic
BACKUP_DIR="${TMPDIR:-/tmp}/tellme_backups"
# Prune backups older than 24 hours
find "$BACKUP_DIR" -type f -mtime +1 -delete 2>/dev/null
mkdir -p "$BACKUP_DIR"

backup_file() {
    local target="$1"
    if [ -f "$target" ]; then
        # Create a flat filename (e.g. ./src/main.py -> _src_main.py)
        local flat_name=$(echo "$target" | sed 's/[\/\.]/_/g')
        cp "$target" "$BACKUP_DIR/$flat_name"
    fi
}

restore_backup() {
    local target="$1"
    local flat_name=$(echo "$target" | sed 's/[\/\.]/_/g')
    local backup_path="$BACKUP_DIR/$flat_name"
    
    if [ -f "$backup_path" ]; then
        cp "$backup_path" "$target"
        return 0
    else
        return 1
    fi
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
    echo "Error: No input provided. Usage: a \"Your message\" or pipe content via stdin" >&2
    exit 1
fi

USER_MSG=$(printf "%s" "$MSG_TEXT" | jq -Rs '{role: "user", parts: [{text: .}]}')
update_history "$USER_MSG"

# 2. Configure Tools & Auth
# --- Tool Definitions ---
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
source "$BASE_DIR/lib/utils.sh"
source "$BASE_DIR/lib/read_file.sh"
source "$BASE_DIR/lib/read_image.sh"
source "$BASE_DIR/lib/read_url.sh"
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

    if [ "$CANDIDATE" == "null" ] || [ -z "$CANDIDATE" ]; then
        echo -e "\033[31mError: API returned no content (Check Safety Settings or Input).\033[0m"
        exit 1
    fi
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
        
        # Check for Rate Limit (429 or "Resource exhausted")
        # Note: curl output is JSON, we look for error code/status inside the JSON if HTTP 200 returned a soft error,
        # or handle HTTP status if we were capturing headers.
        # Simple check: Does the JSON contain an error with code 429 or message "RESOURCE_EXHAUSTED"?
        
        IS_RATE_LIMIT="no"
        if echo "$RESPONSE_JSON" | jq -e '.error.code == 429 or .error.status == "RESOURCE_EXHAUSTED" or (.error.message | contains("Resource exhausted"))' > /dev/null 2>&1; then
            IS_RATE_LIMIT="yes"
        fi

        if [ "$IS_RATE_LIMIT" == "yes" ]; then
             RETRY_COUNT=$((RETRY_COUNT + 1))
             if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                 echo -e "\033[0;33m[System] Rate Limit Hit (429). Retrying in 5s... ($RETRY_COUNT/$MAX_RETRIES)\033[0m"
                 sleep 5
                 continue
             else
                 echo -e "\033[31mError: Rate limit exhausted after $MAX_RETRIES retries.\033[0m"
                 rm "$PAYLOAD_FILE"
                 exit 1
             fi
        else
             # Not a rate limit error, break the retry loop
             break
        fi
    done

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

                if [ "$F_NAME" == "ask_user" ]; then
                    tool_ask_user "$FC_DATA" "$RESP_PARTS_FILE"
                
                elif [ "$F_NAME" == "manage_scratchpad" ]; then
                    tool_manage_scratchpad "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "update_file" ]; then
                    tool_update_file "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "replace_text" ]; then
                    tool_replace_text "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "insert_text" ]; then
                    tool_insert_text "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "apply_patch" ]; then
                    tool_apply_patch "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "rollback_file" ]; then
                    tool_rollback_file "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "move_file" ]; then
                    tool_move_file "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "delete_file" ]; then
                    tool_delete_file "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "list_files" ]; then
                    tool_list_files "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "get_file_info" ]; then
                    tool_get_file_info "$FC_DATA" "$RESP_PARTS_FILE"
                
                elif [ "$F_NAME" == "read_file" ]; then
                    tool_read_file "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "read_image" ]; then
                    tool_read_image "$FC_DATA" "$RESP_PARTS_FILE"
                elif [ "$F_NAME" == "read_url" ]; then
                    tool_read_url "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "search_files" ]; then
                    tool_search_files "$FC_DATA" "$RESP_PARTS_FILE"
                
                elif [ "$F_NAME" == "grep_definitions" ]; then
                    tool_grep_definitions "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "find_file" ]; then
                    tool_find_file "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "get_tree" ]; then
                    tool_get_tree "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "get_git_diff" ]; then
                    tool_get_git_diff "$FC_DATA" "$RESP_PARTS_FILE"
                elif [ "$F_NAME" == "read_git_commit" ]; then
                    tool_read_git_commit "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "get_git_log" ]; then
                    tool_get_git_log "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "get_git_status" ]; then
                    tool_get_git_status "$FC_DATA" "$RESP_PARTS_FILE"
                    
                elif [ "$F_NAME" == "get_git_blame" ]; then
                    tool_get_git_blame "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "execute_command" ]; then
                    tool_execute_command "$FC_DATA" "$RESP_PARTS_FILE"
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

# 6. Render Output
# Use the final JSON response for Recap and Stats
# Note: Recap reads from the *file* history, but we want to render the last message.
RECAP_OUT=$(mktemp)
if [ -z "$RECAP_OUT" ]; then
    RECAP_OUT="${TMPDIR:-/tmp}/tellme_recap_${RANDOM}.txt"
fi

"$BASE_DIR/recap.sh" -l > "$RECAP_OUT"
LINE_COUNT=$(wc -l < "$RECAP_OUT")

if [ "$LINE_COUNT" -gt 20 ]; then
    head -n 10 "$RECAP_OUT"
    echo -e "\n\033[1;30m... (Content Snipped) ...\033[0m\n"
    tail -n 5 "$RECAP_OUT"
else
    cat "$RECAP_OUT"
fi
rm -f "$RECAP_OUT"

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