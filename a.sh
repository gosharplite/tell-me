#!/bin/bash
# a.sh: Final verified script with all fixes and original features.

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

source "$BASE_DIR/lib/core/history_manager.sh"
source "$BASE_DIR/lib/core/utils.sh"

# --- Configuration Setup ---
if [ -n "$1" ] && [ -f "$1" ]; then
    CONFIG_FILE="$1"
elif [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    : # Use provided env var
elif [ -f "config.yaml" ]; then
    CONFIG_FILE="config.yaml"
elif ls "$BASE_DIR/output/last-assist-"*".config.yaml" 1> /dev/null 2>&1; then
    CONFIG_FILE="$(ls -t "$BASE_DIR/output/last-assist-"*".config.yaml" | head -n 1)"
fi

if [ -z "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found."
    exit 1
fi

# Safe YAML Parser using Python3 (handles simple key-value YAML)
eval "$(python3 -c "
import sys, shlex
try:
    with open('$CONFIG_FILE', 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or ':' not in line:
                continue
            k, v = line.split(':', 1)
            k = k.strip()
            v = v.strip().strip('\"').strip(\"'\")
            if k.isidentifier():
                print(f'{k}={shlex.quote(v)}')
except Exception as e:
    print(f'echo \"Error parsing config: {e}\" >&2; exit 1')
")"

# --- Directory/Session Setup ---
SESSION_ID=$(basename "$CONFIG_FILE" .config.yaml)
OUTPUT_DIR="$BASE_DIR/output"
mkdir -p "$OUTPUT_DIR"

file="$OUTPUT_DIR/$SESSION_ID.json"
if [ ! -f "$file" ]; then
    echo '{"messages": []}' > "$file"
fi

if [ -n "$MAX_HISTORY_TOKENS" ]; then
    backup_file "$file"
fi

# --- Load Tools ---
source "$BASE_DIR/lib/core/auth.sh"
# Source all library files recursively from lib/core and lib/tools
while IFS= read -r -d '' lib; do
    # Skip files already sourced explicitly
    case "$(basename "$lib")" in
        history_manager.sh|utils.sh|auth.sh) continue ;;
    esac
    source "$lib"
done < <(find "$BASE_DIR/lib" -maxdepth 3 -name "*.sh" -print0)

# --- Helper Functions ---
update_history() {
  update_history_file "$1" "$file"
}

log_tool_call() {
    local fc_json="$1"
    local turn_info="$2"
    local f_name=$(echo "$fc_json" | jq -r '.name')
    local f_args=$(echo "$fc_json" | jq -c '.args')
    local ts=$(get_log_timestamp)
    
    local msg=""
    case "$f_name" in
        "update_file"|"replace_text"|"insert_text"|"append_file"|"delete_file"|"rollback_file"|"move_file"|"apply_patch")
            local target=$(echo "$f_args" | jq -r '.filepath // .source_path // empty')
            msg="Updating ${target:-file} ($f_name)" ;;
        "read_file"|"get_file_skeleton"|"get_file_info")
            local target=$(echo "$f_args" | jq -r '.filepath')
            msg="Reading $target ($f_name)" ;;
        "manage_scratchpad"|"manage_tasks")
            local action=$(echo "$f_args" | jq -r '.action')
            msg="Updating session state ($f_name: $action)" ;;
        *)
            msg="Calling $f_name" ;;
    esac
    echo -e "${ts} ${turn_info} \033[0;32m${msg}\033[0m"
}

# --- 1. User Input Handling ---
# If $1 was used as CONFIG_FILE, shift it away so $1 becomes the message
if [ "$1" == "$CONFIG_FILE" ]; then
    shift
fi

PROMPT_TEXT="$1"
STDIN_DATA=""
if [ ! -t 0 ]; then STDIN_DATA="$(cat)"; fi

if [ -n "$STDIN_DATA" ]; then
    MSG_TEXT="${PROMPT_TEXT}\n\n${STDIN_DATA}"
elif [ -n "$PROMPT_TEXT" ]; then
    MSG_TEXT="$PROMPT_TEXT"
else
    echo "Error: No input provided. Usage: a \"Your message\"" >&2
    exit 1
fi

USER_MSG=$(printf "%s" "$MSG_TEXT" | jq -Rs '{role: "user", parts: [{text: .}]}')
update_history "$USER_MSG"

