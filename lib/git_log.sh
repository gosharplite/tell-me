tool_get_git_log() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_LIMIT=$(echo "$FC_DATA" | jq -r '.args.limit // 10')
    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath // empty')
    
    local TS=$(get_log_timestamp)
    if [ -n "$FC_PATH" ]; then
        echo -e "${TS} \033[0;36m[Tool Request] Git Log (Limit: $FC_LIMIT, File: $FC_PATH)\033[0m"
    else
        echo -e "${TS} \033[0;36m[Tool Request] Git Log (Limit: $FC_LIMIT)\033[0m"
    fi

    local RESULT_MSG
    local DUR=""

    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # Build command with optional file path
        local CMD="git log --oneline -n \"$FC_LIMIT\""
        if [ -n "$FC_PATH" ]; then
            CMD="$CMD -- \"$FC_PATH\""
        fi
        
        RESULT_MSG=$(eval "$CMD" 2>&1)
        if [ -z "$RESULT_MSG" ]; then RESULT_MSG="No commits found."; fi
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;32m[Tool Success] Git log retrieved.\033[0m"
    else
        RESULT_MSG="Error: Not a git repo or git missing."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Failed] Git Error.\033[0m"
    fi

    # Check for max turns warning (inherited from parent scope)
    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi

    jq -n --arg name "get_git_log" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
