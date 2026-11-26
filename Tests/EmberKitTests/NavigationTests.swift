@testable import EmberKit
import XCTest

/** The sidebar's order and naming rules, search typing and the navigation commands, as the web has them. */
final class NavigationTests: XCTestCase {
  func testSidebarOrderIsStarsThenSharedOrderThenAsGiven() {
    let given = ["a", "b", "c", "d", "e"]
    XCTAssertEqual(RoomList.inSidebarOrder(given, favorites: ["d", "b"], sharedOrder: ["e", "c"], id: { $0 }), ["d", "b", "e", "c", "a"])
    XCTAssertEqual(RoomList.inSidebarOrder(given, favorites: [], sharedOrder: [], id: { $0 }), given)
  }

  func testDirectOrderIsLatestFirstAndLaterMadeOnTies() {
    let directs = [("x", "2026-01-01"), ("y", "2026-03-01"), ("z", "2026-01-01")]
    XCTAssertEqual(RoomList.inDirectOrder(directs, activeAt: \.1).map(\.0), ["y", "z", "x"])
  }

  func testQuietWelcome() {
    let joined = Joined(userId: "me", at: "2026-01-01T00:00:00.000Z")
    let quiet = Room(id: "d", kind: .direct, members: [User(id: "me", name: "Me")], activeAt: joined.at, joined: joined)
    XCTAssertTrue(RoomList.isQuietWelcome(quiet, me: "me"))
    XCTAssertFalse(RoomList.isQuietWelcome(quiet, me: "someone"))
    var spoken = quiet
    spoken.activeAt = "2026-01-02T00:00:00.000Z"
    XCTAssertFalse(RoomList.isQuietWelcome(spoken, me: "me"))
  }

  func testMovingStars() {
    XCTAssertEqual(RoomList.moved(["a", "b", "c"], "b", by: -1), ["b", "a", "c"])
    XCTAssertEqual(RoomList.moved(["a", "b", "c"], "a", by: -1), ["a", "b", "c"])
    XCTAssertEqual(RoomList.movedBefore(["a", "b", "c"], "c", "a"), ["c", "a", "b"])
    XCTAssertEqual(RoomList.movedBefore(["a", "b", "c"], "a", nil), ["b", "c", "a"])
  }

  func testNamesInASentence() {
    XCTAssertEqual(RoomList.toSentence(["Ada"]), "Ada")
    XCTAssertEqual(RoomList.toSentence(["Ada", "Grace"]), "Ada and Grace")
    XCTAssertEqual(RoomList.toSentence(["Ada", "Grace", "Alan"]), "Ada, Grace, and Alan")
    let room = Room(id: "d", kind: .direct, members: [User(id: "me", name: "Me"), User(id: "g", name: "Grace"), User(id: "a", name: "Ada")])
    XCTAssertEqual(room.name(for: "me") { $0.name }, "Grace and Ada")
    let alone = Room(id: "s", kind: .direct, members: [User(id: "me", name: "Me")])
    XCTAssertEqual(alone.name(for: "me") { $0.name }, "Me")
  }

  func testPeopleMatching() {
    let me = Me(id: "me", name: "Me", administrator: false)
    let people = [
      DirectoryUser(id: "1", name: "Ada Lovelace", username: "ada", role: .member, status: .active, avatarUrl: "/1"),
      DirectoryUser(id: "2", name: "alan Turing", username: "alan", role: .member, status: .active, avatarUrl: "/2"),
      DirectoryUser(id: "3", name: "Grace", role: .member, status: .deactivated, avatarUrl: "/3"),
      DirectoryUser(id: "4", name: "Secret Agent", role: .bot, status: .active, avatarUrl: "/4", agent: true, adminsOnly: true),
      DirectoryUser(id: "me", name: "Me", role: .member, status: .active, avatarUrl: "/me"),
    ]
    XCTAssertEqual(PeopleList.matching(people, me: me, name: "").map(\.id), ["1", "2"])
    XCTAssertEqual(PeopleList.matching(people, me: me, name: PeopleList.soughtName("@@al")).map(\.id), ["2"])
    XCTAssertEqual(PeopleList.matching(people, me: me, name: "LOVE").map(\.id), ["1"])
    XCTAssertEqual(PeopleList.matching(people, me: me, name: "love").map(\.id), ["1"])
    let admin = Me(id: "me", name: "Me", administrator: true)
    XCTAssertEqual(PeopleList.matching(people, me: admin, name: "agent").map(\.id), ["4"])
    XCTAssertEqual(PeopleList.startedWithout(["Bot"]), "Bot is only for DMs between administrators, so this DM is without it.")
    XCTAssertEqual(PeopleList.startedWithout(["A", "B"]), "A and B are only for DMs between administrators, so this DM is without them.")
  }

