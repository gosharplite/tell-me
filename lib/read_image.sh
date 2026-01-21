tool_read_image() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"
    
    # Extract Arguments
    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Reading Image: $FC_PATH\033[0m"

    local RESULT_MSG=""
    local IS_SAFE=false
    local REL_CHECK=""
    local DUR=""

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
                DUR=$(get_log_duration)
                echo -e "${DUR} \033[0;31m[Tool Failed] Missing dependencies.\033[0m"
            else
                local MIME_TYPE=$(file --mime-type -b "$FC_PATH")
                # Validate MIME type (must be image)
                if [[ "$MIME_TYPE" == image/* ]]; then
                    # Stream base64 to a temp file to avoid "Argument list too long"
                    base64 < "$FC_PATH" | tr -d '\n' > "${RESP_PARTS_FILE}.b64"
                    
                    RESULT_MSG="Image read successfully. MIME: $MIME_TYPE. Size: $(du -h "$FC_PATH" | cut -f1)."
                    
                    # Inject Inline Data Part using --rawfile
                    jq -n --arg mime "$MIME_TYPE" --rawfile data "${RESP_PARTS_FILE}.b64" \
                        '{inlineData: {mimeType: $mime, data: $data}}' > "${RESP_PARTS_FILE}.blob"
                    rm "${RESP_PARTS_FILE}.b64"
                    
                    jq --slurpfile new "${RESP_PARTS_FILE}.blob" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.blob"

                    DUR=$(get_log_duration)
                    echo -e "${DUR} \033[0;32m[Tool Success] Image processed.\033[0m"
                else
                    RESULT_MSG="Error: File is not a supported image. MIME: $MIME_TYPE"
                    DUR=$(get_log_duration)
                    echo -e "${DUR} \033[0;31m[Tool Failed] Invalid MIME type.\033[0m"
                fi
            fi
        else
            RESULT_MSG="Error: File not found."
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] File not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation. Path must be within current working directory."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Read denied: $FC_PATH\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "read_image" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
