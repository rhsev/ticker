import AppKit
import Foundation

// ── CLI-Modus ──────────────────────────────────────────────────────────────────

if CommandLine.arguments.count > 1 {
    let args = Array(CommandLine.arguments.dropFirst())

    func value(for flags: [String]) -> String? {
        for f in flags {
            if let i = args.firstIndex(of: f), i + 1 < args.count { return args[i + 1] }
        }
        return nil
    }
    func has(_ flags: [String]) -> Bool { flags.contains { args.contains($0) } }

    let text      = value(for: ["--send", "-s",
                                "--urgent", "-u",
                                "--very-urgent", "-vu",
                                "--standby",
                                "--standby-urgent",
                                "--standby-very-urgent"])
    let onClickCmd = value(for: ["--on-click"])
    let duration  = value(for: ["--duration"]).flatMap(Double.init) ?? 5.0
    let width     = value(for: ["--width"]).flatMap(Int.init)

    // --clear
    if has(["--clear"]) {
        let msg = TickerMessage(kind: .clearQueue, text: "", priority: .normal,
                                duration: 0, onClickCommand: nil, width: nil)
        cliSend(msg); exit(0)
    }

    // --quit
    if has(["--quit"]) {
        let msg = TickerMessage(kind: .quit, text: "", priority: .normal,
                                duration: 0, onClickCommand: nil, width: nil)
        cliSend(msg); exit(0)
    }

    // --status
    if has(["--status"]) {
        let msg = TickerMessage(kind: .getStatus, text: "", priority: .normal,
                                duration: 0, onClickCommand: nil, width: nil)
        cliSend(msg); exit(0)
    }

    // --width
    if let w = width, text == nil {
        let msg = TickerMessage(kind: .setWidth, text: "", priority: .normal,
                                duration: 0, onClickCommand: nil, width: w)
        cliSend(msg); exit(0)
    }

    guard let txt = text else {
        fputs("""
        Usage:
          ticker --send TEXT [--on-click CMD]
          ticker --urgent TEXT [--on-click CMD]
          ticker --very-urgent TEXT [--on-click CMD]
          ticker --standby TEXT --duration N
          ticker --standby-urgent TEXT --duration N
          ticker --standby-very-urgent TEXT --duration N
          ticker --width N
          ticker --clear
          ticker --status
          ticker --quit
        """, stderr)
        exit(1)
    }

    let kind: MessageKind = has(["--standby", "--standby-urgent", "--standby-very-urgent"])
        ? .standby : .scroll

    let priority: Priority
    if      has(["--very-urgent", "-vu", "--standby-very-urgent"]) { priority = .veryUrgent }
    else if has(["--urgent",      "-u",  "--standby-urgent"])      { priority = .urgent }
    else                                                            { priority = .normal }

    let msg = TickerMessage(kind: kind, text: txt, priority: priority,
                            duration: duration, onClickCommand: onClickCmd, width: nil)
    cliSend(msg)
    exit(0)
}

// ── App-Modus ──────────────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
