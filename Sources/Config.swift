import Foundation

struct TickerConfig: Codable {
    // Ticker display
    var tickerEnabled:     Bool              = true
    var defaultColor:      String            = "amber"
    var defaultWidth:      Int               = 20
    var scrollSpeed:       Double            = 0.05
    var defaultPause:      Double            = 3.0
    var customChars:       [String: [UInt8]] = [:]
    var transparent:       Bool              = true
    // Farbe im Transparentmodus: "auto" überlässt sie der Menüleiste
    // (hell/dunkel), ein Farbname färbt die Punkte fest ein.
    var transparentColor:  String            = "auto"

    // Milan HTTP port — used by the milan:// URL handler
    var milanPort: Int = 8080
}

private let configURL: URL = {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ticker/config.json")
}()

func loadConfig() -> TickerConfig {
    if let data = try? Data(contentsOf: configURL),
       let decoded = try? JSONDecoder().decode(TickerConfig.self, from: data) {
        return decoded
    }
    let defaults = TickerConfig()
    saveConfig(defaults)
    return defaults
}

func saveConfig(_ config: TickerConfig) {
    let dir = configURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = .prettyPrinted
    if let data = try? enc.encode(config) {
        try? data.write(to: configURL)
    }
}
