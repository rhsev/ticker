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

// Bereits laufende Instanz erkennen: Socket-Datei vorhanden + connect erfolgreich → exit
if FileManager.default.fileExists(atPath: socketPath) {
    let checkFd = socket(AF_UNIX, SOCK_STREAM, 0)
    if checkFd >= 0 {
        var checkAddr = sockaddr_un()
        checkAddr.sun_family = sa_family_t(AF_UNIX)
        let pathSize = MemoryLayout.size(ofValue: checkAddr.sun_path)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &checkAddr.sun_path.0) { _ = strlcpy($0, src, pathSize) }
        }
        let connected = withUnsafePointer(to: &checkAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(checkFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        } == 0
        if connected {
            // Gültigen Request senden damit der Server sauber abhandelt
            let ping = "{\"type\":\"get_status\"}\n"
            ping.withCString { _ = send(checkFd, $0, strlen($0), 0) }
            var buf = [UInt8](repeating: 0, count: 64)
            _ = recv(checkFd, &buf, buf.count, 0)
            close(checkFd)
            fputs("ticker: already running\n", stderr)
            exit(0)
        } else {
            // Veraltete Socket-Datei entfernen
            close(checkFd)
            unlink(socketPath)
        }
    }
}


let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate

// URL-Handler immer registrieren — handleURL prüft config.milanctlPath
NSAppleEventManager.shared().setEventHandler(
    delegate,
    andSelector: #selector(AppDelegate.handleURL(_:withReply:)),
    forEventClass: AEEventClass(kInternetEventClass),
    andEventID: AEEventID(kAEGetURL)
)

app.run()
