# ticker

A retro LED ticker for the macOS menu bar.

Text scrolls across a simulated LED dot-matrix display — black background, amber glow,
uppercase letters. Driven entirely from the command line; the app itself has no UI
beyond the display strip.

---

## Requirements

- macOS 12 or later
- Apple Silicon or Intel

---

## Installation

Copy the `ticker` binary to somewhere on your PATH, then launch it:

```bash
cp ticker /usr/local/bin/ticker
ticker &          # or open at login via a Launch Agent (see below)
```

The app runs as a menu bar accessory (no Dock icon). It creates a Unix domain socket
at `/tmp/menubar_ticker.sock` and waits for commands.

### Auto-start at login

Create `~/Library/LaunchAgents/com.user.ticker.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>com.user.ticker</string>
  <key>ProgramArguments</key>  <array><string>/usr/local/bin/ticker</string></array>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.user.ticker.plist
```

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
\p[N]        pause N seconds when this point reaches the left edge
\p[sticky]   pause until the user clicks the status item
```

The pause triggers when it scrolls into the leftmost visible column, so the
preceding text is fully readable before the hold takes effect.

When `\p[sticky]` activates, the display blinks twice to signal that a click
is expected. An optional shell command runs on click:

```bash
ticker --send "BUILD FAILED \p[sticky]" --on-click "open -a Xcode"
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
| `custom_chars` | Extra glyphs as 5-column bitmaps (see below) |

### Custom glyphs

Glyphs are referenced by name via `\g[name]` in messages:

```json
"customChars": {
  "star":  [4, 14, 31, 14, 4],
  "heart": [6, 15, 30, 15, 6]
}
```

Each value is an array of 5 column bytes (8 rows, bit 0 = top row).

To design a glyph, create a `.led` file — 8 rows × 5 columns, `X` for lit, `.` for dark:

```
..X..
.XXX.
XXXXX
.XXX.
..X..
.....
.....
.....
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

---

## What is not supported

- Lowercase letters (uppercase only — authentic to historical LED displays)
- Rich text, markdown, images
- More than 5 colors
- Persistent message history
- Font size changes
