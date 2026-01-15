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
# This mirrors the efficient caching logic from the main 'a' script.
get_token() {
    local token_cache="${TMPDIR:-/tmp}/gemini_token.txt"
    local token=""
    local mtime
    
    # Get file modification time in a cross-platform way (macOS/Linux).
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mtime=$(stat -f %m "$token_cache" 2>/dev/null || echo 0)
    else
        mtime=$(stat -c %Y "$token_cache" 2>/dev/null || echo 0)
    fi

    # Check if a valid, non-expired token exists in the cache (55 min expiry).
    if [[ -f "$token_cache" && $(($(date +%s) - mtime)) -lt 3300 ]]; then
        token=$(cat "$token_cache")
    fi

    # If no valid token, fetch a new one and update the cache.
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

# --- MAIN EXECUTION ---

# 1. Define the options for the interactive menu.
options=(
    "list-models"
    "analyze-project"
    "code-only"
    "code-review"
    "ext-dependency"
    "cheat-sheet"
    "open-source"
)

# 2. Use fzf to prompt the user for a selection.
ACTION=$(printf "%s\n" "${options[@]}" | fzf --prompt="Select an action > ")

# Exit if the user made no selection (e.g., pressed Esc).
if [[ -z "$ACTION" ]]; then
    echo "No selection made. Aborting."
    exit 0
fi

echo "Action selected: '${ACTION}'"

# 3. Use a case statement to execute the chosen action.
case "$ACTION" in
    "list-models")
        TOKEN=$(get_token) || exit 1
        
        # Fetch data from the API.
        RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models" \
          -H "Authorization: Bearer $TOKEN")
        
        # Validate that the API returned valid JSON before processing.
        if ! echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
            echo "Error: API did not return valid JSON." >&2
            echo "Raw Response: $RESPONSE" >&2
            exit 1
        fi
        
        # Process and print the model names.
        echo "$RESPONSE" | jq -r '.models[].name'
        ;;

    "analyze-project")
        # Create a temporary file to hold the project dump content
        DUMP_FILE=$(mktemp) || { echo "Failed to create temporary file." >&2; exit 1; }
        
        # Ensure the temporary file is cleaned up on script exit
        trap 'rm -f "$DUMP_FILE"' EXIT

        echo "Gathering project statistics..."
        
        # Run dump.sh, redirecting main content to the temp file.
        # The stats from dump.sh (on stderr) will be displayed to the user.
        "$BASE_DIR/dump.sh" . > "$DUMP_FILE"

        # Show the current path being analyzed
        echo -e "\033[0;36m[Path] $(pwd)\033[0m"

        # Ask for user confirmation, showing the stats first.
        read -p "Do you want to proceed with sending this data for analysis? (y/N) " -n 1 -r
        echo # Move to a new line for cleaner output

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Proceeding with analysis..."
            # Pipe the captured content from the temp file to the 'a' script
            cat "$DUMP_FILE" | "$BASE_DIR/a" "Please analyze the following project."
        else
            echo "Analysis aborted by user."
        fi
        ;;

    "code-only")
        "$BASE_DIR/a" "Please just output the code. I will use your next output to directly replace file content."
        ;;

    "code-review")
        "$BASE_DIR/a" "Please code review this project."
        ;;

    "ext-dependency")
        "$BASE_DIR/a" "List all external dependencies. Show if authentication is needed and how it is provided."
        ;;

    "cheat-sheet")
        cat <<'EOF'
a "$(<file.txt)"
a "$(cat <<'EOF'
EOF
        ;;
    "open-source")
        "$BASE_DIR/a" "I am just going to open-source this project tell-me. Please check if there is anything missing or wrong."
        ;;
esac
