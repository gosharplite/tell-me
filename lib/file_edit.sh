# Requires: lib/utils.sh for check_path_safety

tool_update_file() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Writing to file: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG

    local DUR=""

    if [ "$IS_SAFE" == "true" ]; then
        mkdir -p "$(dirname "$FC_PATH")"
        
        # --- Backup Hook ---
        if declare -f backup_file > /dev/null; then
            backup_file "$FC_PATH"
        fi
        # -------------------

        # Use jq to write directly to avoid stripping newlines via command substitution
        echo "$FC_DATA" | jq -r '.args.content' > "$FC_PATH"
        
        if [ $? -eq 0 ]; then
            RESULT_MSG="File updated successfully."
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;32m[Tool Success] File updated.\033[0m"
        else
            RESULT_MSG="Error: Failed to write file."
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] Could not write file.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation. Write path must be within current working directory."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Write denied: $FC_PATH\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "update_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_replace_text() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
    
    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Replacing text in: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG
    local DUR=""

    if [ "$IS_SAFE" == "true" ]; then
        if [ -f "$FC_PATH" ]; then
            # --- Backup Hook ---
            if declare -f backup_file > /dev/null; then
                backup_file "$FC_PATH"
            fi
            
            # Prepare data file for Python to avoid shell variable stripping
            local PY_DATA_FILE=$(mktemp)
            echo "$FC_DATA" > "$PY_DATA_FILE"
            export PY_DATA_FILE
            
            python3 -c '
import os, sys, json

data_file = os.environ["PY_DATA_FILE"]
try:
    with open(data_file, "r") as f:
        data = json.load(f)
        
    path = data["args"]["filepath"]
    old = data["args"]["old_text"]
    new = data["args"]["new_text"]
    
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    
    if old not in content:
        print("Error: old_text not found in file.")
        sys.exit(1)
        
    new_content = content.replace(old, new, 1)
    
    with open(path, "w", encoding="utf-8") as f:
        f.write(new_content)
    
    print("Success: Text replaced.")
except Exception as e:
    print(f"Error: {str(e)}")
    sys.exit(1)
