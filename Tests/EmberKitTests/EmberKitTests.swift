import XCTest
@testable import EmberKit

final class FrameTests: XCTestCase {
  let ada = #"{"id":"0000000000000ada","name":"Ada"}"#

  func message(_ id: String, client: String? = nil, at time: String = "2026-11-11T02:00:00.000Z", parent: String? = nil) -> String {
    let parentField = parent.map { #","parentId":"\#($0)""# } ?? ""
    return #"{"id":"\#(id)","clientMessageId":"\#(client ?? "c-" + id)","roomId":"general","creator":\#(ada),"body":"<p>hi</p>","plainText":"hi","mentions":[],"createdAt":"\#(time)","updatedAt":"\#(time)","editedAt":null,"boosts":[]\#(parentField)}"#
  }

  func testDecodesWelcome() throws {
    let frame = try ServerFrame.decode(#"{"type":"welcome","you":\#(ada),"present":[\#(ada)],"seq":7,"messages":[\#(message("m1"))],"hasMore":true,"hasNewer":false,"around":null}"#)
    guard case let .welcome(you, present, seq, page) = frame else { return XCTFail("\(frame)") }
    XCTAssertEqual(you.name, "Ada")
    XCTAssertEqual(present.count, 1)
    XCTAssertEqual(seq, 7)
    XCTAssertEqual(page.messages.first?.plainText, "hi")
    XCTAssertTrue(page.hasMore)
  }

  func testUnknownFramesDecode() throws {
    XCTAssertEqual(try ServerFrame.decode(#"{"type":"something.new","x":1}"#), .unknown("something.new"))
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"room.unread","roomId":"general"}"#), .roomUnread("general"))
  }

  func testDecodesSidebarRoomsFlat() throws {
    let json = #"{"rooms":[{"id":"general","kind":"open","name":"general","icon":null,"unread":true,"involvement":"mentions"},{"id":"d1","kind":"direct","members":[\#(ada),{"id":"0000000000000bob","name":"Bob"}],"activeAt":"2026-11-11T02:00:00.000Z","unread":false,"involvement":"everything"}],"favorites":{"rooms":[],"version":0},"sharedOrder":[],"invitation":null,"suggestions":[],"huddles":{}}"#
    let sidebar = try JSONDecoder().decode(Sidebar.self, from: Data(json.utf8))
    XCTAssertEqual(sidebar.rooms.count, 2)
    XCTAssertTrue(sidebar.rooms[0].unread)
    XCTAssertEqual(sidebar.rooms[1].room.title(for: "0000000000000ada"), "Bob")
  }

  func testEncodesClientFrames() throws {
    XCTAssertEqual(try ClientFrame.messageCreate(clientMessageId: "c1", body: "<p>x</p>").encoded(), #"{"body":"<p>x</p>","clientMessageId":"c1","type":"message.create"}"#)
    XCTAssertEqual(try ClientFrame.historyBefore(before: "m1", limit: 40).encoded(), #"{"before":"m1","limit":40,"type":"history.before"}"#)
  }

  func testTimelineConfirmsPendingAndKeepsOrder() throws {
    var timeline = Timeline()
    timeline.apply(try ServerFrame.decode(#"{"type":"welcome","you":\#(ada),"present":[],"seq":1,"messages":[\#(message("m1"))],"hasMore":false}"#))
    let sent = try JSONDecoder().decode(Message.self, from: Data(message("pending", client: "c9", at: "2026-11-11T03:00:00.000Z").utf8))
    timeline.send(sent)
    XCTAssertEqual(timeline.lines.count, 2)
    timeline.apply(try ServerFrame.decode(#"{"type":"message.created","seq":2,"message":\#(message("m2", client: "c9", at: "2026-11-11T03:00:00.000Z"))}"#))
    XCTAssertTrue(timeline.pending.isEmpty)
    XCTAssertEqual(timeline.messages.map(\.id), ["m1", "m2"])
    XCTAssertEqual(timeline.seq, 2)
    timeline.apply(try ServerFrame.decode(#"{"type":"message.created","seq":3,"message":\#(message("r1", parent: "m1"))}"#))
    XCTAssertEqual(timeline.messages.count, 2, "a reply sent only to its thread stays out of the room")
    timeline.apply(.messageDeleted(messageId: "m1", seq: 4))
    XCTAssertEqual(timeline.messages.map(\.id), ["m2"])
  }

  func testPresenceMakesJoinAndPartLines() {
    var timeline = Timeline()
    timeline.apply(.presenceJoined(User(id: "b", name: "Bob")))
    timeline.apply(.presenceLeft("b"))
    XCTAssertEqual(timeline.present, [])
    XCTAssertEqual(timeline.events.count, 2)
  }
}

final class BodyTests: XCTestCase {
  let bob = User(id: "0000000000000bob", name: "Bob")

  func testEscapesAndSplitsLines() {
    XCTAssertEqual(MessageBody.markup(for: "a < b\n\nc"), "<p>a &lt; b</p><p><br></p><p>c</p>")
  }

  func testMentions() {
    XCTAssertEqual(
      MessageBody.markup(for: "hi @bob, and bob@example.com", mentioning: [bob]),
      "<p>hi <action-text-attachment sgid=\"0000000000000bob\" content-type=\"application/vnd.campfire.mention\"></action-text-attachment>, and bob@example.com</p>")
    XCTAssertEqual(MessageBody.markup(for: "@bobby", mentioning: [bob]), "<p>@bobby</p>")
    XCTAssertEqual(
      MessageBody.markup(for: "bob: ping", mentioning: [bob]),
      "<p><action-text-attachment sgid=\"0000000000000bob\" content-type=\"application/vnd.campfire.mention\"></action-text-attachment>: ping</p>")
  }

  func testActions() {
    let body = MessageBody.actionMarkup(for: "waves", by: "Ada")
    XCTAssertEqual(body, "<p><em>Ada waves</em></p>")
    XCTAssertTrue(MessageBody.isAction(body: body, plainText: "Ada waves", author: "Ada"))
    XCTAssertFalse(MessageBody.isAction(body: "<p><em>Ada</em> waves</p>", plainText: "Ada waves", author: "Ada"))
  }

  func testCommands() {
    XCTAssertEqual(InputCommand.parse("hello"), .say("hello"))
    XCTAssertEqual(InputCommand.parse("//etc/hosts"), .say("/etc/hosts"))
    XCTAssertEqual(InputCommand.parse("/me waves"), .me("waves"))
    XCTAssertEqual(InputCommand.parse("/join #design"), .join("design"))
    XCTAssertEqual(InputCommand.parse("/msg Bob hey there"), .msg(nick: "Bob", text: "hey there"))
    XCTAssertEqual(InputCommand.parse("/query Bob"), .msg(nick: "Bob", text: nil))
    XCTAssertEqual(InputCommand.parse("   "), nil)
  }

  func testInstanceAddresses() {
    XCTAssertEqual(Instance.baseURL(from: "irc.dxnd.ai")?.absoluteString, "https://irc.dxnd.ai")
    XCTAssertEqual(Instance.baseURL(from: "http://localhost:8787/rooms/x")?.absoluteString, "http://localhost:8787")
    XCTAssertNil(Instance.baseURL(from: "ftp://x"))
    XCTAssertEqual(Instance(baseURL: URL(string: "http://localhost:8787")!).origin, "http://localhost:8787")
  }

  func testSessionCookies() {
    XCTAssertEqual(SessionCookie.token(named: "__Host-session_token", inHeader: "__Host-session_token=abc; Path=/; Max-Age=34560000; HttpOnly"), "abc")
    XCTAssertEqual(SessionCookie.token(named: "__Host-session_token", inHeader: "__Host-session_token=; Path=/; Max-Age=0; HttpOnly"), "")
    XCTAssertEqual(SessionCookie.transferId(in: "https://irc.dxnd.ai/session/transfers#token=xyz"), "xyz")
  }

  func testNickColorsAreStable() {
    XCTAssertEqual(NickColor.index(for: "0000000000000bob", among: 12), NickColor.index(for: "0000000000000bob", among: 12))
  }
}
