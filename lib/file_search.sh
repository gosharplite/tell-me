tool_list_files() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')
    echo -e "\033[0;36m[Tool Request] Listing: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG

    if [ "$IS_SAFE" == "true" ]; then
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

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "list_files" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_get_file_info() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
    echo -e "\033[0;36m[Tool Request] Getting Info: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG

    if [ "$IS_SAFE" == "true" ]; then
        if [ -e "$FC_PATH" ]; then
            local STATS=$(ls -ld "$FC_PATH")
            if command -v file >/dev/null 2>&1; then
                local MIME=$(file -b --mime "$FC_PATH")
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

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "get_file_info" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_search_files() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_QUERY=$(echo "$FC_DATA" | jq -r '.args.query')
    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')

    echo -e "\033[0;36m[Tool Request] Searching for \"$FC_QUERY\" in: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG

    if [ "$IS_SAFE" == "true" ]; then
        if [ -e "$FC_PATH" ]; then
            # Grep: recursive, line numbers, binary ignored
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

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "search_files" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_grep_definitions() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')
    local FC_QUERY=$(echo "$FC_DATA" | jq -r '.args.query // empty')

    echo -e "\033[0;36m[Tool Request] Grep Definitions in: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG

    if [ "$IS_SAFE" == "true" ]; then
        if [ -e "$FC_PATH" ]; then
            local REGEX="^[[:space:]]*(class|def|function|func|interface|type|struct|enum|const)[[:space:]]+"
            local CMD="grep -rnEI \"$REGEX\" \"$FC_PATH\""
            CMD="$CMD --exclude-dir={.git,.idea,.vscode,__pycache__,node_modules,dist,build,coverage,vendor}"
            
            RESULT_MSG=$(eval "$CMD" 2>/dev/null)
            
            if [ -n "$FC_QUERY" ]; then
                RESULT_MSG=$(echo "$RESULT_MSG" | grep -i "$FC_QUERY")
            fi
            
            local LINE_COUNT=$(echo "$RESULT_MSG" | wc -l)
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

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "grep_definitions" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_find_file() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')
    local FC_PATTERN=$(echo "$FC_DATA" | jq -r '.args.name_pattern')
    local FC_TYPE=$(echo "$FC_DATA" | jq -r '.args.type // empty')

    echo -e "\033[0;36m[Tool Request] Find: $FC_PATTERN in $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG

    if [ "$IS_SAFE" == "true" ]; then
        local IGNORES="node_modules|.git|.idea|.vscode|__pycache__|output|dist|build|coverage|target|vendor|.DS_Store"
        local CMD="find \"$FC_PATH\" -name \"$FC_PATTERN\""
        
        if [ "$FC_TYPE" == "f" ]; then CMD="$CMD -type f"; fi
        if [ "$FC_TYPE" == "d" ]; then CMD="$CMD -type d"; fi
        
        CMD="$CMD -not -path '*/.*' -not -path '*node_modules*' -not -path '*output*' -not -path '*dist*' -not -path '*build*'"
        
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
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "find_file" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_get_tree() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')
    local FC_DEPTH=$(echo "$FC_DATA" | jq -r '.args.max_depth // 2')

    echo -e "\033[0;36m[Tool Request] Generating Tree: $FC_PATH (Depth: $FC_DEPTH)\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG

    if [ "$IS_SAFE" == "true" ]; then
        if [ -d "$FC_PATH" ]; then
            local IGNORES="node_modules|.git|.idea|.vscode|__pycache__|output|dist|build|coverage|target|vendor|.DS_Store"
            
            if command -v tree >/dev/null 2>&1; then
                RESULT_MSG=$(tree -a -L "$FC_DEPTH" -I "$IGNORES" "$FC_PATH")
            else
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

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "get_tree" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}