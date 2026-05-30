import AppKit

private let maxPending = 3
private let blinkDuration = 0.4   // Sekunden pro Blink-Phase

// ── Animations-Phase ───────────────────────────────────────────────────────────

private enum Phase {
    case idle
    case scrolling                              // scrollIn + scrollOut in einem
    case pauseInStream(until: Date)             // \p[N] getriggert
    case stickyBlink(phase: Int, until: Date, cmd: String?, blinks: Int)
    case stickyWait(cmd: String?)               // wartet auf Klick
    case defaultPause(until: Date)              // End-of-message Pause
    case standby(until: Date)                   // Standby-Text
}

// ── App Delegate ───────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var animTimer:  Timer?
    private var pauseItem:  NSMenuItem?
    private var config:     TickerConfig!

    // Milan state
    private var milanInstalled = false
    private var milanRunning   = false
    private var statusTimer:   Timer?

    // Zustand
    private var displayWidth: Int = 20
    private var phase: Phase = .idle
    private var userPaused = false
    private var idleRendered = false

    // Aktuelle Scroll-Animation
    private var canvas:      [ColoredColumn] = []
    private var scrollOffset = 0
    private var pendingPauses: [PauseMarker] = []   // noch nicht getriggert
    private var currentMsg:  TickerMessage?          // für very-urgent Replay

    // Queue
    private var queue:     [TickerMessage] = []
    private let queueLock = NSLock()
    private var interrupted: TickerMessage? = nil    // sehr-dringend unterbrochene Msg

    // ── Setup ──────────────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ notification: Notification) {
        config           = loadConfig()
        displayWidth     = config.defaultWidth
        renderTransparent = config.transparent

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = ""

        // Klick-Handler
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp])

        // Milan-Status (nur wenn milanctlPath gesetzt)
        if !config.milanctlPath.isEmpty {
            checkMilanStatus()
            let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                self?.checkMilanStatus()
            }
            RunLoop.main.add(t, forMode: .common)
            statusTimer = t
        }

        // Animations-Timer (immer aktiv; tick() prüft tickerEnabled)
        let timer = Timer(timeInterval: config.scrollSpeed, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        animTimer = timer

        runSocketServer { [weak self] msg -> String in
            guard let self else { return "error" }
            if msg.kind == .getStatus { return self.statusJSON() }
            var reply = "ok"
            DispatchQueue.main.sync { reply = self.receive(msg) }
            return reply
        }
    }

    // ── Milan-Status ───────────────────────────────────────────────────────────

    private func checkMilanStatus() {
        let ctlPath    = (config.milanctlPath as NSString).expandingTildeInPath
        milanInstalled = !config.milanctlPath.isEmpty &&
                         FileManager.default.fileExists(atPath: ctlPath)
        let port = config.milanPort
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let running = Self.tcpReachable(port: port)
            DispatchQueue.main.async {
                guard let self else { return }
                self.milanRunning = running
                self.idleRendered = false
                if case .idle = self.phase { self.setIdle() }
            }
        }
    }

    private static func tcpReachable(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_family      = sa_family_t(AF_INET)
        addr.sin_port        = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func currentIdleColor() -> LEDColor {
        guard !config.milanctlPath.isEmpty else { return LEDColor.from(config.defaultColor) }
        return (milanInstalled && !milanRunning) ? .red : .white
    }

    // ── Menü ───────────────────────────────────────────────────────────────────

    @objc private func statusItemClicked() {
        if case .stickyWait(let cmd) = phase {
            if let cmd = cmd {
                let proc = Process()
                proc.launchPath = "/bin/sh"
                proc.arguments  = ["-c", cmd]
                try? proc.run()
            }
            phase = .scrolling
        } else {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Milan-Abschnitt (nur wenn milanctlPath gesetzt)
        if !config.milanctlPath.isEmpty {
            let label: String
            if !milanInstalled {
                label = "Milan nicht konfiguriert"
            } else {
                label = milanRunning ? "● Milan läuft" : "○ Milan gestoppt"
            }
            let si = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            si.isEnabled = false
            menu.addItem(si)
            if milanInstalled {
                let ti = NSMenuItem(title: milanRunning ? "Stoppen" : "Starten",
                                    action: #selector(toggleMilan), keyEquivalent: "")
                ti.target = self
                menu.addItem(ti)
            }
            menu.addItem(.separator())
        }

        // Ticker-Steuerung (nur wenn aktiv)
        if config.tickerEnabled {
            let ci = NSMenuItem(title: "Clear queue", action: #selector(clearQueue), keyEquivalent: "")
            ci.target = self
            menu.addItem(ci)
            menu.addItem(.separator())
            let pi = NSMenuItem(title: userPaused ? "Resume" : "Pause",
                                action: #selector(togglePause), keyEquivalent: "")
            pi.target = self
            pauseItem = pi
            menu.addItem(pi)
            menu.addItem(.separator())
        }

        // Ticker-Toggle
        let tickerItem = NSMenuItem(title: "Ticker", action: #selector(toggleTickerEnabled),
                                    keyEquivalent: "")
        tickerItem.target = self
        tickerItem.state  = config.tickerEnabled ? .on : .off
        menu.addItem(tickerItem)
        menu.addItem(.separator())

        let qi = NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q")
        qi.target = self
        menu.addItem(qi)

        return menu
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    @objc private func toggleTickerEnabled() {
        config.tickerEnabled.toggle()
        saveConfig(config)
        idleRendered = false
        if case .idle = phase { setIdle() }
    }

    @objc private func toggleMilan() {
        if milanRunning {
            runMilanctl("stop") { [weak self] _, _ in self?.checkMilanStatus() }
        } else {
            runMilanctl("start") { [weak self] _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.checkMilanStatus()
                }
            }
        }
    }

    private func runMilanctl(_ command: String, completion: ((Int32, String) -> Void)? = nil) {
        let path = (config.milanctlPath as NSString).expandingTildeInPath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            completion?(-1, ""); return
        }
        let task = Process()
        let pipe = Pipe()
        task.executableURL  = URL(fileURLWithPath: "/bin/sh")
        task.arguments      = ["-c",
            "export PATH=$HOME/.rbenv/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:$PATH; " +
            "eval \"$(rbenv init - 2>/dev/null)\"; ruby '\(path)' \(command) 2>&1"]
        task.standardOutput = pipe
        task.standardError  = pipe
        task.terminationHandler = { t in
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            DispatchQueue.main.async { completion?(t.terminationStatus, out) }
        }
        try? task.run()
    }

    @objc private func clearQueue() {
        queueLock.lock(); queue.removeAll(); queueLock.unlock()
    }

    @objc private func togglePause() {
        userPaused = !userPaused
        pauseItem?.title = userPaused ? "Resume" : "Pause"
    }

    @objc private func quit() {
        animTimer?.invalidate()
        unlink(socketPath)
        NSApp.terminate(nil)
    }

    // ── URL-Handler (milan:// und ref://) ─────────────────────────────────────

    @objc func handleURL(_ event: NSAppleEventDescriptor,
                         withReply reply: NSAppleEventDescriptor) {
        guard let raw      = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let incoming = URL(string: raw),
              let host     = incoming.host
        else { return }
        let localPath = "/\(host)\(incoming.path)"
        let encoded   = localPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                        ?? localPath
        guard let target = URL(string: "http://localhost:\(config.milanPort)\(encoded)") else { return }
        URLSession.shared.dataTask(with: target) { _, _, _ in }.resume()
    }

    // ── Empfang ────────────────────────────────────────────────────────────────

    @discardableResult
    private func receive(_ msg: TickerMessage) -> String {
        guard config.tickerEnabled else { return "disabled" }

        switch msg.kind {
        case .setWidth:
            if let w = msg.width, w >= 5 { displayWidth = w }
            return "ok"
        case .quit:
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return "ok"
        case .clearQueue:
            queueLock.lock(); queue.removeAll(); queueLock.unlock()
            interrupted = nil
            phase = .idle
            setIdle()
            return "ok"
        case .getStatus:
            return statusJSON()
        case .scroll, .standby:
            break
        }

        switch msg.priority {
        case .normal:
            enqueue(msg)
        case .urgent:
            prependQueue(msg)
        case .veryUrgent:
            if case .scrolling = phase { interrupted = currentMsg }
            else if case .defaultPause = phase { interrupted = currentMsg }
            phase = .idle
            prependQueue(msg)
        }
        return "ok"
    }

    // ── Status ─────────────────────────────────────────────────────────────────

    private func statusJSON() -> String {
        let phaseName: String
        switch phase {
        case .idle:                    phaseName = "idle"
        case .scrolling:               phaseName = "scrolling"
        case .pauseInStream:           phaseName = "scrolling"
        case .defaultPause:            phaseName = "scrolling"
        case .stickyBlink, .stickyWait: phaseName = "sticky"
        case .standby:                 phaseName = "standby"
        }
        queueLock.lock()
        let count = queue.count
        queueLock.unlock()
        return "{\"phase\":\"\(phaseName)\",\"queue\":\(count)}"
    }

    // ── Timer-Tick (Main-Thread) ───────────────────────────────────────────────

    private func tick() {
        guard config.tickerEnabled, !userPaused else { return }

        switch phase {

        case .idle:
            if let saved = interrupted {
                interrupted = nil
                startMessage(saved)
                return
            }
            guard let msg = dequeueNext() else {
                setIdle(); return
            }
            startMessage(msg)

        case .scrolling:
            let vc = visCols(displayWidth: displayWidth)

            if let p = pendingPauses.first, p.at == scrollOffset {
                pendingPauses.removeFirst()
                triggerPause(p.kind)
                return
            }

            showScrollFrame()
            scrollOffset += 1

            if canvas.count <= vc || scrollOffset >= canvas.count - vc {
                phase = .idle
                setIdle()
            }

        case .pauseInStream(let until):
            if Date() >= until {
                phase = .scrolling
            }

        case .stickyBlink(let bphase, let until, let cmd, let blinks):
            if Date() >= until {
                let next = bphase + 1
                if next >= blinks * 2 {
                    showScrollFrame()
                    phase = .stickyWait(cmd: cmd)
                } else {
                    let on = (next % 2 != 0)
                    showScrollFrame(blank: !on)
                    phase = .stickyBlink(phase: next,
                                         until: Date().addingTimeInterval(blinkDuration),
                                         cmd: cmd, blinks: blinks)
                }
            }

        case .stickyWait:
            break  // wartet auf Klick

        case .defaultPause(let until):
            if Date() >= until {
                phase = .scrolling
            }

        case .standby(let until):
            if Date() >= until {
                phase = .idle
                setIdle()
            }
        }
    }

    // ── Nachricht starten ──────────────────────────────────────────────────────

    private func startMessage(_ msg: TickerMessage) {
        idleRendered = false
        currentMsg = msg
        let defColor = LEDColor.from(config.defaultColor)

        switch msg.kind {
        case .scroll:
            let stream   = buildScrollStream(text: msg.text, defaultColor: defColor,
                                              onClickCommand: msg.onClickCommand,
                                              customChars: config.customChars)
            let vc       = visCols(displayWidth: displayWidth)
            let pad      = [ColoredColumn](repeating: ColoredColumn(value: 0, color: defColor), count: vc)
            canvas       = pad + stream.columns + pad
            scrollOffset = 0

            var pauses   = stream.pauses.map { PauseMarker(at: $0.at + vc, kind: $0.kind) }
            let hasEarlyPause = pauses.contains { $0.at == vc }
            if !hasEarlyPause {
                pauses.insert(PauseMarker(at: vc, kind: .timed(seconds: config.defaultPause)), at: 0)
            }
            pendingPauses = pauses.sorted { $0.at < $1.at }
            phase         = .scrolling
            showScrollFrame()

        case .standby:
            let img = renderStandbyFrame(text: msg.text, displayWidth: displayWidth,
                                         defaultColor: defColor, customChars: config.customChars)
            setImage(img)
            phase = .standby(until: Date().addingTimeInterval(msg.duration))

        case .setWidth, .clearQueue, .getStatus, .quit:
            break
        }
    }

    // ── Pause auslösen ─────────────────────────────────────────────────────────

    private func triggerPause(_ kind: PauseKind) {
        switch kind {
        case .timed(let secs):
            phase = .pauseInStream(until: Date().addingTimeInterval(secs))
        case .sticky(let cmd, let blinks):
            if blinks == 0 {
                phase = .stickyWait(cmd: cmd)
            } else {
                showScrollFrame(blank: true)
                phase = .stickyBlink(phase: 0,
                                      until: Date().addingTimeInterval(blinkDuration),
                                      cmd: cmd, blinks: blinks)
            }
        }
    }

    // ── Darstellung ────────────────────────────────────────────────────────────

    private func showScrollFrame(blank: Bool = false) {
        let img = renderScrollFrame(columns: canvas, offset: scrollOffset,
                                     displayWidth: displayWidth, blank: blank)
        setImage(img)
    }

    private func setImage(_ img: NSImage) {
        statusItem.button?.image = img
        statusItem.button?.title = ""
    }

    private func setIdle() {
        guard !idleRendered else { return }
        idleRendered = true
        setImage(renderIdleIcon(color: currentIdleColor()))
    }

    // ── Queue ──────────────────────────────────────────────────────────────────

    private func enqueue(_ msg: TickerMessage) {
        queueLock.lock()
        if queue.count >= maxPending { queue.removeFirst() }
        queue.append(msg)
        queueLock.unlock()
    }

    private func prependQueue(_ msg: TickerMessage) {
        queueLock.lock()
        queue.insert(msg, at: 0)
        queueLock.unlock()
    }

    private func dequeueNext() -> TickerMessage? {
        queueLock.lock()
        defer { queueLock.unlock() }
        return queue.isEmpty ? nil : queue.removeFirst()
    }
}
