tool_get_git_status() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    local RESULT_MSG
    local DUR=""

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Action ($CURRENT_TURN/$MAX_TURNS)] Git Status\033[0m"

    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        RESULT_MSG=$(git status --short --branch 2>&1)
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;32m[Tool Success] Git status retrieved.\033[0m"
    else
        RESULT_MSG="Error: Not a git repo or git missing."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Failed] Git Error.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
    fi

    jq -n --arg name "get_git_status" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
