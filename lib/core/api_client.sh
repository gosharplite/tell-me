#!/bin/bash
# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT

# api_client.sh: Handles the HTTP communication with the Gemini API.

call_gemini_api() {
    local api_url="$1"
    local model="$2"
    local token="$3"
    local payload_file="$4"
    local max_retries="${5:-3}"
    local retry_count=0
    local response_json=""

    while [ $retry_count -lt $max_retries ]; do
        response_json=$(curl -s "${api_url}/${model}:generateContent" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $token" \
          -d @"$payload_file")
        
        # Check for specific retryable error codes (429: Too Many Requests, 500: Internal Server Error)
        if echo "$response_json" | jq -e '.error.code == 429 or .error.code == 500' > /dev/null; then
             local err_code
             err_code=$(echo "$response_json" | jq -r '.error.code')
             retry_count=$((retry_count + 1))
             if [ $retry_count -lt $max_retries ]; then
                 echo -e "\033[33m[Warning] API error $err_code. Retrying in 5s... ($retry_count/$max_retries)\033[0m" >&2
                 sleep 5
                 continue
             fi
             echo -e "\033[31mError: API retry limit exhausted ($err_code).\033[0m" >&2
             return 1
        else
            break
        fi
    done

    # Final error check
    if echo "$response_json" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "\033[31mAPI Error:\033[0m $(echo "$response_json" | jq -r '.error.message')" >&2
        return 1
    fi

    echo "$response_json"
}

