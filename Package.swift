// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexSwitchbar",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwitchCore", targets: ["SwitchCore"]),
        .executable(name: "CodexSwitchbar", targets: ["CodexSwitchbar"])
    ],
    targets: [
        .target(name: "SwitchCore"),
        .executableTarget(name: "CodexSwitchbar", dependencies: ["SwitchCore"]),
        .testTarget(name: "SwitchCoreTests", dependencies: ["SwitchCore"])
    ]
)
