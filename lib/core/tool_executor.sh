#!/bin/bash
# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT

# tool_executor.sh: Handles the detection and execution of function calls from the model.

execute_tools() {
    local candidate="$1"
    local resp_parts_file="$2"
    
    local total_parts
    total_parts=$(echo "$candidate" | jq '.parts | length')
    local fc_count
    fc_count=$(echo "$candidate" | jq '[.parts[] | has("functionCall")] | map(select(. == true)) | length')
    
    local current_fc=0
    for (( i=0; i<total_parts; i++ )); do
        local fc_data
        fc_data=$(echo "$candidate" | jq -c ".parts[$i].functionCall // empty")
        if [ -n "$fc_data" ]; then
            current_fc=$((current_fc + 1))
            log_tool_call "$fc_data" "[Tool Request ($current_fc/$fc_count)]"
            
            local f_name
            f_name=$(echo "$fc_data" | jq -r '.name')
            local cmd_name="tool_$f_name"
            
            if declare -f "$cmd_name" > /dev/null; then
                "$cmd_name" "$fc_data" "$resp_parts_file"
            else
                echo -e "\033[0;31m[System Error] Tool $cmd_name not found.\033[0m" >&2
                # Return error to the model
                jq -n --arg name "$f_name" \
                    '{functionResponse: {name: $name, response: {result: "Error: Tool not found"}}}' \
                    > "${resp_parts_file}.err"
                
                jq --slurpfile new "${resp_parts_file}.err" '. + $new' "$resp_parts_file" > "${resp_parts_file}.tmp" \
                    && mv "${resp_parts_file}.tmp" "$resp_parts_file"
                rm "${resp_parts_file}.err"
            fi
        fi
    done
}

