#!/bin/bash
# Copyright (c) 2026  <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

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
source "$BASE_DIR/lib/core/config_loader.sh"

# --- Configuration Setup ---
load_config "$1" "$BASE_DIR" || exit 1

# --- Directory/Session Setup ---
source "$BASE_DIR/lib/core/session_manager.sh"
file=$(setup_session "$CONFIG_FILE" "$BASE_DIR")

# --- Load Tools ---
source "$BASE_DIR/lib/core/auth.sh"
# Source all library files recursively from lib/core and lib/tools
while IFS= read -r -d '' lib; do
    # Skip files already sourced explicitly
    case "$(basename "$lib")" in
        history_manager.sh|utils.sh|auth.sh|config_loader.sh|session_manager.sh) continue ;;
    esac
    source "$lib"
done < <(find "$BASE_DIR/lib" -maxdepth 3 -name "*.sh" -print0)

# --- Helper Functions ---
update_history() {
  update_history_file "$1" "$file"
}

# --- 1. User Input Handling ---
# If $1 was used as CONFIG_FILE, shift it away
[ "$1" == "$CONFIG_FILE" ] && shift

USER_MSG=$(process_user_input "$1" "$CONFIG_FILE") || exit 1
update_history "$USER_MSG"

# --- Mapping Budget to Thinking Level ---
read -r THINKING_LEVEL BUDGET_VAL <<< $(get_thinking_config "$THINKING_BUDGET")

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
    APIDATA=$(build_payload "$file" "$TOOLS_JSON" "$PERSON" "$AIMODEL" "$THINKING_LEVEL" "$BUDGET_VAL")

    PAYLOAD_FILE=$(mktemp) || exit 1
    echo "$APIDATA" > "$PAYLOAD_FILE"

    # --- Pre-flight Safety Check & Logging ---
    ESTIMATED_TOKENS=0
    if [ -n "$MAX_HISTORY_TOKENS" ]; then
        ESTIMATED_TOKENS=$(estimate_and_check_payload "$PAYLOAD_FILE" "$file" "$MAX_HISTORY_TOKENS") || exit 1
    fi

    PAYLOAD_END=$(date +%s.%N)
    PAYLOAD_DUR=$(awk -v start="$PAYLOAD_START" -v end="$PAYLOAD_END" 'BEGIN { print end - start }')
    echo -e "$(get_log_timestamp) \033[0;90m[System] Payload: ~$ESTIMATED_TOKENS tokens | Generated in ${PAYLOAD_DUR}s\033[0m"

    TURN_START=$(date +%s.%N)
    echo -e "$(get_log_timestamp) \033[0;90m[API] Calling Gemini... (${AIMODEL})\033[0m"

    # 4. Call API with Retry Logic
    RESPONSE_JSON=$(call_gemini_api "$AIURL" "$AIMODEL" "$TOKEN" "$PAYLOAD_FILE") || exit 1

    TURN_END=$(date +%s.%N)
    TURN_DUR=$(awk -v start="$TURN_START" -v end="$TURN_END" 'BEGIN { print end - start }')

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
        
        execute_tools "$CANDIDATE" "$RESP_PARTS_FILE"
        
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
display_session_totals "${file}.log"

END_TIME=$(date +%s.%N)
DURATION=$(awk -v start="$START_TIME" -v end="$END_TIME" 'BEGIN { print end - start }')
START_TIME_FMT=$(date -d "@${START_TIME%.*}" +%H:%M:%S 2>/dev/null || date -r "${START_TIME%.*}" +%H:%M:%S)
END_TIME_FMT=$(date -d "@${END_TIME%.*}" +%H:%M:%S 2>/dev/null || date -r "${END_TIME%.*}" +%H:%M:%S)
printf "\033[0;35m[Total Duration] %.2f seconds [%s] [%s]\033[0m\n" "$DURATION" "$START_TIME_FMT" "$END_TIME_FMT"
