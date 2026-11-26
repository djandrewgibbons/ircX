import AppCoreUI
import AppCoreUITestSupport
@testable import EmberKit
@testable import IRCXUI
import ImageIO
import SwiftUI
import XCTest

/**
 * Writing messages as each theme draws it, to .build/ui-renders/: the composer with files, a quote and
 * a refusal, boosts and an upload, a message open in its editor, the reaction tray, and the dialogs.
 */
@MainActor
final class ComposeRenderTests: XCTestCase {
  let ada = User(id: "ada0000000000001", name: "Ada Lovelace")
  let bob = User(id: "bob0000000000002", name: "Bob")

  func session() -> InstanceSession {
    let session = InstanceSession(instance: Instance(baseURL: URL(string: "https://chat.example.com")!, name: "Example"), tokens: MemoryTokenStore())
    session.showForRendering(
      me: Me(id: ada.id, name: ada.name, administrator: false),
      people: [
        DirectoryUser(id: ada.id, name: ada.name, role: .member, status: .active, avatarUrl: "/a"),
        DirectoryUser(id: bob.id, name: bob.name, role: .administrator, status: .active, avatarUrl: "/b"),
      ])
    return session
  }

  func message(_ id: String, _ creator: User, _ body: String, _ plain: String, minute: Int) -> Message {
    let at = String(format: "2026-11-19T14:%02d:00.000Z", minute)
    return Message(id: id, clientMessageId: "c-\(id)", roomId: "r1", creator: creator, body: body, plainText: plain, mentions: [], createdAt: at, updatedAt: at, editedAt: nil)
  }

  /** A room with a boosted message of Bob's, one of Ada's open in its editor, and a file uploading. */
  func room(_ session: InstanceSession) -> RoomModel {
    let room = RoomModel(room: Room(id: "r1", kind: .open, name: "general"), api: session.api, instance: session)
    var boosted = message("m1", bob, "<p>Shipping <strong>today</strong></p>", "Shipping today", minute: 1)
    boosted.boosts = [
      Boost(id: "b1", messageId: "m1", booster: ada, content: "\u{1F44D}", createdAt: "2026-11-19T14:01:00.000Z"),
      Boost(id: "b2", messageId: "m1", booster: bob, content: "\u{1F44D}", createdAt: "2026-11-19T14:01:00.000Z"),
      Boost(id: "b3", messageId: "m1", booster: bob, content: "nice", createdAt: "2026-11-19T14:01:00.000Z"),
    ]
    let mine = message("m2", ada, "<ul><li>one</li><li>two</li></ul><blockquote>quoted</blockquote>", "one two", minute: 2)
    room.apply(.welcome(you: ada, present: [ada, bob], seq: 1, page: TimelinePage(messages: [boosted, mine], hasMore: false, hasNewer: false, around: nil)))
    room.editing.insert("m2")
    let file = PickedFile(name: "notes.txt", type: "text/plain", size: 12_345, source: .data(Data(count: 12_345)))
    room.composer().pick([file, PickedFile(name: "huge.mov", type: "video/quicktime", size: Files.maxFileSize + 1, source: .data(Data()))])
    room.quote(boosted, into: room.composer())
    return room
  }

  func render(_ view: some View, _ name: String, height: CGFloat) throws {
    for scheme in [ColorScheme.light, .dark] {
      _ = try renderView(view, named: name, size: CGSize(width: 900, height: height), colorScheme: scheme)
    }
  }

  func testSuiteCompose() throws {
    let session = session()
    let room = room(session)
    let app = AppModel(tokens: MemoryTokenStore())
    let view = VStack(alignment: .leading, spacing: 0) {
      ForEach(room.timeline.lines) { line in
        SuiteMessageRow(session: session, room: room, line: line, continues: false, openThread: { _ in })
      }
      SuiteUploadCard(upload: UploadState(name: "harbour.jpg", size: 3_400_000, percent: 42))
      SuiteUploadCard(upload: UploadState(name: "broken.zip", size: 900, percent: 10, error: EmberText.uploadFailed))
      SuiteReactionTray(room: room, message: room.timeline.messages[0]) {}
      Spacer(minLength: 0)
      SuiteComposer(app: app, session: session, room: room, placeholder: "Message #general")
    }
    .frame(width: 900, height: 1100, alignment: .top)
    .background(SemanticColor.background)
    try render(view, "suite-compose", height: 1100)
    XCTAssertEqual(room.composer().files.map(\.name), ["notes.txt"])
    XCTAssertEqual(room.composer().refused, [EmberText.tooLargeToAttach("huge.mov")])
    XCTAssertEqual(
      room.composer().quoting,
      "<blockquote><p>Shipping <strong>today</strong></p></blockquote><cite>Bob <a href=\"https://chat.example.com/rooms/r1/@m1\">#</a></cite><p><br></p>")
  }

