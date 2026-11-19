// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Regia",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Regia", path: "Sources/Regia")
    ]
)
