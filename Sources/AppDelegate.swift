import AppKit

private let idleTitle  = "●"
private let maxPending = 3
private let blinkDuration = 0.15  // Sekunden pro Blink-Phase

// ── Animations-Phase ───────────────────────────────────────────────────────────

private enum Phase {
    case idle
    case scrolling                              // scrollIn + scrollOut in einem
    case pauseInStream(until: Date)             // \p[N] getriggert
    case stickyBlink(phase: Int, until: Date, cmd: String?)  // 0-3: blink
    case stickyWait(cmd: String?)               // wartet auf Klick
    case defaultPause(until: Date)              // End-of-message Pause
    case standby(until: Date)                   // Standby-Text
}

// ── App Delegate ───────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var animTimer:  Timer?
    private var config:     TickerConfig!
    private var pauseItem:  NSMenuItem!

    // Zustand
    private var displayWidth: Int = 20
    private var phase: Phase = .idle
    private var userPaused = false

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
        config       = loadConfig()
        displayWidth = config.defaultWidth

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = idleTitle

        // Klick-Handler (für sticky)
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp])

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Clear queue", action: #selector(clearQueue), keyEquivalent: ""))
        menu.addItem(.separator())
        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        // Menu nur über Rechtsklick öffnen; Linksklick geht an sticky
        statusItem.menu = nil

        animTimer = Timer.scheduledTimer(withTimeInterval: config.scrollSpeed,
                                         repeats: true) { [weak self] _ in self?.tick() }

        runSocketServer { [weak self] msg in
            DispatchQueue.main.async { self?.receive(msg) }
        }
    }

    // ── Empfang ────────────────────────────────────────────────────────────────

    private func receive(_ msg: TickerMessage) {
        switch msg.kind {
        case .setWidth:
            if let w = msg.width, w >= 5 { displayWidth = w }
            return
        case .scroll, .standby:
            break
        }

        switch msg.priority {
        case .normal:
            enqueue(msg)
        case .urgent:
            prependQueue(msg)
        case .veryUrgent:
            // Laufende Nachricht abbrechen und speichern
            if case .scrolling = phase { interrupted = currentMsg }
            else if case .defaultPause = phase { interrupted = currentMsg }
            phase = .idle
            prependQueue(msg)
        }
    }

    // ── Timer-Tick (Main-Thread) ───────────────────────────────────────────────

    private func tick() {
        guard !userPaused else { return }

        switch phase {

        case .idle:
            // Unterbrochene Nachricht zuerst zurückspielen
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

            // Pause-Trigger prüfen (Spalte am linken Rand)
            if let p = pendingPauses.first, p.at == scrollOffset {
                pendingPauses.removeFirst()
                triggerPause(p.kind)
                return
            }

            showScrollFrame()
            scrollOffset += 1

            // Ende: letzter sichtbarer Frame
            if canvas.count <= vc || scrollOffset >= canvas.count - vc {
                phase = .idle
                setIdle()
            }

        case .pauseInStream(let until):
            if Date() >= until {
                phase = .scrolling
            }

        case .stickyBlink(let bphase, let until, let cmd):
            if Date() >= until {
                let next = bphase + 1
                if next >= 4 {
                    phase = .stickyWait(cmd: cmd)
                } else {
                    let on = (next % 2 == 0)
                    showScrollFrame(blank: !on)
                    phase = .stickyBlink(phase: next,
                                         until: Date().addingTimeInterval(blinkDuration),
                                         cmd: cmd)
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

            // Pausen: Offset um vc verschieben (wegen führendem Padding)
            // Außerdem Default-Endpause einfügen wenn keine expliziten Pausen am Ende
            var pauses   = stream.pauses.map { PauseMarker(at: $0.at + vc, kind: $0.kind) }
            // Default-Pause: wenn Text vollständig eingerollt (offset == vc)
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

        case .setWidth:
            break
        }
    }

    // ── Pause auslösen ─────────────────────────────────────────────────────────

    private func triggerPause(_ kind: PauseKind) {
        switch kind {
        case .timed(let secs):
            phase = .pauseInStream(until: Date().addingTimeInterval(secs))
        case .sticky(let cmd):
            // 2 Blinks: 4 Phasen à blinkDuration
            showScrollFrame(blank: true)
            phase = .stickyBlink(phase: 0,
                                  until: Date().addingTimeInterval(blinkDuration),
                                  cmd: cmd)
        }
    }

    // ── Klick ──────────────────────────────────────────────────────────────────

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
            // Rechtsklick-Menü manuell öffnen
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
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
        statusItem.button?.image = nil
        statusItem.button?.title = idleTitle
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

    // ── Menü ───────────────────────────────────────────────────────────────────

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Clear queue", action: #selector(clearQueue), keyEquivalent: ""))
        menu.addItem(.separator())
        let pi = NSMenuItem(title: userPaused ? "Resume" : "Pause",
                            action: #selector(togglePause), keyEquivalent: "")
        pi.target = self
        menu.addItem(pi)
        menu.addItem(.separator())
        let qi = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        qi.target = self
        menu.addItem(qi)
        return menu
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
}
