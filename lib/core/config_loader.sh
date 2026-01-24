#!/bin/bash
# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT

# config_loader.sh: Handles configuration discovery and parsing.

load_config() {
    local config_arg="$1"
    local base_dir="$2"
    local config_file=""

    # 1. Discovery Logic
    if [ -n "$config_arg" ] && [ -f "$config_arg" ]; then
        config_file="$config_arg"
    elif [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        config_file="$CONFIG_FILE"
    elif [ -f "config.yaml" ]; then
        config_file="config.yaml"
    elif ls "$base_dir/output/last-assist-"*".config.yaml" 1> /dev/null 2>&1; then
        config_file="$(ls -t "$base_dir/output/last-assist-"*".config.yaml" | head -n 1)"
    fi

    if [ -z "$config_file" ]; then
        echo "Error: Configuration file not found." >&2
        return 1
    fi

    # 2. Parsing Logic (Safe YAML Parser via Python3)
    local parser_script
    parser_script=$(cat <<'EOF'
import sys, shlex
try:
    with open(sys.argv[1], 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or ':' not in line:
                continue
            k, v = line.split(':', 1)
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            if k.isidentifier():
                print(f'{k}={shlex.quote(v)}')
except Exception as e:
    print(f'echo "Error parsing config: {e}" >&2; exit 1')
EOF
    )

    eval "$(python3 -c "$parser_script" "$config_file")"
    
    # Export the file path for history management
    CONFIG_FILE="$config_file"
    export CONFIG_FILE
}

