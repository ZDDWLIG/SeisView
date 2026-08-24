// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeisView",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SegyKit"),
        .executableTarget(name: "SegyKitTests", dependencies: ["SegyKit"]),
        .executableTarget(name: "SeisView", dependencies: ["SegyKit"]),
    ]
)
