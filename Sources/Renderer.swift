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

let colorOff = NSColor(red: 0.15, green: 0.11, blue: 0.0, alpha: 1.0)

// Transparenter Modus — gesetzt aus Config beim Start
var renderTransparent = false
private let paddingTop  = 3
private let imgHtransparent = ledRows * rowH - ledGap + paddingTop

// Backing-Scale des Bildschirms mit der Menüleiste — gesetzt aus AppDelegate,
// aktualisiert bei Bildschirmwechsel. Ganzzahlig, damit das Punktraster scharf bleibt.
var renderScale = 2

// ── Farben als fertige RGBA-Pixel ─────────────────────────────────────────────
//
// Little-Endian-Layout des Bitmaps: R | G<<8 | B<<16 | A<<24

private func packed(_ c: NSColor) -> UInt32 {
    let rgb = c.usingColorSpace(.deviceRGB) ?? c
    let r = UInt32(rgb.redComponent   * 255.0 + 0.5)
    let g = UInt32(rgb.greenComponent * 255.0 + 0.5)
    let b = UInt32(rgb.blueComponent  * 255.0 + 0.5)
    return r | (g << 8) | (b << 16) | (0xFF << 24)
}

private let packedOn: [LEDColor: UInt32] = {
    var t = [LEDColor: UInt32]()
    for c in [LEDColor.amber, .green, .red, .white, .yellow] { t[c] = packed(nsColor(c)) }
    return t
}()

private let packedOff        = packed(colorOff)
private let packedBlack      = packed(.black)
private let packedTemplate: UInt32 = 0xFF00_0000   // Schwarz, deckend — Template nutzt nur Alpha
private let packedClear:    UInt32 = 0

// ── Hilfsfunktionen ────────────────────────────────────────────────────────────

func imgWidth(displayWidth: Int) -> Int {
    displayWidth * colsPerChar * colW + paddingH * 2
}

func visCols(displayWidth: Int) -> Int {
    displayWidth * colsPerChar
}

// ── Frame-Rendering ────────────────────────────────────────────────────────────
//
// Die Punkte werden direkt in einen RGBA-Puffer geschrieben statt als einzelne
// NSBezierPath-Rechtecke in einen lockFocus-Kontext. Bei Breite 20 sind das 960
// Rasterpunkte pro Frame, 20×/s — der Kontextaufbau und die Core-Graphics-Aufrufe
// dominierten die CPU-Last. Der Puffer ist klein (bei Breite 20 und 2× rund
// 34.000 Pixel), das Füllen ist ein reiner Speicher-Loop.
//
// Bit 0 eines Font-Bytes ist die oberste Zeile; im Bitmap läuft y von oben,
// darum y = yPad + bit * rowH (in der alten Zeichnung von unten gerechnet).

private func renderFrame(columns: [ColoredColumn], offset: Int, visibleCols: Int,
                         width: Int, height: Int, yPad: Int) -> NSImage {
    let s    = max(1, renderScale)
    let pw   = width  * s
    let ph   = height * s
    let size = NSSize(width: Double(width), height: Double(height))

    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pw, pixelsHigh: ph,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: pw * 4, bitsPerPixel: 32),
          let base = rep.bitmapData
    else { return NSImage(size: size) }

    let px = UnsafeMutableRawPointer(base).bindMemory(to: UInt32.self, capacity: pw * ph)

    // Hintergrund
    let bg = renderTransparent ? packedClear : packedBlack
    if bg == 0 {
        memset(base, 0, pw * ph * 4)
    } else {
        for i in 0..<(pw * ph) { px[i] = bg }
    }

    // Punkte
    let dot = ledSize * s
    for ci in 0..<visibleCols {
        let si = offset + ci
        guard si >= 0, si < columns.count else { break }
        let col = columns[si]
        let x0  = (paddingH + ci * colW) * s
        for bit in 0..<ledRows {
            let on = (col.value & (1 << bit)) != 0
            let v: UInt32
            if renderTransparent {
                guard on else { continue }          // unbeleuchtete Punkte bleiben transparent
                v = packedTemplate
            } else {
                v = on ? (packedOn[col.color] ?? packedTemplate) : packedOff
            }
            let y0 = (yPad + bit * rowH) * s
            for dy in 0..<dot {
                let row = (y0 + dy) * pw + x0
                for dx in 0..<dot { px[row + dx] = v }
            }
        }
    }

    rep.size = size
    let img = NSImage(size: size)
    img.addRepresentation(rep)
    img.isTemplate = renderTransparent
    return img
}

// ── Scroll-Frame ───────────────────────────────────────────────────────────────

func renderScrollFrame(columns: [ColoredColumn], offset: Int,
                       displayWidth: Int, blank: Bool = false) -> NSImage {
    renderFrame(columns:    columns,
                offset:     offset,
                visibleCols: blank ? 0 : visCols(displayWidth: displayWidth),
                width:      imgWidth(displayWidth: displayWidth),
                height:     renderTransparent ? imgHtransparent : imgH,
                yPad:       renderTransparent ? paddingTop : paddingV)
}

// ── Idle-Icon (< aus LED-Punkten) ─────────────────────────────────────────────

func renderIdleIcon(color: LEDColor) -> NSImage {
    let cols = FONT[Character("<")] ?? Array(repeating: 0, count: 5)
    return renderFrame(columns:     cols.map { ColoredColumn(value: $0, color: color) },
                       offset:      0,
                       visibleCols: 5,
                       width:       paddingH * 2 + 5 * colW - ledGap,
                       height:      renderTransparent ? imgHtransparent : imgH,
                       yPad:        renderTransparent ? paddingTop : paddingV)
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
