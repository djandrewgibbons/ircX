# ircX

Native macOS and iOS client for Ember (ember-cloudflare). See README.md for the layout.

- `EmberKit` mirrors ember-cloudflare's `packages/protocol`. When Ember's protocol changes, change the
  types in `Models.swift` and `Frames.swift` first, keep `roomProtocol` equal to Ember's
  `ROOM_PROTOCOL`, and add a decoding test in `Tests/EmberKitTests`.
- `EmberKit` has no UI and no SwiftUI import, so its tests run with `swift test`.
- UI code goes in `Sources/IRCXUI` and is shared by both platforms; keep platform differences to
  `#if os(...)` inside views. It has two themes over the same models (`Shared/`), which Settings
  switches (`AppTheme`):
  - `Suite/`: the dxnd suite style. UI: use AppCoreUI (suite-ui skill in dxnd-app-core); never
    reimplement a component it has. Tokens (`Spacing`, `Radius`, `DesignFont`, `SemanticColor`) only.
  - `IRC/`: IRC Classic, the fixed-width throwback. Its colors and fonts come from its own `Theme`,
    never raw values in views; it's exempt from the suite's tokens on purpose.
  - A feature lands in both themes in the same change. Logic both need (commands, models) goes in `Shared/`.
- The Xcode project is generated from `project.yml` (`xcodegen`); don't commit `ircX.xcodeproj`.
- Before committing: `swift build`, `swift test`, and
  `xcodebuild -scheme ircX-macOS build` and `xcodebuild -scheme ircX-iOS -destination 'generic/platform=iOS Simulator' build`.
