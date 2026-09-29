// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Ortu",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Ortu", targets: ["Ortu"])
    ],
    targets: [
        .executableTarget(
            name: "Ortu",
            path: "Sources/Ortu",
            resources: [
                .copy("Resources/BuiltinPacks"),
                .process("Resources/en.lproj"),
                .process("Resources/tr.lproj"),
            ]
        ),
        .testTarget(
            name: "OrtuTests",
            dependencies: ["Ortu"],
            path: "Tests/OrtuTests"
        ),
    ],
)
