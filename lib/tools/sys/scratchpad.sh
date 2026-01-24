# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT
tool_manage_scratchpad() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    # Extract Arguments
    local FC_ACTION=$(echo "$FC_DATA" | jq -r '.args.action')
    local FC_CONTENT=$(echo "$FC_DATA" | jq -r '.args.content // empty')
    local FC_SCOPE=$(echo "$FC_DATA" | jq -r '.args.scope // "session"')
    
    # Define File Path based on Scope
    local SCRATCHPAD_FILE
    if [ "$FC_SCOPE" == "global" ]; then
        SCRATCHPAD_FILE="$AIT_HOME/output/global-scratchpad.md"
    else
        # Default session scratchpad
        SCRATCHPAD_FILE="${file%.*}.scratchpad.md"
    fi

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Action ($CURRENT_TURN/$MAX_TURNS)] Scratchpad Action: $FC_ACTION ($FC_SCOPE)\033[0m"

    local RESULT_MSG
    case "$FC_ACTION" in
        "read")
            if [ -f "$SCRATCHPAD_FILE" ]; then
                RESULT_MSG=$(cat "$SCRATCHPAD_FILE")
                if [ -z "$RESULT_MSG" ]; then RESULT_MSG="[Scratchpad is empty]"; fi
            else
                RESULT_MSG="[Scratchpad does not exist yet]"
            fi
            ;;
        "write")
            echo "$FC_CONTENT" > "$SCRATCHPAD_FILE"
            RESULT_MSG="Scratchpad overwritten."
            ;;
        "append")
            # Ensure we don't append to the end of a line if no newline exists
            if [ -s "$SCRATCHPAD_FILE" ]; then
                # Add a newline separator if appending to non-empty file
                echo "" >> "$SCRATCHPAD_FILE"
            fi
            echo "$FC_CONTENT" >> "$SCRATCHPAD_FILE"
            RESULT_MSG="Content appended to scratchpad."
            ;;
        "clear")
            echo "" > "$SCRATCHPAD_FILE"
            RESULT_MSG="Scratchpad cleared."
            ;;
        *)
            RESULT_MSG="Error: Invalid action. Use read, write, append, or clear."
            ;;
    esac

    local DUR=$(get_log_duration)
    echo -e "${DUR} \033[0;32m[Tool Success] $RESULT_MSG\033[0m"

    # Inject Warning if approaching Max Turns
    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        local WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi

    # Construct Function Response Part
    jq -n --arg name "manage_scratchpad" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    
    # Append to Array
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