' > "${RESP_PARTS_FILE}.py_out" 2>&1
            
            local PY_EXIT=$?
            RESULT_MSG=$(cat "${RESP_PARTS_FILE}.py_out")
            rm "${RESP_PARTS_FILE}.py_out" "$PY_DATA_FILE"
            
            if [ $PY_EXIT -eq 0 ]; then
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;32m[Tool Success] $RESULT_MSG\033[0m"
            else
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;31m[Tool Failed] $RESULT_MSG\033[0m"
            fi
        else
             RESULT_MSG="Error: File not found."
             DUR=$(get_log_duration)
             echo -e "${DUR} \033[0;31m[Tool Failed] File not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation. Edit path must be within current working directory."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Edit denied: $FC_PATH\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "replace_text" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_insert_text() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
    # FC_TEXT and others are extracted inside Python via JSON file to preserve newlines

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Inserting text in: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG
    local DUR=""

    if [ "$IS_SAFE" == "true" ]; then
        if [ -f "$FC_PATH" ]; then
            if declare -f backup_file > /dev/null; then
                backup_file "$FC_PATH"
            fi

            local PY_DATA_FILE=$(mktemp)
            echo "$FC_DATA" > "$PY_DATA_FILE"
            export PY_DATA_FILE

            python3 -c '
import os, sys, json

data_file = os.environ["PY_DATA_FILE"]
try:
    with open(data_file, "r") as f:
        data = json.load(f)
        
    path = data["args"]["filepath"]
    text = data["args"]["text"]
    line_num = int(data["args"]["line_number"])
    place = data["args"]["placement"]

    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    if line_num < 0 or line_num > len(lines) + 1:
        print(f"Error: Line number {line_num} out of bounds.")
        sys.exit(1)

    idx = line_num - 1
    
    # Ensure insertion has separate line if needed, or rely on user content
    if not text.endswith("\n"):
        text += "\n"

    if place == "before":
        if idx < 0: idx = 0
        lines.insert(idx, text)
    else: # after
        if idx < 0: 
             lines.insert(0, text)
        elif idx >= len(lines):
             lines.append(text)
        else:
             lines.insert(idx + 1, text)

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)

    print("Success: Text inserted.")

except Exception as e:
    print(f"Error: {str(e)}")
    sys.exit(1)
' > "${RESP_PARTS_FILE}.py_out" 2>&1

            local PY_EXIT=$?
            RESULT_MSG=$(cat "${RESP_PARTS_FILE}.py_out")
            rm "${RESP_PARTS_FILE}.py_out" "$PY_DATA_FILE"

            if [ $PY_EXIT -eq 0 ]; then
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;32m[Tool Success] $RESULT_MSG\033[0m"
            else
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;31m[Tool Failed] $RESULT_MSG\033[0m"
            fi
        else
             RESULT_MSG="Error: File not found."
             DUR=$(get_log_duration)
             echo -e "${DUR} \033[0;31m[Tool Failed] File not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation. Edit path must be within current working directory."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Insert denied: $FC_PATH\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "insert_text" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_apply_patch() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Applying Patch\033[0m"
    
    local RESULT_MSG
    local DUR=""

    if ! command -v patch >/dev/null 2>&1; then
         RESULT_MSG="Error: 'patch' command not found."
         DUR=$(get_log_duration)
         echo -e "${DUR} \033[0;31m[Tool Failed] patch missing.\033[0m"
    else
        local PATCH_FILE=$(mktemp)
        # Use jq to write directly to avoid stripping newlines via command substitution
        echo "$FC_DATA" | jq -r '.args.patch_content' > "$PATCH_FILE"
        
        local TARGET_FILE=$(grep -m 1 "^+++ b/" "$PATCH_FILE" | sed 's|^+++ b/||')
        if [ -n "$TARGET_FILE" ] && [ -f "$TARGET_FILE" ]; then
             if declare -f backup_file > /dev/null; then
                 backup_file "$TARGET_FILE"
             fi
        fi

        local PATCH_ARGS="--batch --forward"
        if patch --help 2>&1 | grep -q "\--no-backup-if-mismatch"; then
            PATCH_ARGS="$PATCH_ARGS --no-backup-if-mismatch"
        fi

        local OUTPUT
        OUTPUT=$(patch $PATCH_ARGS -p1 < "$PATCH_FILE" 2>&1)
        local EXIT_CODE=$?
        
        if [ $EXIT_CODE -ne 0 ]; then
            local OUTPUT_RETRY
            OUTPUT_RETRY=$(patch $PATCH_ARGS < "$PATCH_FILE" 2>&1)
            if [ $? -eq 0 ]; then
                OUTPUT="$OUTPUT_RETRY"
                EXIT_CODE=0
            else
                OUTPUT="$OUTPUT\nRetry (p0): $OUTPUT_RETRY"
            fi
        fi
        
        rm "$PATCH_FILE"

        if [ $EXIT_CODE -eq 0 ]; then
            RESULT_MSG="Success:\n$OUTPUT"
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;32m[Tool Success] Patch applied.\033[0m"
        else
            RESULT_MSG="Error applying patch:\n$OUTPUT"
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] Patch failed.\033[0m"
        fi
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "apply_patch" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_rollback_file() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Rolling back: $FC_PATH\033[0m"

    local RESULT_MSG
    local DUR=""
    # Assuming restore_backup is available
    if declare -f restore_backup > /dev/null && restore_backup "$FC_PATH"; then
        RESULT_MSG="Success: Reverted $FC_PATH to previous state."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;32m[Tool Success] Rollback complete.\033[0m"
    else
        RESULT_MSG="Error: No backup found for $FC_PATH or restore failed."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Failed] No backup available.\033[0m"
    fi

    jq -n --arg name "rollback_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_move_file() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_SRC=$(echo "$FC_DATA" | jq -r '.args.source_path')
    local FC_DEST=$(echo "$FC_DATA" | jq -r '.args.dest_path')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Moving: $FC_SRC -> $FC_DEST\033[0m"

    local SAFE_SRC=$(check_path_safety "$FC_SRC")
    local SAFE_DEST=$(check_path_safety "$FC_DEST")
    local RESULT_MSG
    local DUR=""

    if [ "$SAFE_SRC" == "true" ] && [ "$SAFE_DEST" == "true" ]; then
        if [ -e "$FC_SRC" ]; then
            local DEST_DIR=$(dirname "$FC_DEST")
            if [ ! -d "$DEST_DIR" ]; then
                mkdir -p "$DEST_DIR"
            fi

            mv "$FC_SRC" "$FC_DEST" 2>&1
            if [ $? -eq 0 ]; then
                RESULT_MSG="Success: Moved $FC_SRC to $FC_DEST"
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;32m[Tool Success] File moved.\033[0m"
            else
                RESULT_MSG="Error: Failed to move file."
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;31m[Tool Failed] Move failed.\033[0m"
            fi
        else
             RESULT_MSG="Error: Source path does not exist."
             DUR=$(get_log_duration)
             echo -e "${DUR} \033[0;31m[Tool Failed] Source not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation. Source and Destination must be within current working directory."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Move denied.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "move_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_delete_file() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Deleting: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG
    local DUR=""

    if [ "$IS_SAFE" == "true" ]; then
        if [ -e "$FC_PATH" ]; then
            if [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)" ]; then
                RESULT_MSG="Error: Cannot delete current working directory."
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;31m[Tool Failed] Deletion Blocked.\033[0m"
            else
                rm -rf "$FC_PATH" 2>&1
                if [ $? -eq 0 ]; then
                    RESULT_MSG="Success: Deleted $FC_PATH"
                    DUR=$(get_log_duration)
                    echo -e "${DUR} \033[0;32m[Tool Success] File deleted.\033[0m"
                else
                    RESULT_MSG="Error: Failed to delete file/directory."
                    DUR=$(get_log_duration)
                    echo -e "${DUR} \033[0;31m[Tool Failed] Delete failed.\033[0m"
                fi
            fi
        else
             RESULT_MSG="Error: Path does not exist."
             DUR=$(get_log_duration)
             echo -e "${DUR} \033[0;31m[Tool Failed] Path not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation. Path must be within current working directory."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Delete denied.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "delete_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
