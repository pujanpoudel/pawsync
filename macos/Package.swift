// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PawSync",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0")
    ],
    targets: [.executableTarget(name: "PawSync", dependencies: [
        .product(name: "Sparkle", package: "Sparkle"),
        .product(name: "Sentry-Dynamic", package: "sentry-cocoa")
    ], path: "Sources/PawSync")],
    swiftLanguageVersions: [.v5]
)
