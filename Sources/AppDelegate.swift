import AppKit

private let maxPending  = 3
private let scrollSpeed = 0.05
private let pauseTicks  = 60
private let idleTitle   = "●"

enum AnimPhase { case idle, scrollIn, pause, scrollOut }

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var animTimer: Timer?

    private var messageQueue: [String] = []
    private let queueLock = NSLock()

    private var phase      = AnimPhase.idle
    private var columns    = [UInt8]()
    private var offset     = 0
    private var pauseCount = 0
    private var textLen    = 0
    private var paused     = false

    private var pauseItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = idleTitle

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Enter message…", action: #selector(addViaMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear queue",    action: #selector(clearQueue),  keyEquivalent: ""))
        menu.addItem(.separator())
        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items { item.target = self }
        statusItem.menu = menu

        animTimer = Timer.scheduledTimer(withTimeInterval: scrollSpeed, repeats: true) { [weak self] _ in
            self?.tick()
        }

        runSocketServer { [weak self] text in
            self?.enqueue(text)
        }
    }

    // ── Animation ───────────────────────────────────────────────────────────────

    private func tick() {
        guard !paused else { return }

        switch phase {
        case .idle:
            guard let text = dequeue() else { return }
            let textCols = textToColumns(text)
            textLen = textCols.count
            columns = [UInt8](repeating: BLANK_COL, count: visibleCols)
                    + textCols
                    + [UInt8](repeating: BLANK_COL, count: visibleCols)
            offset = 0
            phase  = .scrollIn
            showFrame()

        case .scrollIn:
            offset += 1
            showFrame()
            if offset >= visibleCols {
                phase      = .pause
                pauseCount = 0
            }

        case .pause:
            pauseCount += 1
            if pauseCount >= pauseTicks { phase = .scrollOut }

        case .scrollOut:
            offset += 1
            showFrame()
            if offset >= visibleCols + textLen {
                phase = .idle
                statusItem.button?.image = nil
                statusItem.button?.title = idleTitle
            }
        }
    }

    private func showFrame() {
        let img = renderFrame(columns: columns, offset: offset)
        statusItem.button?.image = img
        statusItem.button?.title = ""
    }

    // ── Queue ────────────────────────────────────────────────────────────────────

    private func enqueue(_ text: String) {
        queueLock.lock()
        if messageQueue.count >= maxPending { messageQueue.removeFirst() }
        messageQueue.append(text)
        queueLock.unlock()
    }

    private func dequeue() -> String? {
        queueLock.lock()
        defer { queueLock.unlock() }
        return messageQueue.isEmpty ? nil : messageQueue.removeFirst()
    }

    // ── Menu actions ─────────────────────────────────────────────────────────────

    @objc private func addViaMenu() {
        let alert = NSAlert()
        alert.messageText    = "Enter message"
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn, !input.stringValue.isEmpty {
            enqueue(input.stringValue)
        }
    }

    @objc private func clearQueue() {
        queueLock.lock()
        messageQueue.removeAll()
        queueLock.unlock()
    }

    @objc private func togglePause() {
        paused = !paused
        pauseItem.title = paused ? "Resume" : "Pause"
    }

    @objc private func quit() {
        animTimer?.invalidate()
        unlink(socketPath)
        NSApp.terminate(nil)
    }
}
