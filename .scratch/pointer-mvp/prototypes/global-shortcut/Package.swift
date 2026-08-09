// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GlobalShortcutPrototype",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GlobalShortcutPrototype", targets: ["GlobalShortcutPrototype"])
    ],
    targets: [
        .executableTarget(name: "GlobalShortcutPrototype")
    ],
    swiftLanguageModes: [.v5]
)
