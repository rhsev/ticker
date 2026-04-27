// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ticker",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "ticker",
            path: "Sources"
        )
    ]
)
