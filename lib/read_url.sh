tool_read_url() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_URL=$(echo "$FC_DATA" | jq -r '.args.url')
    
    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Reading URL: $FC_URL\033[0m"

    local RESULT_MSG
    local DUR=""

    if command -v curl >/dev/null 2>&1; then
        # Use curl to fetch content
        # -L: Follow redirects
        # -s: Silent
        # --max-time 10: Timeout
        local CONTENT
        CONTENT=$(curl -L -s --max-time 10 "$FC_URL")
        local EXIT_CODE=$?

        if [ $EXIT_CODE -eq 0 ]; then
            # Basic HTML stripping (very crude) or just return raw text
            # If it's HTML, we might want to use something like 'lynx -dump' if available
            if command -v lynx >/dev/null 2>&1; then
                 RESULT_MSG=$(echo "$CONTENT" | lynx -stdin -dump)
            else
                 # Fallback: Strip tags via sed (imperfect) or just return first 2000 chars
                 RESULT_MSG=$(echo "$CONTENT" | sed 's/<[^>]*>//g' | head -c 5000)
                 if [ ${#CONTENT} -gt 5000 ]; then
                     RESULT_MSG="${RESULT_MSG}\n... (Truncated) ..."
                 fi
            fi
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;32m[Tool Success] URL Fetched.\033[0m"
        else
            RESULT_MSG="Error: Failed to fetch URL (Exit Code: $EXIT_CODE)."
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] Fetch failed.\033[0m"
        fi
    else
        RESULT_MSG="Error: 'curl' command not found."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Failed] Missing dependency.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "read_url" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