  func testIRCCompose() throws {
    let session = session()
    let room = room(session)
    let app = AppModel(tokens: MemoryTokenStore())
    let view = VStack(alignment: .leading, spacing: 0) {
      ForEach(room.timeline.lines) { line in
        MessageLine(session: session, room: room, line: line, openThread: { _ in })
      }
      Spacer(minLength: 0)
      StatusBar(session: session, room: room)
      InputLine(app: app, session: session, room: room)
    }
    .frame(width: 900, height: 400, alignment: .top)
    .background(Theme.irc.buffer)
    .environment(\.theme, .irc)
    try render(view, "irc-compose", height: 400)
  }

  func testDialogs() throws {
    let session = session()
    let room = room(session)
    for look in [AppTheme.suite, .irc] {
      let name = look == .suite ? "suite" : "irc"
      try render(ShortcutsSheet().frame(width: 520, height: 900).environment(\.appTheme, look).environment(\.theme, .irc), "\(name)-shortcuts", height: 900)
      try render(SnippetSheet(composer: room.composer(), title: "deploy.sh").frame(width: 600, height: 420).environment(\.appTheme, look).environment(\.theme, .irc), "\(name)-snippet", height: 420)
      try render(ReportSheet(room: room, message: room.timeline.messages[0]).frame(width: 480, height: 420).environment(\.appTheme, look).environment(\.theme, .irc), "\(name)-report", height: 420)
    }
    try render(SuiteLinkSheet(draft: LinkDraft(text: "docs", url: "https://example.com")) { _, _ in }.frame(width: 440, height: 240), "suite-link", height: 240)
    try render(SuiteEmojiPanel { _ in }.background(SemanticColor.background), "suite-emoji", height: 400)
  }

  func testSendsWhatTheInputLineWrites() throws {
    let session = session()
    let room = RoomModel(room: Room(id: "r1", kind: .open, name: "general"), api: session.api, instance: session)
    room.apply(.welcome(you: ada, present: [ada], seq: 1, page: TimelinePage(messages: [], hasMore: false, hasNewer: false, around: nil)))
    // A typed @name mentions only whom the room's @ prompt offered.
    room.send("hi @Bob")
    let unoffered = try XCTUnwrap(room.timeline.queued.last.flatMap { room.timeline.pending[$0] })
    XCTAssertEqual(unoffered.body, "<p>hi @Bob</p>")
    room.composer().offer([MentionPromptItem(id: bob.id, name: bob.name, username: "bob", agent: false, avatarUrl: nil)])
    room.send("**hi** @Bob")
    let pending = try XCTUnwrap(room.timeline.queued.last.flatMap { room.timeline.pending[$0] })
    XCTAssertEqual(pending.body, "<p><strong>hi</strong> <action-text-attachment sgid=\"bob0000000000002\" content-type=\"application/vnd.campfire.mention\"></action-text-attachment></p>")
    // Not connected: it waits, queued, to go once the socket opens.
    XCTAssertEqual(room.timeline.queued.last, pending.clientMessageId)
    XCTAssertFalse(room.send(ComposerDocument(plain: String(repeating: "a", count: 40_001))))
    XCTAssertEqual(room.notice, EmberText.messageTooLong)
  }
}

/** What the composers keep: drafts with their mentions named, open editors' text, and a room that's gone. */
@MainActor
final class ComposerKeepingTests: XCTestCase {
  let ada = User(id: "ada0000000000001", name: "Ada Lovelace")
  let bob = User(id: "bob0000000000002", name: "Bob")

  func session() -> InstanceSession {
    let session = InstanceSession(instance: Instance(baseURL: URL(string: "https://chat.example.com")!, name: "Example"), tokens: MemoryTokenStore())
    session.showForRendering(
      me: Me(id: ada.id, name: ada.name, administrator: false),
      people: [
        DirectoryUser(id: ada.id, name: ada.name, role: .member, status: .active, avatarUrl: "/a"),
        DirectoryUser(id: bob.id, name: bob.name, role: .administrator, status: .active, avatarUrl: "/b"),
      ])
    return session
  }

