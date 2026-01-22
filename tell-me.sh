#!/bin/bash
# Copyright (c) 2026  <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Usage: ./tell-me.sh CONFIG [new] [nobash] [message...]

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Validation and Dependency Check
if [[ ! -f "$1" ]]; then
    echo "Error: Configuration file '$1' not found."
    echo "Usage: $0 CONFIG [new] [nobash] [message...]"
    exit 1
fi

# Convert CONFIG to absolute path
CONFIG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

# Shift past the config file to parse optional arguments
shift

ACTION_NEW=false
SKIP_BASH=false
MSG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        new)
            ACTION_NEW=true
            shift
            ;;
        nobash)
            SKIP_BASH=true
            shift
            ;;
        *)
            # Treat all remaining arguments as the message
            MSG="$*"
            break
            ;;
    esac
done

# --- Dependency Verification ---

# Check generic dependencies
for cmd in jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Dependency '$cmd' is missing." >&2
        exit 1
    fi
done

# Check specifically for 'yq' and ensure it is the Go implementation
if ! command -v yq &> /dev/null; then
    echo "Error: Dependency 'yq' is missing." >&2
    exit 1
fi

# The Python wrapper (kislyuk/yq) has incompatible syntax.
# The Go version (mikefarah/yq) typically outputs "yq (https://github.com/mikefarah/yq/)..."
if ! yq --version 2>&1 | grep -q -E "mikefarah|github.com/mikefarah/yq"; then
    echo "Error: Incompatible 'yq' implementation detected." >&2
    echo "This project requires the Go implementation (https://github.com/mikefarah/yq)." >&2
    echo "Detected version: $(yq --version 2>&1)" >&2
    echo "Please install the correct version (e.g., via 'brew install yq' or binary download)." >&2
    exit 1
fi
# -------------------------------

# 2. Safely load and export variables from YAML with Robust Logic

# MODE: Critical for filenames
MODE_VAL=$(yq -r '.MODE' "$CONFIG")
if [[ "$MODE_VAL" == "null" ]]; then
    export MODE="assist-gemini"
else
    export MODE="$MODE_VAL"
fi

# PERSON: System instruction
PERSON_VAL=$(yq -r '.PERSON' "$CONFIG")
if [[ "$PERSON_VAL" == "null" ]]; then
    export PERSON="You are a helpful AI assistant."
else
    export PERSON="$PERSON_VAL"
fi

# AIURL: Critical for API connectivity
URL_VAL=$(yq -r '.AIURL' "$CONFIG")
if [[ "$URL_VAL" == "null" ]]; then
    export AIURL="https://generativelanguage.googleapis.com/v1beta/models"
else
    export AIURL="$URL_VAL"
fi

# AIMODEL: Specific model name
MODEL_VAL=$(yq -r '.AIMODEL' "$CONFIG")
if [[ "$MODEL_VAL" == "null" ]]; then
    export AIMODEL="gemini-1.5-pro"
else
    export AIMODEL="$MODEL_VAL"
fi

# KEY_FILE: yq's alternative syntax `// ""` handles nulls by returning empty string
export KEY_FILE=$(yq -r '.KEY_FILE // ""' "$CONFIG")

# USE_SEARCH: Toggle Grounding
SEARCH_VAL=$(yq -r '.USE_SEARCH' "$CONFIG")
if [[ "$SEARCH_VAL" == "null" ]]; then
    export USE_SEARCH="true"
else
    export USE_SEARCH="$SEARCH_VAL"
fi

# MAX_TURNS: Maximum turns per interaction (Tool calls)
TURNS_VAL=$(yq -r '.MAX_TURNS' "$CONFIG")
if [[ "$TURNS_VAL" == "null" ]]; then
    export MAX_TURNS=10
else
    export MAX_TURNS="$TURNS_VAL"
fi

# MAX_HISTORY_TOKENS: Threshold for automatic history pruning
HISTORY_LIMIT_VAL=$(yq -r '.MAX_HISTORY_TOKENS' "$CONFIG")
if [[ "$HISTORY_LIMIT_VAL" == "null" ]]; then
    export MAX_HISTORY_TOKENS=120000
else
    export MAX_HISTORY_TOKENS="$HISTORY_LIMIT_VAL"
fi

export CONFIG

# --- AIT_HOME Check (Fallback) ---
# If AIT_HOME is unset or null, default it to BASE_DIR (the script's directory).
: "${AIT_HOME:=$BASE_DIR}"

export file="$AIT_HOME/output/last-${MODE}.json"
# -------------------------------

# Ensure output directory exists
mkdir -p "$(dirname "$file")"

