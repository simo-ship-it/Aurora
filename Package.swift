// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aurora",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Aurora", path: "Sources/Aurora")
    ]
)
