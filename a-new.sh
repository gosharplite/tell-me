#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Resolve Script Directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check Dependencies
for cmd in jq curl gcloud awk python3 patch; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is missing." >&2
        exit 1
    fi
done

# Helper function to append messages to history safely
update_history() {
  local json_content="$1"
  local item_file=$(mktemp)
  printf "%s" "$json_content" > "$item_file"
  
  if [ -s "$file" ] && jq empty "$file" > /dev/null 2>&1; then
    if ! jq --slurpfile item "$item_file" '.messages += $item' "$file" > "${file}.tmp"; then
        echo "Error: Failed to process history file." >&2
        rm "$item_file"
        exit 1
    fi
    mv "${file}.tmp" "$file"
  else
    jq -n --slurpfile item "$item_file" '{messages: $item}' > "$file"
  fi
  rm "$item_file"
}

# Helper: Shadow Backup Logic
BACKUP_DIR="${TMPDIR:-/tmp}/tellme_backups"
# Prune backups older than 24 hours
find "$BACKUP_DIR" -type f -mtime +1 -delete 2>/dev/null
mkdir -p "$BACKUP_DIR"

backup_file() {
    local target="$1"
    if [ -f "$target" ]; then
        # Create a flat filename (e.g. ./src/main.py -> _src_main.py)
        local flat_name=$(echo "$target" | sed 's/[\/\.]/_/g')
        cp "$target" "$BACKUP_DIR/$flat_name"
    fi
}

restore_backup() {
    local target="$1"
    local flat_name=$(echo "$target" | sed 's/[\/\.]/_/g')
    local backup_path="$BACKUP_DIR/$flat_name"
    
    if [ -f "$backup_path" ]; then
        cp "$backup_path" "$target"
        return 0
    else
        return 1
    fi
}

# 1. Update Conversation History (User Input)
PROMPT_TEXT="$1"
STDIN_DATA=""

if [ ! -t 0 ]; then
    STDIN_DATA="$(cat)"
fi

if [ -n "$STDIN_DATA" ]; then
    MSG_TEXT="${PROMPT_TEXT}\n\n${STDIN_DATA}"
elif [ -n "$PROMPT_TEXT" ]; then
    MSG_TEXT="$PROMPT_TEXT"
else
    MSG_TEXT="$DATA"
    echo "Usage: a \"Your message\" or pipe content via stdin" >&2
    exit 1
fi

USER_MSG=$(printf "%s" "$MSG_TEXT" | jq -Rs '{role: "user", parts: [{text: .}]}')
update_history "$USER_MSG"

# 2. Configure Tools & Auth
# --- Tool Definitions ---
if [ -f "$BASE_DIR/lib/tools.json" ]; then
    FUNC_DECLARATIONS=$(cat "$BASE_DIR/lib/tools.json")
else
    echo "Error: Tool definitions not found at $BASE_DIR/lib/tools.json" >&2
    exit 1
fi

if [ "$USE_SEARCH" == "true" ]; then
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "googleSearch": {} }, { "functionDeclarations": $funcs }]')
else
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "functionDeclarations": $funcs }]')
fi

# --- Auth Setup ---
source "$BASE_DIR/lib/auth.sh"
source "$BASE_DIR/lib/read_file.sh"

# ==============================================================================
# MAIN INTERACTION LOOP
# Handles multi-turn interactions (Tool Call -> Execution -> Tool Response)
# ==============================================================================
source "$BASE_DIR/lib/read_image.sh"

MAX_TURNS=100
source "$BASE_DIR/lib/ask_user.sh"
CURRENT_TURN=0
FINAL_TEXT_RESPONSE=""

START_TIME=$(date +%s.%N)