  func testInvolvementCycle() {
    let room = Room(id: "r", kind: .open, name: "general")
    let direct = Room(id: "d", kind: .direct, members: [])
    XCTAssertEqual(Involvement.mentions.next(in: room), .everything)
    XCTAssertEqual(Involvement.invisible.next(in: room), .mentions)
    XCTAssertEqual(Involvement.everything.next(in: direct), .nothing)
    XCTAssertEqual(Involvement.mentions.next(in: direct), .everything)
    XCTAssertEqual(Involvement.levels(in: direct), [.everything, .nothing])
    // A DM hidden by blocking its person is invisible, which its menu shows as chosen, and the bell goes on to everything.
    XCTAssertEqual(Involvement.choices(in: direct, current: .invisible), [.everything, .nothing, .invisible])
    XCTAssertEqual(Involvement.choices(in: direct, current: .nothing), [.everything, .nothing])
    XCTAssertEqual(Involvement.invisible.next(in: direct), .everything)
  }

  func testTypedSearchFilters() {
    let typed = Searches.withTypedFilters(Search(q: "deploy has:link from:me  is:thread in:ops from:bob sort:oldest"), me: "me",
      room: { $0 == "ops" ? "r1" : nil }, person: { $0 == "bob" ? "u2" : nil })
    XCTAssertEqual(typed.search.q, "deploy")
    XCTAssertEqual(typed.search.hasLink, true)
    XCTAssertEqual(typed.search.inThread, true)
    XCTAssertEqual(typed.search.in, "r1")
    XCTAssertEqual(typed.search.from, "u2")
    XCTAssertEqual(typed.sort, .oldest)
    XCTAssertEqual(Searches.modifierTyped("words in:gen"), TypedModifier(key: "in", value: "gen"))
    XCTAssertNil(Searches.modifierTyped("words"))
  }

  func testSearchMarksAreWholeWords() {
    let text = "Deploy the deployment, then deploy."
    let marked = Searches.marks(["deploy"], in: text).map { String(text[$0]) }
    XCTAssertEqual(marked, ["Deploy", "deploy"])
    XCTAssertEqual(NavigationText.resultCount(1, more: false), "1 result")
    XCTAssertEqual(NavigationText.resultCount(100, more: true), "100+ results")
  }

  func testNavigationCommands() {
    XCTAssertEqual(InputCommand.parse("/query ada bob"), .query(["ada", "bob"]))
    XCTAssertEqual(InputCommand.parse("/newroom -p #ops ada"), .newRoom(name: "ops", closed: true, nicks: ["ada"]))
    XCTAssertEqual(InputCommand.parse("/create design"), .newRoom(name: "design", closed: false, nicks: []))
    XCTAssertEqual(InputCommand.parse("/star"), .star(nil, true))
    XCTAssertEqual(InputCommand.parse("/unstar #general"), .star("general", false))
    XCTAssertEqual(InputCommand.parse("/move up"), .move(.up))
    XCTAssertEqual(InputCommand.parse("/notify off"), .notify(.nothing))
    XCTAssertEqual(InputCommand.parse("/notify"), .notify(nil))
    XCTAssertEqual(InputCommand.parse("/unhide #random"), .hide("random", false))
    XCTAssertEqual(InputCommand.parse("/leave"), .leave)
    XCTAssertEqual(InputCommand.parse("/part"), .part)
    XCTAssertEqual(InputCommand.parse("/back"), .back)
    XCTAssertEqual(InputCommand.parse("/search deploy has:link"), .search("deploy has:link"))
    XCTAssertEqual(InputCommand.parse("/goto 3"), .goto(3))
    XCTAssertEqual(InputCommand.parse("/searches clear"), .searches(clear: true))
    XCTAssertEqual(InputCommand.parse("/private ada bob"), .makePrivate(["ada", "bob"]))
    XCTAssertEqual(InputCommand.parse("/invite"), .invite(nil))
    XCTAssertEqual(InputCommand.parse("/deleteroom"), .deleteRoom)
  }

  /** The live sidebar has no `suggestions`, and its rooms carry their marks and levels. */
  func testSidebarDecodesTheLiveShape() throws {
    let json = """
      {"rooms":[{"id":"r1","kind":"open","name":"general","icon":"coffee","unread":true,"unreadSince":"2026-01-01T00:00:00.000Z","involvement":"nothing"},
      {"id":"d1","kind":"direct","members":[{"id":"me","name":"Me"},{"id":"u","name":"U"}],"activeAt":"2026-01-01T00:00:00.000Z",
      "joined":{"userId":"me","at":"2026-01-01T00:00:00.000Z"},"unread":true,"unreadCount":3,"involvement":"everything"}],
      "favorites":{"rooms":["r1"],"version":2},"sharedOrder":[],"huddles":{},"blocks":{"userIds":[],"version":0}}
      """
    let sidebar = try JSONDecoder().decode(Sidebar.self, from: Data(json.utf8))
    XCTAssertEqual(sidebar.rooms.count, 2)
    XCTAssertTrue(sidebar.rooms[0].isMarkedUnread)
    XCTAssertEqual(sidebar.rooms[0].room.icon, "coffee")
    XCTAssertEqual(sidebar.rooms[1].unreadCount, 3)
    XCTAssertTrue(RoomList.isQuietWelcome(sidebar.rooms[1].room, me: "me"))
  }
}
