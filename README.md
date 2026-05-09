# ticker

A LED-style ticker for the macOS menu bar, controlled from the command line. 

Notifications can be overlooked. Motion catches the eye. ticker scrolls urgent messages through the menu bar, and the movement is what makes them register. The LED dot-matrix style amplifies this. There is no font pipeline: text is composed from a bitmap table, easy enough to scroll at 20 fps with negligible CPU load.

When a message arrives, the ticker appears in the menu bar and scrolls through all queued messages in sequence. Then it disappears or stays and waits for acknowledgment.

NEW: Now supports transparent background mode for a native menu bar look.

**Quick example**

```bash
ticker --send "HELLO WORLD!"
```

LED mode with black background:

![ticker demo](demo.gif)

Transparent mode — adapts to your menu bar:

![ticker transparent](screenshot_transparent.png)

Each character is stored as six 8-bit glyph columns, five pixels wide plus one gap column, derived from the classic Adafruit GFX 5×7 bitmap font. Scrolling advances the canvas by exactly one column per tick, so the animation is pixel-smooth without any font rendering, which keeps CPU load very low. The same bitmap font drives the display and the custom glyph system. Like a real LED matrix display.

For a technical deep-dive see [TECHNICAL.md](TECHNICAL.md).

---

## Requirements

- macOS 12 or later
- Apple Silicon or Intel

---

## Installation

Download the binary from the [latest release](https://github.com/rhsev/ticker/releases/latest), then:

```bash
cp ~/Downloads/ticker /usr/local/bin/ticker
xattr -d com.apple.quarantine /usr/local/bin/ticker  # bypass Gatekeeper
ticker &                                             # & starts it in the background
```

The app runs as a menu bar accessory (no Dock icon). It creates a Unix domain socket
at `/tmp/menubar_ticker.sock` and waits for commands.

### Auto-start at login

Add `ticker` under **System Settings → General → Login Items**.

---

## Sending messages

```bash
ticker --send "HELLO WORLD"          # append to queue
ticker --urgent "IMPORTANT"          # jump to front; current message finishes
ticker --very-urgent "STOP PRESS"    # interrupt immediately; resumes after
```

Short aliases: `-s`, `-u`, `-vu`.

### Standby text

Displayed instantly (no scroll), clipped to the visible width, for a fixed duration:

```bash
ticker --standby "OPEN 09:00-17:00" --duration 10
ticker --standby-urgent "CLOSING SOON" --duration 5
ticker --standby-very-urgent "EVACUATE NOW" --duration 30
```

### Display width

```bash
ticker --width 30    # wider
ticker --width 10    # compact (minimum: 5)
```

Width persists until changed. Default is set in the config file.

### Queue control

```bash
ticker --clear           # clear queue and stop current message
ticker --status          # query current state (JSON)
ticker --quit            # quit the app
```

`--status` returns:

```json
{"phase":"scrolling","queue":2}
```

Possible `phase` values: `idle`, `scrolling`, `sticky`, `standby`.

---

## Inline control codes

Control codes are embedded in the message text. They are not displayed.

### Color

```
\c[amber]    orange-amber (default)
\c[green]    terminal green
\c[red]      red
\c[white]    white
\c[yellow]   yellow
```

Color applies to all following characters until the next `\c[…]`.

```bash
ticker --send "STATUS \c[green]OK\c[amber] ALL CLEAR"
ticker --send "\c[red]ERROR \c[white]disk full on \c[yellow]backup-01"
```

### Glyph

```
\g[name]     render a named custom glyph from config
```

```bash
ticker --send "SCORE \g[star] 9999"
ticker --send "I \g[heart] SWIFT"
```

Glyphs are defined in `custom_chars` in the config file (see below).

### Pause

```
\p[N]          pause N seconds when this point reaches the left edge
\p[sticky]     pause until the user clicks the status item
\p[sticky:N]   pause with N blinks before waiting (e.g. \p[sticky:3])
```

The pause triggers when it scrolls into the leftmost visible column, so the
preceding text is fully readable before the hold takes effect.

When `\p[sticky:N]` activates, the display blinks N times to draw attention,
then holds the text until the user clicks.

### Optional shell command on click

An optional shell command runs when the user clicks the sticky item:

```bash
ticker --send "BUILD FAILED \p[sticky:3]" --on-click "open -a Xcode"
ticker --send "DEPLOY DONE \p[3] RESTARTING..."
```

---

## Priority rules

| Flag | Behaviour |
|---|---|
| `--send` / `--standby` | Appended to queue |
| `--urgent` / `--standby-urgent` | Inserted at front; current message finishes first |
| `--very-urgent` / `--standby-very-urgent` | Interrupts immediately; interrupted message is re-queued and replayed |

---

## Context menu

Right-click the ticker to access:

- **Clear queue** — discard all pending messages
- **Pause / Resume** — freeze animation
- **Quit**

---

## Configuration

`~/.config/ticker/config.json` — created on first run with defaults:

```json
{
  "default_color": "amber",
  "default_width": 20,
  "scroll_speed": 0.05,
  "default_pause": 3.0,
  "custom_chars": {}
}
```

| Key | Description |
|---|---|
| `default_color` | LED color: `amber` `green` `red` `white` `yellow` |
| `default_width` | Visible character columns (default 20) |
| `scroll_speed` | Seconds per pixel column (default 0.05 = fast) |
| `default_pause` | Seconds to hold when the message is fully visible (default 3) |
| `transparent` | `true` for transparent background with system text color — works well on dark or coloured menu bars (default `false`) |
| `custom_chars` | Extra glyphs as 6-column bitmaps (see below) |

### Custom glyphs

Glyphs are referenced by name via `\g[name]` in messages:

```json
"customChars": {
  "star":  [4, 14, 31, 14, 4, 0],
  "heart": [6, 15, 30, 15, 6, 0]
}
```

Each value is an array of 6 column bytes (8 rows, bit 0 = top row). Column 6 is the
trailing gap — use `0` for normal spacing, or non-zero to connect two glyphs seamlessly
into a wider symbol: `\g[left]\g[right]`.

To design a glyph, create a `.led` file — 8 rows × 6 columns, `X` for lit, `.` for dark:

```
..X...
.XXX..
XXXXX.
.XXX..
..X...
......
......
......
```

Then convert with the included tool:

```bash
bash tools/make_char.sh tools/glyphs/star.led star
# → "star": [4, 14, 31, 14, 4]
```

Example glyphs are in `tools/glyphs/`.

---

## Building from source

```bash
swift build -c release
# binary at .build/release/ticker
```

Requires Xcode Command Line Tools (`xcode-select --install`).

