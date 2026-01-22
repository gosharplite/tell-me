tool_ask_user() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    local FC_QUESTION
    local USER_ANSWER
    local RESULT_MSG
    local WARN_MSG

    # Extract Arguments
    FC_QUESTION=$(echo "$FC_DATA" | jq -r '.args.question')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[1;35m[AI Question ($CURRENT_TURN/$MAX_TURNS)] $FC_QUESTION\033[0m"

    # Read user input directly from TTY
    if [ -t 0 ]; then
        read -e -p "Answer > " USER_ANSWER
    else
         read -e -p "Answer > " USER_ANSWER < /dev/tty
    fi
    
    RESULT_MSG="$USER_ANSWER"
    
    local DUR=$(get_log_duration)
    echo -e "${DUR} \033[0;32m[User Answered]\033[0m"

    # Inject Warning if approaching Max Turns
    # Relies on global CURRENT_TURN and MAX_TURNS
    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi

    # Construct Function Response Part
    jq -n --arg name "ask_user" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    
    # Append to Array
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
