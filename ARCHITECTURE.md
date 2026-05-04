# ticker — Technical Notes

## No font rendering

Motion is perceptible in a way that static text is not — notifications get dismissed
unread, but movement in the corner of your eye registers. Scrolling text in the menu
bar exploits this, and the LED matrix style amplifies it further: the dot pattern
draws attention even before the content is read.

A menu bar app runs permanently in the background, so the rendering approach matters.
CoreText would work, but it brings font loading, glyph metrics, and subpixel
rasterization to something that runs at 20 fps indefinitely.

The alternative: a bitmap table. Every character is stored as six bytes in a
`[Character: [UInt8]]` dictionary, derived from the Adafruit GFX 5×7 font — a
format originally designed for embedded LED matrix panels, which turns out to be
exactly the right level of detail for a small menu bar display. Each byte is one
column of eight pixels, bit 0 at the top. Rendering a frame means a lookup and
a few `NSBezierPath` calls. The LED matrix aesthetic is a consequence of this
approach, not the starting point.

The off-LEDs are not black. They use a dark amber `(0.15, 0.11, 0.0)` to simulate
the faintly visible unlit dots of a physical LED panel.

## The 6-column trick

Standard bitmap fonts are 5 pixels wide. ticker uses 6 columns per glyph — the
sixth is a trailing gap, normally zero. Putting the gap inside the glyph rather than
inserting it dynamically between characters has a useful consequence: two consecutive
glyphs can share their boundary. `\g[left]\g[right]` renders as one seamless symbol
because the sixth column of the left part becomes part of the combined shape instead
of empty space.

## Canvas, not real-time parsing

When a message arrives, `buildScrollStream()` parses the entire text once and
produces a flat array of colored columns — the canvas. Control codes, custom glyphs,
pause markers: everything is resolved upfront. The animation loop then just advances
a window over that array, one column per tick.

Pause markers are the interesting part. Each `\p[N]` in the text gets assigned a
canvas offset during stream construction — the exact column position where the pause
should fire. During scrolling, each tick does a single integer comparison:

```swift
if let p = pendingPauses.first, p.at == scrollOffset { triggerPause(p.kind) }
```

The pause fires precisely when the marked column reaches the left edge of the
display, so the preceding text is fully readable before the hold takes effect.

## RunLoop mode

The animation timer runs on `RunLoop.main` in `.common` mode. Without `.common`,
any menu interaction — including opening the context menu on the ticker itself —
would freeze the animation until the menu closed. One line, easy to miss, easy to
get wrong.

## One binary

The CLI and the server are the same binary. With arguments it sends a JSON message
over a Unix domain socket; without arguments it starts the app. One file to install,
no separate daemon, no launchd plumbing required.
