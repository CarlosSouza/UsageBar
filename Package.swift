// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "UsageBar", targets: ["UsageBar"]),
        .executable(name: "UsageBarWidget", targets: ["UsageBarWidget"])
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "UsageBar", dependencies: ["UsageCore"]),
        // WidgetKit extensions must start at NSExtensionMain; with the default entry point the
        // extension traps during bootstrap and never shows up in the widget gallery.
        .executableTarget(
            name: "UsageBarWidget",
            dependencies: ["UsageCore"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .executableTarget(name: "UsageCoreChecks", dependencies: ["UsageCore"], path: "Tests/UsageCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
