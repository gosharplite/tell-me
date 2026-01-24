# Copyright (c) 2026 gosharplite@gmail.com
# SPDX-License-Identifier: MIT
#!/bin/bash

# Auth Setup
# Expects: AIURL, KEY_FILE (optional)
# Sets: TOKEN, TARGET_SCOPE, CACHE_SUFFIX, FUNC_ROLE

if [[ "$AIURL" == *"aiplatform.googleapis.com"* ]]; then
    TARGET_SCOPE="https://www.googleapis.com/auth/cloud-platform"
    CACHE_SUFFIX="vertex"
    FUNC_ROLE="function"
else
    TARGET_SCOPE="https://www.googleapis.com/auth/generative-language"
    CACHE_SUFFIX="studio"
    FUNC_ROLE="function"
fi

TOKEN_CACHE="${TMPDIR:-/tmp}/gemini_token_${CACHE_SUFFIX}.txt"

get_file_mtime() {
    if [[ "$OSTYPE" == "darwin"* ]]; then stat -f %m "$1"; else stat -c %Y "$1"; fi
}

if [ -f "$TOKEN_CACHE" ]; then
    NOW=$(date +%s)
    LAST_MOD=$(get_file_mtime "$TOKEN_CACHE")
    if [ $((NOW - LAST_MOD)) -lt 3300 ]; then TOKEN=$(cat "$TOKEN_CACHE"); fi
fi

if [ -z "$TOKEN" ]; then
    if [ -n "$KEY_FILE" ] && [ -f "$KEY_FILE" ]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$KEY_FILE"
        TOKEN=$(gcloud auth application-default print-access-token --scopes="${TARGET_SCOPE}")
    else
        TOKEN=$(gcloud auth print-access-token --scopes="${TARGET_SCOPE}")
    fi
    echo "$TOKEN" > "$TOKEN_CACHE"
fi

export TOKEN