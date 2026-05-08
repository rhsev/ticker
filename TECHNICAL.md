# ticker — Technical Notes

## No font rendering

A menu bar app runs permanently in the background, so the rendering approach matters. CoreText would work, but it brings font loading, glyph metrics, and subpixel rasterization to something that runs at 20 fps.

The alternative: a bitmap table. Every character is stored as six bytes in a `[Character: [UInt8]]` dictionary, derived from the Adafruit GFX 5×7 font — a format originally designed for embedded LED matrix panels, which is the right level of detail for a small menu bar display. Each byte is one column of eight pixels, bit 0 at the top. Rendering a frame means a lookup and a few `NSBezierPath` calls. The LED matrix aesthetic is a consequence of this approach, not the starting point.

The off-LEDs are not black. They use a dark amber `(0.15, 0.11, 0.0)` to simulate the faintly visible unlit dots of a physical LED panel.

## 6-columns per glyph

Standard bitmap fonts are 5 pixels wide. ticker uses 6 columns per glyph. The sixth is a trailing gap, normally zero. Putting the gap inside the glyph rather than inserting it dynamically between characters has a useful consequence: two consecutive glyphs can share their boundary. `\g[left]\g[right]` renders as one seamless symbol because the sixth column of the left part becomes part of the combined shape instead of empty space.

## Canvas, not real-time parsing

When a message arrives, `buildScrollStream()` parses the entire text once and produces a flat array of colored columns - the canvas. Control codes, custom glyphs, pause markers: everything is resolved upfront. The animation loop then just advances a window over that array, one column per tick.

During scrolling, each tick does a single integer comparison:

```swift
if let p = pendingPauses.first, p.at == scrollOffset { triggerPause(p.kind) }
```

The pause fires precisely when the marked column `\p[N]` reaches the left edge of the display.

## RunLoop mode

The animation timer runs on `RunLoop.main` in `.common` mode. Without `.common`, any menu interaction — including opening the context menu on the ticker itself — would freeze the animation until the menu closed.

## One binary

The CLI and the server are the same binary. With arguments it sends a JSON message over a Unix domain socket; without arguments it starts the app. One file to install, no separate daemon, no launchd plumbing required.
