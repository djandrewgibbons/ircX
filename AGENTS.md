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
  - `Suite/`: the dxnd suite style. UI: use AppCoreUI; never
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

## Suite conventions

Swift 6.4, macOS/iOS 27, Xcode 27 beta. Shared code comes from the `dxnd-*` packages.

- Build the smallest thing that meets the stated need. For a rare failure, give the user a manual step instead of adding code.
- Ask a question only about scope, before a plan is agreed. Never offer a choice that has one sensible option.
- Commit and open a pull request only when the user says to land. The PR Review checks are the gate: fix their Critical and High findings, and leave merging to the user.
- No fallbacks or silent failures: errors are thrown or logged with `Logger` and shown to the user. No `try?` except around `Task.sleep`, no `?? ""`, `?? 0` or `?? false`.
- Extend the package that owns a capability (AppCoreUI, dxnd-sync, dxnd-updater) rather than building a parallel one.
- UI: one line of text per surface, 1–3 word labels, explanations in `.help()`. Use AppCoreUI components and tokens; the list is `plugins/dxnd-suite/skills/suite-ui/components.md` in dxnd-app-core (`~/dev/dxnd-app-core` locally, the SwiftPM checkout elsewhere).
- Packages are remote URLs pinned in `Package.resolved`. The user tags releases.
- Report what was verified. No reminders about what is untested or what the user should test.
- No Claude attribution or session links in commit messages or pull requests.
