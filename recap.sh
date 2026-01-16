#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Enable pipefail to catch errors in jq | glow pipeline
set -o pipefail

# 1. Initialize variables
FILERECAP="$file"
RAW_MODE="false"
CODE_MODE="false"
LAST_MESSAGES=0
LAST_PAIRS=0
SUMMARY_MESSAGES=0 # NEW: Variable for summary mode

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
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                LAST_MESSAGES=$2
                shift
            else
                LAST_MESSAGES=1
            fi
            shift
            ;;
        -ll)
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                LAST_PAIRS=$2
                shift
            else
                LAST_PAIRS=1
            fi
            shift
            ;;
        -c|--code)
            CODE_MODE="true"
            LAST_MESSAGES=1 # Force showing last message for code extraction
            shift
            ;;
        # NEW: Argument for summary view
        -s|--summary)
            SUMMARY_MESSAGES=10 # Default to last 10 if no number is given
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                SUMMARY_MESSAGES=$2
                shift
            fi
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
if [ "$SUMMARY_MESSAGES" -gt 0 ]; then # NEW: Prioritize summary scope
    JQ_PREFIX=".messages[-${SUMMARY_MESSAGES}:] | .[]"
elif [ "$LAST_PAIRS" -gt 0 ]; then
    NUM_TO_SLICE=$(( LAST_PAIRS * 2 ))
    JQ_PREFIX=".messages[-${NUM_TO_SLICE}:] | .[]"
elif [ "$LAST_MESSAGES" -gt 0 ]; then
    JQ_PREFIX=".messages[-${LAST_MESSAGES}:] | .[]"
else
    # Process all items
    JQ_PREFIX='.messages[]'
fi

# --- Rendering ---

# NEW: Mode 0: Summary View
if [ "$SUMMARY_MESSAGES" -gt 0 ]; then
    jq -r "
      $JQ_PREFIX |
      (
        # 1. Set the role prefix with color
        (if .role == \"user\" then \"\\u001b[1;32m[USER] \" else \"\\u001b[1;34m[MODEL]\" end) + \"\\u001b[0m: \" +
        # 2. Get all text content, replace newlines with spaces, and collapse multiple spaces
        ((.parts // []) | map(.text // \"\") | join(\"\") | gsub(\"\\n\"; \" \") | gsub(\"[ \t]+\"; \" \")) |
        # 3. Truncate the resulting one-liner if it's longer than 120 characters
        (if length > 120 then .[0:117] + \"...\" else . end)
      )
    " "$FILERECAP"
    exit 0
fi

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
