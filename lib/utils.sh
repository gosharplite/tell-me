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