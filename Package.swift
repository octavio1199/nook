// swift-tools-version: 6.2
import PackageDescription

let isolation: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Nook",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Nook", path: "Sources/Nook", swiftSettings: isolation),
        .testTarget(name: "NookTests", dependencies: ["Nook"], path: "Tests/NookTests", swiftSettings: isolation),
    ]
)
