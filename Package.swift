// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Galpium",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "GalpiumCore", targets: ["GalpiumCore"]),
    .executable(name: "Galpium", targets: ["GalpiumApp"]),
    .executable(name: "galpium-mcp", targets: ["GalpiumMCP"]),
    .executable(name: "galpium-embedder", targets: ["GalpiumEmbedder"]),
  ],
  targets: [
    .systemLibrary(name: "CSQLite"),
    .target(name: "GalpiumCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
    .executableTarget(name: "GalpiumApp", dependencies: ["GalpiumCore"]),
    .executableTarget(name: "GalpiumMCP", dependencies: ["GalpiumCore"]),
    .executableTarget(name: "GalpiumEmbedder", dependencies: ["GalpiumCore"]),
    .testTarget(name: "GalpiumCoreTests", dependencies: ["GalpiumCore"]),
    .testTarget(name: "GalpiumAppTests", dependencies: ["GalpiumApp", "GalpiumCore"]),
  ],
  swiftLanguageModes: [.v6]
)
