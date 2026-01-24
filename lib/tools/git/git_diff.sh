tool_get_git_diff() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    local FC_STAGED
    local RESULT_MSG
    local LINE_COUNT
    local DUR=""

    FC_STAGED=$(echo "$FC_DATA" | jq -r '.args.staged // false')
    
    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Action ($CURRENT_TURN/$MAX_TURNS)] Git Diff (Staged: $FC_STAGED)\033[0m"

    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        [ "$FC_STAGED" == "true" ] && RESULT_MSG=$(git diff --cached 2>&1) || RESULT_MSG=$(git diff 2>&1)
        [ -z "$RESULT_MSG" ] && RESULT_MSG="No changes found."
        LINE_COUNT=$(echo "$RESULT_MSG" | wc -l)
        [ "$LINE_COUNT" -gt 200 ] && RESULT_MSG="$(echo "$RESULT_MSG" | head -n 200)\n... (Truncated) ..."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;32m[Tool Success] Git diff retrieved.\033[0m"
    else
        RESULT_MSG="Error: Not a git repo or git missing."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Failed] Git Error.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
    fi

    jq -n --arg name "get_git_diff" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
