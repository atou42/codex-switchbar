// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexSwitchbar",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwitchCore", targets: ["SwitchCore"]),
        .executable(name: "CodexSwitchbar", targets: ["CodexSwitchbar"]),
        .executable(name: "codex-switch", targets: ["CodexSwitchCLI"])
    ],
    targets: [
        .target(name: "SwitchCore"),
        .executableTarget(name: "CodexSwitchbar", dependencies: ["SwitchCore"]),
        .executableTarget(name: "CodexSwitchCLI", dependencies: ["SwitchCore"]),
        .testTarget(name: "SwitchCoreTests", dependencies: ["SwitchCore"]),
        .testTarget(name: "AppLifecycleTests", dependencies: ["CodexSwitchbar"])
    ]
)
