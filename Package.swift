// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftLib",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftLibCore", targets: ["SwiftLibCore"]),
        .executable(name: "SwiftLib", targets: ["SwiftLib"]),
        .executable(name: "swiftlib-cli", targets: ["SwiftLibCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.7.0"),
        .package(url: "https://github.com/Lakr233/MarkdownView.git", from: "3.9.1"),
    ],
    targets: [
        .target(
            name: "SwiftLibCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            exclude: [
                "Services/MetadataResolution.swift.bak",
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "SwiftLib",
            dependencies: [
                "SwiftLibCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MarkdownView", package: "MarkdownView"),
            ],
            exclude: [
                "SwiftLib.entitlements"
            ],
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "SwiftLibCLI",
            dependencies: [
                "SwiftLibCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SwiftLibCoreTests",
            dependencies: ["SwiftLibCore"],
            path: "Tests/SwiftLibCoreTests"
        ),
        .testTarget(
            name: "SwiftLibTests",
            dependencies: ["SwiftLib", "SwiftLibCore"],
            path: "Tests/SwiftLibTests"
        ),
        .testTarget(
            name: "SwiftLibCLITests",
            dependencies: [],
            path: "Tests/SwiftLibCLITests"
        ),
    ]
)