while [ $CURRENT_TURN -lt $MAX_TURNS ]; do
    CURRENT_TURN=$((CURRENT_TURN + 1))

    # 3. Build API Payload (reads current history from file)
    APIDATA=$(jq -n \
      --arg person "$PERSON" \
      --argjson tools "$TOOLS_JSON" \
      --slurpfile history "$file" \
      '{
        contents: $history[0].messages,
        tools: $tools,
        generationConfig: { 
            temperature: 1.0 
            # thinkingConfig removed for compatibility
        },
        safetySettings: [
          { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" }
        ]
      } + 
      (if $person != "" then { systemInstruction: { role: "system", parts: [{text: $person}] } } else {} end)'
source "$BASE_DIR/lib/git_blame.sh"
    )

    PAYLOAD_FILE=$(mktemp) || exit 1
    echo "$APIDATA" > "$PAYLOAD_FILE"

    # 4. Call API with Retry Logic
    RETRY_COUNT=0
    MAX_RETRIES=3
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RESPONSE_JSON=$(curl -s "${AIURL}/${AIMODEL}:generateContent" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d @"$PAYLOAD_FILE")
        
        # Check for Rate Limit (429 or "Resource exhausted")
        # Note: curl output is JSON, we look for error code/status inside the JSON if HTTP 200 returned a soft error,
        # or handle HTTP status if we were capturing headers.
        # Simple check: Does the JSON contain an error with code 429 or message "RESOURCE_EXHAUSTED"?
        
        IS_RATE_LIMIT="no"
        if echo "$RESPONSE_JSON" | jq -e '.error.code == 429 or .error.status == "RESOURCE_EXHAUSTED" or (.error.message | contains("Resource exhausted"))' > /dev/null 2>&1; then
            IS_RATE_LIMIT="yes"
        fi

        if [ "$IS_RATE_LIMIT" == "yes" ]; then
             RETRY_COUNT=$((RETRY_COUNT + 1))
             if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                 echo -e "\033[0;33m[System] Rate Limit Hit (429). Retrying in 5s... ($RETRY_COUNT/$MAX_RETRIES)\033[0m"
                 sleep 5
                 continue
             else
                 echo -e "\033[31mError: Rate limit exhausted after $MAX_RETRIES retries.\033[0m"
                 rm "$PAYLOAD_FILE"
                 exit 1
             fi
        else
             # Not a rate limit error, break the retry loop
             break
        fi
    done

    rm "$PAYLOAD_FILE"

    # Basic Validation
    if echo "$RESPONSE_JSON" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "\033[31mAPI Error:\033[0m $(echo "$RESPONSE_JSON" | jq -r '.error.message')"
        exit 1
    fi

    CANDIDATE=$(echo "$RESPONSE_JSON" | jq -c '.candidates[0].content')
    
    # 5. Check for Function Call(s)
    # Gemini may return multiple function calls in one turn (parallel calling).
    # We must identify if ANY part is a function call.
    HAS_FUNC=$(echo "$CANDIDATE" | jq -e '.parts[] | has("functionCall")' >/dev/null 2>&1 && echo "yes" || echo "no")

    if [ "$HAS_FUNC" == "yes" ]; then
        # --- Handle Tool Execution (Parallel Compatible) ---
        
        # 1. Update History with the Model's Request (The Function Call)
        update_history "$CANDIDATE"

        # 2. Iterate over parts to execute calls and build responses
        RESP_PARTS_FILE=$(mktemp)
        echo "[]" > "$RESP_PARTS_FILE"
        
        PART_COUNT=$(echo "$CANDIDATE" | jq '.parts | length')

        for (( i=0; i<$PART_COUNT; i++ )); do
            FC_DATA=$(echo "$CANDIDATE" | jq -c ".parts[$i].functionCall // empty")
            
            if [ -n "$FC_DATA" ]; then
                F_NAME=$(echo "$FC_DATA" | jq -r '.name')

                if [ "$F_NAME" == "ask_user" ]; then
                    tool_ask_user "$FC_DATA" "$RESP_PARTS_FILE"
                
                elif [ "$F_NAME" == "manage_scratchpad" ]; then
                    # Extract Arguments
                    FC_ACTION=$(echo "$FC_DATA" | jq -r '.args.action')
                    FC_CONTENT=$(echo "$FC_DATA" | jq -r '.args.content // empty')
                    
                    SCRATCHPAD_FILE="${file%.*}.scratchpad.md"

                    echo -e "\033[0;36m[Tool Request] Scratchpad Action: $FC_ACTION\033[0m"

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

                    echo -e "\033[0;32m[Tool Success] $RESULT_MSG\033[0m"

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "manage_scratchpad" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "update_file" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
                    FC_CONTENT=$(echo "$FC_DATA" | jq -r '.args.content')

                    echo -e "\033[0;36m[Tool Request] Writing to file: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        mkdir -p "$(dirname "$FC_PATH")"
                        
                        # --- Backup Hook ---
                        backup_file "$FC_PATH"
                        # -------------------

                        printf "%s" "$FC_CONTENT" > "$FC_PATH"
                        if [ $? -eq 0 ]; then
                            RESULT_MSG="File updated successfully."
                            echo -e "\033[0;32m[Tool Success] File updated.\033[0m"
                        else
                            RESULT_MSG="Error: Failed to write file."
                            echo -e "\033[0;31m[Tool Failed] Could not write file.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Write path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Write denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "update_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "replace_text" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
                    FC_OLD=$(echo "$FC_DATA" | jq -r '.args.old_text')
                    FC_NEW=$(echo "$FC_DATA" | jq -r '.args.new_text')

                    echo -e "\033[0;36m[Tool Request] Replacing text in: $FC_PATH\033[0m"

                    # Security Check
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -f "$FC_PATH" ]; then
                            # --- Backup Hook ---
                            backup_file "$FC_PATH"
                            # -------------------

                            # Use Python for safe replacement (Surgical: 1st occurrence only)
                            export PYTHON_OLD="$FC_OLD"
                            export PYTHON_NEW="$FC_NEW"
                            export PYTHON_PATH="$FC_PATH"
                            
                            python3 -c '
