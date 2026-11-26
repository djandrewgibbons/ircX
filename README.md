# ircX

A native Mac, iPhone and iPad client for [Ember](https://github.com/NYLLON-SOFTWARE/ember-cloudflare),
the team chat that runs on your own Cloudflare account. It signs in to as many Ember instances as
you like, starting with irc.dxnd.ai, and lays them out the way Slack does: a rail of servers, each
one's channels and DMs, the conversation, and its thread beside it, in one of two themes:

- **Suite**, the dxnd suite's style, built on [AppCoreUI](https://github.com/djandrewgibbons/dxnd-app-core):
  panel cards, the icon rail, glass, and messages laid out as Slack lays them out.
- **IRC Classic**, a fixed-width throwback to the IRC client you ran in 1999: a terminal palette,
  nicks aligned in a column, and a BitchX-blue status bar.

```
[02:31] [@andrew] [dxnd/#general] [Act: 3,5]                              bob typing…
[andrew(#general)] ▸ /me waves
```

## What it does

Everything Ember's web app does, natively, in both themes:

- **Many servers at once.** Each Ember instance keeps its own session in the Keychain. ⌘1–⌘9 switch
  between them, ⌘K jumps to any room, DM or pasted Ember link on any of them, and ⌘[ and ⌘] go back
  and forward across servers. A server that moves to a new address is followed there.
- **Live.** Each instance's workspace socket keeps unread marks and counts, rooms, people, presence and
  blocks current, and the open room's socket brings messages, edits, reactions, typing and who's here as
  they happen. A dropped connection comes back with only what changed since, and says when the server
  has been updated.
- **Messages as Ember writes them.** Rich text (lists, quotes, code blocks with syntax highlighting,
  headings, mentions, links), files and pictures with progress, text snippets, link previews, bot cards
  with buttons, reactions from Ember's own set plus custom ones, edits, deletes, quotes, permalinks,
  translation, reports and a queued outbox that keeps unsent messages through leaving a room. Suite's
  composer is a rich editor with the web's formatting row and shortcuts; IRC Classic takes the same
  Markdown-style input.
- **Finding things.** Search with the web's filters, the Activity feed of mentions and replies, the
  Huddles page, threads beside the room (with *Also send to #room*), stars first in the room list,
  hidden rooms, and each conversation's notification level.
- **People.** Profiles and the profile editor (picture, password, sign-in link, sounds, appearance,
  connected apps and Outside AI), new DMs and group DMs, blocking, reporting, and the people list.
- **Sign in** with an email address and password, a sign-in link, just a name where guests are allowed,
  Memberful or single sign-on, with password reset, joining by invitation, Turnstile checks, and first-run
  setup of a new Ember.
- **Admin.** Each server's Server Settings: general, rooms and their order, membership (join links,
  email domains, invitations, Memberful, SSO, email, Turnstile, reports, blocked words, people), custom
  domain, chat bots, Ember AI with its agents and apps, huddles, and styles.
- **Huddles.** Voice, cameras and (from a Mac) screen sharing in any room or DM, through Cloudflare's
  Realtime SFU as Ember's web app does, with stickers, reactions, the huddle's thread beside it,
  invitations that ring, and Ember's own sounds. ⌘⌥⇧H starts, joins or leaves; ⌘⇧Space mutes.
- **Notifications.** Each server's Notifications page turns this device's notifications on, through
  APNs, where the server is set up for it, and lists the devices and browsers notified, with a test
  notification for each. A notification opens its server, room and message, a room's notifications clear
  once it's read, and the badge counts the conversations marked unread.
- **IRC habits.** In IRC Classic every action is also a command: `/join`, `/newroom`, `/part`, `/leave`,
  `/msg`, `/query`, `/me`, `/edit`, `/quote`, `/react`, `/thread`, `/search`, `/names`, `/whois`,
  `/ignore`, `/report`, `/notify`, `/push`, `/huddle`, `/mute`, `/admin`, `/ai`, `/bots`, `/server` and
  more (`/help`). Tab completes nicks, ↑ recalls what you sent, ⌥↑ and ⌥↓ step through windows, and
  joins and parts print as `-->` and `<--` lines, which Settings can hide.
- **Themes.** Switch between Suite and IRC Classic in Settings; Suite follows Light, Dark or System.

## Building

Requires Xcode 26 or later (macOS 26 and iOS 26), [XcodeGen](https://github.com/yonaskolb/XcodeGen),
and access to [dxnd-app-core](https://github.com/djandrewgibbons/dxnd-app-core), the private package
the Suite theme is built on. `swift build` fetches it with your Git credentials; run it once before
building in Xcode.

```sh
brew install xcodegen
xcodegen                 # makes ircX.xcodeproj from project.yml
open ircX.xcodeproj      # run the macOS or iOS scheme
swift test               # EmberKit's tests, no Xcode project needed
```

Set your team under Signing & Capabilities (or `DEVELOPMENT_TEAM` in `project.yml`) to run on a device.

## How it's built

| Path | What |
|---|---|
| `Shared/EmberKit` | Ember's HTTP API and WebSocket protocol in Swift: the models and frames of ember-cloudflare's `packages/protocol`, sessions, sockets that reconnect, and the timeline that applies a room's frames. No UI. |
| `Shared/HuddleMedia` | Huddles' media on Google's libwebrtc ([stasel/WebRTC](https://github.com/stasel/WebRTC)'s M158 build): the microphone, cameras, a Mac's shared screen (ScreenCaptureKit), and the connections to Cloudflare's Realtime SFU. EmberKit's `HuddleSending` and `HuddleReceiving` decide what's connected when. |
| `Shared/IRCXUI/Core` | What both themes share: the app, instance and room models, the input line's commands, Settings and the sheets. |
| `Shared/IRCXUI/Suite` | The Suite theme, on AppCoreUI. |
| `Shared/IRCXUI/IRC` | The IRC Classic theme. |
| `macOS`, `iOS` | Each platform's app target: its `@main` entry point, and on macOS the sandbox entitlements. |
| `Tests` | EmberKit's tests, and IRCXUI's render tests, which draw screens to `.build/ui-renders/` (`swift test`). |
| `project.yml` | The Xcode project: the `macOS` and `iOS` targets and schemes, both `ai.dxnd.ircX`. |

ircX speaks to Ember exactly as Ember's own web app does, so it works with any Ember deployment,
unchanged. Ember keeps sessions in an HttpOnly `__Host-session_token` cookie; ircX keeps each
instance's token in the Keychain and sends it in that cookie itself, with the `Origin` and
`Sec-Fetch-Site` headers a browser on the instance's own pages would send, which Ember checks before
any write or socket upgrade.

## License

Apache License 2.0. See [LICENSE](LICENSE). The huddle sounds in `Shared/IRCXUI/Resources/HuddleSounds` are
Ember's own (`apps/web/src/lib/huddle-sounds` in ember-cloudflare, under Ember's Apache 2.0 license), with
their README and the Fluid R3 SoundFont's MIT license beside them.
