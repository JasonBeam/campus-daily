// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CampusHotWater",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WaterCore", targets: ["WaterCore"]),
               .executable(name: "water-evidence-check", targets: ["WaterEvidenceCheck"]),
               .executable(name: "campus-read-check", targets: ["CampusReadCheck"])],
    targets: [.target(name: "WaterCore"),
              .executableTarget(name: "WaterEvidenceCheck", dependencies: ["WaterCore"]),
              .executableTarget(name: "CampusReadCheck", dependencies: ["WaterCore"]),
              .testTarget(name: "WaterCoreTests", dependencies: ["WaterCore"])],
    swiftLanguageModes: [.v5]
)
