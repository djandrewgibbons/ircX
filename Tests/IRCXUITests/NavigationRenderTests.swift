import AppCoreUI
import AppCoreUITestSupport
@testable import EmberKit
@testable import IRCXUI
import SwiftUI
import XCTest

/**
 * Finding and organising rooms as each theme draws it, to .build/ui-renders/: the sidebar with stars,
 * marks, a DM's count and presence, Activity, the welcome card, New direct message, the search page
 * and workspace settings.
 */
@MainActor
final class NavigationRenderTests: XCTestCase {
  let ada = User(id: "ada0000000000001", name: "Ada Lovelace")
  let bob = User(id: "bob0000000000002", name: "Bob")
  let grace = User(id: "gra0000000000003", name: "Grace Hopper")

  func session() throws -> InstanceSession {
    let session = InstanceSession(instance: Instance(baseURL: URL(string: "https://chat.example.com")!, name: "Example"), tokens: MemoryTokenStore())
    var account = try JSONDecoder().decode(Account.self, from: Data(MessageRenderTests.account.utf8))
    account.tagline = "Ship it together"
    let at = "2026-11-19T14:00:00.000Z"
    let rooms = [
      SidebarRoom(room: Room(id: "r1", kind: .open, name: "general"), unread: false, involvement: .mentions),
      SidebarRoom(room: Room(id: "r2", kind: .open, name: "design"), unread: true, unreadSince: at, involvement: .mentions),
      SidebarRoom(room: Room(id: "r3", kind: .closed, name: "ops"), unread: true, unreadSince: at, involvement: .nothing),
      SidebarRoom(room: Room(id: "r4", kind: .open, name: "hidden"), unread: true, involvement: .invisible),
      SidebarRoom(room: Room(id: "d1", kind: .direct, members: [ada, bob], activeAt: "2026-11-19T15:00:00.000Z"), unread: true, unreadSince: at, unreadCount: 3, involvement: .everything),
      SidebarRoom(room: Room(id: "d2", kind: .direct, members: [ada, bob, grace], activeAt: at), unread: false, involvement: .everything),
      SidebarRoom(
        room: Room(id: "d3", kind: .direct, members: [ada, grace], activeAt: at, joined: Joined(userId: ada.id, at: at)), unread: false,
        involvement: .everything),
    ]
    session.showForRendering(
      me: Me(id: ada.id, name: ada.name, administrator: true),
      people: [
        DirectoryUser(id: ada.id, name: ada.name, username: "ada", role: .administrator, status: .active, avatarUrl: "/a"),
        DirectoryUser(id: bob.id, name: bob.name, username: "bob", role: .member, status: .active, avatarUrl: "/b"),
        DirectoryUser(id: grace.id, name: grace.name, role: .member, status: .active, avatarUrl: "/g"),
        DirectoryUser(id: "ember", name: "Ember", role: .bot, status: .active, avatarUrl: "/e", agent: true),
      ],
      huddles: ["r1": LiveHuddle(startedAt: at, userIds: [bob.id, grace.id])],
      rooms: rooms, favorites: ["r2"], invitation: Invitation(roomId: "r1", joinCode: "abc123"), account: account, active: [bob.id])
    session.selectedRoomID = "r1"
    return session
  }

  func render(_ view: some View, _ name: String, width: CGFloat = 320, height: CGFloat) throws {
    for scheme in [ColorScheme.light, .dark] {
      _ = try renderView(view, named: name, size: CGSize(width: width, height: height), colorScheme: scheme)
    }
  }

  func testSidebarOrderAndMarks() throws {
    let session = try session()
    XCTAssertEqual(session.listedRooms.map(\.id), ["r2", "r1", "r3"])
    XCTAssertEqual(session.listedDirects.map(\.id), ["d1", "d2"])
    XCTAssertEqual(session.activityCount, 3)
    session.showingActivity = true
    XCTAssertEqual(session.listedRooms.map(\.id), ["r2", "r3"])
    XCTAssertEqual(session.listedDirects.map(\.id), ["d1"])
  }