import os, sys

path = os.environ["PYTHON_PATH"]
old = os.environ["PYTHON_OLD"]
new = os.environ["PYTHON_NEW"]

try:
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
                            
                            PY_EXIT=$?
                            RESULT_MSG=$(cat "${RESP_PARTS_FILE}.py_out")
                            rm "${RESP_PARTS_FILE}.py_out"
                            
                            if [ $PY_EXIT -eq 0 ]; then
                                echo -e "\033[0;32m[Tool Success] $RESULT_MSG\033[0m"
                            else
                                echo -e "\033[0;31m[Tool Failed] $RESULT_MSG\033[0m"
                            fi
                        else
                             RESULT_MSG="Error: File not found."
                             echo -e "\033[0;31m[Tool Failed] File not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Edit path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Edit denied: $FC_PATH\033[0m"
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    jq -n --arg name "replace_text" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "insert_text" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
                    FC_TEXT=$(echo "$FC_DATA" | jq -r '.args.text')
                    FC_LINE=$(echo "$FC_DATA" | jq -r '.args.line_number')
                    FC_PLACE=$(echo "$FC_DATA" | jq -r '.args.placement')

                    echo -e "\033[0;36m[Tool Request] Inserting text $FC_PLACE line $FC_LINE in: $FC_PATH\033[0m"

                    # Security Check
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -f "$FC_PATH" ]; then
                            # --- Backup Hook ---
                            backup_file "$FC_PATH"
                            # -------------------

                            export PY_PATH="$FC_PATH"
                            export PY_TEXT="$FC_TEXT"
                            export PY_LINE="$FC_LINE"
                            export PY_PLACE="$FC_PLACE"

                            python3 -c '
import os, sys

path = os.environ["PY_PATH"]
text = os.environ["PY_TEXT"]
line_num = int(os.environ["PY_LINE"])
place = os.environ["PY_PLACE"]

