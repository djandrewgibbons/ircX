# ircX

Native macOS and iOS client for Ember (ember-cloudflare). See README.md for the layout.

- `EmberKit` mirrors ember-cloudflare's `packages/protocol`. When Ember's protocol changes, change the
  types in `Models.swift` and `Frames.swift` first, keep `roomProtocol` equal to Ember's
  `ROOM_PROTOCOL`, and add a decoding test in `Tests/EmberKitTests`.
- `EmberKit` has no UI and no SwiftUI import, so its tests run with `swift test`.
- UI code goes in `Sources/IRCXUI` and is shared by both platforms; keep platform differences to
  `#if os(...)` inside views. Colors and fonts come from `Theme`, never raw values in views.
- The Xcode project is generated from `project.yml` (`xcodegen`); don't commit `ircX.xcodeproj`.
- Before committing: `swift build`, `swift test`, and
  `xcodebuild -scheme ircX-macOS build` and `xcodebuild -scheme ircX-iOS -destination 'generic/platform=iOS Simulator' build`.
