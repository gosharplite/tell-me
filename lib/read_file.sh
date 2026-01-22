tool_read_file() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    
    # Extract Arguments
    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
    local FC_START=$(echo "$FC_DATA" | jq -r '.args.start_line // 1')
    local FC_END=$(echo "$FC_DATA" | jq -r '.args.end_line // empty')
    local RANGE_DESC
    local IS_SAFE
    local RESULT_MSG
    local WARN_MSG
    local TOTAL_LINES
    local LINES_TO_READ
    local TRUNC_MSG
    local REL_CHECK

    if [ -z "$FC_END" ] || [ "$FC_END" == "null" ]; then
        RANGE_DESC="Start: $FC_START"
    else
        RANGE_DESC="Lines: $FC_START-$FC_END"
    fi

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request ($CURRENT_TURN/$MAX_TURNS)] Reading: $FC_PATH ($RANGE_DESC)\033[0m"

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
            TOTAL_LINES=$(wc -l < "$FC_PATH")
            
            # Validate Start
            if [ "$FC_START" -lt 1 ]; then FC_START=1; fi
            
            # Determine End
            if [ -z "$FC_END" ] || [ "$FC_END" == "null" ]; then
                # If no end specified, read 500 lines max
                FC_END=$((FC_START + 499))
            fi
            
            # Cap End at Total
            if [ "$TOTAL_LINES" -gt 0 ]; then
                if [ "$FC_END" -gt "$TOTAL_LINES" ]; then
                    FC_END="$TOTAL_LINES"
                fi
            fi

            # Calculate limit check
            LINES_TO_READ=$((FC_END - FC_START + 1))
            
            # Sanity check if range is inverted
            if [ "$LINES_TO_READ" -lt 1 ]; then
                LINES_TO_READ=0
                FC_END=$FC_START
            fi

            if [ "$LINES_TO_READ" -gt 500 ]; then
                # Cap at 500 lines for safety
                FC_END=$((FC_START + 499))
                TRUNC_MSG="\n\n... (Output truncated to 500 lines. Use pagination to read more) ..."
            else
                TRUNC_MSG=""
            fi

            RESULT_MSG=$(sed -n "${FC_START},${FC_END}p" "$FC_PATH")
            RESULT_MSG="${RESULT_MSG}${TRUNC_MSG}"
            
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;32m[Tool Success] File read ($FC_START-$FC_END).\033[0m"
        else
            RESULT_MSG="Error: File not found."
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] File not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation. Path must be within current working directory."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Read denied: $FC_PATH\033[0m"
    fi

    # Inject Warning if approaching Max Turns
    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi

    # Construct Function Response Part
    jq -n --arg name "read_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    
    # Append to Array
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
