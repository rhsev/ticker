import Foundation

// ── Typen ──────────────────────────────────────────────────────────────────────

enum LEDColor: String, Codable {
    case amber, green, red, white, yellow

    static func from(_ s: String) -> LEDColor {
        LEDColor(rawValue: s.lowercased()) ?? .amber
    }
}

enum Priority: String, Codable {
    case normal, urgent, veryUrgent = "very_urgent"
}

enum MessageKind: String, Codable {
    case scroll, standby, setWidth = "set_width"
    case clearQueue = "clear_queue"
    case getStatus  = "get_status"
}

enum PauseKind {
    case timed(seconds: Double)
    case sticky(onClickCommand: String?, blinks: Int)
}

struct TickerMessage {
    let kind:           MessageKind
    let text:           String
    let priority:       Priority
    let duration:       Double      // standby only
    let onClickCommand: String?
    let width:          Int?        // setWidth only
}

// ── Scroll-Stream ──────────────────────────────────────────────────────────────

struct ColoredColumn {
    let value: UInt8
    let color: LEDColor
}

struct PauseMarker {
    let at:   Int   // Spalten-Index im Stream (vor Padding)
    let kind: PauseKind
}

struct ScrollStream {
    let columns: [ColoredColumn]
    let pauses:  [PauseMarker]
}

// ── Parser ─────────────────────────────────────────────────────────────────────

func buildScrollStream(text: String, defaultColor: LEDColor,
                       onClickCommand: String?,
                       customChars: [String: [UInt8]] = [:]) -> ScrollStream {
    var columns: [ColoredColumn] = []
    var pauses:  [PauseMarker]   = []
    var color    = defaultColor
    var i        = text.startIndex

    while i < text.endIndex {
        // Control code?
        if text[i] == "\\", text.index(after: i) < text.endIndex {
            let ni = text.index(after: i)
            if text[ni] == "c" || text[ni] == "p" || text[ni] == "g" {
                if let (code, end) = parseCode(text, from: i) {
                    switch code {
                    case .color(let c):
                        color = c
                    case .pause(var k):
                        if case .sticky(nil, let b) = k, let cmd = onClickCommand {
                            k = .sticky(onClickCommand: cmd, blinks: b)
                        }
                        pauses.append(PauseMarker(at: columns.count, kind: k))
                    case .glyph(let name):
                        if let vals = customChars[name] {
                            var padded = vals
                            while padded.count < 6 { padded.append(0x00) }
                            columns += padded.map { ColoredColumn(value: $0, color: color) }
                        }
                    }
                    i = end
                    continue
                }
            }
        }

        // Reguläres Zeichen
        let ch   = Character(String(text[i]).uppercased())
        let vals: [UInt8]

        if let custom = customChars[String(ch)] {
            vals = custom
        } else {
            vals = FONT[ch] ?? FONT[" "]!
        }

        // Pad to 6 columns so custom chars with fewer values still get a gap
        var padded = vals
        while padded.count < 6 { padded.append(0x00) }

        columns += padded.map { ColoredColumn(value: $0, color: color) }
        i = text.index(after: i)
    }

    return ScrollStream(columns: columns, pauses: pauses)
}

private enum ParsedCode {
    case color(LEDColor)
    case pause(PauseKind)
    case glyph(String)
}

private func parseCode(_ text: String, from start: String.Index) -> (ParsedCode, String.Index)? {
    var i = text.index(after: start)
    guard i < text.endIndex else { return nil }
    let type = text[i]
    i = text.index(after: i)
    guard i < text.endIndex, text[i] == "[" else { return nil }
    i = text.index(after: i)
    var content = ""
    while i < text.endIndex, text[i] != "]" { content.append(text[i]); i = text.index(after: i) }
    guard i < text.endIndex else { return nil }
    i = text.index(after: i)

    switch type {
    case "c": return (.color(LEDColor.from(content)), i)
    case "p":
        if content.hasPrefix("sticky") {
            let blinks = content.hasPrefix("sticky:") ? Int(content.dropFirst(7)) ?? 2 : 2
            return (.pause(.sticky(onClickCommand: nil, blinks: blinks)), i)
        }
        if let s = Double(content) { return (.pause(.timed(seconds: s)), i) }
    case "g": return (.glyph(content.lowercased()), i)
    default: break
    }
    return nil
}

// ── JSON-Kodierung für Socket-Protokoll ────────────────────────────────────────

struct SocketMessage: Codable {
    var type:      String
    var text:      String?
    var priority:  String?
    var duration:  Double?
    var on_click:  String?
    var width:     Int?
}

func decodeSocketMessage(_ raw: String) -> TickerMessage? {
    guard let data = raw.data(using: .utf8),
          let m = try? JSONDecoder().decode(SocketMessage.self, from: data)
    else { return nil }

    let kind     = MessageKind(rawValue: m.type) ?? .scroll
    let priority = Priority(rawValue: m.priority ?? "normal") ?? .normal

    return TickerMessage(
        kind:           kind,
        text:           m.text ?? "",
        priority:       priority,
        duration:       m.duration ?? 5,
        onClickCommand: m.on_click,
        width:          m.width
    )
}

func encodeSocketMessage(_ msg: TickerMessage) -> String {
    var m        = SocketMessage(type: msg.kind.rawValue)
    m.text       = msg.text.isEmpty ? nil : msg.text
    m.priority   = msg.priority.rawValue
    m.duration   = msg.kind == .standby ? msg.duration : nil
    m.on_click   = msg.onClickCommand
    m.width      = msg.width
    let data     = try? JSONEncoder().encode(m)
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}
