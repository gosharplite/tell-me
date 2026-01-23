# Requires: jq

tool_manage_tasks() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    
    # Derive tasks filename based on Scope
    local SCOPE=$(echo "$FC_DATA" | jq -r '.args.scope // "session"')
    local TASKS_FILE
    if [ "$SCOPE" == "global" ]; then
        TASKS_FILE="$AIT_HOME/output/global-tasks.json"
    else
        # Default session tasks
        local BASE_NAME="${file:-./history.json}"
        TASKS_FILE="${BASE_NAME%.*}.tasks.json"
    fi

    local ACTION=$(echo "$FC_DATA" | jq -r '.args.action')
    local TASK_ID=$(echo "$FC_DATA" | jq -r '.args.task_id // empty')
    local CONTENT=$(echo "$FC_DATA" | jq -r '.args.content // empty')
    local STATUS=$(echo "$FC_DATA" | jq -r '.args.status // empty')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Action ($CURRENT_TURN/$MAX_TURNS)] Manage Tasks: $ACTION ($SCOPE)\033[0m"

    local RESULT_MSG=""

    # Initialize tasks file if not exists
    if [ ! -f "$TASKS_FILE" ]; then
        # Ensure directory exists (e.g., output/)
        mkdir -p "$(dirname "$TASKS_FILE")"
        echo "[]" > "$TASKS_FILE"
    fi

    case "$ACTION" in
        add)
            if [ -z "$CONTENT" ]; then
                RESULT_MSG="Error: 'content' is required for 'add' action."
            else
                local NEXT_ID=$(jq 'if length == 0 then 1 else (map(.id) | max + 1) end' "$TASKS_FILE")
                # Add new task with status 'pending'
                jq --arg id "$NEXT_ID" --arg content "$CONTENT" \
                   '. + [{id: ($id|tonumber), content: $content, status: "pending"}]' \
                   "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
                RESULT_MSG="Task added with ID: $NEXT_ID"
            fi
            ;;
            
        update)
            if [ -z "$TASK_ID" ]; then
                RESULT_MSG="Error: 'task_id' is required for 'update' action."
            else
                # Check if ID exists
                if jq -e ".[] | select(.id == ($TASK_ID|tonumber))" "$TASKS_FILE" >/dev/null; then
                    # Build update logic
                    local JQ_CMD="map(if .id == ($TASK_ID|tonumber) then ."
                    if [ -n "$CONTENT" ]; then
                        JQ_CMD="${JQ_CMD} + {content: \"$CONTENT\"}"
                    fi
                    if [ -n "$STATUS" ]; then
                        JQ_CMD="${JQ_CMD} + {status: \"$STATUS\"}"
                    fi
                    JQ_CMD="${JQ_CMD} else . end)"

                    jq "$JQ_CMD" "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
                    RESULT_MSG="Task $TASK_ID updated."
                else
                    RESULT_MSG="Error: Task ID $TASK_ID not found."
                fi
            fi
            ;;

        list)
            local FILTER="."
            if [ -n "$STATUS" ]; then
                FILTER="map(select(.status == \"$STATUS\"))"
            fi
            
            local LIST_OUTPUT
            LIST_OUTPUT=$(jq -r "$FILTER | .[] | \"[\(.id)] [\(.status)] \(.content)\"" "$TASKS_FILE")
            
            if [ -z "$LIST_OUTPUT" ]; then
                RESULT_MSG="No tasks found."
            else
                RESULT_MSG="Current Tasks:\n$LIST_OUTPUT"
            fi
            ;;

        delete)
            if [ -z "$TASK_ID" ]; then
                RESULT_MSG="Error: 'task_id' is required for 'delete' action."
            else
                if jq -e ".[] | select(.id == ($TASK_ID|tonumber))" "$TASKS_FILE" >/dev/null; then
                    jq "map(select(.id != ($TASK_ID|tonumber)))" "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
                    RESULT_MSG="Task $TASK_ID deleted."
                else
                    RESULT_MSG="Error: Task ID $TASK_ID not found."
                fi
            fi
            ;;
        
        clear)
             echo "[]" > "$TASKS_FILE"
             RESULT_MSG="All tasks cleared."
             ;;

        *)
            RESULT_MSG="Error: Unknown action '$ACTION'. Valid actions: add, update, list, delete, clear."
            ;;
    esac

    local DUR=$(get_log_duration)
    echo -e "${DUR} \033[0;32m[Tool Success] $RESULT_MSG\033[0m"

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi
    jq -n --arg name "manage_tasks" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