# --- Mapping Budget to Thinking Level ---
THINKING_LEVEL="HIGH"
BUDGET_VAL=${THINKING_BUDGET:-4000}
if [ "$BUDGET_VAL" -lt 2000 ]; then THINKING_LEVEL="MINIMAL";
elif [ "$BUDGET_VAL" -lt 4001 ]; then THINKING_LEVEL="LOW";
elif [ "$BUDGET_VAL" -lt 8001 ]; then THINKING_LEVEL="MEDIUM"; fi

# --- Logging Helper ---
log_usage() {
    local resp="$1"
    local dur="$2"
    local search_cnt="$3"
    local log_file="$4"
    read -r hit prompt_total completion total thinking_tokens <<< $(echo "$resp" | jq -r '
      .usageMetadata | 
      (.cachedContentTokenCount // 0), 
      (.promptTokenCount // 0), 
      (.candidatesTokenCount // .completionTokenCount // 0), 
      (.totalTokenCount // 0),
      (.candidatesTokenCountDetails.thinkingTokenCount // .thoughtsTokenCount // 0)
    ' | xargs)
    local miss=$(( prompt_total - hit ))
    local newtoken=$(( miss + completion + thinking_tokens ))
    local percent=0
    if [ "$total" -gt 0 ]; then percent=$(( (newtoken * 100) / total )); fi
    local stats_msg=$(printf "[%s] H: %d M: %d C: %d T: %d N: %d(%d%%) S: %d Th: %d [%.2fs]" \
      "$(date +%H:%M:%S)" "$hit" "$miss" "$completion" "$total" "$newtoken" "$percent" "$search_cnt" "$thinking_tokens" "$dur")
    echo "$stats_msg" >> "$log_file"
    echo -e "\033[0;90m$stats_msg\033[0m"
}

# ==============================================================================
# MAIN INTERACTION LOOP
# ==============================================================================

MAX_TURNS=${MAX_TURNS:-30}
CURRENT_TURN=0
FUNC_ROLE="function"

if [ -n "$MAX_HISTORY_TOKENS" ]; then
    prune_history_if_needed "$file" "$MAX_HISTORY_TOKENS"
fi

START_TIME=$(date +%s.%N)

# --- Prepare Tool Definitions (Once per session) ---
FUNC_DECLARATIONS=$(cat "$BASE_DIR/lib/tools.json")
if [ "$USE_SEARCH" == "true" ]; then
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "googleSearch": {} }, { "functionDeclarations": $funcs }]')
else
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "functionDeclarations": $funcs }]')
fi

while true; do
    CURRENT_TURN=$((CURRENT_TURN + 1))

    PAYLOAD_START=$(date +%s.%N)
    # 3. Build API Payload
    APIDATA=$(jq -c -n \
      --arg person "$PERSON" \
      --argjson tools "$TOOLS_JSON" \
      --arg model "$AIMODEL" \
      --arg level "$THINKING_LEVEL" \
      --arg budget "$BUDGET_VAL" \
      --slurpfile history "$file" \
      '{
        contents: ([$history[0].messages[]? | select(.parts and (.parts | length > 0))]),
        tools: $tools,
        generationConfig: ({
            temperature: 1.0
        } + (if ($model | startswith("gemini-3")) then {
            thinkingConfig: { thinkingLevel: $level, includeThoughts: true }
        } elif ($model | startswith("gemini-2.0-flash-thinking")) then {
            thinkingConfig: { includeThinkingProcess: true, thinkingBudgetTokens: ($budget | tonumber? // 4000) }
        } else {} end)),
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

    # --- Pre-flight Safety Check & Logging ---
    ESTIMATED_TOKENS=0
    if [ -n "$MAX_HISTORY_TOKENS" ]; then
        ESTIMATED_TOKENS=$(python3 -c "import os; print(int(os.path.getsize('$PAYLOAD_FILE') / 3.5))")
        if [ "$ESTIMATED_TOKENS" -gt "$MAX_HISTORY_TOKENS" ]; then
            echo -e "\033[0;31m[Safety Error] Payload estimate ($ESTIMATED_TOKENS tokens) exceeds limit ($MAX_HISTORY_TOKENS)!\033[0m"
            echo -e "\033[0;33m[System] Rolling back history to last known good state...\033[0m"
            restore_backup "$file"
            echo -e "\033[0;33m[System] History restored. You may need to refine your query or reduce the output size.\033[0m"
            exit 1
        fi
        backup_file "$file"
    fi

    PAYLOAD_END=$(date +%s.%N)
    PAYLOAD_DUR=$(awk -v start="$PAYLOAD_START" -v end="$PAYLOAD_END" 'BEGIN { print end - start }')
    echo -e "$(get_log_timestamp) \033[0;90m[System] Payload: ~$ESTIMATED_TOKENS tokens | Generated in ${PAYLOAD_DUR}s\033[0m"

    TURN_START=$(date +%s.%N)
    echo -e "$(get_log_timestamp) \033[0;90m[API] Calling Gemini... (${AIMODEL})\033[0m"

    # 4. Call API with Retry Logic
    RETRY_COUNT=0; MAX_RETRIES=3
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RESPONSE_JSON=$(curl -s "${AIURL}/${AIMODEL}:generateContent" \
          -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d @"$PAYLOAD_FILE")
        
        if echo "$RESPONSE_JSON" | jq -e '.error.code == 429 or .error.code == 500' > /dev/null; then
             ERR_CODE=$(echo "$RESPONSE_JSON" | jq -r '.error.code')
             RETRY_COUNT=$((RETRY_COUNT + 1))
             if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                 echo -e "\033[33m[Warning] API error $ERR_CODE. Retrying in 5s... ($RETRY_COUNT/$MAX_RETRIES)\033[0m"
                 sleep 5
                 continue
             fi
             echo -e "\033[31mError: API retry limit exhausted.\033[0m"; exit 1
        else break; fi
    done

    TURN_END=$(date +%s.%N)
    TURN_DUR=$(awk -v start="$TURN_START" -v end="$TURN_END" 'BEGIN { print end - start }')

    if echo "$RESPONSE_JSON" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "\033[31mAPI Error:\033[0m $(echo "$RESPONSE_JSON" | jq -r '.error.message')"
        exit 1
    fi

    CANDIDATE=$(echo "$RESPONSE_JSON" | jq -c '.candidates[0].content // empty')
    
    if [ -z "$CANDIDATE" ] || [ "$CANDIDATE" == "null" ]; then
        FINISH_REASON=$(echo "$RESPONSE_JSON" | jq -r '.candidates[0].finishReason // "UNKNOWN"')
        echo -e "\033[33m[Warning] Model returned no content. Finish Reason: $FINISH_REASON\033[0m"
        # If blocked by safety, explain why
        if [ "$FINISH_REASON" == "SAFETY" ]; then
             echo -e "\033[33m[System] Response was blocked by safety filters.\033[0m"
        fi
        # Log usage anyway
        SEARCH_COUNT=0
        log_usage "$RESPONSE_JSON" "$TURN_DUR" "0" "${file}.log"
        break
    fi

    # Display thoughts if enabled
    if [ "$SHOW_THOUGHTS" == "true" ]; then
        THOUGHTS=$(echo "$CANDIDATE" | jq -r '.parts[] | select(.thought == true and .text != null) | .text' 2>/dev/null)
        CLEAN_THOUGHTS=$(printf "%s" "$THOUGHTS" | tr -d '\r' | python3 -c "import sys; print('\n'.join(line.strip() for line in sys.stdin.read().splitlines() if any(c.isprintable() and not c.isspace() for c in line)))")
        [ -n "$CLEAN_THOUGHTS" ] && printf "\033[0;90m%s [Thinking]\n%s\033[0m\n" "$(get_log_timestamp)" "$CLEAN_THOUGHTS"
    fi

    # 4.5 Log Usage immediately for this turn
    SEARCH_COUNT=$(echo "$RESPONSE_JSON" | jq -r '.candidates[0].groundingMetadata.webSearchQueries | length // 0' 2>/dev/null)
    log_usage "$RESPONSE_JSON" "$TURN_DUR" "$SEARCH_COUNT" "${file}.log"

    # 5. Check for Function Call(s)
    HAS_FUNC=$(echo "$CANDIDATE" | jq -e '.parts[] | has("functionCall")' >/dev/null 2>&1 && echo "yes" || echo "no")

    if [ "$HAS_FUNC" == "yes" ]; then
        update_history "$CANDIDATE"
        RESP_PARTS_FILE=$(mktemp); echo "[]" > "$RESP_PARTS_FILE"
        TOTAL_PARTS=$(echo "$CANDIDATE" | jq '.parts | length')
        FC_COUNT=$(echo "$CANDIDATE" | jq '[.parts[] | has("functionCall")] | map(select(. == true)) | length')
        current_fc=0
        for (( i=0; i<$TOTAL_PARTS; i++ )); do
            FC_DATA=$(echo "$CANDIDATE" | jq -c ".parts[$i].functionCall // empty")
            if [ -n "$FC_DATA" ]; then
                current_fc=$((current_fc + 1))
                log_tool_call "$FC_DATA" "[Tool Request ($current_fc/$FC_COUNT)]"
                CMD_NAME="tool_$(echo "$FC_DATA" | jq -r '.name')"
                if declare -f "$CMD_NAME" > /dev/null; then
                    "$CMD_NAME" "$FC_DATA" "$RESP_PARTS_FILE"
                else
                    echo -e "\033[0;31m[System Error] Tool $CMD_NAME not found.\033[0m"
                    jq -n --arg name "$(echo "$FC_DATA" | jq -r '.name')" \
                        '{functionResponse: {name: $name, response: {result: "Error: Tool not found"}}}' \
                        > "${RESP_PARTS_FILE}.err"
                    jq --slurpfile new "${RESP_PARTS_FILE}.err" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" \
                        && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.err"
                fi
            fi
        done
        TOOL_RESPONSE=$(jq -n --arg role "$FUNC_ROLE" --slurpfile parts "$RESP_PARTS_FILE" '{ role: $role, parts: $parts[0] }')
        update_history "$TOOL_RESPONSE"; rm "$RESP_PARTS_FILE"
        if [ "$SEARCH_COUNT" -gt 0 ]; then
            echo -e "\033[0;32m> Grounding Search Queries:\033[0m"
            echo "$RESPONSE_JSON" | jq -r '.candidates[0].groundingMetadata.webSearchQueries[]' | sed 's/^/> /'
        fi

        # --- Final Turn Protection ---
        if [ $CURRENT_TURN -ge $MAX_TURNS ]; then
            echo -e "\n\033[0;33m[Warning] MAX_TURNS ($MAX_TURNS) reached after tool execution.\033[0m"
            echo -e "\033[0;33m[System] The model will not see the results of the last tool call.\033[0m"
            break
        fi

        continue
    else
        update_history "$CANDIDATE"
        break
    fi
done

# 6. Render Output
"$BASE_DIR/recap.sh" -l -nc
if [ "$SEARCH_COUNT" -gt 0 ]; then
    echo -e "\033[0;32m> Grounding Search Queries:\033[0m"
    echo "$RESPONSE_JSON" | jq -r '.candidates[0].groundingMetadata.webSearchQueries[]' | sed 's/^/> /'
fi

# Display Session Totals (Usage History)
if [ -f "${file}.log" ]; then
    echo -e "\n\033[0;36m--- Usage History ---\033[0m"
    tail -n 3 "${file}.log"
    echo ""
    awk '{ gsub(/\./, ""); h+=$3; m+=$5; c+=$7; t+=$9; s+=$13 } END { printf "\033[0;34m[Session Total]\033[0m Hit: %d | Miss: %d | Comp: %d | \033[1mTotal: %d\033[0m | Search: %d\n", h, m, c, t, s }' "${file}.log"
fi
END_TIME=$(date +%s.%N)
DURATION=$(awk -v start="$START_TIME" -v end="$END_TIME" 'BEGIN { print end - start }')
START_TIME_FMT=$(date -d "@${START_TIME%.*}" +%H:%M:%S 2>/dev/null || date -r "${START_TIME%.*}" +%H:%M:%S)
END_TIME_FMT=$(date -d "@${END_TIME%.*}" +%H:%M:%S 2>/dev/null || date -r "${END_TIME%.*}" +%H:%M:%S)
printf "\033[0;35m[Total Duration] %.2f seconds [%s] [%s]\033[0m\n" "$DURATION" "$START_TIME_FMT" "$END_TIME_FMT"