try:
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

                            PY_EXIT=$?
                            RESULT_MSG=$(cat "${RESP_PARTS_FILE}.py_out")
                            rm "${RESP_PARTS_FILE}.py_out"

                            if [ $PY_EXIT -eq 0 ]; then
                                echo -e "\033[0;32m[Tool Success] $RESULT_MSG\033[0m"
                            else
                                echo -e "\033[0;31m[Tool Failed] $RESULT_MSG\033[0m"
                            fi
                        else
                             RESULT_MSG="Error: File not found."
                             echo -e "\033[0;31m[Tool Failed] File not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Edit path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Insert denied: $FC_PATH\033[0m"
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    jq -n --arg name "insert_text" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "apply_patch" ]; then
                    # Extract Arguments
                    FC_PATCH=$(echo "$FC_DATA" | jq -r '.args.patch_content')

                    echo -e "\033[0;36m[Tool Request] Applying Patch\033[0m"

                    if ! command -v patch >/dev/null 2>&1; then
                         RESULT_MSG="Error: 'patch' command not found."
                         echo -e "\033[0;31m[Tool Failed] patch missing.\033[0m"
                    else
                        PATCH_FILE=$(mktemp)
                        printf "%s" "$FC_PATCH" > "$PATCH_FILE"
                        
                        # --- Backup Hook (Naive approach: Parse filename from patch?) ---
                        # Patch files are complex. We need to identify the target file(s).
                        # Simple grep for "--- a/" or "+++ b/"
                        TARGET_FILE=$(grep -m 1 "^+++ b/" "$PATCH_FILE" | sed 's|^+++ b/||')
                        if [ -n "$TARGET_FILE" ] && [ -f "$TARGET_FILE" ]; then
                             backup_file "$TARGET_FILE"
                        fi
                        # -------------------------------------------------------------

                        # GNU patch specific: prevent .orig files on mismatch (cleaner workspace)
                        PATCH_ARGS="--batch --forward"
                        if patch --help 2>&1 | grep -q "\--no-backup-if-mismatch"; then
                            PATCH_ARGS="$PATCH_ARGS --no-backup-if-mismatch"
                        fi

                        OUTPUT=$(patch $PATCH_ARGS -p1 < "$PATCH_FILE" 2>&1)
                        EXIT_CODE=$?
                        
                        if [ $EXIT_CODE -ne 0 ]; then
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
                            echo -e "\033[0;32m[Tool Success] Patch applied.\033[0m"
                        else
                            RESULT_MSG="Error applying patch:\n$OUTPUT"
                            echo -e "\033[0;31m[Tool Failed] Patch failed.\033[0m"
                        fi
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    jq -n --arg name "apply_patch" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "rollback_file" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

                    echo -e "\033[0;36m[Tool Request] Rolling back: $FC_PATH\033[0m"

                    if restore_backup "$FC_PATH"; then
                        RESULT_MSG="Success: Reverted $FC_PATH to previous state."
                        echo -e "\033[0;32m[Tool Success] Rollback complete.\033[0m"
                    else
                        RESULT_MSG="Error: No backup found for $FC_PATH."
                        echo -e "\033[0;31m[Tool Failed] No backup available.\033[0m"
                    fi

                    jq -n --arg name "rollback_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "move_file" ]; then
                    # Extract Arguments
                    FC_SRC=$(echo "$FC_DATA" | jq -r '.args.source_path')
                    FC_DEST=$(echo "$FC_DATA" | jq -r '.args.dest_path')

                    echo -e "\033[0;36m[Tool Request] Moving: $FC_SRC -> $FC_DEST\033[0m"

                    # Security Check: Ensure BOTH paths are within CWD
                    IS_SAFE=false
                    SAFE_SRC=false
                    SAFE_DEST=false
                    
                    # Check Source
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_SRC")
                        [ "$REL_CHECK" == "True" ] && SAFE_SRC=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_SRC")" == "$(pwd -P)"* ] && SAFE_SRC=true
                    else
                        if [[ "$FC_SRC" != /* && "$FC_SRC" != *".."* ]]; then SAFE_SRC=true; fi
                    fi
                    
                    # Check Dest
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_DEST")
                        [ "$REL_CHECK" == "True" ] && SAFE_DEST=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_DEST")" == "$(pwd -P)"* ] && SAFE_DEST=true
                    else
                        if [[ "$FC_DEST" != /* && "$FC_DEST" != *".."* ]]; then SAFE_DEST=true; fi
                    fi

                    if [ "$SAFE_SRC" = true ] && [ "$SAFE_DEST" = true ]; then
                        if [ -e "$FC_SRC" ]; then
                            # Ensure dest directory exists if it looks like a directory path
                            DEST_DIR=$(dirname "$FC_DEST")
                            if [ ! -d "$DEST_DIR" ]; then
                                mkdir -p "$DEST_DIR"
                            fi

                            mv "$FC_SRC" "$FC_DEST" 2>&1
                            if [ $? -eq 0 ]; then
                                RESULT_MSG="Success: Moved $FC_SRC to $FC_DEST"
                                echo -e "\033[0;32m[Tool Success] File moved.\033[0m"
                            else
                                RESULT_MSG="Error: Failed to move file."
                                echo -e "\033[0;31m[Tool Failed] Move failed.\033[0m"
                            fi
                        else
                             RESULT_MSG="Error: Source path does not exist."
                             echo -e "\033[0;31m[Tool Failed] Source not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Source and Destination must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Move denied.\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "move_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "delete_file" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

                    echo -e "\033[0;36m[Tool Request] Deleting: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -e "$FC_PATH" ]; then
                             # Prevent deleting the CWD itself
                            if [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)" ]; then
                                RESULT_MSG="Error: Cannot delete current working directory."
                                echo -e "\033[0;31m[Tool Failed] Deletion Blocked.\033[0m"
                            else
                                rm -rf "$FC_PATH" 2>&1
                                if [ $? -eq 0 ]; then
                                    RESULT_MSG="Success: Deleted $FC_PATH"
                                    echo -e "\033[0;32m[Tool Success] File deleted.\033[0m"
                                else
                                    RESULT_MSG="Error: Failed to delete file/directory."
                                    echo -e "\033[0;31m[Tool Failed] Delete failed.\033[0m"
                                fi
                            fi
                        else
                             RESULT_MSG="Error: Path does not exist."
                             echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Delete denied.\033[0m"
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    jq -n --arg name "delete_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "list_files" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')

                    echo -e "\033[0;36m[Tool Request] Listing: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD (Reuse existing logic)
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -e "$FC_PATH" ]; then
                            # Run ls -F (adds / to dirs, * to executables)
                            RESULT_MSG=$(ls -F "$FC_PATH" 2>&1)
                            echo -e "\033[0;32m[Tool Success] Directory listed.\033[0m"
                        else
                            RESULT_MSG="Error: Path does not exist."
                            echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] List denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "list_files" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "get_file_info" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

                    echo -e "\033[0;36m[Tool Request] Getting Info: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -e "$FC_PATH" ]; then
                            STATS=$(ls -ld "$FC_PATH")
                            if command -v file >/dev/null 2>&1; then
                                MIME=$(file -b --mime "$FC_PATH")
                                RESULT_MSG="Path: $FC_PATH\n$STATS\nType: $MIME"
                            else
                                RESULT_MSG="Path: $FC_PATH\n$STATS"
                            fi
                            echo -e "\033[0;32m[Tool Success] Info retrieved.\033[0m"
                        else
                            RESULT_MSG="Error: Path does not exist."
                            echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Info denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "get_file_info" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                
                elif [ "$F_NAME" == "read_file" ]; then
                    tool_read_file "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "read_image" ]; then
                    tool_read_image "$FC_DATA" "$RESP_PARTS_FILE"
                elif [ "$F_NAME" == "read_url" ]; then
                    # Extract Arguments
                    FC_URL=$(echo "$FC_DATA" | jq -r '.args.url')

                    echo -e "\033[0;36m[Tool Request] Reading URL: $FC_URL\033[0m"

                    # Use Python to fetch and strip HTML for cleaner context
                    RESULT_MSG=$(python3 -c "
import sys, urllib.request, re, ssl

url = sys.argv[1]
try:
    # Handle SSL context for some environments
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, context=ctx, timeout=10) as response:
        content = response.read().decode('utf-8', errors='ignore')
        
        # Simple heuristic: if it looks like HTML, strip tags
        if '<html' in content.lower() or '<body' in content.lower():
            # Remove scripts and styles
            content = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', content, flags=re.DOTALL | re.IGNORECASE)
            # Remove tags
            text = re.sub(r'<[^>]+>', '', content)
            # Collapse whitespace
            text = re.sub(r'\n\s*\n', '\n\n', text).strip()
            print(text)
        else:
            print(content)

except Exception as e:
    print(f'Error fetching URL: {e}')
" "$FC_URL")
                    
                    # Truncate if too long
                    LINE_COUNT=$(echo "$RESULT_MSG" | wc -l)
                    if [ "$LINE_COUNT" -gt 500 ]; then
                         RESULT_MSG="$(echo "$RESULT_MSG" | head -n 500)\n\n... (Content truncated at 500 lines) ..."
                    fi
                    
                    if [[ "$RESULT_MSG" == Error* ]]; then
                         echo -e "\033[0;31m[Tool Failed] URL fetch failed.\033[0m"
                    else
                         echo -e "\033[0;32m[Tool Success] URL read.\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "read_url" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "search_files" ]; then
                    # Extract Arguments
                    FC_QUERY=$(echo "$FC_DATA" | jq -r '.args.query')
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')

                    echo -e "\033[0;36m[Tool Request] Searching for \"$FC_QUERY\" in: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -e "$FC_PATH" ]; then
                            # Grep: recursive, line numbers, binary ignored
                            # Limit to first 50 lines to prevent token explosion
                            RESULT_MSG=$(grep -rnI "$FC_QUERY" "$FC_PATH" 2>/dev/null | head -n 50)
                            
                            if [ -z "$RESULT_MSG" ]; then
                                RESULT_MSG="No matches found."
                            elif [ $(echo "$RESULT_MSG" | wc -l) -eq 50 ]; then
                                RESULT_MSG="${RESULT_MSG}\n... (Matches truncated at 50 lines) ..."
                            fi
                            echo -e "\033[0;32m[Tool Success] Search complete.\033[0m"
                        else
                            RESULT_MSG="Error: Path does not exist."
                            echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Search denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "search_files" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                
                elif [ "$F_NAME" == "grep_definitions" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')
                    FC_QUERY=$(echo "$FC_DATA" | jq -r '.args.query // empty')

                    echo -e "\033[0;36m[Tool Request] Grep Definitions in: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -e "$FC_PATH" ]; then
                            # Regex to capture common definitions:
                            # class, def, function, func, interface, type, struct, enum
                            # We use grep -E for extended regex
                            # Ignores binary files (-I), recursive (-r), line numbers (-n)
                            # Exclude hidden files and standard ignore directories
                            
                            REGEX="^[[:space:]]*(class|def|function|func|interface|type|struct|enum|const)[[:space:]]+"
                            
                            CMD="grep -rnEI \"$REGEX\" \"$FC_PATH\""
                            
                            # Add standard excludes to prevent searching node_modules etc
                            CMD="$CMD --exclude-dir={.git,.idea,.vscode,__pycache__,node_modules,dist,build,coverage,vendor}"
                            
                            RESULT_MSG=$(eval "$CMD" 2>/dev/null)
                            
                            # If query provided, filter results
                            if [ -n "$FC_QUERY" ]; then
                                RESULT_MSG=$(echo "$RESULT_MSG" | grep -i "$FC_QUERY")
                            fi
                            
                            # Truncate
                            LINE_COUNT=$(echo "$RESULT_MSG" | wc -l)
                            if [ "$LINE_COUNT" -gt 100 ]; then
                                RESULT_MSG="$(echo "$RESULT_MSG" | head -n 100)\n... (Truncated at 100 matches) ..."
                            fi
                            
                            if [ -z "$RESULT_MSG" ]; then RESULT_MSG="No definitions found."; fi
                            
                            echo -e "\033[0;32m[Tool Success] Definitions found.\033[0m"
                        else
                            RESULT_MSG="Error: Path does not exist."
                            echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Grep denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "grep_definitions" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "find_file" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')
                    FC_PATTERN=$(echo "$FC_DATA" | jq -r '.args.name_pattern')
                    FC_TYPE=$(echo "$FC_DATA" | jq -r '.args.type // empty')

                    echo -e "\033[0;36m[Tool Request] Find: $FC_PATTERN in $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        # Build find command
                        # Exclude common ignore dirs
                        IGNORES="node_modules|.git|.idea|.vscode|__pycache__|output|dist|build|coverage|target|vendor|.DS_Store"
                        
                        CMD="find \"$FC_PATH\" -name \"$FC_PATTERN\""
                        
                        # Add type filter if specified
                        if [ "$FC_TYPE" == "f" ]; then CMD="$CMD -type f"; fi
                        if [ "$FC_TYPE" == "d" ]; then CMD="$CMD -type d"; fi
                        
                        # Exclude hidden files/dirs logic manually
                        CMD="$CMD -not -path '*/.*' -not -path '*node_modules*' -not -path '*output*' -not -path '*dist*' -not -path '*build*'"
                        
                        # Execute
                        RESULT_MSG=$(eval "$CMD" 2>/dev/null | head -n 50)
                        
                        if [ -z "$RESULT_MSG" ]; then
                            RESULT_MSG="No files found matching pattern: $FC_PATTERN"
                        elif [ $(echo "$RESULT_MSG" | wc -l) -eq 50 ]; then
                            RESULT_MSG="${RESULT_MSG}\n... (Matches truncated at 50 lines) ..."
                        fi
                        echo -e "\033[0;32m[Tool Success] Find complete.\033[0m"
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Find denied: $FC_PATH\033[0m"
                    fi
                    
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    jq -n --arg name "find_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "get_tree" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')
                    FC_DEPTH=$(echo "$FC_DATA" | jq -r '.args.max_depth // 2')

                    echo -e "\033[0;36m[Tool Request] Generating Tree: $FC_PATH (Depth: $FC_DEPTH)\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -d "$FC_PATH" ]; then
                            IGNORES="node_modules|.git|.idea|.vscode|__pycache__|output|dist|build|coverage|target|vendor|.DS_Store"
                            
                            if command -v tree >/dev/null 2>&1; then
                                RESULT_MSG=$(tree -a -L "$FC_DEPTH" -I "$IGNORES" "$FC_PATH")
                            else
                                # Fallback to find
                                RESULT_MSG=$(find "$FC_PATH" -maxdepth "$FC_DEPTH" -not -path '*/.*' -not -path "*node_modules*" -not -path "*output*" -not -path "*dist*" -not -path "*build*" | sort)
                            fi
                            echo -e "\033[0;32m[Tool Success] Tree generated.\033[0m"
                        else
                            RESULT_MSG="Error: Path is not a directory."
                            echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Tree denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "get_tree" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "get_git_diff" ]; then
                    FC_STAGED=$(echo "$FC_DATA" | jq -r '.args.staged // false')
                    echo -e "\033[0;36m[Tool Request] Git Diff (Staged: $FC_STAGED)\033[0m"

                    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                        [ "$FC_STAGED" == "true" ] && RESULT_MSG=$(git diff --cached 2>&1) || RESULT_MSG=$(git diff 2>&1)
                        [ -z "$RESULT_MSG" ] && RESULT_MSG="No changes found."
                        LINE_COUNT=$(echo "$RESULT_MSG" | wc -l)
                        [ "$LINE_COUNT" -gt 200 ] && RESULT_MSG="$(echo "$RESULT_MSG" | head -n 200)\n... (Truncated) ..."
                        echo -e "\033[0;32m[Tool Success] Git diff retrieved.\033[0m"
                    else
                        RESULT_MSG="Error: Not a git repo or git missing."
                        echo -e "\033[0;31m[Tool Failed] Git Error.\033[0m"
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn."
                    fi

                    jq -n --arg name "get_git_diff" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "read_git_commit" ]; then
                    FC_HASH=$(echo "$FC_DATA" | jq -r '.args.hash')
                    echo -e "\033[0;36m[Tool Request] Git Show: $FC_HASH\033[0m"

                    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                        RESULT_MSG=$(git show --stat --patch "$FC_HASH" 2>&1 | head -n 300)
                        
                        if [ -z "$RESULT_MSG" ]; then
                             RESULT_MSG="Error: Commit not found."
                        elif [ $(echo "$RESULT_MSG" | wc -l) -eq 300 ]; then
                            RESULT_MSG="${RESULT_MSG}\n... (Output truncated at 300 lines) ..."
                        fi
                        echo -e "\033[0;32m[Tool Success] Commit details retrieved.\033[0m"
                    else
                        RESULT_MSG="Error: Not a git repo or git missing."
                        echo -e "\033[0;31m[Tool Failed] Git Error.\033[0m"
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn."
                    fi

                    jq -n --arg name "read_git_commit" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "get_git_log" ]; then
                    FC_LIMIT=$(echo "$FC_DATA" | jq -r '.args.limit // 10')
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath // empty')
                    
                    if [ -n "$FC_PATH" ]; then
                        echo -e "\033[0;36m[Tool Request] Git Log (Limit: $FC_LIMIT, File: $FC_PATH)\033[0m"
                    else
                        echo -e "\033[0;36m[Tool Request] Git Log (Limit: $FC_LIMIT)\033[0m"
                    fi

                    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                        # Build command with optional file path
                        CMD="git log --oneline -n \"$FC_LIMIT\""
                        if [ -n "$FC_PATH" ]; then
                            CMD="$CMD -- \"$FC_PATH\""
                        fi
                        
                        RESULT_MSG=$(eval "$CMD" 2>&1)
                        if [ -z "$RESULT_MSG" ]; then RESULT_MSG="No commits found."; fi
                        echo -e "\033[0;32m[Tool Success] Git log retrieved.\033[0m"
                    else
                        RESULT_MSG="Error: Not a git repo or git missing."
                        echo -e "\033[0;31m[Tool Failed] Git Error.\033[0m"
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn."
                    fi

                    jq -n --arg name "get_git_log" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "get_git_status" ]; then
                    echo -e "\033[0;36m[Tool Request] Git Status\033[0m"

                    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                        RESULT_MSG=$(git status --short --branch 2>&1)
                        echo -e "\033[0;32m[Tool Success] Git status retrieved.\033[0m"
                    else
                        RESULT_MSG="Error: Not a git repo or git missing."
                        echo -e "\033[0;31m[Tool Failed] Git Error.\033[0m"
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn."
                    fi

                    jq -n --arg name "get_git_status" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                    
                elif [ "$F_NAME" == "get_git_blame" ]; then
                    tool_get_git_blame "$FC_DATA" "$RESP_PARTS_FILE"

                elif [ "$F_NAME" == "execute_command" ]; then
                    # Extract Arguments
                    FC_CMD=$(echo "$FC_DATA" | jq -r '.args.command')

                    echo -e "\033[0;36m[Tool Request] Execute Command: $FC_CMD\033[0m"

                    # Safety: Ask for confirmation
                    CONFIRM="n"
                    if [ -t 0 ]; then
                        # Interactive mode: Ask user
                        # We use /dev/tty to ensure we read from keyboard even if stdin was piped initially
                        read -p "⚠️  Execute this command? (y/N) " -n 1 -r CONFIRM < /dev/tty
                        echo "" 
                    else
                        echo "Non-interactive mode: Auto-denying command execution."
                    fi

                    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                        # Execute and capture stdout + stderr
                        CMD_OUTPUT=$(eval "$FC_CMD" 2>&1)
                        EXIT_CODE=$?
                        
                        # Truncate if too long (100 lines)
                        LINE_COUNT=$(echo "$CMD_OUTPUT" | wc -l)
                        if [ "$LINE_COUNT" -gt 100 ]; then
                            CMD_OUTPUT="$(echo "$CMD_OUTPUT" | head -n 100)\n... (Output truncated at 100 lines) ..."
                        fi

                        if [ $EXIT_CODE -eq 0 ]; then
                            RESULT_MSG="Exit Code: 0\nOutput:\n$CMD_OUTPUT"
                            echo -e "\033[0;32m[Tool Success] Command executed.\033[0m"
                        else
                            RESULT_MSG="Exit Code: $EXIT_CODE\nError/Output:\n$CMD_OUTPUT"
                            echo -e "\033[0;31m[Tool Failed] Command returned non-zero exit code.\033[0m"
                        fi
                    else
                        RESULT_MSG="User denied execution of command: $FC_CMD"
                        echo -e "\033[0;33m[Tool Skipped] Execution denied.\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "execute_command" --rawfile content <(printf "%s" "$RESULT_MSG") \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                fi
            fi
        done

        # 3. Construct Full Tool Response
        TOOL_RESPONSE=$(jq -n --arg role "$FUNC_ROLE" --slurpfile parts "$RESP_PARTS_FILE" '{ role: $role, parts: $parts[0] }')
        rm "$RESP_PARTS_FILE"
        
        # 4. Update History with Tool Result
        update_history "$TOOL_RESPONSE"

        # Loop continues to send this result back to the model...
        continue

    else
        # --- Handle Text Response (Final Answer) ---
        FINAL_TEXT_RESPONSE="$RESPONSE_JSON"
        update_history "$CANDIDATE"
        break
    fi
