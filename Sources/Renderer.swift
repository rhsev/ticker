import AppKit

// ── Layout ─────────────────────────────────────────────────────────────────────
let ledSize   = 2
let ledGap    = 1
let ledRows   = 8
let paddingH  = 4
let paddingV  = 0
let visibleCols = 80

let colW    = ledSize + ledGap
let rowH    = ledSize + ledGap
let imgW    = visibleCols * colW + paddingH * 2
let imgH    = ledRows * rowH - ledGap + paddingV * 2

let colorBg  = NSColor.black
let colorOn  = NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0)   // amber
let colorOff = NSColor(red: 0.08, green: 0.06, blue: 0.0, alpha: 1.0)

func renderFrame(columns: [UInt8], offset: Int) -> NSImage {
    let size = NSSize(width: Double(imgW), height: Double(imgH))
    let img = NSImage(size: size)
    img.lockFocus()

    colorBg.set()
    NSBezierPath.fill(NSRect(origin: .zero, size: size))

    let total = columns.count
    for colIdx in 0..<visibleCols {
        let colVal = columns[(offset + colIdx) % total]
        let x = Double(paddingH + colIdx * colW)
        for bit in 0..<ledRows {
            let on = (colVal & (1 << bit)) != 0
            let y = Double(paddingV + (ledRows - 1 - bit) * rowH)
            (on ? colorOn : colorOff).set()
            NSBezierPath.fill(NSRect(x: x, y: y, width: Double(ledSize), height: Double(ledSize)))
        }
    }

    img.unlockFocus()
    img.isTemplate = false
    return img
}
