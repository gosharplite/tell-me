#!/bin/bash
# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT

# payload_manager.sh: Handles construction of API payloads and safety checks.

build_payload() {
    local history_file="$1"
    local tools_json="$2"
    local person="$3"
    local model="$4"
    local thinking_level="$5"
    local budget_val="$6"

    jq -c -n \
      --arg person "$person" \
      --argjson tools "$tools_json" \
      --arg model "$model" \
      --arg level "$thinking_level" \
      --arg budget "$budget_val" \
      --slurpfile history "$history_file" \
      '{
        contents: ([$history[0].messages[]? | select(.parts and (.parts | length > 0))]),
        tools: $tools,
        generationConfig: ({
            temperature: 1.0
        } + (if ($model | startswith("gemini-3")) then {
            thinkingConfig: { thinkingLevel: $level, includeThoughts: true }
        } elif ($model | startswith("gemini-2.0-flash-thinking")) then {
            thinkingConfig: { includeThinkingProcess: true, thinkingBudgetTokens: ($budget | tonumber? // 4000) }
        } else {} end)),
        safetySettings: [
          { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" }
        ]
      } + 
      (if $person != "" then { systemInstruction: { role: "system", parts: [{text: $person}] } } else {} end)'
}

estimate_and_check_payload() {
    local payload_file="$1"
    local history_file="$2"
    local max_tokens="$3"

    local est_tokens
    est_tokens=$(python3 -c "import os; print(int(os.path.getsize('$payload_file') / 3.5))")
    
    if [ "$est_tokens" -gt "$max_tokens" ]; then
        echo -e "\033[0;31m[Safety Error] Payload estimate ($est_tokens tokens) exceeds limit ($max_tokens)!\033[0m" >&2
        echo -e "\033[0;33m[System] Rolling back history to last known good state...\033[0m" >&2
        restore_backup "$history_file"
        echo -e "\033[0;33m[System] History restored. You may need to refine your query or reduce the output size.\033[0m" >&2
        return 1
    fi
    
    backup_file "$history_file"
    echo "$est_tokens"
}

