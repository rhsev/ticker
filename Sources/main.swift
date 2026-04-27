import AppKit

// CLI mode: ticker --send "TEXT"
if CommandLine.arguments.count > 1 {
    let args = CommandLine.arguments.dropFirst()
    if let idx = args.firstIndex(where: { $0 == "--send" || $0 == "-s" }),
       args.index(after: idx) < args.endIndex {
        cliSend(String(args[args.index(after: idx)]))
        exit(0)
    }
    fputs("Usage: ticker --send \"MESSAGE\"\n", stderr)
    exit(1)
}

// App mode
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // kein Dock-Icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
