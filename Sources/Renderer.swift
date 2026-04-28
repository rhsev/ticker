import AppKit

// ── Layout (compile-time constants) ───────────────────────────────────────────
let ledSize     = 2
let ledGap      = 1
let ledRows     = 8
let paddingH    = 4
let paddingV    = 0
let colsPerChar = 6   // 5 Pixel + 1 Abstandsspalte

let colW = ledSize + ledGap
let rowH = ledSize + ledGap
let imgH = ledRows * rowH - ledGap + paddingV * 2

// ── Farben ─────────────────────────────────────────────────────────────────────

func nsColor(_ c: LEDColor) -> NSColor {
    switch c {
    case .amber:  return NSColor(red: 1.0,  green: 0.55, blue: 0.0,  alpha: 1)
    case .green:  return NSColor(red: 0.0,  green: 1.0,  blue: 0.25, alpha: 1)
    case .red:    return NSColor(red: 1.0,  green: 0.1,  blue: 0.0,  alpha: 1)
    case .white:  return NSColor(red: 1.0,  green: 1.0,  blue: 1.0,  alpha: 1)
    case .yellow: return NSColor(red: 1.0,  green: 0.9,  blue: 0.0,  alpha: 1)
    }
}

let colorOff = NSColor(red: 0.08, green: 0.06, blue: 0.0, alpha: 1.0)

// ── Hilfsfunktionen ────────────────────────────────────────────────────────────

func imgWidth(displayWidth: Int) -> Int {
    displayWidth * colsPerChar * colW + paddingH * 2
}

func visCols(displayWidth: Int) -> Int {
    displayWidth * colsPerChar
}

// ── Scroll-Frame ───────────────────────────────────────────────────────────────

func renderScrollFrame(columns: [ColoredColumn], offset: Int,
                       displayWidth: Int, blank: Bool = false) -> NSImage {
    let vc  = visCols(displayWidth: displayWidth)
    let w   = imgWidth(displayWidth: displayWidth)
    let img = NSImage(size: NSSize(width: Double(w), height: Double(imgH)))
    img.lockFocus()

    NSColor.black.set()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: Double(w), height: Double(imgH)))

    if !blank {
        for ci in 0..<vc {
            let si = offset + ci
            guard si < columns.count else { break }
            let col = columns[si]
            let x   = Double(paddingH + ci * colW)
            for bit in 0..<ledRows {
                let on = (col.value & (1 << bit)) != 0
                let y  = Double(paddingV + (ledRows - 1 - bit) * rowH)
                (on ? nsColor(col.color) : colorOff).set()
                NSBezierPath.fill(NSRect(x: x, y: y, width: Double(ledSize), height: Double(ledSize)))
            }
        }
    }

    img.unlockFocus()
    img.isTemplate = false
    return img
}

// ── Idle-Icon (T aus LED-Punkten) ─────────────────────────────────────────────

func renderIdleIcon(color: LEDColor) -> NSImage {
    let cols = FONT[Character("<")] ?? Array(repeating: 0, count: 5)
    let w    = paddingH * 2 + 5 * colW - ledGap
    let img  = NSImage(size: NSSize(width: Double(w), height: Double(imgH)))
    img.lockFocus()

    NSColor.black.set()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: Double(w), height: Double(imgH)))

    for ci in 0..<5 {
        let x = Double(paddingH + ci * colW)
        for bit in 0..<ledRows {
            let on = (cols[ci] & (1 << bit)) != 0
            let y  = Double(paddingV + (ledRows - 1 - bit) * rowH)
            (on ? nsColor(color) : colorOff).set()
            NSBezierPath.fill(NSRect(x: x, y: y, width: Double(ledSize), height: Double(ledSize)))
        }
    }

    img.unlockFocus()
    img.isTemplate = false
    return img
}

// ── Standby-Frame (links-ausgerichtet, geclippt) ───────────────────────────────

func renderStandbyFrame(text: String, displayWidth: Int,
                        defaultColor: LEDColor,
                        customChars: [String: [UInt8]]) -> NSImage {
    let stream  = buildScrollStream(text: text, defaultColor: defaultColor,
                                    onClickCommand: nil, customChars: customChars)
    let clipped = Array(stream.columns.prefix(visCols(displayWidth: displayWidth)))
    return renderScrollFrame(columns: clipped, offset: 0, displayWidth: displayWidth)
}
