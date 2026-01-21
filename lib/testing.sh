tool_run_tests() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_CMD=$(echo "$FC_DATA" | jq -r '.args.command')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Running Tests: $FC_CMD\033[0m"

    local RESULT_MSG
    local DUR=""

    # Security: Ensure command is a test command
    # Allowed: ./run_tests.sh, ./dummy_run_tests.sh, pytest, npm test, go test, cargo test, make test
    if [[ "$FC_CMD" =~ ^(\./.*run_tests\.sh|pytest|npm[[:space:]]+test|go[[:space:]]+test|cargo[[:space:]]+test|make[[:space:]]+test) ]]; then
        local OUTPUT
        OUTPUT=$(eval "$FC_CMD" 2>&1)
        local EXIT_CODE=$?
        
        if [ $EXIT_CODE -eq 0 ]; then
            RESULT_MSG="PASS"
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;32m[Tool Success] Tests passed.\033[0m"
        else
            # If failed, return output to help diagnose
            local LINE_COUNT=$(echo "$OUTPUT" | wc -l)
            if [ "$LINE_COUNT" -gt 100 ]; then
                OUTPUT="$(echo "$OUTPUT" | head -n 100)\n... (Output truncated) ..."
            fi
            RESULT_MSG="FAIL:\n$OUTPUT"
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] Tests failed.\033[0m"
        fi
    else
        RESULT_MSG="Error: Invalid test command. Allowed: ./run_tests.sh, pytest, npm test, go test, cargo test, make test."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Command denied.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "run_tests" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
