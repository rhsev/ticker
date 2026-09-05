#!/usr/bin/env python3
# One-off: regenerate ticker's app icon with the hero mark as an LED dot-matrix
# "<" (matching the menu bar's idle icon / Sources/Renderer.swift + FontData.swift),
# on the standard icon-gen blueprint tile (default blue, no name label, glyph
# vertically centered) — see rhsev/scripts/icon-gen/make-icons.py.
#
# The blueprint tile is deliberately copied here rather than imported from
# icon-gen: this repo is public, and the sibling scripts' import path
# (`../../scripts/icon-gen/make-icons.py`) points outside the repo, so it
# breaks in a clone. The cost is drift — a change to icon-gen's tile does not
# reach this file. That is the trade, not a bug.

import argparse, os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFont

S, MARGIN, RADIUS = 1024, 88, 190
INK = (255, 255, 255)
BASE = (15, 66, 122)  # icon-gen DEFAULT_COLOR "#0f427a"
FONT = "/System/Library/Fonts/Menlo.ttc"

def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# FontData.swift: "<": [0x08, 0x14, 0x22, 0x41, 0x00] over 8 LED rows (bit0=bottom).
LT_COLS = [0x08, 0x14, 0x22, 0x41, 0x00]
NROWS = 8

def draw_led_lt(d, cx, cy, cell, gap):
    ncols = len(LT_COLS)
    dot = cell - gap
    # Center on the glyph's actual lit rows, not the full 8-row grid — the
    # "<" only lights bits 0..6 (top row always empty), so centering on
    # NROWS=8 left it visibly low.
    lit_bits = [b for col in LT_COLS for b in range(NROWS) if col & (1 << b)]
    top_bit, bot_bit = max(lit_bits), min(lit_bits)
    span_rows = top_bit - bot_bit + 1
    total_w = ncols * cell - gap
    total_h = span_rows * cell - gap
    x0 = cx - total_w / 2
    y0 = cy - total_h / 2
    for ci, col in enumerate(LT_COLS):
        for bit in range(NROWS):
            if col & (1 << bit):
                row_from_top = top_bit - bit
                x = x0 + ci * cell
                y = y0 + row_from_top * cell
                d.rounded_rectangle([x, y, x + dot, y + dot], radius=6, fill=INK)

def master():
    top, bot = mix(BASE, (255, 255, 255), 0.16), mix(BASE, (0, 0, 0), 0.34)
    tile = Image.new("RGB", (S, S), top)
    px = tile.load()
    for y in range(S):
        row = mix(top, bot, y / (S - 1))
        for x in range(S):
            px[x, y] = row
    d = ImageDraw.Draw(tile, "RGBA")

    step, x0, y0, x1, y1 = 64, MARGIN, MARGIN, S - MARGIN, S - MARGIN
    for axis in (0, 1):
        n, p = 0, (x0 if axis == 0 else y0)
        while p <= (x1 if axis == 0 else y1):
            major = n % 4 == 0
            col = (255, 255, 255, 60 if major else 34)
            xy = [(p, y0), (p, y1)] if axis == 0 else [(x0, p), (x1, p)]
            d.line(xy, fill=col, width=2 if major else 1)
            p += step; n += 1

    frame_offset = 40
    inset = MARGIN + frame_offset
    frame_radius = RADIUS - frame_offset
    d.rounded_rectangle([inset, inset, S - inset, S - inset],
                        radius=frame_radius, outline=(*INK, 150), width=4)
    for tx, ty in [(inset, inset), (S - inset, inset),
                   (inset, S - inset), (S - inset, S - inset)]:
        d.line([(tx - 16, ty), (tx + 16, ty)], fill=(*INK, 180), width=3)
        d.line([(tx, ty - 16), (tx, ty + 16)], fill=(*INK, 180), width=3)

    # hero mark: LED dot-matrix "<", vertically centered on the tile
    draw_led_lt(d, S * 0.5, S * 0.5, cell=58, gap=8)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([MARGIN, MARGIN, S - MARGIN, S - MARGIN],
                                           radius=RADIUS, fill=255)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas.paste(tile, (0, 0), mask)
    return canvas

ICONSET = [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"),
           (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"),
           (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"),
           (1024, "icon_512x512@2x")]

def build_icns(png_path, icns_path):
    with tempfile.TemporaryDirectory(suffix=".iconset") as d:
        for px, fn in ICONSET:
            subprocess.run(["sips", "-z", str(px), str(px), png_path,
                            "--out", os.path.join(d, fn + ".png")],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["iconutil", "-c", "icns", d, "-o", icns_path], check=True)

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="ticker's LED app icon (PNG + .icns).")
    # Default: the repo's icons/, resolved from this file — runs from any cwd.
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  os.pardir, "icons"))
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    png = os.path.join(a.out, "ticker.png")
    icns = os.path.join(a.out, "ticker.icns")
    master().save(png)
    build_icns(png, icns)
    print("wrote", png, icns)
