#!/usr/bin/env python3
"""
Convert a 5×8 LED matrix text file to a custom_chars entry for
~/.config/ticker/config.json.

Usage:
    python3 make_char.py <file.led> <name>

The .led file must contain exactly 8 lines of exactly 5 characters each.
Use X for lit pixels, . for dark pixels.

Example (star.led):
    ..X..
    .XXX.
    XXXXX
    .XXX.
    ..X..
    .....
    .....
    .....

Output:
    "star": [4, 14, 31, 14, 4]
"""

import sys

def main():
    if len(sys.argv) != 3:
        print("Usage: make_char.py <file.led> <name>", file=sys.stderr)
        sys.exit(1)

    path, name = sys.argv[1], sys.argv[2].lower()

    with open(path) as f:
        lines = [l.rstrip('\n') for l in f.readlines()]

    lines = [l for l in lines if l.strip()]

    if len(lines) != 8:
        print(f"Error: expected 8 rows, got {len(lines)}", file=sys.stderr)
        sys.exit(1)

    for i, line in enumerate(lines):
        if len(line) != 5:
            print(f"Error: row {i+1} has {len(line)} columns, expected 5", file=sys.stderr)
            sys.exit(1)

    cols = []
    for col in range(5):
        byte = 0
        for row in range(8):
            if lines[row][col].upper() == 'X':
                byte |= (1 << row)
        cols.append(byte)

    print(f'"{name}": {cols}')

if __name__ == "__main__":
    main()
