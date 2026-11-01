// swift-tools-version: 6.0
import PackageDescription

// UI-free logic shared by the app and the widget, one folder per feature (Swift 6 mode).
// Tests: one target per feature folder; synthetic fixtures in Tests/Fixtures.
let package = Package(
    name: "Core",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "CoreTestSupport", dependencies: ["Core"], path: "Tests/Support"),
        .testTarget(name: "CampusTests", dependencies: ["Core", "CoreTestSupport"]),
        .testTarget(name: "ShowerTests", dependencies: ["Core", "CoreTestSupport"]),
        .testTarget(name: "LaundryTests", dependencies: ["Core", "CoreTestSupport"]),
        .testTarget(name: "SnapshotTests", dependencies: ["Core", "CoreTestSupport"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Core", "CoreTestSupport"]),
        .testTarget(name: "StorageTests", dependencies: ["Core"]),
        .testTarget(name: "CommonTests", dependencies: ["Core", "CoreTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
