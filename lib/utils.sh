# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Helper: Check path safety (must be within CWD)
# Returns "true" or "false"
check_path_safety() {
    local CHECK_PATH="$1"
    local IS_SAFE="false"
    
    if command -v python3 >/dev/null 2>&1; then
        local REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$CHECK_PATH")
        [ "$REL_CHECK" == "True" ] && IS_SAFE="true"
    elif command -v realpath >/dev/null 2>&1; then
        [ "$(realpath -m "$CHECK_PATH")" == "$(pwd -P)"* ] && IS_SAFE="true"
    else
        # Fallback: simple string check (imperfect)
        if [[ "$CHECK_PATH" != /* && "$CHECK_PATH" != *".."* ]]; then IS_SAFE="true"; fi
    fi
    echo "$IS_SAFE"
}

# Helper: Append to JSON array file safely
update_history_file() {
  local json_content="$1"
  local target_file="$2"
  local item_file=$(mktemp)
  printf "%s" "$json_content" > "$item_file"
  
  if [ -s "$target_file" ] && jq empty "$target_file" > /dev/null 2>&1; then
    if ! jq --slurpfile item "$item_file" '.messages += $item' "$target_file" > "${target_file}.tmp"; then
        echo "Error: Failed to process history file." >&2
        rm "$item_file"
        return 1
    fi
    mv "${target_file}.tmp" "$target_file"
  else
    jq -n --slurpfile item "$item_file" '{messages: $item}' > "$target_file"
  fi
  rm "$item_file"
}

# Helper: Shadow Backup Logic
BACKUP_DIR="${TMPDIR:-/tmp}/tellme_backups"
# Prune backups older than 24 hours
mkdir -p "$BACKUP_DIR"
find "$BACKUP_DIR" -type f -mtime +1 -delete 2>/dev/null

backup_file() {
    local target="$1"
    if [ -f "$target" ]; then
        # Create a flat filename (e.g. ./src/main.py -> _src_main.py)
        local flat_name=$(echo "$target" | sed 's/[\/\.]/_/g')
        cp "$target" "$BACKUP_DIR/$flat_name"
    fi
}

restore_backup() {
    local target="$1"
    local flat_name=$(echo "$target" | sed 's/[\/\.]/_/g')
    local backup_path="$BACKUP_DIR/$flat_name"
    
    if [ -f "$backup_path" ]; then
        cp "$backup_path" "$target"
        return 0
    else
        return 1
    fi
}

# Helper: Get Timestamp for Logging
get_log_timestamp() {
    local TS=$(date +%H:%M:%S)
    printf "[%s]" "$TS"
}

# Helper: Get Duration for Logging
get_log_duration() {
    local DUR_MSG="0.00s"
    # Calculate Duration if START_TIME is set
    if [ -n "$START_TIME" ]; then
        local NOW=$(date +%s.%N)
        local DUR=$(awk -v start="$START_TIME" -v end="$NOW" 'BEGIN { print end - start }')
        DUR_MSG=$(printf "%.2fs" "$DUR")
    fi
    printf "[%s]" "$DUR_MSG"
}

# Helper: Display Media File (Image/Video) in Terminal or External Viewer
display_media_file() {
    local FILEPATH="$1"
    
    if [ ! -f "$FILEPATH" ]; then
        return
    fi
    
    local MIMETYPE=""
    if command -v file >/dev/null 2>&1; then
        MIMETYPE=$(file --mime-type -b "$FILEPATH")
    else
        # Fallback extension check
        if [[ "$FILEPATH" == *.png || "$FILEPATH" == *.jpg || "$FILEPATH" == *.jpeg ]]; then MIMETYPE="image/png"; fi
        if [[ "$FILEPATH" == *.mp4 ]]; then MIMETYPE="video/mp4"; fi
    fi
    
    if [[ "$MIMETYPE" == image/* ]]; then
        # Try iTerm2 imgcat
        if [ "$TERM_PROGRAM" == "iTerm.app" ] && command -v imgcat >/dev/null 2>&1; then
             echo -e "\033[0;33m[Viewer] Displaying image inline (iTerm2)...\033[0m"
             imgcat "$FILEPATH"
             return
        fi
        
        # Try Chafa (Sixel/Unicode)
        if command -v chafa >/dev/null 2>&1; then
             echo -e "\033[0;33m[Viewer] Displaying image inline (chafa)...\033[0m"
             chafa "$FILEPATH"
             return
        fi
    fi
    
    # Fallback to External Viewer (Open/XDG-Open) for both Image and Video
    if command -v open >/dev/null 2>&1; then
        echo -e "\033[0;33m[Viewer] Opening externally...\033[0m"
        open "$FILEPATH"
    elif command -v xdg-open >/dev/null 2>&1; then
        echo -e "\033[0;33m[Viewer] Opening externally...\033[0m"
        xdg-open "$FILEPATH" > /dev/null 2>&1
    else
        echo -e "\033[0;33m[Viewer] No suitable viewer found. Saved at $FILEPATH\033[0m"
    fi
}

