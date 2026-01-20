tool_read_git_commit() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_HASH=$(echo "$FC_DATA" | jq -r '.args.hash')
    
    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Git Show: $FC_HASH\033[0m"

    local RESULT_MSG
    local DUR=""
    
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        RESULT_MSG=$(git show --stat --patch "$FC_HASH" 2>&1 | head -n 300)
        
        if [ -z "$RESULT_MSG" ]; then
             RESULT_MSG="Error: Commit not found."
        elif [ $(echo "$RESULT_MSG" | wc -l) -eq 300 ]; then
            RESULT_MSG="${RESULT_MSG}\n... (Output truncated at 300 lines) ..."
        fi
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;32m[Tool Success] Commit details retrieved.\033[0m"
    else
        RESULT_MSG="Error: Not a git repo or git missing."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Failed] Git Error.\033[0m"
    fi

    # Check for max turns warning
    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi

    jq -n --arg name "read_git_commit" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
