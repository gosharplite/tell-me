#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Resolve Script Directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check Dependencies
for cmd in jq curl gcloud awk; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is missing." >&2
        exit 1
    fi
done

# Helper function to append messages to history safely
update_history() {
  local json_content="$1"
  local item_file=$(mktemp)
  printf "%s" "$json_content" > "$item_file"
  
  if [ -s "$file" ] && jq empty "$file" > /dev/null 2>&1; then
    if ! jq --slurpfile item "$item_file" '.messages += $item' "$file" > "${file}.tmp"; then
        echo "Error: Failed to process history file." >&2
        rm "$item_file"
        exit 1
    fi
    mv "${file}.tmp" "$file"
  else
    jq -n --slurpfile item "$item_file" '{messages: $item}' > "$file"
  fi
  rm "$item_file"
}

# 1. Update Conversation History
PROMPT_TEXT="$1"
STDIN_DATA=""

if [ ! -t 0 ]; then
    STDIN_DATA="$(cat)"
fi

if [ -n "$STDIN_DATA" ]; then
    MSG_TEXT="${PROMPT_TEXT}\n\n${STDIN_DATA}"
elif [ -n "$PROMPT_TEXT" ]; then
    MSG_TEXT="$PROMPT_TEXT"
else
    MSG_TEXT="$DATA"
    echo "Usage: a \"Your message\" or pipe content via stdin" >&2
    exit 1
fi

USER_MSG=$(printf "%s" "$MSG_TEXT" | jq -Rs '{role: "user", parts: [{text: .}]}')
update_history "$USER_MSG"

# 2. Configure Tools & Auth based on Platform
TOOLS_JSON='[{ "googleSearch": {} }]'

if [[ "$AIURL" == *"aiplatform.googleapis.com"* ]]; then
    TARGET_SCOPE="https://www.googleapis.com/auth/cloud-platform"
    CACHE_SUFFIX="vertex"
else
    TARGET_SCOPE="https://www.googleapis.com/auth/generative-language"
    CACHE_SUFFIX="studio"
fi

# 3. Build API Payload
APIDATA=$(jq -n \
  --arg person "$PERSON" \
  --argjson tools "$TOOLS_JSON" \
  --slurpfile history "$file" \
  '{
    contents: $history[0].messages,
    tools: $tools,
    generationConfig: { 
      temperature: 1.0,
      thinkingConfig: { thinkingLevel: "HIGH" }
    },
    safetySettings: [
      { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" }
    ]
  } + 
  (if $person != "" then {
     systemInstruction: {
       role: "system", 
       parts: [{text: $person}]
     }
   } else {} end)'
)

# 4. Authentication (Token Caching)
TOKEN_CACHE="${TMPDIR:-/tmp}/gemini_token_${CACHE_SUFFIX}.txt"

get_file_mtime() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f %m "$1"
    else
        stat -c %Y "$1"
    fi
}

if [ -f "$TOKEN_CACHE" ]; then
    NOW=$(date +%s)
    LAST_MOD=$(get_file_mtime "$TOKEN_CACHE")
    DIFF=$((NOW - LAST_MOD))
    
    if [ $DIFF -lt 3300 ]; then
        TOKEN=$(cat "$TOKEN_CACHE")
    fi
fi

if [ -z "$TOKEN" ]; then
    if [ -n "$KEY_FILE" ] && [ -f "$KEY_FILE" ]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$KEY_FILE"
        TOKEN=$(gcloud auth application-default print-access-token --scopes="${TARGET_SCOPE}")
    else
        AUTH_ARGS=("--scopes=${TARGET_SCOPE}")
        TOKEN=$(gcloud auth print-access-token "${AUTH_ARGS[@]}")
    fi
    echo "$TOKEN" > "$TOKEN_CACHE"
fi

# 5. Call AI API
PAYLOAD_FILE=$(mktemp) || { echo "Failed to create temporary file." >&2; exit 1; }
trap 'rm -f "$PAYLOAD_FILE"' EXIT
echo "$APIDATA" > "$PAYLOAD_FILE"

START_TIME=$(date +%s.%N)

TEXT=$(curl -s "${AIURL}/${AIMODEL}:generateContent" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d @"$PAYLOAD_FILE")

END_TIME=$(date +%s.%N)
CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ]; then
    echo -e "\033[31mNetwork Error: Curl failed with exit code $CURL_EXIT\033[0m"
    exit 1
fi

