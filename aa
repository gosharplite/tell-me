#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prompt user
echo -e "\033[0;33m[Reading multi-line input. Press Ctrl+D to send]\033[0m"

# Capture stdin into variable
INPUT="$(cat)"

# Check if input is empty
if [ -z "$INPUT" ]; then
    echo "Input empty. Aborted."
    exit 0
fi

echo -e "\033[0;36m[Input captured. Processing request...]\033[0m"

# Pass to 'a' script
"$BASE_DIR/a" "$INPUT"
