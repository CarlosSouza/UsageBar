// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "UsageBar", targets: ["UsageBar"])],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "UsageBar", dependencies: ["UsageCore"]),
        .executableTarget(name: "UsageCoreChecks", dependencies: ["UsageCore"], path: "Tests/UsageCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