if ! echo "$TEXT" | jq empty > /dev/null 2>&1; then
    echo -e "\033[31mAPI Error: Invalid JSON response received.\033[0m"
    echo "Raw Output: $TEXT"
    exit 1
fi

if echo "$TEXT" | jq -e '.error' > /dev/null 2>&1; then
    ERROR_MSG=$(echo "$TEXT" | jq -r '.error.message // "Unknown API Error"')
    ERROR_CODE=$(echo "$TEXT" | jq -r '.error.code // "N/A"')
    echo -e "\033[31mAPI Error ($ERROR_CODE): $ERROR_MSG\033[0m"
    exit 1
fi

# 6. Process AI Response
REPLY=$(echo "$TEXT" | jq -c '.candidates[0].content')

if [ "$REPLY" == "null" ]; then
    echo -e "\033[31mError: No content generated. (Check safety settings or input)\033[0m"
    exit 1
fi

update_history "$REPLY"

# --- Split output logic ---
RECAP_OUT=$(mktemp)
"$BASE_DIR/recap.sh" -l > "$RECAP_OUT"
LINE_COUNT=$(wc -l < "$RECAP_OUT")

if [ "$LINE_COUNT" -gt 20 ]; then
    head -n 10 "$RECAP_OUT"
    echo -e "\n\033[1;30m... (Content Snipped) ...\033[0m\n"
    tail -n 5 "$RECAP_OUT"
else
    cat "$RECAP_OUT"
fi
rm "$RECAP_OUT"
# --------------------------

# 7. Grounding Detection
HAS_GROUNDING=$(echo "$TEXT" | jq -r 'if .candidates[0].groundingMetadata then "yes" else "no" end')
SEARCH_COUNT=$(echo "$TEXT" | jq -r '(.candidates[0].groundingMetadata.webSearchQueries // []) | length')

if [ "$HAS_GROUNDING" == "yes" ]; then
    if [ "$SEARCH_COUNT" -gt 0 ]; then
        echo -e "\033[0;33m[Grounding] Performed $SEARCH_COUNT Google Search(es)\033[0m"
    else
        # Metadata exists but query list is empty (common in Vertex)
        SEARCH_COUNT=1
        echo -e "\033[0;33m[Grounding] Data Retrieved (Queries hidden)\033[0m"
    fi
fi

DURATION=$(awk -v start="$START_TIME" -v end="$END_TIME" 'BEGIN { print end - start }')
printf "\033[0;35m[Response Time] %.2f seconds\033[0m\n" "$DURATION"

# 8. Stats & Metrics
read -r HIT PROMPT_TOTAL COMPLETION TOTAL <<< $(echo "$TEXT" | jq -r '
  .usageMetadata | 
  (.cachedContentTokenCount // 0), 
  (.promptTokenCount // 0), 
  (.candidatesTokenCount // .completionTokenCount // 0), 
  (.totalTokenCount // 0)
' | xargs)

MISS=$(( PROMPT_TOTAL - HIT ))
NEWTOKEN=$(( MISS + COMPLETION ))

if [ "$TOTAL" -gt 0 ]; then
    PERCENT=$(( ($NEWTOKEN * 100) / $TOTAL ))
else
    PERCENT=0
fi

LOG_FILE="${file}.log"
STATS_MSG=$(printf "[%s] Hit/Miss: %-7d / %-7d. Comp: %-5d. Total: %-7d. New: %-7d (%3d%%). Search: %d [%.2fs]" \
  "$(date +%H:%M:%S)" "$HIT" "$MISS" "$COMPLETION" "$TOTAL" "$NEWTOKEN" "$PERCENT" "$SEARCH_COUNT" "$DURATION")
echo "$STATS_MSG" >> "$LOG_FILE"

if [ -f "$LOG_FILE" ]; then
    echo -e "\033[0;36m--- Usage History ---\033[0m"
    tail -n 3 "$LOG_FILE"
    echo ""
    awk '{ gsub(/\./, ""); h+=$3; m+=$5; c+=$7; t+=$9 } END { printf "\033[0;34m[Session Total]\033[0m Hit: %d | Miss: %d | Comp: %d | \033[1mTotal: %d\033[0m\n", h, m, c, t }' "$LOG_FILE"
fi

if [ -f "${file}" ]; then
    TIMESTAMP=$(date -u "+%y%m%d-%H")$(printf "%02d" $(( (10#$(date -u "+%M") / 10) * 10 )) )
    cp "$file" "${file%.*}-${TIMESTAMP}-trace.${file##*.}"
fi
