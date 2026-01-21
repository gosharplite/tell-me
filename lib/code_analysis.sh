# Requires: lib/utils.sh for check_path_safety

tool_get_file_skeleton() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Analyzing Skeleton: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG
    local DUR=""

    if [ "$IS_SAFE" == "true" ]; then
        if [ -f "$FC_PATH" ]; then
            local EXT="${FC_PATH##*.}"
            
            # --- Python Logic ---
            if [ "$EXT" == "py" ]; then
                 local PY_PARSER=$(mktemp)
                 cat << 'EOF' > "$PY_PARSER"
import ast
import sys

def get_skeleton(file_path):
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            tree = ast.parse(f.read())
    except Exception as e:
        return f"Error parsing Python file: {e}"

    lines = []
    
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            # Get the first line of the definition
            def_line = f"{type(node).__name__}: {node.name}(...)"
            
            # Decorators
            if node.decorator_list:
                def_line = f"@{len(node.decorator_list)} decorators\n" + def_line
                
            lines.append(def_line)
            
            # Docstring
            doc = ast.get_docstring(node)
            if doc:
                lines.append(f'  """{doc.splitlines()[0]}..."""')
                
            if isinstance(node, ast.ClassDef):
                 for item in node.body:
                     if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                         lines.append(f"  method: {item.name}(...)")
                         method_doc = ast.get_docstring(item)
                         if method_doc:
                             lines.append(f'    """{method_doc.splitlines()[0]}..."""')

        elif isinstance(node, ast.Assign):
            # Global variables (simple heuristic)
            if len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                lines.append(f"var: {node.targets[0].id} = ...")
                
    if not lines:
        return "No definitions found (script might be flat code)."
        
    return "\n".join(lines)

if __name__ == "__main__":
    print(get_skeleton(sys.argv[1]))
EOF
                 RESULT_MSG=$(python3 "$PY_PARSER" "$FC_PATH" 2>&1)
                 rm "$PY_PARSER"

            # --- Shell Logic ---
            elif [ "$EXT" == "sh" ] || [ "$EXT" == "bash" ]; then
                # Grep for function definitions
                RESULT_MSG=$(grep -E "^(function )?[a-zA-Z0-9_]+(\(\))? \{?" "$FC_PATH")
                if [ -z "$RESULT_MSG" ]; then RESULT_MSG="No shell functions found."; fi

            # --- Generic / JS / Go Logic (Simple Regex) ---
            else
                # Look for lines starting with 'function', 'class', 'func', 'type'
                # or lines ending with '{' that look like definitions
                RESULT_MSG=$(grep -E "^[[:space:]]*(export )?(async )?(function|class|func|type|struct|interface|const|var|let) [a-zA-Z0-9_]+" "$FC_PATH" | head -n 100)
                if [ -z "$RESULT_MSG" ]; then
                     # Fallback to reading first 20 lines if no structure found
                     RESULT_MSG="No explicit structure found. First 20 lines:\n$(head -n 20 "$FC_PATH")"
                else
                     if [ $(echo "$RESULT_MSG" | wc -l) -eq 100 ]; then
                         RESULT_MSG="${RESULT_MSG}\n... (Truncated) ..."
                     fi
                fi
            fi
            
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;32m[Tool Success] Skeleton generated.\033[0m"

        else
            RESULT_MSG="Error: File not found."
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] File not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Skeleton denied.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "get_file_skeleton" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_find_usages() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_QUERY=$(echo "$FC_DATA" | jq -r '.args.query')
    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.path // "."')
    local FC_FILE_TYPE=$(echo "$FC_DATA" | jq -r '.args.file_type // empty')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Finding usages of '$FC_QUERY' in $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG
    local DUR=""

    if [ "$IS_SAFE" == "true" ]; then
        if [ -e "$FC_PATH" ]; then
            # Build excludes
            local EXCLUDES="--exclude-dir={.git,.idea,.vscode,__pycache__,node_modules,dist,build,coverage,vendor}"
            local INCLUDES=""
            if [ -n "$FC_FILE_TYPE" ]; then
                INCLUDES="--include=*$FC_FILE_TYPE"
            fi

            # 1. Search for the word boundary match
            # 2. Filter out definitions (heuristic)
            
            # Definition patterns to exclude
            # Python: def query, class query
            # JS/TS: function query, class query, var/let/const query =
            # Go: func query, type query
            # Bash: query() {, function query
            
            local RAW_MATCHES
            # We use grep -rnI (recursive, line num, binary ignore) with word boundaries (-w)
            # We accept failure (set +e equivalent) if no matches
            RAW_MATCHES=$(grep -rnIw $INCLUDES $EXCLUDES "$FC_QUERY" "$FC_PATH" 2>/dev/null)
            
            if [ -z "$RAW_MATCHES" ]; then
                RESULT_MSG="No usages found for '$FC_QUERY'."
            else
                # Filter out definitions
                # We interpret the grep output (file:line:content)
                # We exclude lines where the query is preceded by def/class/function/func
                # or followed by () { (bash style)
                
                # Regex for definitions:
                # ^.*(def|class|function|func|type|var|let|const)[[:space:]]+QUERY
                # ^.*QUERY(\(\))?[[:space:]]*\{
                
                RESULT_MSG=$(echo "$RAW_MATCHES" | grep -vE "(:.*(def|class|function|func|type|var|let|const)[[:space:]]+${FC_QUERY}\b|:.*${FC_QUERY}(\(\))?[[:space:]]*\{)")
                
                if [ -z "$RESULT_MSG" ]; then
                     RESULT_MSG="No usages found (only definitions were found)."
                else
                     local COUNT=$(echo "$RESULT_MSG" | wc -l)
                     if [ "$COUNT" -gt 100 ]; then
                         RESULT_MSG="$(echo "$RESULT_MSG" | head -n 100)\n... (Truncated at 100 matches) ..."
                     fi
                fi
            fi
            
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;32m[Tool Success] Usages found.\033[0m"
        else
            RESULT_MSG="Error: Path does not exist."
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] Path not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Find usages denied.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "find_usages" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

