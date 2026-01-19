#!/bin/bash
# Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
# SPDX-License-Identifier: MIT

# Resolve Script Directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check Dependencies
for cmd in jq curl gcloud awk python3; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is missing." >&2
        exit 1
    fi
done

# Helper function to append messages to history safely
update_history() {
  local json_content="$1"
  local item_file=$(mktemp)
  printf "%s" "$json_content" > "$item_file"
  
  if [ -s "$file" ] && jq empty "$file" > /dev/null 2>&1; then
    if ! jq --slurpfile item "$item_file" '.messages += $item' "$file" > "${file}.tmp"; then
        echo "Error: Failed to process history file." >&2
        rm "$item_file"
        exit 1
    fi
    mv "${file}.tmp" "$file"
  else
    jq -n --slurpfile item "$item_file" '{messages: $item}' > "$file"
  fi
  rm "$item_file"
}

# 1. Update Conversation History (User Input)
PROMPT_TEXT="$1"
STDIN_DATA=""

if [ ! -t 0 ]; then
    STDIN_DATA="$(cat)"
fi

if [ -n "$STDIN_DATA" ]; then
    MSG_TEXT="${PROMPT_TEXT}\n\n${STDIN_DATA}"
elif [ -n "$PROMPT_TEXT" ]; then
    MSG_TEXT="$PROMPT_TEXT"
else
    MSG_TEXT="$DATA"
    echo "Usage: a \"Your message\" or pipe content via stdin" >&2
    exit 1
fi

USER_MSG=$(printf "%s" "$MSG_TEXT" | jq -Rs '{role: "user", parts: [{text: .}]}')
update_history "$USER_MSG"

# 2. Configure Tools & Auth
# --- Tool Definitions ---
read -r -d '' FUNC_DECLARATIONS <<EOM
[
  {
    "name": "ask_user",
    "description": "Asks the user a specific question to clarify requirements or request confirmation. Use this when you need input before proceeding.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "question": {
          "type": "STRING",
          "description": "The question to ask the user."
        }
      },
      "required": ["question"]
    }
  },
  {
    "name": "update_file",
    "description": "Overwrites a specific file with new content. Use this to save code or text to a file.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "filepath": {
          "type": "STRING",
          "description": "The path to the file to write (e.g., ./README.md)"
        },
        "content": {
          "type": "STRING",
          "description": "The full text content to write into the file"
        }
      },
      "required": ["filepath", "content"]
    }
  },
  {
    "name": "replace_text",
    "description": "Replaces a specific text block in a file with new content. Replaces only the first occurrence found.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "filepath": {
          "type": "STRING",
          "description": "The path to the file to edit."
        },
        "old_text": {
          "type": "STRING",
          "description": "The exact text block to find and replace."
        },
        "new_text": {
          "type": "STRING",
          "description": "The new text to insert."
        }
      },
      "required": ["filepath", "old_text", "new_text"]
    }
  },
  {
    "name": "move_file",
    "description": "Moves or renames a file or directory. Source and destination must be within the current working directory.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "source_path": {
          "type": "STRING",
          "description": "The path to the file or directory to move."
        },
        "dest_path": {
          "type": "STRING",
          "description": "The destination path."
        }
      },
      "required": ["source_path", "dest_path"]
    }
  },
  {
    "name": "list_files",
    "description": "Lists files and directories in the specified path. Use this to explore the file system structure.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "path": {
          "type": "STRING",
          "description": "The directory path to list (defaults to current directory '.')",
          "default": "."
        }
      },
      "required": ["path"]
    }
  },
  {
    "name": "read_file",
    "description": "Reads the content of a specific file. Use this to inspect code or configs before editing them.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "filepath": {
          "type": "STRING",
          "description": "The path to the file to read (e.g., ./src/main.py)"
        }
      },
      "required": ["filepath"]
    }
  },
  {
    "name": "search_files",
    "description": "Searches for a text pattern in files within a directory. Use this to find code usage or definitions.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "query": {
          "type": "STRING",
          "description": "The string or regex to search for."
        },
        "path": {
          "type": "STRING",
          "description": "The directory to search (defaults to '.')",
          "default": "."
        }
      },
      "required": ["query"]
    }
  },
  {
    "name": "get_tree",
    "description": "Returns a visual directory tree structure. Respects standard ignore rules (node_modules, .git, etc). Use this to understand project architecture.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "path": {
          "type": "STRING",
          "description": "The directory path to list (defaults to current directory '.')",
          "default": "."
        },
        "max_depth": {
          "type": "INTEGER",
          "description": "Depth of the tree (default 2)",
          "default": 2
        }
      },
      "required": ["path"]
    }
  },
  {
    "name": "execute_command",
    "description": "Executes a shell command. Use this to run tests, list complex directories, or check system status. Commands are executed in the current shell environment.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "command": {
          "type": "STRING",
          "description": "The shell command to execute (e.g., 'ls -la', 'python3 main.py')."
        }
      },
      "required": ["command"]
    }
  },
  {
    "name": "get_git_diff",
    "description": "Retrieves the git diff of the current repository.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "staged": {
          "type": "BOOLEAN",
          "description": "If true, shows staged changes.",
          "default": false
        }
      }
    }
  }
]
EOM

