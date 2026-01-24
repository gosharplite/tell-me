#!/bin/bash
# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT

# ui_utils.sh: UI and logging helpers for the assistant.

log_tool_call() {
    local fc_json="$1"
    local turn_info="$2"
    local f_name
    f_name=$(echo "$fc_json" | jq -r '.name')
    local f_args
    f_args=$(echo "$fc_json" | jq -c '.args')
    local ts
    ts=$(get_log_timestamp)
    
    local msg=""
    case "$f_name" in
        "update_file"|"replace_text"|"insert_text"|"append_file"|"delete_file"|"rollback_file"|"move_file"|"apply_patch")
            local target
            target=$(echo "$f_args" | jq -r '.filepath // .source_path // empty')
            msg="Updating ${target:-file} ($f_name)" ;;
        "read_file"|"get_file_skeleton"|"get_file_info")
            local target
            target=$(echo "$f_args" | jq -r '.filepath')
            msg="Reading $target ($f_name)" ;;
        "manage_scratchpad"|"manage_tasks")
            local action
            action=$(echo "$f_args" | jq -r '.action')
            msg="Updating session state ($f_name: $action)" ;;
        *)
            msg="Calling $f_name" ;;
    esac
    echo -e "${ts} ${turn_info} \033[0;32m${msg}\033[0m"
}

