#!/bin/bash
# Create 7 dummy files for testing tool limits
mkdir -p tests
for i in {1..7}; do
    echo "This is test file $i" > "tests/file_$i.txt"
done
echo "Created 7 files in ./tests/"