if [ "$USE_SEARCH" == "true" ]; then
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "googleSearch": {} }, { "functionDeclarations": $funcs }]')
else
    TOOLS_JSON=$(jq -n --argjson funcs "$FUNC_DECLARATIONS" '[{ "functionDeclarations": $funcs }]')
fi

# --- Auth Setup ---
if [[ "$AIURL" == *"aiplatform.googleapis.com"* ]]; then
    TARGET_SCOPE="https://www.googleapis.com/auth/cloud-platform"
    CACHE_SUFFIX="vertex"
    FUNC_ROLE="function"
else
    TARGET_SCOPE="https://www.googleapis.com/auth/generative-language"
    CACHE_SUFFIX="studio"
    FUNC_ROLE="function"
fi

TOKEN_CACHE="${TMPDIR:-/tmp}/gemini_token_${CACHE_SUFFIX}.txt"

get_file_mtime() {
    if [[ "$OSTYPE" == "darwin"* ]]; then stat -f %m "$1"; else stat -c %Y "$1"; fi
}

if [ -f "$TOKEN_CACHE" ]; then
    NOW=$(date +%s)
    LAST_MOD=$(get_file_mtime "$TOKEN_CACHE")
    if [ $((NOW - LAST_MOD)) -lt 3300 ]; then TOKEN=$(cat "$TOKEN_CACHE"); fi
fi

if [ -z "$TOKEN" ]; then
    if [ -n "$KEY_FILE" ] && [ -f "$KEY_FILE" ]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$KEY_FILE"
        TOKEN=$(gcloud auth application-default print-access-token --scopes="${TARGET_SCOPE}")
    else
        TOKEN=$(gcloud auth print-access-token --scopes="${TARGET_SCOPE}")
    fi
    echo "$TOKEN" > "$TOKEN_CACHE"
fi

# ==============================================================================
# MAIN INTERACTION LOOP
# Handles multi-turn interactions (Tool Call -> Execution -> Tool Response)
# ==============================================================================

MAX_TURNS=15
CURRENT_TURN=0
FINAL_TEXT_RESPONSE=""

START_TIME=$(date +%s.%N)

