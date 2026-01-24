# Copyright (c) 2026  <gosharplite@gmail.com>
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

  # Safety check: Ensure the message has at least one part
  if ! echo "$json_content" | jq -e '.parts | length > 0' > /dev/null 2>&1; then
      echo "Warning: Attempted to append message with empty parts. Skipping." >&2
      return 0
  fi

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
        local flat_name=$(echo "$target" | sed 's/[\/\.]/_/g')
        local dest="$BACKUP_DIR/$flat_name"
        cp "$target" "$dest"
    fi
}

restore_backup() {
    local target="$1"
    local flat_name=$(echo "$target" | sed 's/[\/\.]/_/g')
    local backup_path="$BACKUP_DIR/$flat_name"
    
    if [ -f "$backup_path" ]; then
        cp "$backup_path" "$target"
        return 0
    fi
    return 1
}

# Helper: Get Timestamp for Logging
get_log_timestamp() {
    local TS=$(date +%H:%M:%S)
    printf "[%s]" "$TS"
}

# Helper: Get Duration for Logging (Now returns Timestamp as per requirement)
get_log_duration() {
    get_log_timestamp
}



