#!/bin/bash
# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT

# metrics.sh: Handles token usage logging and session statistics.

log_usage() {
    local resp="$1"
    local dur="$2"
    local search_cnt="$3"
    local log_file="$4"

    # Extract metrics using jq
    read -r hit prompt_total completion total thinking_tokens <<< $(echo "$resp" | jq -r '
      .usageMetadata | 
      (.cachedContentTokenCount // 0), 
      (.promptTokenCount // 0), 
      (.candidatesTokenCount // .completionTokenCount // 0), 
      (.totalTokenCount // 0),
      (.candidatesTokenCountDetails.thinkingTokenCount // .thoughtsTokenCount // 0)
    ' | xargs)

    local miss=$(( prompt_total - hit ))
    local newtoken=$(( miss + completion + thinking_tokens ))
    local percent=0
    if [ "$total" -gt 0 ]; then percent=$(( (newtoken * 100) / total )); fi

    local stats_msg
    stats_msg=$(printf "[%s] H: %d M: %d C: %d T: %d N: %d(%d%%) S: %d Th: %d [%.2fs]" \
      "$(date +%H:%M:%S)" "$hit" "$miss" "$completion" "$total" "$newtoken" "$percent" "$search_cnt" "$thinking_tokens" "$dur")

    echo "$stats_msg" >> "$log_file"
    echo -e "\033[0;90m$stats_msg\033[0m"
}

display_session_totals() {
    local log_file="$1"
    if [ -f "$log_file" ]; then
        echo -e "\n\033[0;36m--- Usage History ---\033[0m"
        tail -n 3 "$log_file"
        echo ""
        awk '{ gsub(/\./, ""); h+=$3; m+=$5; c+=$7; t+=$9; s+=$13 } END { printf "\033[0;34m[Session Total]\033[0m Hit: %d | Miss: %d | Comp: %d | \033[1mTotal: %d\033[0m | Search: %d\n", h, m, c, t, s }' "$log_file"
    fi
}

