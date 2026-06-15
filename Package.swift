// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SystemMonitorBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SystemMonitorBar",
            path: "Sources/SystemMonitorBar"
        )
    ]
)
