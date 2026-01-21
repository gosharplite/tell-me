#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Enable pipefail to catch errors in jq | glow pipeline
set -o pipefail

# 1. Initialize variables
FILERECAP="$file"
RAW_MODE="false"
CODE_MODE="false"
NO_CODE="false"
LAST_MESSAGES=0
LAST_PAIRS=0
SUMMARY_MESSAGES=0
HEAD_LINES=0
TAIL_LINES=0

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
        -nc|--no-code)
            NO_CODE="true"
            shift
            ;;
        -s|--summary)
            SUMMARY_MESSAGES=10 # Default to last 10 if no number is given
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                SUMMARY_MESSAGES=$2
                shift
            fi
            shift
            ;;
        -t|--top)
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                HEAD_LINES=$2
                shift
            else
                echo "Error: -t requires a number." >&2
                exit 1
            fi
            shift
            ;;
        -b|--bottom)
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                TAIL_LINES=$2
                shift
            else
                echo "Error: -b requires a number." >&2
                exit 1
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
if [ "$SUMMARY_MESSAGES" -gt 0 ]; then
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

# --- Smart Coloring ---
# If stdout is a terminal (TTY), use ANSI colors.
# If stdout is a pipe/file, use empty strings (plain text).
if [ -t 1 ]; then
    C_USER=$(printf "\033[1;32m")
    C_MODEL=$(printf "\033[1;34m")
    C_TOOL=$(printf "\033[1;36m")
    C_RESET=$(printf "\033[0m")
else
    C_USER=""
    C_MODEL=""
    C_TOOL=""
    C_RESET=""
fi

# --- Rendering Function ---
produce_output() {
    # Mode 0: Summary View
    if [ "$SUMMARY_MESSAGES" -gt 0 ]; then
        jq -r --arg u "$C_USER" --arg m "$C_MODEL" --arg t "$C_TOOL" --arg r "$C_RESET" "
          $JQ_PREFIX |
          (
            (if .role == \"user\" then \$u + \"[USER] \" 
             elif .role == \"function\" then \$t + \"[TOOL] \"
             else \$m + \"[MODEL] \" end) + \$r + \": \" +
            ((.parts // []) | map(.text // (.functionCall | \"Call: \" + .name) // (.functionResponse | \"Result: \" + (.response.result | tostring)) // \"\") | join(\" \") | gsub(\"\\n\"; \" \") | gsub(\"[ \t]+\"; \" \")) |
            (if length > 120 then .[0:117] + \"...\" else . end)
          )
        " "$FILERECAP"
        return
    fi

    # Mode 1: Code/Content Only (Extract Code)
    if [ "$CODE_MODE" = "true" ]; then
      jq -r "
        $JQ_PREFIX |
        ((.parts // []) | map(.text // \"\") | join(\"\"))
      " "$FILERECAP" | sed -e '1{/^```/d;}' -e '${/^```/d;}'
      return
    fi

    # Helper: Apply No-Code Filter if requested
    apply_filters() {
        if [ "$NO_CODE" = "true" ]; then
            sed '/^```/,/^```/d'
        else
            cat
        fi
    }

    # Mode 2: Markdown (Glow)
    # Note: Glow automatically handles TTY detection and usually strips styles when piped.
    if [ "$RAW_MODE" = "false" ] && command -v glow >/dev/null 2>&1; then
      jq -r "
        $JQ_PREFIX |
        (if .role == \"user\" then \"## 👤 USER\" 
         elif .role == \"function\" then \"## ⚙️ TOOL RESPONSE\"
         else \"## 🤖 MODEL\" end) + \"\\n\" +
        ((.parts // []) | map(
            .text // 
            (.functionCall | \"> Calling: **\" + .name + \"**\\n> Args: `\" + (.args | tojson) + \"`\") // 
            (.functionResponse | \"> Tool: **\" + .name + \"**\\n> Result: \" + (.response.result | tostring)) // 
            \"*[Non-text content]*\"
        ) | join(\"\")) +
        \"\\n\\n---\"
      " "$FILERECAP" | apply_filters | glow -

    # Mode 3: Raw/ANSI Fallback (Manual Coloring)
    else
      jq -r --arg u "$C_USER" --arg m "$C_MODEL" --arg t "$C_TOOL" --arg r "$C_RESET" "
        $JQ_PREFIX |
        (if .role == \"user\" then \$u + \"[USER]\" 
         elif .role == \"function\" then \$t + \"[TOOL]\"
         else \$m + \"[MODEL]\" end) +
        \$r + \": \" +
        ((.parts // []) | map(
            .text // 
            (.functionCall | \"[Call: \" + .name + \"] \" + (.args | tojson)) // 
            (.functionResponse | \"[Result: \" + .name + \"] \" + (.response.result | tostring)) //
            \"<Non-text content>\"
        ) | join(\"\")) + \"\\n\"
      " "$FILERECAP" | apply_filters
    fi
}

# --- Execution ---
if [ "$HEAD_LINES" -gt 0 ]; then
    produce_output | head -n "$HEAD_LINES"
elif [ "$TAIL_LINES" -gt 0 ]; then
    produce_output | tail -n "$TAIL_LINES"
else
    produce_output
fi

