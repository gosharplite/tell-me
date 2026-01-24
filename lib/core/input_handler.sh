#!/bin/bash
# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT

# input_handler.sh: Processes user input from CLI or STDIN.

process_user_input() {
    local prompt_text="$1"
    local config_file="$2"
    local stdin_data=""

    # 1. Capture STDIN if present
    if [ ! -t 0 ]; then stdin_data="$(cat)"; fi

    local msg_text=""
    if [ -n "$stdin_data" ]; then
        msg_text="${prompt_text}\n\n${stdin_data}"
    elif [ -n "$prompt_text" ]; then
        msg_text="$prompt_text"
    else
        echo "Error: No input provided. Usage: a \"Your message\"" >&2
        return 1
    fi

    # 2. Format as JSON for history
    printf "%s" "$msg_text" | jq -Rs '{role: "user", parts: [{text: .}]}'
}

