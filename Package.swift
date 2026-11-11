// swift-tools-version: 6.2
import PackageDescription

// EmberKit speaks Ember's HTTP API and WebSocket protocol (ember-cloudflare's packages/protocol). IRCXUI
// is the SwiftUI app shared by the macOS and iOS targets, which project.yml wraps in an Xcode project:
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
    .target(name: "EmberKit"),
    .target(name: "IRCXUI", dependencies: ["EmberKit", .product(name: "AppCoreUI", package: "dxnd-app-core")]),
    .testTarget(name: "EmberKitTests", dependencies: ["EmberKit"]),
  ],
  swiftLanguageModes: [.v5]
)
