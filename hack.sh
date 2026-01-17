#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Provides an fzf-powered menu for common, pre-defined AI tasks.

# Exit immediately if a command in a pipeline fails.
set -o pipefail

# --- SETUP ---

# Resolve the script's absolute directory to reliably call other scripts.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify that all required command-line tools are available.
for cmd in fzf gcloud curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is not installed or not in your PATH." >&2
        exit 1
    fi
done

# --- FUNCTIONS ---

# Retrieves a cached Google Cloud access token or generates a new one
# if the cache is missing or has expired (older than 55 minutes).
get_token() {
    local token_cache="${TMPDIR:-/tmp}/gemini_token.txt"
    local token=""
    local mtime
    
    # Get file modification time in a cross-platform way (macOS vs Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mtime=$(stat -f %m "$token_cache" 2>/dev/null || echo 0)
    else
        mtime=$(stat -c %Y "$token_cache" 2>/dev/null || echo 0)
    fi

    # Use cached token if it's less than 3300 seconds (55 minutes) old.
    if [[ -f "$token_cache" && $(($(date +%s) - mtime)) -lt 3300 ]]; then
        token=$(cat "$token_cache")
    fi

    # If no valid token, fetch a new one from gcloud.
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

# A helper function to display a message to the user before sending it to the AI.
send_prompt() {
    local msg="$1"
    echo "Sending prompt: \"$msg\""
    "$BASE_DIR/a.sh" "$msg"
}

# --- MAIN EXECUTION ---

# Define the list of actions for the user to choose from.
options=(
    "list-models"
    "analyze-project"
    "code-review"
    "ext-dependency"
    "code-only"
    "show-last"
    "cheat-sheet"
)

# Use fzf to display an interactive menu and capture the user's selection.
ACTION=$(printf "%s\n" "${options[@]}" | fzf --prompt="Select an action > ")

if [[ -z "$ACTION" ]]; then
    echo "No selection made. Exiting."
    exit 0
fi

echo "Action selected: '${ACTION}'"

# Execute the chosen action.
case "$ACTION" in
    "list-models")
        TOKEN=$(get_token) || exit 1
        echo "Fetching available models..."
        RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models" \
          -H "Authorization: Bearer $TOKEN")
        
        # Validate that the API returned valid JSON.
        if ! echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
            echo "Error: Invalid API response. The server may be down." >&2
            echo "Raw output: $RESPONSE"
            exit 1
        fi

        # Check for a specific API error message within the JSON.
        if echo "$RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
             echo -e "\033[31mAPI Error:\033[0m"
             echo "$RESPONSE" | jq -r '.error.message'
             exit 1
        fi
        
        # If successful, print the list of model names.
        echo "$RESPONSE" | jq -r '.models[].name'
        ;;

    "analyze-project")
        # Create a temporary file to hold the project dump to avoid command-line length limits.
        DUMP_FILE=$(mktemp) || { echo "Failed to create temporary file." >&2; exit 1; }
        trap 'rm -f "$DUMP_FILE"' EXIT # Ensure cleanup on exit.

        echo "Dumping project structure and contents..."
        
        # Run dump.sh, redirecting its main output to the temp file.
        # The stats from dump.sh (on stderr) will be displayed directly to the user.
        "$BASE_DIR/dump.sh" . > "$DUMP_FILE"

        echo -e "\033[0;36m[Path] $(pwd)\033[0m"

        # Ask for user confirmation before sending the data.
        read -p "Do you want to proceed with sending this data for analysis? (y/N) " -n 1 -r
        echo # Move to a new line for cleaner output.

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Proceeding with analysis..."
            # Pipe the captured project content from the temp file to the 'a' script.
            cat "$DUMP_FILE" | "$BASE_DIR/a.sh" "Please provide a high-level analysis of the following project."
        else
            echo "Analysis aborted by user."
        fi
        ;;

    "code-review")
        send_prompt "Please perform a code review on the provided project content. Focus on potential bugs, security vulnerabilities, adherence to best practices, and opportunities for simplification."
        ;;

    "ext-dependency")
        send_prompt "Analyze the provided code and list all external dependencies. For each, specify if authentication is required and, if possible, how it appears to be implemented (e.g., API key in environment variable, OAuth)."
        ;;

    "code-only")
        send_prompt "For your next response, please provide only the raw code. Do not include any explanations, greetings, or markdown fences. I will use the output to directly replace a file's content."
        ;;

    "show-last")
        # Display the last user/model pair using the pager
        "$BASE_DIR/recap.sh" -ll | more
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