# 3. Initialize/Handle Context
if [[ "$ACTION_NEW" == "true" ]]; then
    # User explicitly requested a new session, so delete the old files.
    # Archive existing session files with a timestamp in the backups folder
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SESSION_BACKUP_DIR="$(dirname "$file")/backups/$TIMESTAMP"
    mkdir -p "$SESSION_BACKUP_DIR"
    echo "Archiving existing session files to $SESSION_BACKUP_DIR"
    for f in "$file" "${file}.log" "${file%.*}.scratchpad.md" "${file%.*}.tasks.json" "${file%.*}.config.yaml"; do
        [ -f "$f" ] && mv "$f" "$SESSION_BACKUP_DIR/"
    done
elif [[ -f "$file" ]]; then
    # History file exists and 'new' was not specified. Ask the user.
    echo "An existing session history was found for '$MODE'."
    
    # Calculate total conversation turns for display
    TURNS_TO_SHOW=3
    MESSAGES_TO_RECAP=$(( TURNS_TO_SHOW * 2 ))
    TOTAL_MESSAGES=$(jq '.messages | length' "$file" 2>/dev/null || echo 0)
    TOTAL_TURNS=$(( TOTAL_MESSAGES / 2 ))

    echo -e "\033[0;36m--- Last ${TURNS_TO_SHOW} Conversation Turns (${TURNS_TO_SHOW}/${TOTAL_TURNS}) ---\033[0m"
    "$BASE_DIR/recap.sh" -s "$MESSAGES_TO_RECAP"
    echo "-------------------------------------------"

    if [[ -f "${file}.log" ]]; then
        echo -e "\033[0;36m--- Session Usage Statistics ---\033[0m"
        tail -n 3 "${file}.log"
        echo ""
        # Aggregated stats calculation (sums Hit, Miss, Comp, Total, Search fields)
        awk '{ gsub(/\./, ""); h+=$3; m+=$5; c+=$7; t+=$9; s+=$13 } END { printf "\033[0;34m[Session Total]\033[0m Hit: %d | Miss: %d | Comp: %d | \033[1mTotal: %d\033[0m | Search: %d\n", h, m, c, t, s }' "${file}.log"
        echo "-------------------------------------------"
    fi

    read -p "Do you want to continue the previous session? (Y/n) " -n 1 -r
    echo # Move to a new line after input

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        # User chose to continue (default).
        echo "Resuming previous session..."
    else
        # User chose to start a new session.
        echo "Starting a new session."
        # Archive existing session files with a timestamp in the backups folder
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        SESSION_BACKUP_DIR="$(dirname "$file")/backups/$TIMESTAMP"
        mkdir -p "$SESSION_BACKUP_DIR"
        echo "Archiving previous session files to $SESSION_BACKUP_DIR"
        for f in "$file" "${file}.log" "${file%.*}.scratchpad.md" "${file%.*}.tasks.json" "${file%.*}.config.yaml"; do
            [ -f "$f" ] && mv "$f" "$SESSION_BACKUP_DIR/"
        done
    fi
fi

# Save current config to output folder (after potential archiving)
cp "$CONFIG" "${file%.*}.config.yaml"
chmod 600 "${file%.*}.config.yaml"

if [[ -n "$MSG" ]]; then
    # If a message is provided on the command line, send it.
    "$BASE_DIR/a.sh" "$MSG"
fi

# 4. Enter Interactive Shell
if [[ "$SKIP_BASH" == "false" ]]; then
    FILENAME=$(basename "$CONFIG" .yaml)
    
    # Determine Auth Message
    if [[ -n "$KEY_FILE" && -f "$KEY_FILE" ]]; then
        AUTH_INFO="Service Account ($KEY_FILE)"
    else
        AUTH_INFO="Standard User Auth (gcloud)"
    fi

    bash --rcfile <(cat <<EOF
alias a='"$BASE_DIR/a.sh"'
alias aa='"$BASE_DIR/aa.sh"'
alias recap='"$BASE_DIR/recap.sh"'
alias h='"$BASE_DIR/hack.sh"'
alias dump='"$BASE_DIR/dump.sh"'
stats() {
    if [ -f "\$file.log" ]; then
        echo -e "\033[0;36m--- Usage History ---\033[0m"
        tail -n 3 "\$file.log"
        echo ""
        awk '{ gsub(/\./, ""); h+=\$3; m+=\$5; c+=\$7; t+=\$9; s+=\$13 } END { printf "\033[0;34m[Session Total]\033[0m Hit: %d | Miss: %d | Comp: %d | \033[1mTotal: %d\033[0m | Search: %d\n", h, m, c, t, s }' "\$file.log"
    else
        echo "No stats available yet."
    fi
}
export PS1="\[\033[01;32m\]\u@tell-me\[\033[00m\]:\[\033[01;35m\]${FILENAME}\[\033[00m\]\$ "
echo -e "\033[1;34mChat session started using $CONFIG\033[0m"
echo -e "\033[0;36m[Auth] $AUTH_INFO\033[0m"
echo -e "\033[0;36m[Search] $USE_SEARCH\033[0m"
echo -e "Type \033[1;32ma \"your message\"\033[0m to chat."
EOF
    )
fi
