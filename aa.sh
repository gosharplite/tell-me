#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Block Piped Input
# [ ! -t 0 ] returns true if stdin is NOT a terminal (i.e., it's a pipe or file)
if [ ! -t 0 ]; then
    echo -e "\033[31mError: 'aa' is strictly for interactive multi-line input.\033[0m" >&2
    echo "To pipe content, please use 'a' instead:" >&2
    echo -e "  \033[1;32mcat file.txt | a \"Your instruction\"\033[0m" >&2
    exit 1
fi

# 2. Interactive Mode Logic
echo -e "\033[0;33m[Reading multi-line input. Press Ctrl+D to send]\033[0m"

# Capture stdin (Keyboard input)
INPUT="$(cat)"

# Check if input is empty
if [ -z "$INPUT" ]; then
    echo "Input empty. Aborted."
    exit 0
fi

echo -e "\033[0;36m[Input captured. Processing request...]\033[0m"

# Pass to 'a.sh' script
"$BASE_DIR/a.sh" "$INPUT"
