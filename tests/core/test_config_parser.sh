#!/bin/bash
# tests/test_config_parser.sh

CONFIG_FILE="test_config.yaml"
cat <<EOF > "$CONFIG_FILE"
PERSON: "You are an AI."
MAX_TURNS: 10
# Comment line
MALICIOUS: "\$(rm -rf /)"
STRICT_VAR: 'safe_value'
EOF

echo "Testing config parser logic..."

# The logic from a-new.sh
PARSED_VARS=$(python3 -c "
import sys, shlex
try:
    with open('$CONFIG_FILE', 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or ':' not in line:
                continue
            k, v = line.split(':', 1)
            k = k.strip()
            v = v.strip().strip('\"').strip(\"'\")
            if k.isidentifier():
                print(f'{k}={shlex.quote(v)}')
except Exception as e:
    print(f'echo \"Error parsing config: {e}\" >&2; exit 1')
")

eval "$PARSED_VARS"

echo "PERSON: $PERSON"
echo "MAX_TURNS: $MAX_TURNS"
echo "MALICIOUS: $MALICIOUS"
echo "STRICT_VAR: $STRICT_VAR"

if [ "$MALICIOUS" == "\$(rm -rf /)" ]; then
    echo "SUCCESS: Malicious input was quoted safely."
else
    echo "FAILURE: Malicious input was executed or incorrectly parsed: $MALICIOUS"
    exit 1
fi

rm "$CONFIG_FILE"

