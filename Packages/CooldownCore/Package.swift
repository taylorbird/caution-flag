// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "CooldownCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CooldownCore", targets: ["CooldownCore"]),
        .executable(name: "cooldown-harness", targets: ["cooldown-harness"]),
    ],
    targets: [
        .target(name: "CooldownCore", swiftSettings: v5),
        .executableTarget(name: "cooldown-harness", dependencies: ["CooldownCore"], swiftSettings: v5),
        .testTarget(name: "CooldownCoreTests", dependencies: ["CooldownCore"], swiftSettings: v5),
    ]
)
