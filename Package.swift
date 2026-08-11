// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Pointer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PointerCore", targets: ["PointerCore"]),
        .library(name: "PointerAppKit", targets: ["PointerAppKit"]),
        .executable(name: "Pointer", targets: ["Pointer"]),
    ],
    targets: [
        .target(name: "PointerCore"),
        .target(
            name: "PointerAppKit",
            dependencies: ["PointerCore"]
        ),
        .executableTarget(
            name: "Pointer",
            dependencies: ["PointerAppKit"]
        ),
        .testTarget(name: "PointerCoreTests", dependencies: ["PointerCore"]),
        .testTarget(
            name: "PointerAppKitTests",
            dependencies: ["PointerAppKit"]
        ),
    ]
)
