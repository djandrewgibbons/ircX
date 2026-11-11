// swift-tools-version: 6.2
import PackageDescription

// EmberKit speaks Ember's HTTP API and WebSocket protocol (ember-cloudflare's packages/protocol). IRCXUI
// is the SwiftUI app shared by the macOS and iOS targets (macOS/ and iOS/), which project.yml makes:
// its Suite theme is built on AppCoreUI, and its IRC Classic theme is its own.
let package = Package(
  name: "ircX",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "EmberKit", targets: ["EmberKit"]),
    .library(name: "IRCXUI", targets: ["IRCXUI"]),
  ],
  dependencies: [
    // The dxnd suite's design system, which the Suite theme is built on.
    .package(url: "https://github.com/djandrewgibbons/dxnd-app-core", branch: "main"),
  ],
  targets: [
    .target(name: "EmberKit", path: "Shared/EmberKit"),
    .target(name: "IRCXUI", dependencies: ["EmberKit", .product(name: "AppCoreUI", package: "dxnd-app-core")], path: "Shared/IRCXUI"),
    .testTarget(name: "EmberKitTests", dependencies: ["EmberKit"], path: "Tests/EmberKitTests"),
  ],
  swiftLanguageModes: [.v5]
)
