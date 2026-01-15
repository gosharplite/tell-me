#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Enable pipefail to catch errors in jq | glow pipeline
set -o pipefail

# 1. Initialize variables
FILERECAP="$file"
RAW_MODE="false"
LAST_ONLY="false"
CODE_MODE="false"

# Check environment variable override
if [ "${RAW:-false}" = "true" ]; then RAW_MODE="true"; fi

# 2. Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--raw)
            RAW_MODE="true"
            shift
            ;;
        -l|--last)
            LAST_ONLY="true"
            shift
            ;;
        -c|--code)
            CODE_MODE="true"
            LAST_ONLY="true"
            shift
            ;;
        *)
            FILERECAP="$1"
            shift
            ;;
    esac
done

# --- Validation ---
if [[ -z "$FILERECAP" || ! -f "$FILERECAP" ]]; then
  echo "Error: File '${FILERECAP:-empty}' not found." >&2
  exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required." >&2
    exit 1
fi

# --- Determine JQ Filter Scope ---
if [ "$LAST_ONLY" = "true" ]; then
    # Slice the last item only
    JQ_PREFIX='.messages[-1:] | .[]'
else
    # Process all items
    JQ_PREFIX='.messages[]'
fi

# --- Rendering ---

# Mode 1: Code/Content Only
if [ "$CODE_MODE" = "true" ]; then
  jq -r "
    $JQ_PREFIX | 
    ((.parts // []) | map(.text // \"\") | join(\"\"))
  " "$FILERECAP" | sed -e '1{/^```/d;}' -e '${/^```/d;}'
  exit 0
fi

# Mode 2: Markdown (Glow)
if [ "$RAW_MODE" = "false" ] && command -v glow >/dev/null 2>&1; then
  jq -r "
    $JQ_PREFIX | 
    (if .role == \"user\" then \"## 👤 USER\" else \"## 🤖 MODEL\" end) + \"\\n\" + 
    ((.parts // []) | map(.text // \"*[Non-text content]*\") | join(\"\")) + 
    \"\\n\\n---\"
  " "$FILERECAP" | glow -

# Mode 3: Raw/ANSI Fallback
else
  jq -r "
    $JQ_PREFIX | 
    (if .role == \"user\" then \"\\u001b[1;32m[USER]\" else \"\\u001b[1;34m[MODEL]\" end) + 
    \"\\u001b[0m: \" + 
    ((.parts // []) | map(.text // \"<Non-text content>\") | join(\"\")) + \"\\n\"
  " "$FILERECAP"
fi
