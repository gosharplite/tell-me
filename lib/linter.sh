# Requires: lib/utils.sh for check_path_safety

tool_validate_syntax() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Action ($CURRENT_TURN/$MAX_TURNS)] Validating Syntax: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG
    local EXIT_CODE=0
    local DUR=""

    if [ "$IS_SAFE" == "true" ]; then
        if [ -f "$FC_PATH" ]; then
            local EXT="${FC_PATH##*.}"
            local OUTPUT=""

            case "$EXT" in
                sh|bash)
                    OUTPUT=$(bash -n "$FC_PATH" 2>&1)
                    EXIT_CODE=$?
                    ;;
                py)
                    OUTPUT=$(python3 -m py_compile "$FC_PATH" 2>&1)
                    EXIT_CODE=$?
                    # py_compile doesn't output anything on success, usually
                    ;;
                json)
                    OUTPUT=$(jq empty "$FC_PATH" 2>&1)
                    EXIT_CODE=$?
                    ;;
                js)
                    if command -v node >/dev/null 2>&1; then
                        OUTPUT=$(node --check "$FC_PATH" 2>&1)
                        EXIT_CODE=$?
                    else
                        RESULT_MSG="Warning: 'node' not found, cannot validate JS."
                        EXIT_CODE=1
                    fi
                    ;;
                *)
                    RESULT_MSG="Info: No linter available for .$EXT files."
                    EXIT_CODE=0 # Treat as pass/ignore
                    ;;
            esac

            if [ -z "$RESULT_MSG" ]; then
                if [ $EXIT_CODE -eq 0 ]; then
                    RESULT_MSG="PASS: Syntax is valid."
                    DUR=$(get_log_duration)
                    echo -e "${DUR} \033[0;32m[Tool Success] Syntax Valid.\033[0m"
                else
                    RESULT_MSG="FAIL: Syntax errors found:\n$OUTPUT"
                    DUR=$(get_log_duration)
                    echo -e "${DUR} \033[0;31m[Tool Failed] Syntax Invalid.\033[0m"
                fi
            fi
        else
            RESULT_MSG="Error: File not found."
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] File not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Access denied.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi
    jq -n --arg name "validate_syntax" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
