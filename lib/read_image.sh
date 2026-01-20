tool_read_image() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    
    # Extract Arguments
    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

    echo -e "\033[0;36m[Tool Request] Reading Image: $FC_PATH\033[0m"

    local RESULT_MSG=""
    local IS_SAFE=false
    local REL_CHECK=""

    # Security Check: Ensure path is within CWD
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
            if ! command -v file >/dev/null 2>&1 || ! command -v base64 >/dev/null 2>&1; then
                RESULT_MSG="Error: Missing 'file' or 'base64' command."
                echo -e "\033[0;31m[Tool Failed] Missing dependencies.\033[0m"
            else
                local MIME_TYPE=$(file -b --mime-type "$FC_PATH")
                if [[ "$MIME_TYPE" == image/* ]]; then
                    # Write base64 data to a temp file to avoid ARG_MAX limits with large strings
                    base64 < "$FC_PATH" | tr -d '\n' > "${RESP_PARTS_FILE}.b64"
                    
                    RESULT_MSG="Image loaded successfully into context."
                    echo -e "\033[0;32m[Tool Success] Image read ($MIME_TYPE).\033[0m"
                    
                    # Create inlineData part using --rawfile to safely handle large data
                    jq -n --arg mime "$MIME_TYPE" --rawfile data "${RESP_PARTS_FILE}.b64" \
                        '{inlineData: {mimeType: $mime, data: $data}}' > "${RESP_PARTS_FILE}.img"
                        
                    rm "${RESP_PARTS_FILE}.b64"

                    # Append inlineData part to parts file
                    jq --slurpfile new "${RESP_PARTS_FILE}.img" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.img"
                else
                    RESULT_MSG="Error: File is not a recognized image type ($MIME_TYPE)."
                    echo -e "\033[0;31m[Tool Failed] Not an image.\033[0m"
                fi
            fi
        else
            RESULT_MSG="Error: File not found."
            echo -e "\033[0;31m[Tool Failed] File not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation. Path must be within current working directory."
        echo -e "\033[0;31m[Tool Security Block] Read denied: $FC_PATH\033[0m"
    fi

    # Inject Warning if approaching Max Turns
    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        local WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi

    # Construct Function Response Part
    jq -n --arg name "read_image" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    
    # Append to Array
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}