# Copyright (c) 2026  <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Prunes history file if the last recorded token count exceeds a threshold.
# Usage: prune_history_if_needed <history_file> <limit>
prune_history_if_needed() {
    local hist_file="$1"
    local limit="$2"
    local log_file="${hist_file}.log"

    if [[ ! -f "$log_file" || ! -f "$hist_file" ]]; then
        return
    fi

    # 1. Get the total token count from the last line of the log
    # Format: ... T: 46102 ...
    local last_total=$(tail -n 1 "$log_file" | awk '{for(i=1;i<=NF;i++) if($i=="T:") print $(i+1)}' | sed 's/\.//g')

    if [[ -z "$last_total" ]]; then return; fi

    # --- ADVANCE WARNING ---
    # If we are at 85% of the limit, warn the model in its system context (via a hidden user message)
    if [[ "$last_total" -gt $(( (limit * 85) / 100 )) && "$last_total" -le "$limit" ]]; then
        # Check if we already warned it recently to avoid spam
        if ! jq -e '.messages[-1].parts[0].text | contains("Context is reaching the limit")' "$hist_file" >/dev/null 2>&1; then
             local warn_msg=$(jq -n --arg T "$last_total" '{role: "user", parts: [{text: "[SYSTEM NOTICE] Context is reaching the limit (\($T) tokens). Please ensure the scratchpad and tasks are up to date before history is pruned."}]}')
             update_history_file "$warn_msg" "$hist_file"
             echo -e "\033[0;33m[System] Sent advance warning to AI (Context at 85% capacity).\033[0m"
        fi
        return
    fi

    if [[ "$last_total" -le "$limit" ]]; then
        return
    fi

    # --- PRUNING LOGIC ---
    local total_messages=$(jq '.messages | length' "$hist_file")
    local target_prune=$(( total_messages / 5 ))
    if [ "$target_prune" -lt 10 ]; then target_prune=10; fi

    # Find the first 'user' message AFTER the target_prune index to ensure we cut at a boundary.
    local safe_index=$(jq -r "[(.messages | to_entries[] | select(.key >= $target_prune and .value.role == \"user\"))] | .[0].key" "$hist_file")

    # If no user message found ahead, fallback to the target
    if [[ "$safe_index" == "null" || -z "$safe_index" ]]; then
        safe_index=$target_prune
    fi

    echo -e "\033[0;33m[System] History exceeds $limit tokens ($last_total). Pruning $safe_index messages at conversation boundary...\033[0m"

    # 3. Truncate and Inject "Memory Loss" Notice
    local notice="[SYSTEM NOTICE] Older conversation history has been pruned to save space. I may have forgotten early details. Please refer to the scratchpad and tasks for long-term project state."
    
    jq --argjson idx "$safe_index" --arg notice "$notice" '
        .messages |= .[$idx:] |
        .messages = [{role: "user", parts: [{text: $notice}]}] + .messages
    ' "$hist_file" > "${hist_file}.tmp" && mv "${hist_file}.tmp" "$hist_file"

    local new_count=$(jq '.messages | length' "$hist_file")
    echo -e "\033[0;32m[System] Pruning complete. Context reset with memory notice.\033[0m"
}

