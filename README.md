# ircX

A native Mac, iPhone and iPad client for [Ember](https://github.com/NYLLON-SOFTWARE/ember-cloudflare),
the team chat that runs on your own Cloudflare account. It signs in to as many Ember instances as
you like, starting with irc.dxnd.ai, and lays them out the way Slack does: a rail of servers, each
one's channels and DMs, the conversation, and its thread beside it. It just looks like an IRC client
from 1999 while doing it.

```
[02:31] [@andrew] [dxnd/#general] [Act: 3,5]                              bob typing…
[andrew(#general)] ▸ /me waves
```

## What it does

- **Many servers at once.** Each Ember instance keeps its own session in the Keychain. ⌘1–⌘9 switch
  between them, and ⌘K jumps to any channel or DM on any of them.
- **Live.** Each instance's workspace socket keeps unread marks, rooms and people current, and the
  open room's socket brings messages, edits, reactions, typing and who's here as they happen. A
  dropped connection comes back with only what changed since.
- **IRC habits.** `/join #room`, `/msg nick text`, `/query nick`, `/me`, `/part`, `/names`, `/whois`,
  `/server host`; Tab completes nicks, `nick:` mentions them, ↑ recalls what you sent, ⌥↑ and ⌥↓ step
  through windows. Joins and parts print as `-->` and `<--` lines, which Settings can hide.
- **Slack habits.** Threads open beside the room (with *Also send to #room*), reactions show as
  `[👍 2]` and toggle on click, starred rooms come first, and each room's notification level is a
  right-click away.
- **Sign in** with an email address and password, with the sign-in link from your Ember profile's QR
  code, or with just a name where the instance allows guests.

## Building

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen                 # makes ircX.xcodeproj from project.yml
open ircX.xcodeproj      # run ircX-macOS or ircX-iOS
swift test               # EmberKit's tests, no Xcode project needed
```

Set your team under Signing & Capabilities (or `DEVELOPMENT_TEAM` in `project.yml`) to run on a device.

## How it's built

| Path | What |
|---|---|
| `Sources/EmberKit` | Ember's HTTP API and WebSocket protocol in Swift: the models and frames of ember-cloudflare's `packages/protocol`, sessions, sockets that reconnect, and the timeline that applies a room's frames. No UI. |
| `Sources/IRCXUI` | The SwiftUI app, shared by macOS and iOS: the instance rail, sidebar, buffer, thread pane, nick list and input line, and the IRC theme. |
| `App` | The `@main` entry point both targets build. |
| `project.yml` | The Xcode project: one macOS and one iOS target, both `ai.dxnd.ircX`. |

ircX speaks to Ember exactly as Ember's own web app does, so it works with any Ember deployment,
unchanged. Ember keeps sessions in an HttpOnly `__Host-session_token` cookie; ircX keeps each
instance's token in the Keychain and sends it in that cookie itself, with the `Origin` and
`Sec-Fetch-Site` headers a browser on the instance's own pages would send, which Ember checks before
any write or socket upgrade.

## License

Apache License 2.0. See [LICENSE](LICENSE).
