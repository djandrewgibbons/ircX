import AppCoreUI
import AppCoreUITestSupport
@testable import EmberKit
@testable import IRCXUI
import SwiftUI
import XCTest

/**
 * Huddles as each theme draws them, to .build/ui-renders/: the bar, the huddle opened with its tiles,
 * stickers and reactions, the preview, Invite people, and an invitation ringing.
 */
@MainActor
final class HuddleRenderTests: XCTestCase {
  let ada = User(id: "ada0000000000001", name: "Ada Lovelace")
  let bob = User(id: "bob0000000000002", name: "Bob Rivera")
  let grace = User(id: "gra0000000000003", name: "Grace Hopper")

  func session() throws -> InstanceSession {
    let session = InstanceSession(instance: Instance(baseURL: URL(string: "https://chat.example.com")!, name: "Example"), tokens: MemoryTokenStore())
    let account = try JSONDecoder().decode(Account.self, from: Data(MessageRenderTests.account.utf8))
    let at = "2026-11-19T14:00:00.000Z"
    session.showForRendering(
      me: Me(id: ada.id, name: ada.name, administrator: false),
      people: [
        DirectoryUser(id: ada.id, name: ada.name, role: .member, status: .active, avatarUrl: "/a"),
        DirectoryUser(id: bob.id, name: bob.name, role: .member, status: .active, avatarUrl: "/b"),
        DirectoryUser(id: grace.id, name: grace.name, role: .member, status: .active, avatarUrl: "/g"),
      ],
      huddles: ["r1": LiveHuddle(startedAt: at, userIds: [bob.id, grace.id])],
      rooms: [
        SidebarRoom(room: Room(id: "r1", kind: .open, name: "general"), unread: false, involvement: .mentions),
        SidebarRoom(room: Room(id: "d1", kind: .direct, members: [ada, bob, grace], activeAt: at), unread: false, involvement: .everything),
      ],
      account: account)
    session.selectedRoomID = "r1"
    return session
  }

  func call(_ session: InstanceSession, room: RoomID = "r1", open: Bool = true) -> HuddleCall {
    HuddleCall.shown(
      session: session, roomId: room, you: ada,
      people: [
        HuddlePerson(user: ada, muted: false, audio: true, video: false, screen: false, sticker: nil),
        HuddlePerson(user: bob, muted: true, audio: true, video: false, screen: false, sticker: .hand),
        HuddlePerson(user: grace, muted: false, audio: true, video: false, screen: false, sticker: .thumbsUp),
      ],
      open: open, speaking: [grace.id], reactions: [(bob.id, "\u{1F389}"), (grace.id, "\u{1F44D}")])
  }

  /** Bob shares a screen, Ada too where `both`: the screen shows large, the rest in a strip beside or under it. */
  func sharing(_ session: InstanceSession, both: Bool = false) -> HuddleCall {
    HuddleCall.shown(
      session: session, roomId: "r1", you: ada,
      people: [
        HuddlePerson(user: ada, muted: false, audio: true, video: false, screen: both, sticker: nil),
        HuddlePerson(user: bob, muted: false, audio: true, video: false, screen: true, sticker: nil),
        HuddlePerson(user: grace, muted: true, audio: true, video: false, screen: false, sticker: .brb),
      ],
      speaking: [bob.id], sharing: both ? [ada.id, bob.id] : [bob.id])
  }

  func testStage() throws {
    let session = try session()
    let app = AppModel(tokens: MemoryTokenStore())
    // Wider than tall: the strip beside the screen; taller than wide, under it.
    try render(SuiteHuddleView(app: app, call: sharing(session)).background(SemanticColor.background).suiteTheme(.ircX), "suite-huddle-stage", width: 860, height: 560)
    try render(
      SuiteHuddleView(app: app, call: sharing(session, both: true)).background(SemanticColor.background).suiteTheme(.ircX), "suite-huddle-stage-upright",
      width: 420, height: 760)
    try render(IRCHuddleView(app: app, call: sharing(session)).environment(\.theme, .irc), "irc-huddle-stage", width: 860, height: 560)
    try render(IRCHuddleView(app: app, call: sharing(session, both: true)).environment(\.theme, .irc), "irc-huddle-stage-upright", width: 420, height: 760)
  }

