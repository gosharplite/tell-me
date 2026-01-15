#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Usage: ./setup.sh CONFIG [new] [nobash] [message...]

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

for cmd in yq jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Dependency '$cmd' is missing."
        exit 1
    fi
done

# 2. Safely load and export variables from YAML
export MODE=$(yq -r '.MODE' "$CONFIG")
export PERSON=$(yq -r '.PERSON' "$CONFIG")
export AIURL=$(yq -r '.AIURL' "$CONFIG")
export AIMODEL=$(yq -r '.AIMODEL' "$CONFIG")
export CONFIG

# Automatically construct the history file path from the MODE variable.
if [[ -n "$AIT_HOME" ]]; then
    export file="$AIT_HOME/output/last-${MODE}.json"
else
    # AIT_HOME is essential for storing session files in a consistent location.
    echo "Error: The AIT_HOME environment variable is not set." >&2
    echo "Please define it in your shell profile (e.g., ~/.bashrc)." >&2
    exit 1
fi

# Ensure output directory exists
mkdir -p "$(dirname "$file")"

# 3. Initialize/Handle Context
if [[ "$ACTION_NEW" == "true" ]]; then
    [ -f "$file" ] && rm "$file"
    [ -f "${file}.log" ] && rm "${file}.log"
fi

if [[ -n "$MSG" ]]; then
    "$BASE_DIR/a" "$MSG"
elif [[ "$ACTION_NEW" == "false" ]]; then
    "$BASE_DIR/recap.sh"
fi

# 4. Enter Interactive Shell
if [[ "$SKIP_BASH" == "false" ]]; then
    FILENAME=$(basename "$CONFIG" .yaml)
    
    bash --rcfile <(cat <<EOF
alias a='"$BASE_DIR/a"'
alias aa='"$BASE_DIR/aa"'
alias recap='"$BASE_DIR/recap.sh"'
alias h='"$BASE_DIR/hack.sh"'
alias dump='"$BASE_DIR/dump.sh"'
export PS1="\[\033[01;32m\]\u@tell-me\[\033[00m\]:\[\033[01;35m\]${FILENAME}\[\033[00m\]\$ "
echo -e "\033[1;34mChat session started using $CONFIG\033[0m"
echo -e "Type \033[1;32ma \"your message\"\033[0m to chat."
EOF
    )
fi
