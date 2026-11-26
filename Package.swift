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
    .target(name: "EmberKit", path: "Shared/EmberKit", resources: [.copy("Resources/emoji.json"), .copy("Resources/icon-catalog.json")]),
    // Google's libwebrtc as stasel/WebRTC builds it (M158, an XCFramework for macOS and iOS), by the release
    // asset and checksum stasel/WebRTC's own Package.swift names.
    .binaryTarget(
      name: "WebRTC", url: "https://github.com/stasel/WebRTC/releases/download/158.0.0/WebRTC-M158.xcframework.zip",
      checksum: "dd26ba28fb9c8dbc82f4be3085e8d112a4e2a4e654e1786a9977a748c24c4912"),
    // Huddles' media: microphone, cameras, screens and the connections to Cloudflare's Realtime SFU.
    .target(name: "HuddleMedia", dependencies: ["EmberKit", "WebRTC"], path: "Shared/HuddleMedia"),
    .target(
      name: "IRCXUI", dependencies: ["EmberKit", "HuddleMedia", .product(name: "AppCoreUI", package: "dxnd-app-core")], path: "Shared/IRCXUI",
      resources: [.copy("Resources/HuddleSounds")]),
    .testTarget(name: "EmberKitTests", dependencies: ["EmberKit"], path: "Tests/EmberKitTests"),
    // Render tests: each screen drawn headless to .build/ui-renders/<name>-<light|dark>.png, to look at.
    .testTarget(
      name: "IRCXUITests", dependencies: ["IRCXUI", "EmberKit", .product(name: "AppCoreUITestSupport", package: "dxnd-app-core")],
      path: "Tests/IRCXUITests"),
  ],
  swiftLanguageModes: [.v5]
)
