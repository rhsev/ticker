# LED Ticker — Feature Spec v2

## Core Principles

- Input is always CLI — no text input window in the app
- One message per command, repeated commands for repeated messages
- Messages are queued and play once, in order
- The display is always visible (menu bar), never needs focus

---

## CLI Interface

```bash
ticker --send "MESSAGE"           # append to queue
ticker -s "MESSAGE"

ticker --urgent "MESSAGE"         # prepend to queue; current message finishes first
ticker -u "MESSAGE"

ticker --very-urgent "MESSAGE"    # interrupt immediately; interrupted message
ticker -vu "MESSAGE"              #   is re-queued at front and replayed after
```

---

## Inline Control Codes

Control codes are embedded in the message string. They are not displayed.

### Color

```
\c[amber]   amber / orange (default)
\c[green]   terminal green
\c[red]     red
\c[white]   white
\c[yellow]  yellow
```

Color applies to all following characters until the next `\c[...]`.
Emojis are rendered in their own pixel color — no color code needed or applied.

Example:
```
ticker --send "STATUS \c[green]OK\c[amber] ALL CLEAR"
```

### Pause

```
\p[N]       pause N seconds when this code reaches the left edge of the display
\p[sticky]  pause indefinitely until the user clicks the status item
```

A pause code triggers when it scrolls into the leftmost visible position,
so the preceding text is fully visible before the pause takes effect.

**Sticky blink:** when `\p[sticky]` activates, the display blinks twice
(off → on → off → on) to signal that interaction is expected.

Example:
```
ticker --send "DEPLOY COMPLETE \p[3] RESTARTING..."
ticker --urgent "BUILD FAILED \p[sticky]" --on-click "open -a Xcode"
```

### Click action

```
--on-click "SHELL COMMAND"
```

Executed when the user clicks the status item during a `\p[sticky]` pause.
Clicking also resumes scrolling.

---

## Display Behavior

- Text scrolls in from the right, pauses, scrolls out to the left
- Default pause: 3 seconds (no `\p` code needed for standard messages)
- After scroll-out: next message from queue, or standby text / idle indicator
- `--urgent` jumps to front; current message always completes first
- `--very-urgent` interrupts immediately; interrupted message is re-queued
  and replayed from the beginning

---

## Standby Text

A message that appears instantly (no scroll-in/out), stays for N seconds,
then disappears. Text longer than the visible display is clipped — no scrolling.

```bash
ticker --standby "OPEN 09:00-17:00" --duration 10
ticker --standby-urgent "CLOSED" --duration 5
ticker --standby-very-urgent "FIRE ALARM" --duration 30
```

Same priority rules as scrolling messages:
- `--standby` appends to queue
- `--standby-urgent` jumps to front; current message finishes first
- `--standby-very-urgent` interrupts immediately; interrupted message is re-queued

After the duration the display returns to the next queued message or idle (●).

---

## Display Width

The visible display width can be changed at any time. Minimum: 5 characters.
No maximum — macOS clips whatever doesn't fit in the menu bar. Default: 20 characters.

```bash
ticker --width 30    # wider display
ticker --width 10    # compact
```

Width persists until changed by another `--width` command. Default is defined
in the config file. Standby text is clipped to the current width; scrolling
messages are unaffected (they scroll past).

---

## Rendering

- Black background, always — independent of menu bar color
- Amber LEDs by default
- Uppercase only — authentic to historical LED displays
- LED size and scroll speed: hardcoded (tunable at compile time)
- Emoji rendering: pixel bitmaps, natural color (no `\c` applied)
- Custom characters: defined in config file (see Configuration)

---

## Configuration File

`~/.config/ticker/config.json` (created on first run with defaults)

```json
{
  "default_color": "amber",
  "default_width": 20,
  "scroll_speed": 0.05,
  "default_pause": 3,
  "custom_chars": {
    "☑": "path/to/checkmark.bitmap",
    "★": "path/to/star.bitmap"
  }
}
```

Custom characters are 5×8 bitmaps (same format as the built-in font table),
defined as arrays of 5 column values.

```json
"custom_chars": {
  "★": [0x08, 0x1C, 0x7F, 0x1C, 0x08]
}
```

---

## What is explicitly NOT supported

- Rich text / markdown
- More than 5 colors
- Charts, tables, images
- Lowercase letters
- Persistent message history
- Font size changes
- SF Symbol rendering
