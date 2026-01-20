tool_run_tests() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_CMD=$(echo "$FC_DATA" | jq -r '.args.command')

    echo -e "\033[0;36m[Tool Request] Running Tests: $FC_CMD\033[0m"

    local RESULT_MSG
    local OUTPUT_FILE=$(mktemp)

    # Execute command, redirecting both stdout and stderr to the temp file
    # We use 'eval' to allow complex commands (pipes, etc) but this is risky if unmonitored.
    # The agent is trusted in this environment.
    
    (eval "$FC_CMD") > "$OUTPUT_FILE" 2>&1
    local EXIT_CODE=$?
    
    local OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
    rm "$OUTPUT_FILE"

    if [ $EXIT_CODE -eq 0 ]; then
        RESULT_MSG="PASS"
        echo -e "\033[0;32m[Tool Success] Tests Passed.\033[0m"
    else
        # Truncate output if massive
        local LINE_COUNT=$(echo "$OUTPUT_CONTENT" | wc -l)
        if [ "$LINE_COUNT" -gt 100 ]; then
             OUTPUT_CONTENT="$(echo "$OUTPUT_CONTENT" | head -n 100)\n... (Output truncated) ..."
        fi
        
        RESULT_MSG="FAIL (Exit Code: $EXIT_CODE):\n$OUTPUT_CONTENT"
        echo -e "\033[0;31m[Tool Failed] Tests Failed.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "run_tests" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