done

END_TIME=$(date +%s.%N)
DURATION=$(awk -v start="$START_TIME" -v end="$END_TIME" 'BEGIN { print end - start }')

# 6. Render Output
# Use the final JSON response for Recap and Stats
# Note: Recap reads from the *file* history, but we want to render the last message.
RECAP_OUT=$(mktemp)
if [ -z "$RECAP_OUT" ]; then
    RECAP_OUT="${TMPDIR:-/tmp}/tellme_recap_${RANDOM}.txt"
fi

"$BASE_DIR/recap.sh" -l > "$RECAP_OUT"
LINE_COUNT=$(wc -l < "$RECAP_OUT")

if [ "$LINE_COUNT" -gt 20 ]; then
    head -n 10 "$RECAP_OUT"
    echo -e "\n\033[1;30m... (Content Snipped) ...\033[0m\n"
    tail -n 5 "$RECAP_OUT"
else
    cat "$RECAP_OUT"
fi
rm -f "$RECAP_OUT"

# 7. Grounding Detection
SEARCH_COUNT=$(echo "$FINAL_TEXT_RESPONSE" | jq -r '(.candidates[0].groundingMetadata.webSearchQueries // []) | length')
if [ "$SEARCH_COUNT" -gt 0 ]; then
    echo -e "\033[0;33m[Grounding] Performed $SEARCH_COUNT Google Search(es):\033[0m"
    echo "$FINAL_TEXT_RESPONSE" | jq -r '.candidates[0].groundingMetadata.webSearchQueries[]' | while read -r query; do
            echo -e "  \033[0;33m> \"$query\"\033[0m"
    done