tool_calculate_complexity() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local FC_PATH=$(echo "$FC_DATA" | jq -r '.args.filepath')

    local TS=$(get_log_timestamp)
    echo -e "${TS} \033[0;36m[Tool Request] Calculating Complexity: $FC_PATH\033[0m"

    local IS_SAFE=$(check_path_safety "$FC_PATH")
    local RESULT_MSG
    local DUR=""

    if [ "$IS_SAFE" == "true" ]; then
        if [ -f "$FC_PATH" ]; then
             local EXT="${FC_PATH##*.}"
             
             if [ "$EXT" == "py" ]; then
                 local PY_PARSER=$(mktemp)
                 cat << 'EOF' > "$PY_PARSER"
import ast
import sys

class ComplexityVisitor(ast.NodeVisitor):
    def __init__(self):
        self.functions = []

    def visit_FunctionDef(self, node):
        complexity = 1
        for child in ast.walk(node):
            if isinstance(child, (ast.If, ast.For, ast.While, ast.With, ast.Try, ast.ExceptHandler)):
                complexity += 1
            elif isinstance(child, ast.BoolOp):
                complexity += len(child.values) - 1
        
        self.functions.append((node.name, complexity))
        self.generic_visit(node)

def analyze(file_path):
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            tree = ast.parse(f.read())
        visitor = ComplexityVisitor()
        visitor.visit(tree)
        
        # Sort by complexity descending
        visitor.functions.sort(key=lambda x: x[1], reverse=True)
        
        res = []
        for name, score in visitor.functions:
            res.append(f"{name}: {score}")
            
        if not res:
            return "No functions found."
        return "\n".join(res)
    except Exception as e:
        return f"Error parsing Python file: {e}"

if __name__ == "__main__":
    print(analyze(sys.argv[1]))
EOF
                 RESULT_MSG=$(python3 "$PY_PARSER" "$FC_PATH" 2>&1)
                 rm "$PY_PARSER"
             
             elif [ "$EXT" == "sh" ] || [ "$EXT" == "bash" ]; then
                 # Simple bash complexity: Count if/for/while/case inside functions
                 # This is a rough heuristic
                 RESULT_MSG=$(grep -rnE "^(function )?[a-zA-Z0-9_]+(\(\))? \{?|if |for |while |case " "$FC_PATH")
                 
                 # It's hard to parse scope with grep. 
                 # Let's count keywords per file as a proxy, or just dump the raw stats.
                 local COUNT_IF=$(grep -c "if " "$FC_PATH")
                 local COUNT_FOR=$(grep -c "for " "$FC_PATH")
                 local COUNT_WHILE=$(grep -c "while " "$FC_PATH")
                 local COUNT_CASE=$(grep -c "case " "$FC_PATH")
                 local TOTAL_SCORE=$((COUNT_IF + COUNT_FOR + COUNT_WHILE + COUNT_CASE))
                 
                 RESULT_MSG="Bash Complexity (Whole File Score):\nTotal Score: $TOTAL_SCORE\n(If: $COUNT_IF, For: $COUNT_FOR, While: $COUNT_WHILE, Case: $COUNT_CASE)\nNote: Per-function analysis requires more advanced parsing."
             else
                 RESULT_MSG="Complexity analysis not supported for this file type."
             fi
             
             DUR=$(get_log_duration)
             echo -e "${DUR} \033[0;32m[Tool Success] Complexity calculated.\033[0m"
        else
            RESULT_MSG="Error: File not found."
            DUR=$(get_log_duration)
            echo -e "${DUR} \033[0;31m[Tool Failed] File not found.\033[0m"
        fi
    else
        RESULT_MSG="Error: Security violation."
        DUR=$(get_log_duration)
        echo -e "${DUR} \033[0;31m[Tool Security Block] Complexity denied.\033[0m"
    fi

    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        RESULT_MSG="${RESULT_MSG} [SYSTEM WARNING]: Last turn approaching."
    fi

    jq -n --arg name "calculate_complexity" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}
