// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Keyflow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Keyflow",
            path: "Sources/Keyflow"
        )
    ]
)