fi

printf "\033[0;35m[Response Time] %.2f seconds\033[0m\n" "$DURATION"

# 8. Stats & Metrics
read -r HIT PROMPT_TOTAL COMPLETION TOTAL <<< $(echo "$FINAL_TEXT_RESPONSE" | jq -r '
  .usageMetadata | 
  (.cachedContentTokenCount // 0), 
  (.promptTokenCount // 0), 
  (.candidatesTokenCount // .completionTokenCount // 0), 
  (.totalTokenCount // 0)
' | xargs)

MISS=$(( PROMPT_TOTAL - HIT ))
NEWTOKEN=$(( MISS + COMPLETION ))

if [ "$TOTAL" -gt 0 ]; then PERCENT=$(( ($NEWTOKEN * 100) / $TOTAL )); else PERCENT=0; fi

LOG_FILE="${file}.log"
STATS_MSG=$(printf "[%s] H: %d M: %d C: %d T: %d N: %d(%d%%) S: %d [%.2fs]" \
  "$(date +%H:%M:%S)" "$HIT" "$MISS" "$COMPLETION" "$TOTAL" "$NEWTOKEN" "$PERCENT" "$SEARCH_COUNT" "$DURATION")
echo "$STATS_MSG" >> "$LOG_FILE"

if [ -f "$LOG_FILE" ]; then
    echo -e "\033[0;36m--- Usage History ---\033[0m"
    tail -n 3 "$LOG_FILE"
    echo ""
    awk '{ gsub(/\./, ""); h+=$3; m+=$5; c+=$7; t+=$9; s+=$13 } END { printf "\033[0;34m[Session Total]\033[0m Hit: %d | Miss: %d | Comp: %d | \033[1mTotal: %d\033[0m | Search: %d\n", h, m, c, t, s }' "$LOG_FILE"
fi

# Backup History
if [ -f "${file}" ]; then
    TIMESTAMP=$(date -u "+%y%m%d-%H")$(printf "%02d" $(( (10#$(date -u "+%M") / 10) * 10 )) )
    cp "$file" "${file%.*}-${TIMESTAMP}-trace.${file##*.}"
fi