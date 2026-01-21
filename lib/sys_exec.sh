tool_execute_command() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    # Extract Arguments
    local FC_CMD=$(echo "$FC_DATA" | jq -r '.args.command')
    local FC_REASON=$(echo "$FC_DATA" | jq -r '.args.reason // empty')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Execute Command: $FC_CMD\033[0m"

    local CONFIRM="n"
    local SAFE_COMMANDS="grep|ls|pwd|cat|echo|head|tail|wc|stat|date|whoami|diff"
    
    # Extract the first word of the command to check against whitelist
    local CMD_BASE=$(echo "$FC_CMD" | awk '{print $1}')

    # Strict Validation:
    # 1. Must start with a safe command.
    # 2. Must NOT contain command separators (; | &), redirection (> <), or subshells ($ `).
    if [[ "$CMD_BASE" =~ ^($SAFE_COMMANDS)$ ]] && [[ ! "$FC_CMD" =~ [\|\&\;\>\<] ]] && [[ ! "$FC_CMD" =~ \$\( ]] && [[ ! "$FC_CMD" =~ \` ]]; then
         echo -e "\033[0;32m[Auto-Approved] Safe read-only command detected.\033[0m"
         CONFIRM="y"
    elif [ -t 0 ]; then
        # Interactive mode: Ask user
        if [ -n "$FC_REASON" ]; then
            echo -e "\033[0;33mReason: $FC_REASON\033[0m"
        fi
        # We use /dev/tty to ensure we read from keyboard even if stdin was piped initially
        read -p "⚠️  Execute this command? (y/N) " -n 1 -r CONFIRM < /dev/tty
        echo "" 
    else
        echo "Non-interactive mode: Auto-denying command execution."
    fi

    local RESULT_MSG
    local DUR=""
    
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        # Execute and capture stdout + stderr
        local CMD_OUTPUT
        CMD_OUTPUT=$(bash -c "$FC_CMD" 2>&1)
        local EXIT_CODE=$?
        
        # Truncate if too long (100 lines)
        local LINE_COUNT=$(echo "$CMD_OUTPUT" | wc -l)
        if [ "$LINE_COUNT" -gt 100 ]; then
            CMD_OUTPUT="$(echo "$CMD_OUTPUT" | head -n 100)\n... (Output truncated at 100 lines) ..."
        fi

        if [ $EXIT_CODE -eq 0 ]; then
            RESULT_MSG="Exit Code: 0\nOutput:\n$CMD_OUTPUT"
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;32m[Tool Success] Command executed.\033[0m"
        else
            RESULT_MSG="Exit Code: $EXIT_CODE\nError/Output:\n$CMD_OUTPUT"
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] Command returned non-zero exit code.\033[0m"
        fi
    else
        RESULT_MSG="User denied execution of command: $FC_CMD"
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;33m[Tool Skipped] Execution denied.\033[0m"
    fi

    # Inject Warning if approaching Max Turns
    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        local WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi

    # Construct Function Response Part
    jq -n --arg name "execute_command" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    
    # Append to Array
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
