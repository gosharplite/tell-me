tool_get_git_blame() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    local FC_PATH
    local FC_START
    local FC_END
    local RESULT_MSG
    local WARN_MSG
    local IS_SAFE
    local REL_CHECK
    local CMD
    local LINE_COUNT

    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
    FC_START=$(echo "$FC_DATA" | jq -r '.args.start_line // 1')
    FC_END=$(echo "$FC_DATA" | jq -r '.args.end_line // empty')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Git Blame: $FC_PATH\033[0m"

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
    
    local DUR=""

    if [ "$IS_SAFE" = true ]; then
        if [ -f "$FC_PATH" ]; then
            CMD="git blame --date=short"
            # Handle line ranges
            if [ -n "$FC_END" ] && [ "$FC_END" != "null" ]; then
                CMD="$CMD -L $FC_START,$FC_END"
            elif [ "$FC_START" -gt 1 ]; then
                # If only start is provided, blame to end
                CMD="$CMD -L $FC_START,"
            fi
            CMD="$CMD \"$FC_PATH\""

            if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                RESULT_MSG=$(eval "$CMD" 2>&1 | head -n 100)
                    
                if [ -z "$RESULT_MSG" ]; then
                    RESULT_MSG="No blame info found."
                elif [ $(echo "$RESULT_MSG" | wc -l) -eq 100 ]; then
                    RESULT_MSG="${RESULT_MSG}\n... (Output truncated at 100 lines) ..."
                fi
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;32m[Tool Success] Git blame retrieved.\033[0m"
            else
                RESULT_MSG="Error: Not a git repo or git missing."
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;31m[Tool Failed] Git Error.\033[0m"
            fi
        else
                RESULT_MSG="Error: File not found."
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;31m[Tool Failed] File not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation. Path must be within current working directory."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Blame denied: $FC_PATH\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi

    jq -n --arg name "get_git_blame" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
