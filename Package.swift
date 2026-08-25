// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeisView",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SegyKit"),
        .target(name: "Localization", dependencies: ["SegyKit"]),
        .executableTarget(name: "SegyKitTests", dependencies: ["SegyKit", "Localization"]),
        .executableTarget(name: "SeisView", dependencies: ["SegyKit", "Localization"]),
    ]
)
