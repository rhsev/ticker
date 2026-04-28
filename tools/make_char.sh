#!/usr/bin/env bash
# Convert a 5×8 LED matrix text file to a custom_chars entry for
# ~/.config/ticker/config.json.
#
# Usage:
#   make_char.sh <file.led> <name>
#
# The .led file must contain exactly 8 lines of exactly 5 characters each.
# Use X for lit pixels, . for dark pixels.
#
# Example (star.led):
#   ..X..
#   .XXX.
#   XXXXX
#   .XXX.
#   ..X..
#   .....
#   .....
#   .....
#
# Output:
#   "star": [4, 14, 31, 14, 4]

set -e

[[ $# -eq 2 ]] || { echo "Usage: make_char.sh <file.led> <name>" >&2; exit 1; }

FILE=$1
NAME=${2,,}   # lowercase

mapfile -t LINES < <(grep -v '^\s*$' "$FILE")

[[ ${#LINES[@]} -eq 8 ]] || { echo "Error: expected 8 rows, got ${#LINES[@]}" >&2; exit 1; }

for i in "${!LINES[@]}"; do
    [[ ${#LINES[$i]} -eq 5 ]] || { echo "Error: row $((i+1)) has ${#LINES[$i]} columns, expected 5" >&2; exit 1; }
done

COLS=()
for col in 0 1 2 3 4; do
    byte=0
    for row in 0 1 2 3 4 5 6 7; do
        ch="${LINES[$row]:$col:1}"
        [[ "${ch^^}" == "X" ]] && (( byte |= (1 << row) )) || true
    done
    COLS+=("$byte")
done

echo "\"$NAME\": [${COLS[0]}, ${COLS[1]}, ${COLS[2]}, ${COLS[3]}, ${COLS[4]}]"
