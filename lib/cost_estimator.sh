tool_estimate_cost() {
    local FC_DATA="$1"
    local RESP_PARTS_FILE="$2"

    local log_file="${file}.log"
    if [[ ! -f "$log_file" ]]; then
        local RESULT="Error: Log file not found at $log_file"
    else
        # Use Python for precise line-by-line cost calculation
        local CALC_OUT=$(python3 -c "
import sys
model = sys.argv[1]
log_path = sys.argv[2]
total_cost = 0.0
total_h, total_m, total_c, total_s, total_th = 0, 0, 0, 0, 0

try:
    with open(log_path, 'r') as f:
        for line in f:
            parts = line.split()
            if len(parts) < 15: continue
            try:
                # [Time] H: 0 M: 45201 C: 217 T: 46102 N: 45418(98%) S: 1 Th: 1540 [13.5s]
                h = int(parts[2])
                m = int(parts[4])
                c = int(parts[6])
                s = int(parts[12])
                th = int(parts[14])
            except: continue
            
            total_h += h; total_m += m; total_c += c; total_s += s; total_th += th
            
            # Rate determination based on model and context window
            if 'gemini-3-pro' in model:
                rh, rm, rc = 0.20, 2.00, 12.00
                if (h + m) > 200000:
                    rm, rc = 4.00, 18.00
                total_cost += (h * rh / 1e6) + (m * rm / 1e6) + ((c + th) * rc / 1e6)
            elif 'gemini-3-flash' in model:
                total_cost += (h * 0.05 / 1e6) + (m * 0.50 / 1e6) + ((c + th) * 3.00 / 1e6)
            else: # Fallback to 1.5 Pro standard rates
                rh, rm, rc = 0.3125, 1.25, 3.75
                if (h + m) > 128000:
                    rm, rc = 2.50, 7.50
                total_cost += (h * rh / 1e6) + (m * rm / 1e6) + ((c + th) * rc / 1e6)
            
            # Grounding cost (Search)
            total_cost += s * 0.014
            
    print(f'{total_h}|{total_m}|{total_c}|{total_s}|{total_th}|{total_cost:.6f}')
except Exception as e:
    print(f'Error: {e}')
" "$AIMODEL" "$log_file")

        if [[ "$CALC_OUT" == Error* ]]; then
            local RESULT="Calculation $CALC_OUT"
        else
            IFS='|' read -r hit miss completion search thinking total_cost <<< "$CALC_OUT"
            local RESULT=$(printf "Estimated Cost for Session (%s):\n- Model: %s\n- Tokens: Hit: %'d, Miss: %'d, Comp: %'d, Thinking: %'d\n- Search Queries: %d\n- Total Cost: \$%.4f" \
                "$MODE" "$AIMODEL" "$hit" "$miss" "$completion" "$thinking" "$search" "$total_cost")
        fi
    fi

    # Construct Function Response Part
    jq -n --arg name "estimate_cost" --arg res "$RESULT" \
        '{functionResponse: {name: $name, response: {result: $res}}}' > "${RESP_PARTS_FILE}.part"
    
    # Append to Array
    jq --slurpfile new "${RESP_PARTS_FILE}.part" '. + $new' "$RESP_PARTS_FILE" > "${RESP_PARTS_FILE}.tmp" && mv "${RESP_PARTS_FILE}.tmp" "$RESP_PARTS_FILE"
    rm "${RESP_PARTS_FILE}.part"
}