  func room(_ session: InstanceSession, id: RoomID = "r1") -> RoomModel {
    let room = RoomModel(room: Room(id: id, kind: .open, name: "general"), api: session.api, instance: session)
    let at = "2026-11-19T14:02:00.000Z"
    let mine = Message(
      id: "m2", clientMessageId: "c-m2", roomId: id, creator: ada, body: "<p>Hi <strong>all</strong></p><ul><li>one</li></ul>", plainText: "Hi all one",
      mentions: [], createdAt: at, updatedAt: at, editedAt: nil)
    room.apply(.welcome(you: ada, present: [ada, bob], seq: 1, page: TimelinePage(messages: [mine], hasMore: false, hasNewer: false, around: nil)))
    return room
  }

  func render(_ view: some View, _ name: String, height: CGFloat) throws {
    for scheme in [ColorScheme.light, .dark] {
      _ = try renderView(view, named: name, size: CGSize(width: 700, height: height), colorScheme: scheme)
    }
  }

  func testDraftKeepsItsMentionsNamed() {
    let session = session()
    let roomId = "draft-\(UUID().uuidString)"
    let key = "composer-draft-\(session.instance.host)-\(ada.id)-\(roomId)"
    let mention = #"<action-text-attachment sgid="bob0000000000002" content-type="application/vnd.campfire.mention"></action-text-attachment>"#
    UserDefaults.standard.set("<p>Hi \(mention)</p>", forKey: key + ".html")
    defer { UserDefaults.standard.removeObject(forKey: key + ".html") }
    let composer = room(session, id: roomId).composer()
    XCTAssertEqual(composer.document.plainText, "Hi @Bob")
    composer.giveBack(GivenBack(text: "Hi @Bob", why: "No", html: "<p>Bye \(mention)</p>"))
    XCTAssertEqual(composer.document.plainText, "Bye @Bob")
    composer.clear()
  }

  func testOpenEditorsKeepTheirText() {
    let room = room(session())
    let message = room.timeline.messages[0]
    room.editing.insert(message.id)
    let editor = room.editor(for: message)
    XCTAssertEqual(editor.document.html, message.body)
    editor.document = ComposerDocument(plain: "changed")
    XCTAssertTrue(room.editor(for: message) === editor)
    room.editing.remove(message.id)
    XCTAssertEqual(room.editor(for: message).document.html, message.body)
    // IRC Classic's /edit writes it as Markdown-style text that saves back the same.
    XCTAssertEqual(room.editableLine(message), "Hi **all**\n- one")
  }

  func testRoomDeletedInPlaceOfTheComposer() throws {
    let session = session()
    let room = room(session)
    room.end(.notFound)
    XCTAssertTrue(room.ended)
    let app = AppModel(tokens: MemoryTokenStore())
    try render(
      VStack(spacing: 0) {
        SuiteRoomDeleted()
        SuiteComposer(app: app, session: session, room: self.room(session, id: "r2"), placeholder: "Message #general")
      }
      .frame(width: 700, height: 260)
      .background(SemanticColor.background),
      "suite-room-deleted", height: 260)
    try render(
      VStack(spacing: 0) {
        IRCRoomDeleted()
        InputLine(app: app, session: session, room: self.room(session, id: "r3"))
      }
      .frame(width: 700, height: 160)
      .background(Theme.irc.buffer)
      .environment(\.theme, .irc),
      "irc-room-deleted", height: 160)
  }

  func testPictureChip() throws {
    let session = session()
    let room = room(session, id: "r4")
    let picture = Self.png()
    room.composer().pick([
      PickedFile(name: "harbour.png", type: "image/png", size: picture.count, source: .data(picture)),
      PickedFile(name: "notes.txt", type: "text/plain", size: 5, source: .data(Data("notes".utf8))),
    ])
    let view = SuiteComposer(app: AppModel(tokens: MemoryTokenStore()), session: session, room: room, placeholder: "Message #general")
      .frame(width: 700, height: 220)
      .background(SemanticColor.background)
    try render(view, "suite-picture-chip", height: 220)
    room.composer().clear()
  }

  /** A small orange-and-blue PNG. */
  static func png() -> Data {
    let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    context.setFillColor(CGColor(red: 0, green: 0.3, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 20))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }
}
