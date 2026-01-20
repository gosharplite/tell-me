tool_read_url() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    # Extract Arguments
    local FC_URL=$(echo "$FC_DATA" | jq -r '.args.url')

    echo -e "\033[0;36m[Tool Request] Reading URL: $FC_URL\033[0m"

    # Use Python to fetch and strip HTML for cleaner context
    local RESULT_MSG
    RESULT_MSG=$(python3 -c "
import sys, urllib.request, re, ssl

url = sys.argv[1]
try:
    # Handle SSL context for some environments
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, context=ctx, timeout=10) as response:
        content = response.read().decode('utf-8', errors='ignore')
        
        # Simple heuristic: if it looks like HTML, strip tags
        if '<html' in content.lower() or '<body' in content.lower():
            # Remove scripts and styles
            content = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', content, flags=re.DOTALL | re.IGNORECASE)
            # Remove tags
            text = re.sub(r'<[^>]+>', '', content)
            # Collapse whitespace
            text = re.sub(r'\n\s*\n', '\n\n', text).strip()
            print(text)
        else:
            print(content)

except Exception as e:
    print(f'Error fetching URL: {e}')
" "$FC_URL")
    
    # Truncate if too long
    local LINE_COUNT=$(echo "$RESULT_MSG" | wc -l)
    if [ "$LINE_COUNT" -gt 500 ]; then
         RESULT_MSG="$(echo "$RESULT_MSG" | head -n 500)\n\n... (Content truncated at 500 lines) ..."
    fi
    
    if [[ "$RESULT_MSG" == Error* ]]; then
         echo -e "\033[0;31m[Tool Failed] URL fetch failed.\033[0m"
    else
         echo -e "\033[0;32m[Tool Success] URL read.\033[0m"
    fi

    # Inject Warning if approaching Max Turns
    if [ "$CURRENT_TURN" -eq $((MAX_TURNS - 1)) ]; then
        local WARN_MSG=" [SYSTEM WARNING]: You have reached the tool execution limit ($MAX_TURNS/$MAX_TURNS). This is your FINAL turn. You MUST provide the final text response now."
        RESULT_MSG="${RESULT_MSG}${WARN_MSG}"
        echo -e "\033[1;31m[System] Warning sent to Model: Last turn approaching.\033[0m"
    fi

    # Construct Function Response Part
    jq -n --arg name "read_url" --rawfile content <(printf "%s" "$RESULT_MSG") \
        '{functionResponse: {name: $name, response: {result: $content}}}' > "${RESP_PARTS_FILE}.part"
    
    # Append to Array
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}