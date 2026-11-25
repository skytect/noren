// swift-tools-version: 6.2
import PackageDescription

// Swift 6.2's approachable concurrency: async functions run where they are called unless marked
// @concurrent, and conformances may be isolated
let approachableConcurrency: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
  name: "noren",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "noren", targets: ["Noren"])
  ],
  dependencies: [
    // TOML 1.1 into Codable types, pure Swift, MIT
    .package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.5")
  ],
  targets: [
    // The app: AppKit, so on the main actor unless said otherwise
    .executableTarget(
      name: "Noren",
      dependencies: ["NorenCore", "NorenPrivate"],
      swiftSettings: approachableConcurrency + [.defaultIsolation(MainActor.self)]
    ),
    // C declarations for the Dock protocol and the private macOS calls (its module.modulemap)
    .systemLibrary(name: "NorenPrivate"),
    // What can be worked out without the screen, AeroSpace or macOS: kept apart so it is tested
    .target(
      name: "NorenCore",
      dependencies: ["TOMLDecoder"],
      swiftSettings: approachableConcurrency
    ),
    .testTarget(
      name: "NorenCoreTests",
      dependencies: ["NorenCore"],
      swiftSettings: approachableConcurrency
    ),
  ]
)
