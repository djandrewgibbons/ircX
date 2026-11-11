// swift-tools-version: 5.10
import PackageDescription

// EmberKit speaks Ember's HTTP API and WebSocket protocol (ember-cloudflare's packages/protocol). IRCXUI
// is the SwiftUI app shared by the macOS and iOS targets, which project.yml wraps in an Xcode project.
let package = Package(
  name: "ircX",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "EmberKit", targets: ["EmberKit"]),
    .library(name: "IRCXUI", targets: ["IRCXUI"]),
  ],
  targets: [
    .target(name: "EmberKit"),
    .target(name: "IRCXUI", dependencies: ["EmberKit"]),
    .testTarget(name: "EmberKitTests", dependencies: ["EmberKit"]),
  ]
)
