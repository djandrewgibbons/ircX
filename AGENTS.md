# ircX

Native macOS and iOS client for Ember (ember-cloudflare). See README.md for the layout.

- `EmberKit` mirrors ember-cloudflare's `packages/protocol`. When Ember's protocol changes, change the
  types in `Models.swift` and `Frames.swift` first, keep `roomProtocol` equal to Ember's
  `ROOM_PROTOCOL`, and add a decoding test in `Tests/EmberKitTests`.
- `EmberKit` has no UI and no SwiftUI import, so its tests run with `swift test`.
- Code both platforms run goes in `Shared/` (`EmberKit`, `IRCXUI`); keep platform differences to
  `#if os(...)` inside views. `macOS/` and `iOS/` hold only each app target's entry point and
  configuration. `IRCXUI` has two themes over the same models (`Core/`), which Settings switches
  (`AppTheme`):
  - `Suite/`: the dxnd suite style. UI: use AppCoreUI (suite-ui skill in dxnd-app-core); never
    reimplement a component it has. Tokens (`Spacing`, `Radius`, `DesignFont`, `SemanticColor`) only.
  - `IRC/`: IRC Classic, the fixed-width throwback. Its colors and fonts come from its own `Theme`,
    never raw values in views; it's exempt from the suite's tokens on purpose.
  - A feature lands in both themes in the same change. Logic both need (commands, models) goes in `Core/`.
- The Xcode project is generated from `project.yml` (`xcodegen`); don't commit `ircX.xcodeproj` or
  the `Info.plist` files it writes into `macOS/` and `iOS/`.
- `dxnd-app-core` stays private (Andrew's call), so `swift build` must fetch it before `xcodebuild`,
  which then needs `-clonedSourcePackagesDirPath .build -skipPackageUpdates`.
- Before committing: `swift build`, `swift test`, and
  `xcodebuild -scheme macOS build` and `xcodebuild -scheme iOS -destination 'generic/platform=iOS Simulator' build`.
