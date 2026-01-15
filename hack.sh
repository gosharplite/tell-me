#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# A menu-driven utility script for common project tasks.

# Exit immediately if a command in a pipeline fails.
set -o pipefail

# --- PREPARATION ---

# Resolve the absolute path of the script's directory.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Check for required command-line tools.
for cmd in fzf gcloud curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is not installed." >&2
        exit 1
    fi
done

# --- FUNCTIONS ---

# Function to get a cached or new Google Cloud access token.
get_token() {
    local token_cache="${TMPDIR:-/tmp}/gemini_token.txt"
    local token=""
    local mtime
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mtime=$(stat -f %m "$token_cache" 2>/dev/null || echo 0)
    else
        mtime=$(stat -c %Y "$token_cache" 2>/dev/null || echo 0)
    fi

    if [[ -f "$token_cache" && $(($(date +%s) - mtime)) -lt 3300 ]]; then
        token=$(cat "$token_cache")
    fi

    if [[ -z "$token" ]]; then
        token=$(gcloud auth print-access-token --scopes=https://www.googleapis.com/auth/generative-language)
        if [[ -n "$token" ]]; then
            echo "$token" > "$token_cache"
        else
            echo "Error: Failed to retrieve Google Cloud access token." >&2
            return 1
        fi
    fi
    echo "$token"
}

# Helper function to dump the project and send a specific prompt
analyze_with_prompt() {
    local user_prompt="$1"
    
    # Create a temporary file to hold the project dump content
    local dump_file=$(mktemp) || { echo "Failed to create temporary file." >&2; exit 1; }
    
    # Ensure the temporary file is cleaned up
    trap 'rm -f "$dump_file"' RETURN

    echo "Gathering project statistics..."
    
    # Run dump.sh to temp file, displaying stderr stats to user
    "$BASE_DIR/dump.sh" . > "$dump_file"

    # Show the current path being analyzed
    echo -e "\033[0;36m[Path] $(pwd)\033[0m"
    echo "Processing..."

    # Pipe the dump + prompt to the 'a' script immediately (Confirmation removed)
    cat "$dump_file" | "$BASE_DIR/a" "$user_prompt"
}

# --- MAIN EXECUTION ---

# 1. Define the options
options=(
    "list-models"
    "analyze-project"
    "code-review"
    "ext-dependency"
    "open-source"
    "code-only"
    "cheat-sheet"
)

# 2. FZF Selection
ACTION=$(printf "%s\n" "${options[@]}" | fzf --prompt="Select an action > ")

if [[ -z "$ACTION" ]]; then
    echo "No selection made."
    exit 0
fi

echo "Action selected: '${ACTION}'"

# 3. Execute Action
case "$ACTION" in
    "list-models")
        TOKEN=$(get_token) || exit 1
        echo "Fetching models..."
        RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models" \
          -H "Authorization: Bearer $TOKEN")
        
        # Check if response is valid JSON
        if ! echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
            echo "Error: Invalid API response." >&2
            echo "Raw output: $RESPONSE"
            exit 1
        fi

        # Check for API Error object
        if echo "$RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
             echo -e "\033[31mAPI Error:\033[0m"
             echo "$RESPONSE" | jq -r '.error.message'
             exit 1
        fi
        
        # Success output
        echo "$RESPONSE" | jq -r '.models[].name'
        ;;

    "analyze-project")
        analyze_with_prompt "Please analyze the following project."
        ;;

    "code-review")
        analyze_with_prompt "Please code review this project. Focus on logic errors, security, and best practices."
        ;;

    "ext-dependency")
        analyze_with_prompt "List all external dependencies found in this code. Show if authentication is needed and how it is provided."
        ;;

    "open-source")
        analyze_with_prompt "I am planning to open-source this project. Please review the code for any hardcoded secrets, sensitive paths, or missing licenses."
        ;;

    "code-only")
        # This remains text-only as it is usually a modifier for a previous request
        "$BASE_DIR/a" "Please just output the code. I will use your next output to directly replace file content."
        echo "Please just output the code. I will use your next output to directly replace file content."
        ;;

    "cheat-sheet")
        cat <<'EOF'
-------------------------------------
 CHEAT SHEET
-------------------------------------
1. File Input:
   a "$(<file.txt)"

2. Heredoc Input:
   a "$(cat <<'END'
   Your multi-line text here
   END
   )"

3. Pipe Input:
   cat file.txt | a "Summarize this"
-------------------------------------
EOF
        ;;
esac