  func render(_ view: some View, _ name: String, width: CGFloat, height: CGFloat) throws {
    for scheme in [ColorScheme.light, .dark] {
      _ = try renderView(view, named: name, size: CGSize(width: width, height: height), colorScheme: scheme)
    }
  }

  func testWords() throws {
    let session = try session()
    let call = call(session)
    XCTAssertEqual(call.name, "Huddle in general")
    XCTAssertEqual(call.status, "Bob, Grace, and you are in the huddle")
    XCTAssertFalse(call.isAlone)
    XCTAssertEqual(call.people.first { $0.user.id == ada.id }?.muted, false)
  }

  func testSuiteBar() throws {
    let session = try session()
    try render(SuiteHuddleBar(call: call(session, open: false)).padding().background(SemanticColor.background).suiteTheme(.ircX), "suite-huddle-bar", width: 900, height: 90)
  }

  func testSuiteHuddleView() throws {
    let session = try session()
    let app = AppModel(tokens: MemoryTokenStore())
    try render(SuiteHuddleView(app: app, call: call(session)).background(SemanticColor.background).suiteTheme(.ircX), "suite-huddle-view", width: 860, height: 560)
  }

  func testIRCHuddle() throws {
    let session = try session()
    let app = AppModel(tokens: MemoryTokenStore())
    try render(IRCHuddleBar(call: call(session, open: false)).environment(\.theme, .irc), "irc-huddle-bar", width: 900, height: 22)
    try render(IRCHuddleView(app: app, call: call(session)).environment(\.theme, .irc), "irc-huddle-view", width: 860, height: 560)
    try render(IRCHuddleRoster(call: call(session)).frame(width: 170).background(Theme.irc.buffer).environment(\.theme, .irc), "irc-huddle-roster", width: 170, height: 110)
  }

  func testPreview() throws {
    let session = try session()
    let app = AppModel(tokens: MemoryTokenStore())
    for look in AppTheme.allCases {
      let view = HuddlePreviewSheet(request: HuddlePreviewRequest(session: session, roomId: "r1"), center: app.huddles)
        .frame(width: 460, height: 480)
        .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
        .environment(\.appTheme, look)
        .environment(\.theme, .irc)
      try render(view, "\(look.rawValue)-huddle-preview", width: 460, height: 480)
    }
  }

  func testInvite() throws {
    let session = try session()
    for look in AppTheme.allCases {
      let view = HuddleInviteSheet(call: call(session, room: "d1"))
        .frame(width: 420, height: 440)
        .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
        .environment(\.appTheme, look)
        .environment(\.theme, .irc)
      try render(view, "\(look.rawValue)-huddle-invite", width: 420, height: 440)
    }
  }

  /** Grace isn't in the DM's huddle: she's listed with her face, ticked, as the only one to invite. */
  func testInviteSomeone() throws {
    let session = try session()
    for look in AppTheme.allCases {
      let call = HuddleCall.shown(
        session: session, roomId: "d1", you: ada,
        people: [
          HuddlePerson(user: ada, muted: false, audio: true, video: false, screen: false, sticker: nil),
          HuddlePerson(user: bob, muted: false, audio: true, video: false, screen: false, sticker: nil),
        ])
      let view = HuddleInviteSheet(call: call)
        .frame(width: 420, height: 440)
        .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
        .environment(\.appTheme, look)
        .environment(\.theme, .irc)
      try render(view, "\(look.rawValue)-huddle-invite-someone", width: 420, height: 440)
    }
  }

  func testInvitations() throws {
    let session = try session()
    let app = AppModel(tokens: MemoryTokenStore())
    let invitation = HuddleInvitation(roomId: "r1", by: bob.id, at: Date())
    session.ringForRendering([invitation])
    XCTAssertEqual(session.ringing, [invitation])
    try render(
      SuiteHuddleInvitations(center: app.huddles, ringing: [(session, invitation)]).background(SemanticColor.secondaryBackground).suiteTheme(.ircX),
      "suite-huddle-invitation", width: 380, height: 160)
    try render(
      IRCHuddleInvitations(center: app.huddles, ringing: [(session, invitation)]).background(Theme.irc.buffer).environment(\.theme, .irc),
      "irc-huddle-invitation", width: 600, height: 60)
  }
}
