#!/bin/bash
# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT

# session_manager.sh: Handles session initialization and model configuration mapping.

setup_session() {
    local config_file="$1"
    local base_dir="$2"
    
    local session_id
    session_id=$(basename "$config_file" .config.yaml)
    local output_dir="$base_dir/output"
    mkdir -p "$output_dir"

    local history_file="$output_dir/$session_id.json"
    if [ ! -f "$history_file" ]; then
        echo '{"messages": []}' > "$history_file"
    fi

    # Backup for safety if limits are defined
    if [ -n "$MAX_HISTORY_TOKENS" ]; then
        backup_file "$history_file"
    fi
    
    # Return the history file path
    echo "$history_file"
}

get_thinking_config() {
    local budget="${1:-4000}"
    local level="HIGH"
    
    if [ "$budget" -lt 2000 ]; then 
        level="MINIMAL"
    elif [ "$budget" -lt 4001 ]; then 
        level="LOW"
    elif [ "$budget" -lt 8001 ]; then 
        level="MEDIUM"
    fi
    
    # Return values as space-separated string: "LEVEL BUDGET"
    echo "$level $budget"
}

