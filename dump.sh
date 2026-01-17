#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

TARGET_DIR=${1:-"."}

# If AIT_HOME is set and is a directory, use it for output.
# Otherwise, fall back to the current directory for standalone usage.
if [[ -n "$AIT_HOME" && -d "$AIT_HOME" ]]; then
    OUTPUT_DIR="$AIT_HOME/output"
else
    # Fallback for when the script is run outside the `ait` session
    OUTPUT_DIR="./output"
fi

# Define ignore list
IGNORES=(
    "node_modules" ".git" ".idea" ".vscode" "__pycache__"
    "output" "dist" "build" "coverage" "target" "vendor" ".DS_Store"
    ".env" ".env.local" ".pem" "id_rsa" ".key"
)

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: $TARGET_DIR is not a directory." >&2
    exit 1
fi

# ==========================================================
# LOGGING SETUP
# ==========================================================
mkdir -p "$OUTPUT_DIR"

# 1. Timestamp: YYMMDD-HHMM
TIMESTAMP=$(date +%y%m%d-%H%M)

# 2. Mode: Uses $MODE from env (exported by tell-me.sh), defaults to 'manual'
MODE_NAME="${MODE:-manual}"

# 3. Filename: last-assist-gemini-260113-1340-dump.txt
LOG_FILE="$OUTPUT_DIR/last-${MODE_NAME}-${TIMESTAMP}-dump.txt"

# Function: File Processing (Same as before)
process_file() {
    local file="$1"
    local filename=$(basename "$file")

    case "$filename" in
        .DS_Store|*.pyc|*.lock|package-lock.json|yarn.lock|pnpm-lock.yaml) return ;;
    esac

    IS_TEXT=false
    if command -v file >/dev/null 2>&1; then
        if file --mime "$file" | grep -Eq 'text/|application/(json|xml|x-sh|x-yaml|javascript|typescript|toml)'; then
            IS_TEXT=true
        fi
    else
        case "${file,,}" in
            *.txt|*.md|*.markdown|*.sh|*.bash|*.zsh|*.yaml|*.yml|*.json|*.toml|*.ini|*.cfg|*.conf|*.xml|*.csv) IS_TEXT=true ;;
            *.py|*.js|*.jsx|*.ts|*.tsx|*.html|*.css|*.scss|*.less) IS_TEXT=true ;;
            *.c|*.cpp|*.h|*.hpp|*.go|*.rs|*.java|*.kt|*.scala|*.php|*.rb|*.pl|*.lua) IS_TEXT=true ;;
            *.sql|*.dockerfile|makefile|gemfile) IS_TEXT=true ;;
        esac
    fi

    if [ "$IS_TEXT" = true ]; then
        EXT="${file##*.}"
        [ "$EXT" == "$file" ] && EXT=""
        MAX_TICKS=$(grep -o '`\+' "$file" 2>/dev/null | awk '{ print length }' | sort -rn | head -1)
        : ${MAX_TICKS:=0}

        if [ "$MAX_TICKS" -ge 3 ]; then FENCE_LEN=$(( MAX_TICKS + 1 )); else FENCE_LEN=3; fi
        FENCE=""
        for ((i=0; i<FENCE_LEN; i++)); do FENCE="${FENCE}\`"; done

        echo -e "\n----------------------------------------------------------"
        echo "FILE: $file"
        echo "----------------------------------------------------------"
        echo "${FENCE}${EXT}"
        cat "$file"
        echo -e "\n${FENCE}"
    fi
}

# --- MAIN EXECUTION BLOCK (Captured by tee) ---
{
    echo "Current Working Directory: $(pwd)"
    echo ""

    echo "=========================================================="
    echo "PROJECT STRUCTURE"
    echo "=========================================================="

    TREE_IGNORE=$(IFS='|'; echo "${IGNORES[*]}")
    if command -v tree >/dev/null 2>&1; then
        tree -a -I "$TREE_IGNORE" "$TARGET_DIR"
    else
        find "$TARGET_DIR" -maxdepth 3 -not -path '*/.*'
    fi

    echo -e "\n=========================================================="
    echo "FILE CONTENTS"
    echo "=========================================================="

    USE_GIT=false
    if command -v git >/dev/null 2>&1 && git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        USE_GIT=true
    fi

    if [ "$USE_GIT" = true ]; then
        REGEX_IGNORE=$(IFS='|'; echo "${IGNORES[*]}")
        git -C "$TARGET_DIR" ls-files -z --cached --others --exclude-standard | \
        grep -z -vE "(^|/)($REGEX_IGNORE)(/|$)" | \
        while IFS= read -r -d '' git_file; do
            if [ "$TARGET_DIR" == "." ]; then FULL_PATH="./$git_file"; else FULL_PATH="${TARGET_DIR%/}/$git_file"; fi
            if [ -f "$FULL_PATH" ]; then process_file "$FULL_PATH"; fi
        done
    else
        PRUNE_OPTS=()
        for ignore in "${IGNORES[@]}"; do
            if [ ${#PRUNE_OPTS[@]} -gt 0 ]; then PRUNE_OPTS+=("-o"); fi
            PRUNE_OPTS+=("-name" "$ignore")
        done
        find "$TARGET_DIR" \( -type d \( "${PRUNE_OPTS[@]}" \) -prune \) -o \
            \( -type f \( -not -path '*/.*' -o -name '.gitignore' -o -name '.env.example' \) -print0 \) |
            while IFS= read -r -d '' file; do process_file "$file"; done
    fi

} | tee "$LOG_FILE"

# 1. Get raw size in bytes
BYTES=$(wc -c < "$LOG_FILE")

# 2. Estimate Tokens (1 token ~= 4 chars)
TOKENS=$((BYTES / 4))

# 3. Calculate Human Readable Size (B, KB, MB, GB)
HSIZE=$(awk -v b="$BYTES" 'BEGIN {
    split("B KB MB GB TB", units);
    u = 1;
    while(b >= 1024 && u < 5) { b/=1024; u++ }
    printf "%.2f %s", b, units[u]
}')

# 4. Print Stats to Stderr
echo -e "\n\033[0;32m[Dump saved to: $LOG_FILE]\033[0m" >&2
echo -e "\033[0;36m[Stats] Size: $HSIZE | Est. Tokens: ~$TOKENS\033[0m" >&2