  func testSuiteSidebar() throws {
    let session = try session()
    let app = AppModel(tokens: MemoryTokenStore())
    try render(
      SuiteSidebar(app: app, session: session).frame(width: 320, height: 640).background(SemanticColor.background).suiteTheme(.ircX),
      "suite-sidebar", height: 640)
    session.showingActivity = true
    try render(
      SuiteSidebar(app: app, session: session).frame(width: 320, height: 640).background(SemanticColor.background).suiteTheme(.ircX),
      "suite-sidebar-activity", height: 640)
  }

  func testIRCSidebar() throws {
    let session = try session()
    let app = AppModel(tokens: MemoryTokenStore())
    try render(
      ChannelSidebar(app: app, session: session).frame(width: 320, height: 640).environment(\.theme, .irc).environment(\.appTheme, .irc),
      "irc-sidebar", height: 640)
  }

  func testWelcomeCard() throws {
    let session = try session()
    let room = RoomModel(room: Room(id: "r1", kind: .open, name: "general"), api: session.api, instance: session)
    room.apply(.welcome(you: ada, present: [ada], seq: 1, page: TimelinePage(messages: [], hasMore: false, hasNewer: false, around: nil)))
    XCTAssertNotNil(WelcomeCard.invitation(session, room))
    for look in AppTheme.allCases {
      let view = WelcomeCard(session: session, room: room)
        .frame(width: 700, height: 260, alignment: .top)
        .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
        .environment(\.appTheme, look)
        .environment(\.theme, .irc)
      try render(view, "\(look.rawValue)-welcome-card", width: 700, height: 260)
    }
  }

  func testNewDirectSheet() throws {
    let session = try session()
    for look in AppTheme.allCases {
      let view = NewDirectSheet(session: session).frame(width: 480, height: 520).environment(\.appTheme, look).environment(\.theme, .irc)
      try render(view, "\(look.rawValue)-new-direct", width: 480, height: 520)
    }
  }

  func testSearchPage() throws {
    let session = try session()
    let at = "2026-11-19T14:05:00.000Z"
    let message = Message(
      id: "m1", clientMessageId: "c1", roomId: "r2", creator: bob, body: "<p>Deploy the deployment, then deploy.</p>",
      plainText: "Deploy the deployment, then deploy.", createdAt: at, updatedAt: at)
    let results = SearchResults(search: nil, matches: [SearchMatch(message: message, words: ["deploy"])], next: nil, rooms: [], recent: [])
    session.search.showForRendering(Search(q: "deploy", hasLink: true), results)
    for look in AppTheme.allCases {
      let view = SearchResultsPage(session: session).frame(width: 700, height: 360).environment(\.appTheme, look).environment(\.theme, .irc)
        .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
      try render(view, "\(look.rawValue)-search-page", width: 700, height: 360)
    }
    XCTAssertEqual(session.search.countLabel, "1 result")
  }

  func testWorkspaceSettings() throws {
    let session = try session()
    for look in AppTheme.allCases {
      session.adminSection = .rooms
      session.admin.section = .rooms
      session.admin.settings = try JSONDecoder().decode(WorkspaceSettings.self, from: Data(Self.memberSettings(session).utf8))
      let view = ServerSettingsView(app: AppModel(tokens: MemoryTokenStore()), session: session).frame(width: 760, height: 760)
        .environment(\.appTheme, look).environment(\.theme, .irc).suiteTheme(.ircX)
      try render(view, "\(look.rawValue)-workspace-settings", width: 760, height: 760)
    }
  }

  /** Workspace settings as `GET /api/account` answers an administrator with nothing set up. */
  static func memberSettings(_ session: InstanceSession) throws -> String {
    let account = String(decoding: try JSONEncoder().encode(try XCTUnwrap(session.account)), as: UTF8.self)
    let rest = #"""
      "joinCode":"abc123","canAdminister":true,"memberfulSite":null,"memberfulWebhooks":false,"memberfulKeys":null,"memberfulSiteKept":null,"sso":null,
      "turnstile":null,"email":{"provider":null,"resendKey":null,"cloudflare":false,"from":null},"invitations":[],"emailDomains":[],"blockedWords":[],
      "addresses":{"deployed":null,"others":[]},"assistant":null,"huddles":null,"outsideAi":false,"cloudflareAccountId":null}
      """#
    return #"{"account":"# + account + "," + rest
  }
}
