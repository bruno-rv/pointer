// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MarkRenderingPrototype",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MarkRenderingPrototype"),
        .testTarget(
            name: "MarkRenderingPrototypeTests",
            dependencies: ["MarkRenderingPrototype"]
        )
    ]
)
