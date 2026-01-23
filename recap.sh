#!/bin/bash
# Copyright (c) 2026  <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Enable pipefail to catch errors in jq | glow pipeline
set -o pipefail

# 1. Initialize variables
FILERECAP="$file"
RAW_MODE="false"
MARKDOWN_MODE="false"
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
        -m|--markdown)
            MARKDOWN_MODE="true"
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
        ((.parts // [] | map(select(.thought != true))) | map(.text // \"\"\)) | join(\"\"\))
      " "$FILERECAP" | sed -e '1{/^```/d;}' -e '${/^```/d;}'
      return
    fi

    # Helper: Apply No-Code Filter if requested
    apply_filters() {
        if [ "$NO_CODE" = "true" ]; then
            sed '/^```/,/^```/c\> *[Code Block Hidden]*'
        else
            cat
        fi
    }

    # Mode 2: Markdown (Glow)
    # Note: Glow automatically handles TTY detection and usually strips styles when piped.
    if [ "$MARKDOWN_MODE" = "true" ] || ([ "$RAW_MODE" = "false" ] && command -v glow >/dev/null 2>&1); then
      local out
      out=$(jq -r "
        $JQ_PREFIX |
        (if .role == \"user\" then \"## 👤 USER\" 
         elif .role == \"function\" then \"## ⚙️ TOOL RESPONSE\"
         else \"## 🤖 MODEL\" end) + \"\\n\" +
        (if ((.parts // []) | map(select(.thought != true)) | length > 0) then
            ((.parts // []) | map(select(.thought != true)) | map(
                .text // 
                (if \"$SHOW_TOOLS\" == \"true\" then 
                    (.functionCall | \"> Calling: **\" + .name + \"**\\n> Args: \`\" + (.args | tojson) + \"\`\") // 
                    (.functionResponse | \"> Tool: **\" + .name + \"**\\n> Result: \" + (.response.result | tostring))
                 else empty end) // 
                \"*[Non-text content]*\"
            ) | join(\"\")) +
            (if (\"$SHOW_THOUGHTS\" == \"true\") then
                ((.parts // []) | map(select(.thought == true)) | map(.text // \"\") | join(\"\\n\") | 
                 split(\"\\n\") | map(select(test(\"^\\\\s*$\") | not)) | join(\"\\n\") | if length > 0 then \"\\n\\n> *[Thought]*\\n\" + . else \"\" end)
             else \"\" end)
         elif ((.parts // []) | map(select(.thought == true)) | length > 0) then
            (if (\"$SHOW_THOUGHTS\" == \"true\") then
                ((.parts // []) | map(select(.thought == true)) | map(.text // \"\") | join(\"\\n\") | 
                 split(\"\\n\") | map(select(test(\"^\\\\s*$\") | not)) | join(\"\\n\") | if length > 0 then \"## 🧠 THOUGHT\\n\" + . else \"\" end)
             else \"*[Thought Only]*\" end)
         else \"*[Empty Message]*\" end) +
        \"\\n\\n---\"
      " "$FILERECAP" | apply_filters)

      if [ "$MARKDOWN_MODE" = "true" ]; then
          echo "$out"
      else
          echo "$out" | glow -
      fi

    # Mode 3: Raw/ANSI Fallback (Manual Coloring)
    else
      jq -r --arg u "$C_USER" --arg m "$C_MODEL" --arg t "$C_TOOL" --arg r "$C_RESET" "
        $JQ_PREFIX |
        (if .role == \"user\" then \$u + \"[USER]\" 
         elif .role == \"function\" then \$t + \"[TOOL]\"
         else \$m + \"[MODEL]\" end) +
        \$r + \": \" +
        (if .parts then
            ((.parts | map(select(.thought != true))) | map(
                .text // 
                (if \"$SHOW_TOOLS\" == \"true\" then
                    (.functionCall | \"[Call: \" + .name + \"] \" + (.args | tojson)) // 
                    (.functionResponse | \"[Result: \" + .name + \"] \" + (.response.result | tostring))
                 else empty end) //
                \"<Non-text content>\"
            ) | join(\"\")) +
            (if (\"$SHOW_THOUGHTS\" == \"true\") then
                ((.parts // []) | map(select(.thought == true)) | map(.text // \"\") | join(\"\\n\") | 
                 split(\"\\n\") | map(select(test(\"^\\\\s*$\") | not)) | join(\"\\n\") | if length > 0 then \"\\n\\n[Thought]\\n\" + . else \"\" end)
             else \"\" end)
         else \"<Empty Message>\" end) + \"\\n\"
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

