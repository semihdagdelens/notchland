// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Notchland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Notchland",
            path: "Sources/Notchland"
        )
    ]
)