while [ $CURRENT_TURN -lt $MAX_TURNS ]; do
    CURRENT_TURN=$((CURRENT_TURN + 1))

    # 3. Build API Payload (reads current history from file)
    APIDATA=$(jq -n \
      --arg person "$PERSON" \
      --argjson tools "$TOOLS_JSON" \
      --slurpfile history "$file" \
      '{
        contents: $history[0].messages,
        tools: $tools,
        generationConfig: { 
            temperature: 1.0 
            # thinkingConfig removed for compatibility
        },
        safetySettings: [
          { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" }
        ]
      } + 
      (if $person != "" then { systemInstruction: { role: "system", parts: [{text: $person}] } } else {} end)'
    )

    PAYLOAD_FILE=$(mktemp) || exit 1
    echo "$APIDATA" > "$PAYLOAD_FILE"

    # 4. Call API
    RESPONSE_JSON=$(curl -s "${AIURL}/${AIMODEL}:generateContent" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TOKEN" \
      -d @"$PAYLOAD_FILE")
    
    rm "$PAYLOAD_FILE"

    # Basic Validation
    if echo "$RESPONSE_JSON" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "\033[31mAPI Error:\033[0m $(echo "$RESPONSE_JSON" | jq -r '.error.message')"
        exit 1
    fi

    CANDIDATE=$(echo "$RESPONSE_JSON" | jq -c '.candidates[0].content')
    
    # 5. Check for Function Call(s)
    # Gemini may return multiple function calls in one turn (parallel calling).
    # We must identify if ANY part is a function call.
    HAS_FUNC=$(echo "$CANDIDATE" | jq -e '.parts[] | has("functionCall")' >/dev/null 2>&1 && echo "yes" || echo "no")

    if [ "$HAS_FUNC" == "yes" ]; then
        # --- Handle Tool Execution (Parallel Compatible) ---
        
        # 1. Update History with the Model's Request (The Function Call)
        update_history "$CANDIDATE"

        # 2. Iterate over parts to execute calls and build responses
        RESP_PARTS_FILE=$(mktemp)
        echo "[]" > "$RESP_PARTS_FILE"
        
        PART_COUNT=$(echo "$CANDIDATE" | jq '.parts | length')

        for (( i=0; i<$PART_COUNT; i++ )); do
            FC_DATA=$(echo "$CANDIDATE" | jq -c ".parts[$i].functionCall // empty")
            
            if [ -n "$FC_DATA" ]; then
                F_NAME=$(echo "$FC_DATA" | jq -r '.name')

                if [ "$F_NAME" == "ask_user" ]; then
                    # Extract Arguments
                    FC_QUESTION=$(echo "$FC_DATA" | jq -r '.args.question')

                    echo -e "\033[1;35m[AI Question] $FC_QUESTION\033[0m"

                    # Read user input directly from TTY
                    if [ -t 0 ]; then
                        read -e -p "Answer > " USER_ANSWER
                    else
                         read -e -p "Answer > " USER_ANSWER < /dev/tty
                    fi
                    
                    RESULT_MSG="$USER_ANSWER"
                    echo -e "\033[0;32m[User Answered]\033[0m"

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "ask_user" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                
                elif [ "$F_NAME" == "update_file" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
                    FC_CONTENT=$(echo "$FC_DATA" | jq -r '.args.content')

                    echo -e "\033[0;36m[Tool Request] Writing to file: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        mkdir -p "$(dirname "$FC_PATH")"
                        printf "%s" "$FC_CONTENT" > "$FC_PATH"
                        if [ $? -eq 0 ]; then
                            RESULT_MSG="File updated successfully."
                            echo -e "\033[0;32m[Tool Success] File updated.\033[0m"
                        else
                            RESULT_MSG="Error: Failed to write file."
                            echo -e "\033[0;31m[Tool Failed] Could not write file.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Write path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Write denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "update_file" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "replace_text" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')
                    FC_OLD=$(echo "$FC_DATA" | jq -r '.args.old_text')
                    FC_NEW=$(echo "$FC_DATA" | jq -r '.args.new_text')

                    echo -e "\033[0;36m[Tool Request] Replacing text in: $FC_PATH\033[0m"

                    # Security Check
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -f "$FC_PATH" ]; then
                            # Use Python for safe replacement (Surgical: 1st occurrence only)
                            export PYTHON_OLD="$FC_OLD"
                            export PYTHON_NEW="$FC_NEW"
                            export PYTHON_PATH="$FC_PATH"
                            
                            python3 -c '
import os, sys

path = os.environ["PYTHON_PATH"]
old = os.environ["PYTHON_OLD"]
new = os.environ["PYTHON_NEW"]

try:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    
    if old not in content:
        print("Error: old_text not found in file.")
        sys.exit(1)
        
    new_content = content.replace(old, new, 1)
    
    with open(path, "w", encoding="utf-8") as f:
        f.write(new_content)
    
    print("Success: Text replaced.")
except Exception as e:
    print(f"Error: {str(e)}")
    sys.exit(1)
' > "${RESP_PARTS_FILE}.py_out" 2>&1
                            
                            PY_EXIT=$?
                            RESULT_MSG=$(cat "${RESP_PARTS_FILE}.py_out")
                            rm "${RESP_PARTS_FILE}.py_out"
                            
                            if [ $PY_EXIT -eq 0 ]; then
                                echo -e "\033[0;32m[Tool Success] $RESULT_MSG\033[0m"
                            else
                                echo -e "\033[0;31m[Tool Failed] $RESULT_MSG\033[0m"
                            fi
                        else
                             RESULT_MSG="Error: File not found."
                             echo -e "\033[0;31m[Tool Failed] File not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Edit path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Edit denied: $FC_PATH\033[0m"
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    jq -n --arg name "replace_text" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "move_file" ]; then
                    # Extract Arguments
                    FC_SRC=$(echo "$FC_DATA" | jq -r '.args.source_path')
                    FC_DEST=$(echo "$FC_DATA" | jq -r '.args.dest_path')

                    echo -e "\033[0;36m[Tool Request] Moving: $FC_SRC -> $FC_DEST\033[0m"

                    # Security Check: Ensure BOTH paths are within CWD
                    IS_SAFE=false
                    SAFE_SRC=false
                    SAFE_DEST=false
                    
                    # Check Source
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_SRC")
                        [ "$REL_CHECK" == "True" ] && SAFE_SRC=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_SRC")" == "$(pwd -P)"* ] && SAFE_SRC=true
                    else
                        if [[ "$FC_SRC" != /* && "$FC_SRC" != *".."* ]]; then SAFE_SRC=true; fi
                    fi
                    
                    # Check Dest
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_DEST")
                        [ "$REL_CHECK" == "True" ] && SAFE_DEST=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_DEST")" == "$(pwd -P)"* ] && SAFE_DEST=true
                    else
                        if [[ "$FC_DEST" != /* && "$FC_DEST" != *".."* ]]; then SAFE_DEST=true; fi
                    fi

                    if [ "$SAFE_SRC" = true ] && [ "$SAFE_DEST" = true ]; then
                        if [ -e "$FC_SRC" ]; then
                            # Ensure dest directory exists if it looks like a directory path
                            DEST_DIR=$(dirname "$FC_DEST")
                            if [ ! -d "$DEST_DIR" ]; then
                                mkdir -p "$DEST_DIR"
                            fi

                            mv "$FC_SRC" "$FC_DEST" 2>&1
                            if [ $? -eq 0 ]; then
                                RESULT_MSG="Success: Moved $FC_SRC to $FC_DEST"
                                echo -e "\033[0;32m[Tool Success] File moved.\033[0m"
                            else
                                RESULT_MSG="Error: Failed to move file."
                                echo -e "\033[0;31m[Tool Failed] Move failed.\033[0m"
                            fi
                        else
                             RESULT_MSG="Error: Source path does not exist."
                             echo -e "\033[0;31m[Tool Failed] Source not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Source and Destination must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Move denied.\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "move_file" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "list_files" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')

                    echo -e "\033[0;36m[Tool Request] Listing: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD (Reuse existing logic)
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -e "$FC_PATH" ]; then
                            # Run ls -F (adds / to dirs, * to executables)
                            RESULT_MSG=$(ls -F "$FC_PATH" 2>&1)
                            echo -e "\033[0;32m[Tool Success] Directory listed.\033[0m"
                        else
                            RESULT_MSG="Error: Path does not exist."
                            echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] List denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "list_files" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                
                elif [ "$F_NAME" == "read_file" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

                    echo -e "\033[0;36m[Tool Request] Reading: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -f "$FC_PATH" ]; then
                            # Read file content
                            # Limit size to prevent token explosion (e.g., 500 lines)
                            LINE_COUNT=$(wc -l < "$FC_PATH")
                            if [ "$LINE_COUNT" -gt 500 ]; then
                                RESULT_MSG=$(head -n 500 "$FC_PATH")
                                RESULT_MSG="${RESULT_MSG}\n\n... (File truncated at 500 lines) ..."
                            else
                                RESULT_MSG=$(cat "$FC_PATH")
                            fi
                            echo -e "\033[0;32m[Tool Success] File read.\033[0m"
                        else
                            RESULT_MSG="Error: File not found."
                            echo -e "\033[0;31m[Tool Failed] File not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Read denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "read_file" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "search_files" ]; then
                    # Extract Arguments
                    FC_QUERY=$(echo "$FC_DATA" | jq -r '.args.query')
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')

                    echo -e "\033[0;36m[Tool Request] Searching for \"$FC_QUERY\" in: $FC_PATH\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -e "$FC_PATH" ]; then
                            # Grep: recursive, line numbers, binary ignored
                            # Limit to first 50 lines to prevent token explosion
                            RESULT_MSG=$(grep -rnI "$FC_QUERY" "$FC_PATH" 2>/dev/null | head -n 50)
                            
                            if [ -z "$RESULT_MSG" ]; then
                                RESULT_MSG="No matches found."
                            elif [ $(echo "$RESULT_MSG" | wc -l) -eq 50 ]; then
                                RESULT_MSG="${RESULT_MSG}\n... (Matches truncated at 50 lines) ..."
                            fi
                            echo -e "\033[0;32m[Tool Success] Search complete.\033[0m"
                        else
                            RESULT_MSG="Error: Path does not exist."
                            echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Search denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "search_files" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "get_tree" ]; then
                    # Extract Arguments
                    FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')
                    FC_DEPTH=$(echo "$FC_DATA" | jq -r '.args.max_depth // 2')

                    echo -e "\033[0;36m[Tool Request] Generating Tree: $FC_PATH (Depth: $FC_DEPTH)\033[0m"

                    # Security Check: Ensure path is within CWD
                    IS_SAFE=false
                    if command -v python3 >/dev/null 2>&1; then
                        REL_CHECK=$(python3 -c "import os, sys; print(os.path.abspath(sys.argv[1]).startswith(os.getcwd()))" "$FC_PATH")
                        [ "$REL_CHECK" == "True" ] && IS_SAFE=true
                    elif command -v realpath >/dev/null 2>&1; then
                        [ "$(realpath -m "$FC_PATH")" == "$(pwd -P)"* ] && IS_SAFE=true
                    else
                        if [[ "$FC_PATH" != /* && "$FC_PATH" != *".."* ]]; then IS_SAFE=true; fi
                    fi

                    if [ "$IS_SAFE" = true ]; then
                        if [ -d "$FC_PATH" ]; then
                            IGNORES="node_modules|.git|.idea|.vscode|__pycache__|output|dist|build|coverage|target|vendor|.DS_Store"
                            
                            if command -v tree >/dev/null 2>&1; then
                                RESULT_MSG=$(tree -a -L "$FC_DEPTH" -I "$IGNORES" "$FC_PATH")
                            else
                                # Fallback to find
                                RESULT_MSG=$(find "$FC_PATH" -maxdepth "$FC_DEPTH" -not -path '*/.*' -not -path "*node_modules*" -not -path "*output*" -not -path "*dist*" -not -path "*build*" | sort)
                            fi
                            echo -e "\033[0;32m[Tool Success] Tree generated.\033[0m"
                        else
                            RESULT_MSG="Error: Path is not a directory."
                            echo -e "\033[0;31m[Tool Failed] Path not found.\033[0m"
                        fi
                    else
                        RESULT_MSG="Error: Security violation. Path must be within current working directory."
                        echo -e "\033[0;31m[Tool Security Block] Tree denied: $FC_PATH\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "get_tree" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "get_git_diff" ]; then
                    FC_STAGED=$(echo "$FC_DATA" | jq -r '.args.staged // false')
                    echo -e "\033[0;36m[Tool Request] Git Diff (Staged: $FC_STAGED)\033[0m"

                    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                        [ "$FC_STAGED" == "true" ] && RESULT_MSG=$(git diff --cached 2>&1) || RESULT_MSG=$(git diff 2>&1)
                        [ -z "$RESULT_MSG" ] && RESULT_MSG="No changes found."
                        LINE_COUNT=$(echo "$RESULT_MSG" | wc -l)
                        [ "$LINE_COUNT" -gt 200 ] && RESULT_MSG="$(echo "$RESULT_MSG" | head -n 200)\n... (Truncated) ..."
                        echo -e "\033[0;32m[Tool Success] Git diff retrieved.\033[0m"
                    else
                        RESULT_MSG="Error: Not a git repo or git missing."
                        echo -e "\033[0;31m[Tool Failed] Git Error.\033[0m"
                    fi

                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn."
                    fi

                    jq -n --arg name "get_git_diff" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"

                elif [ "$F_NAME" == "execute_command" ]; then
                    # Extract Arguments
                    FC_CMD=$(echo "$FC_DATA" | jq -r '.args.command')

                    echo -e "\033[0;36m[Tool Request] Execute Command: $FC_CMD\033[0m"

                    # Safety: Ask for confirmation
                    CONFIRM="n"
                    if [ -t 0 ]; then
                        # Interactive mode: Ask user
                        # We use /dev/tty to ensure we read from keyboard even if stdin was piped initially
                        read -p "⚠️  Execute this command? (y/N) " -n 1 -r CONFIRM < /dev/tty
                        echo "" 
                    else
                        echo "Non-interactive mode: Auto-denying command execution."
                    fi

                    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                        # Execute and capture stdout + stderr
                        CMD_OUTPUT=$(eval "$FC_CMD" 2>&1)
                        EXIT_CODE=$?
                        
                        # Truncate if too long (100 lines)
                        LINE_COUNT=$(echo "$CMD_OUTPUT" | wc -l)
                        if [ "$LINE_COUNT" -gt 100 ]; then
                            CMD_OUTPUT="$(echo "$CMD_OUTPUT" | head -n 100)\n... (Output truncated at 100 lines) ..."
                        fi

                        if [ $EXIT_CODE -eq 0 ]; then
                            RESULT_MSG="Exit Code: 0\nOutput:\n$CMD_OUTPUT"
                            echo -e "\033[0;32m[Tool Success] Command executed.\033[0m"
                        else
                            RESULT_MSG="Exit Code: $EXIT_CODE\nError/Output:\n$CMD_OUTPUT"
                            echo -e "\033[0;31m[Tool Failed] Command returned non-zero exit code.\033[0m"
                        fi
                    else
                        RESULT_MSG="User denied execution of command: $FC_CMD"
                        echo -e "\033[0;33m[Tool Skipped] Execution denied.\033[0m"
                    fi

                    # Inject Warning if approaching Max Turns
                    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
                        WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
                        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
                        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
                    fi

                    # Construct Function Response Part
                    jq -n --arg name "execute_command" --arg content "$RESULT_MSG" \
                        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
                    
                    # Append to Array
                    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
                    rm "${RESP_PARTS_FILE}.part"
                fi
            fi
        done

        # 3. Construct Full Tool Response
        TOOL_RESPONSE=$(jq -n --arg role "$FUNC_ROLE" --slurpfile parts "$RESP_PARTS_FILE" '{ role: $role, parts: $parts[0] }')
        rm "$RESP_PARTS_FILE"
        
        # 4. Update History with Tool Result
        update_history "$TOOL_RESPONSE"

        # Loop continues to send this result back to the model...
        continue

    else
        # --- Handle Text Response (Final Answer) ---
        FINAL_TEXT_RESPONSE="$RESPONSE_JSON"
        update_history "$CANDIDATE"
        break
    fi
done

END_TIME=$(date +%s.%N)
DURATION=$(awk -v start="$START_TIME" -v end="$END_TIME" 'BEGIN { print end - start }')

# 6. Render Output
# Use the final JSON response for Recap and Stats
# Note: Recap reads from the *file* history, but we want to render the last message.
RECAP_OUT=$(mktemp)
"$BASE_DIR/recap.sh" -l > "$RECAP_OUT"
LINE_COUNT=$(wc -l < "$RECAP_OUT")

if [ "$LINE_COUNT" -gt 20 ]; then
    head -n 10 "$RECAP_OUT"
    echo -e "\n\033[1;30m... (Content Snipped) ...\033[0m\n"
    tail -n 5 "$RECAP_OUT"
else
    cat "$RECAP_OUT"
fi
rm "$RECAP_OUT"

# 7. Grounding Detection
SEARCH_COUNT=$(echo "$FINAL_TEXT_RESPONSE" | jq -r '(.candidates[0].groundingMetadata.webSearchQueries // []) | length')
if [ "$SEARCH_COUNT" -gt 0 ]; then
    echo -e "\033[0;33m[Grounding] Performed $SEARCH_COUNT Google Search(es):\033[0m"
    echo "$FINAL_TEXT_RESPONSE" | jq -r '.candidates[0].groundingMetadata.webSearchQueries[]' | while read -r query; do
            echo -e "  \033[0;33m> \"$query\"\033[0m"
    done
fi

printf "\033[0;35m[Response Time] %.2f seconds\033[0m\n" "$DURATION"

# 8. Stats & Metrics
read -r HIT PROMPT_TOTAL COMPLETION TOTAL <<< $(echo "$FINAL_TEXT_RESPONSE" | jq -r '
  .usageMetadata | 
  (.cachedContentTokenCount // 0), 
  (.promptTokenCount // 0), 
  (.candidatesTokenCount // .completionTokenCount // 0), 
  (.totalTokenCount // 0)
' | xargs)

MISS=$(( PROMPT_TOTAL - HIT ))
NEWTOKEN=$(( MISS + COMPLETION ))

if [ "$TOTAL" -gt 0 ]; then PERCENT=$(( ($NEWTOKEN * 100) / $TOTAL )); else PERCENT=0; fi

LOG_FILE="${file}.log"
STATS_MSG=$(printf "[%s] H: %d M: %d C: %d T: %d N: %d(%d%%) S: %d [%.2fs]" \
  "$(date +%H:%M:%S)" "$HIT" "$MISS" "$COMPLETION" "$TOTAL" "$NEWTOKEN" "$PERCENT" "$SEARCH_COUNT" "$DURATION")
echo "$STATS_MSG" >> "$LOG_FILE"

if [ -f "$LOG_FILE" ]; then
    echo -e "\033[0;36m--- Usage History ---\033[0m"
    tail -n 3 "$LOG_FILE"
    echo ""
    awk '{ gsub(/\./, ""); h+=$3; m+=$5; c+=$7; t+=$9; s+=$13 } END { printf "\033[0;34m[Session Total]\033[0m Hit: %d | Miss: %d | Comp: %d | \033[1mTotal: %d\033[0m | Search: %d\n", h, m, c, t, s }' "$LOG_FILE"
fi

# Backup History
if [ -f "${file}" ]; then
    TIMESTAMP=$(date -u "+%y%m%d-%H")$(printf "%02d" $(( (10#$(date -u "+%M") / 10) * 10 )) )
    cp "$file" "${file%.*}-${TIMESTAMP}-trace.${file##*.}"
fi