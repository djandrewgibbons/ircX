import AppCoreUI
import AppCoreUITestSupport
@testable import EmberKit
@testable import IRCXUI
import SwiftUI
import XCTest

/**
 * Messages as each theme draws them, written to .build/ui-renders/ to look at: rich text, code, emoji,
 * edits, stand-ins, files, link previews, huddles, bot cards, typing and the room's notice.
 */
@MainActor
final class MessageRenderTests: XCTestCase {
  let ada = User(id: "ada0000000000001", name: "Ada Lovelace")
  let bob = User(id: "bob0000000000002", name: "Bob")
  let bot = User(id: "bot0000000000003", name: "Deploys")

  func session() -> InstanceSession {
    let session = InstanceSession(instance: Instance(baseURL: URL(string: "https://chat.example.com")!, name: "Example"), tokens: MemoryTokenStore())
    session.showForRendering(
      me: Me(id: ada.id, name: ada.name, administrator: true),
      people: [
        DirectoryUser(id: ada.id, name: ada.name, role: .administrator, status: .active, avatarUrl: "/a"),
        DirectoryUser(id: bob.id, name: bob.name, role: .member, status: .active, avatarUrl: "/b"),
        DirectoryUser(id: bot.id, name: bot.name, role: .bot, status: .active, avatarUrl: "/c"),
      ],
      huddles: ["r1": LiveHuddle(startedAt: "2026-11-19T15:00:00.000Z", userIds: [ada.id, bob.id])])
    return session
  }

  func message(_ id: String, _ creator: User, _ body: String, _ plain: String, minute: Int, edited: Bool = false, mentions: [User] = []) -> Message {
    let at = String(format: "2026-11-19T14:%02d:00.000Z", minute)
    return Message(
      id: id, clientMessageId: "c-\(id)", roomId: "r1", creator: creator, body: body, plainText: plain, mentions: mentions, createdAt: at,
      updatedAt: at, editedAt: edited ? at : nil)
  }

  func cards() throws -> [Card] {
    let json = #"""
      [{"source":"attachment","color":"good","pretext":"<p>Deploy finished</p>","parts":[
        {"kind":"author","name":"GitHub Actions","href":"https://github.com"},
        {"kind":"title","text":"web #482 deployed","href":"https://github.com/x/y/actions/1"},
        {"kind":"text","html":"<p>All <strong>12</strong> checks passed.</p>"},
        {"kind":"fields","fields":[{"title":"Branch","html":"<p>main</p>","short":true},{"title":"Took","html":"<p>3m 12s</p>","short":true}]},
        {"kind":"context","items":[{"html":"<p>Triggered by Bob</p>"}]},
        {"kind":"divider"},
        {"kind":"table","rows":[["<p>Region</p>","<p>Status</p>"],["<p>us-east</p>","<p>healthy</p>"]],"columns":[{"align":"left","wrap":false},{"align":"right","wrap":false}]},
        {"kind":"buttons","buttons":[{"text":"Roll back","action":{"id":"rollback"},"style":"danger"},{"text":"Approve","action":{"id":"approve","value":"1"},"style":"primary"},{"text":"Open run","href":"https://github.com/x/y/actions/1"}]},
        {"kind":"footer","text":"deploy-bot","at":1763560000}
      ]},
      {"source":"blocks","parts":[
        {"kind":"header","text":"Pick a lunch spot"},
        {"kind":"tiles","tiles":[{"title":"Noodle Bar","subtitle":"0.2 mi","body":"<p>Ramen, fast</p>","buttons":[{"text":"Vote","action":{"id":"vote","value":"noodle"},"style":"primary"}]},{"title":"Taqueria","subtitle":"0.4 mi","buttons":[{"text":"Vote","action":{"id":"vote","value":"taco"}}]}]}
      ]}]
      """#
    return try JSONDecoder().decode([Card].self, from: Data(json.utf8))
  }

  func room(_ session: InstanceSession) throws -> RoomModel {
    let room = RoomModel(room: Room(id: "r1", kind: .open, name: "general"), api: session.api, instance: session)
    let mention = #"<action-text-attachment sgid="\#(bob.id)" content-type="application/vnd.campfire.mention"></action-text-attachment>"#
    let preview = #"<action-text-attachment content-type="application/vnd.actiontext.opengraph-embed" content="&lt;actiontext-opengraph-embed&gt;&lt;div class=&quot;og-embed&quot;&gt;&lt;div class=&quot;og-embed__content&quot;&gt;&lt;div class=&quot;og-embed__title&quot;&gt;&lt;a href=&quot;https://swift.org/blog&quot;&gt;Swift Blog&lt;/a&gt;&lt;/div&gt;&lt;div class=&quot;og-embed__description&quot;&gt;News and posts about Swift.&lt;/div&gt;&lt;/div&gt;&lt;/div&gt;&lt;/actiontext-opengraph-embed&gt;"></action-text-attachment>"#
    var deleted = message("m5", bob, "", "", minute: 5)
    deleted.deleted = true
    deleted.thread = ThreadSummary(count: 2, latestAt: "2026-11-19T14:30:00.000Z", people: [ada, bob])
    var file = message("m7", bob, "", "notes.pdf", minute: 7)
    file.attachment = StoredFile(id: "f1", name: "quarterly-notes.pdf", contentType: "application/pdf", byteSize: 182_000, url: "/f/1", downloadUrl: "/f/1/d")
    var huddle = message("m8", bob, "", "", minute: 8)
    huddle.huddle = MessageHuddle(startedAt: "2026-11-19T15:00:00.000Z", endedAt: nil, people: nil)
    var over = message("m9", bob, "", "", minute: 9)
    over.huddle = MessageHuddle(startedAt: "2026-11-19T13:00:00.000Z", endedAt: "2026-11-19T14:05:00.000Z", people: [ada, bob])
    var cardMessage = message("m10", bot, "", "Deploy finished", minute: 10)
    cardMessage.cards = try cards()
    var reply = message("m11", bob, "<p>Agreed, ship it</p>", "Agreed, ship it", minute: 11)
    reply.parentId = "m2"
    reply.alsoSent = true
    reply.parentText = "Here's the plan for today"
    let messages = [
      message("m1", ada, "<p>Morning <strong>all</strong>, the <em>new</em> build is at https://example.org/build and <code>main</code> is green.</p>", "Morning all", minute: 1),
      message(
        "m2", bob, "<h2>Plan</h2><ul><li>Ship <s>Tuesday</s> Wednesday</li><li>Ask \(mention)</li></ul><ol><li>One</li><li>Two</li></ol><blockquote>Measure twice</blockquote>",
        "Here's the plan for today", minute: 2, edited: true, mentions: [bob]),
      message("m3", ada, #"<pre data-language="swift">let x = 1 // one</pre><pre data-language="js">const a = "b"; // c</pre>"#, "code", minute: 3),
      message("m4", bob, "<p>\u{1F389}\u{1F525}</p>", "\u{1F389}\u{1F525}", minute: 4),
      deleted,
      message("m6", bob, "<p>https://swift.org/blog</p>\(preview)", "https://swift.org/blog", minute: 6),
      file, huddle, over, cardMessage, reply,
      message("m12", ada, String(repeating: "<b>", count: 450), "deep", minute: 12),
    ]
    room.apply(.welcome(you: ada, present: [ada, bob], seq: 1, page: TimelinePage(messages: messages, hasMore: false, hasNewer: false, around: nil)))
    room.receive(#"{"type":"typing","user":{"id":"bot0000000000003","name":"Deploys"},"typing":true,"doing":"is using Digg: digg_get_feed"}"#)
    room.receive(#"{"type":"error","message":"This community doesn't allow one of these words.","failed":"boost.create"}"#)
    return room
  }

  func render(_ view: some View, _ name: String, height: CGFloat = 2600) throws {
    for scheme in [ColorScheme.light, .dark] {
      _ = try renderView(view, named: name, size: CGSize(width: 900, height: height), colorScheme: scheme)
    }
  }

  func testSuiteMessages() throws {
    let session = session()
    let room = try room(session)
    let view = VStack(alignment: .leading, spacing: 0) {
      ForEach(room.timeline.lines) { line in
        SuiteMessageRow(session: session, room: room, line: line, continues: false, openThread: { _ in })
      }
      SuiteRoomNotice(room: room)
      Text(room.typingText ?? "nobody").font(DesignFont.detail)
      Spacer(minLength: 0)
    }
    .frame(width: 900, height: 2600, alignment: .top)
    .background(SemanticColor.background)
    try render(view, "suite-messages")
    XCTAssertEqual(room.typingText, "Deploys is using Digg: digg_get_feed")
    XCTAssertEqual(room.notice, "This community doesn't allow one of these words.")
  }

  func testIRCMessages() throws {
    let session = session()
    let room = try room(session)
    let view = VStack(alignment: .leading, spacing: 0) {
      ForEach(room.timeline.lines) { line in
        MessageLine(session: session, room: room, line: line, openThread: { _ in })
      }
      StatusBar(session: session, room: room)
      Spacer(minLength: 0)
    }
    .frame(width: 900, height: 2200, alignment: .top)
    .background(Theme.irc.buffer)
    .environment(\.theme, .irc)
    try render(view, "irc-messages", height: 2200)
  }

  func testTranslationButtons() throws {
    var account = try JSONDecoder().decode(Account.self, from: Data(Self.account.utf8))
    account.hideTranslationButtons = false
    let view = VStack(alignment: .leading, spacing: Spacing.lg) {
      HStack { TextField("Email", text: .constant("")); TranslationButton(key: "email_address", account: account) }
      HStack { TextField("password", text: .constant("")); TranslationButton(key: "password", account: account, classic: true) }
    }
    .padding(Spacing.xl)
    .frame(width: 420, height: 140)
    .background(SemanticColor.background)
    try render(view, "translation-buttons", height: 140)
  }

  // MARK: - Attachments, the image viewer, refusals and threads

  /** A picture of `size` in one color, as a file's preview loads. */
  func swatch(_ width: CGFloat, _ height: CGFloat, _ color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
      color.setFill()
      rect.fill()
      NSColor.white.withAlphaComponent(0.6).setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.25)).fill()
      return true
    }
  }

  /** One file of every kind a message shows, their pictures and text loaded as they would have been. */
  func attachmentRoom(_ session: InstanceSession) -> RoomModel {
    let room = RoomModel(room: Room(id: "r1", kind: .open, name: "general"), api: session.api, instance: session)
    func file(_ id: String, _ name: String, _ type: String, size: Int, width: Int? = nil, height: Int? = nil, preview: String? = nil) -> StoredFile {
      StoredFile(id: id, name: name, contentType: type, byteSize: size, width: width, height: height, url: "/f/\(id)", downloadUrl: "/f/\(id)/d", previewUrl: preview)
    }
    let picture = file("p1", "harbour.jpg", "image/jpeg", size: 820_000, width: 1200, height: 800, preview: "/f/p1/preview")
    let video = file("v1", "launch.mp4", "video/mp4", size: 9_400_000, width: 1280, height: 720, preview: "/f/v1/poster")
    let svg = file("s1", "logo.svg", "image/svg+xml", size: 2_400)
    let snippet = file("t1", "deploy.py", "text/plain", size: 120)
    let long = file("t2", "server.log", "text/plain", size: 900)
    let pdf = file("d1", "quarterly-notes.pdf", "application/pdf", size: 182_000)
    ImageCache.shared.setObject(swatch(600, 400, .systemTeal), forKey: session.api.url("/f/p1/preview") as NSURL)
    ImageCache.shared.setObject(swatch(640, 360, .systemIndigo), forKey: session.api.url("/f/v1/poster") as NSURL)
    FileLoads.svgs.setObject(swatch(160, 80, .systemOrange), forKey: "s1")
    FileLoads.keep(("def deploy():\n    print(\"shipping\")  # now", "def deploy():\n    print(\"shipping\")  # now"), for: snippet)
    let log = (1...12).map { "12:0\($0 % 10) GET /api/rooms 200 \($0 * 7)ms" }.joined(separator: "\n")
    FileLoads.keep((log, log), for: long)
    let messages = [picture, video, svg, snippet, long, pdf].enumerated().map { index, stored -> Message in
      var shown = message("a\(index)", bob, "", stored.name, minute: index + 1)
      shown.attachment = stored
      return shown
    }
    room.apply(.welcome(you: ada, present: [ada, bob], seq: 1, page: TimelinePage(messages: messages, hasMore: false, hasNewer: false, around: nil)))
    return room
  }

  func testSuiteAttachments() throws {
    let session = session()
    let room = attachmentRoom(session)
    XCTAssertEqual(room.timeline.lines.compactMap { line -> AttachmentShown? in
      guard case let .message(message, _) = line, let file = message.attachment else { return nil }
      return AttachmentShown(file)
    }, [.picture(path: "/f/p1/preview"), .video, .svg, .text(language: "python"), .text(language: nil), .card])
    let view = VStack(alignment: .leading, spacing: 0) {
      ForEach(room.timeline.lines) { line in
        SuiteMessageRow(session: session, room: room, line: line, continues: false, openThread: { _ in })
      }
      Spacer(minLength: 0)
    }
    .frame(width: 900, height: 1500, alignment: .top)
    .background(SemanticColor.background)
    try render(view, "suite-attachments", height: 1500)
  }

  func testIRCAttachments() throws {
    let session = session()
    let room = attachmentRoom(session)
    let view = VStack(alignment: .leading, spacing: 0) {
      ForEach(room.timeline.lines) { line in
        MessageLine(session: session, room: room, line: line, openThread: { _ in })
      }
      Spacer(minLength: 0)
    }
    .frame(width: 900, height: 1100, alignment: .top)
    .background(Theme.irc.buffer)
    .environment(\.theme, .irc)
    try render(view, "irc-attachments", height: 1100)
  }

  func testImageViewers() throws {
    let session = session()
    ImageCache.shared.setObject(swatch(1200, 800, .systemTeal), forKey: session.api.url("/f/p1") as NSURL)
    let viewed = ViewedImage(path: "/f/p1", name: "harbour.jpg", downloadPath: "/f/p1/d")
    try render(ImageViewer(api: session.api, image: viewed).frame(width: 900, height: 600), "suite-image-viewer", height: 600)
    try render(ImageViewer(api: session.api, image: viewed, classic: true).frame(width: 900, height: 600).environment(\.theme, .irc), "irc-image-viewer", height: 600)
  }

  /** A room that refused a message for a word Blocked words keeps out, and what the composer takes back. */
  func refusedRoom(_ session: InstanceSession) -> (RoomModel, GivenBack?) {
    let room = RoomModel(room: Room(id: "r1", kind: .open, name: "general"), api: session.api, instance: session)
    room.apply(.welcome(you: ada, present: [ada], seq: 1, page: TimelinePage(messages: [], hasMore: false, hasNewer: false, around: nil)))
    room.send("ship the darn build")
    guard case let .message(pending, _)? = room.timeline.lines.last else { return (room, nil) }
    room.receive(#"{"type":"error","message":"This community doesn't allow one of these words.","clientMessageId":"\#(pending.clientMessageId)","failed":"message.create","rewrite":true}"#)
    XCTAssertEqual(room.notice, "This community doesn't allow one of these words.")
    let given = room.takeBack(composerEmpty: true)
    // The composer says why, so the room's notice goes (web `given-back`).
    XCTAssertNil(room.notice)
    XCTAssertTrue(room.timeline.pending.isEmpty)
    return (room, given)
  }

  func testComposersAfterRefusal() throws {
    let session = session()
    let (room, given) = refusedRoom(session)
    let back = try XCTUnwrap(given)
    XCTAssertEqual(back.text, "ship the darn build")
    XCTAssertEqual(back.why, "This community doesn't allow one of these words.")
    XCTAssertEqual(back.html, "<p>ship the darn build</p>")
    let app = AppModel(tokens: MemoryTokenStore())
    let suite = SuiteComposer(app: app, session: session, room: room, placeholder: "Message #general", draft: back.text, refusal: back.why)
      .frame(width: 700, height: 160, alignment: .bottom)
      .background(SemanticColor.background)
    try render(suite, "suite-composer-refused", height: 160)
    let classic = InputLine(app: app, session: session, room: room, draft: back.text, refusal: back.why)
      .frame(width: 700, height: 80, alignment: .bottom)
      .background(Theme.irc.buffer)
      .environment(\.theme, .irc)
    try render(classic, "irc-input-refused", height: 80)
  }

  /** A thread open beside its room, @ember typing in it, and a page of its replies that failed. */
  func threadRoom(_ session: InstanceSession) throws -> RoomModel {
    let room = try room(session)
    room.openThread("m2")
    var reply = message("m20", bot, "<p>Looking into it</p>", "Looking into it", minute: 20)
    reply.parentId = "m2"
    room.apply(.threadOpened(parentId: "m2", parent: room.timeline.message("m2"), messages: [reply], hasMore: true))
    room.receive(#"{"type":"typing","user":{"id":"bot0000000000003","name":"Deploys"},"typing":true,"threadId":"m2","doing":"is searching this room"}"#)
    room.receive(#"{"type":"typing","user":{"id":"bob0000000000002","name":"Bob"},"typing":true,"threadId":"other"}"#)
    room.receive(#"{"type":"error","message":"Couldn't load older replies.","failed":"thread.before"}"#)
    return room
  }

  func testSuiteThread() throws {
    let session = session()
    let room = try threadRoom(session)
    XCTAssertEqual(room.threadTypingText, "Deploys is searching this room")
    XCTAssertEqual(room.thread?.notice, "Couldn't load older replies.")
    // A thread's error is the thread's, not the room's.
    XCTAssertEqual(room.notice, "This community doesn't allow one of these words.")
    let view = SuiteThreadPane(app: AppModel(tokens: MemoryTokenStore()), session: session, room: room)
      .frame(width: 420, height: 900)
      .background(SemanticColor.background)
    try render(view, "suite-thread", height: 900)
  }

  func testIRCThread() throws {
    let session = session()
    let room = try threadRoom(session)
    XCTAssertTrue(room.thread?.lines.contains { if case .event(_, _, "Couldn't load older replies.", .error) = $0 { true } else { false } } == true)
    let view = ThreadPane(app: AppModel(tokens: MemoryTokenStore()), session: session, room: room)
      .frame(width: 420, height: 700)
      .environment(\.theme, .irc)
    try render(view, "irc-thread", height: 700)
  }

  func testGrouping() throws {
    let first = message("g1", bob, "<p>one</p>", "one", minute: 1)
    let second = message("g2", bob, "<p>two</p>", "two", minute: 2)
    XCTAssertTrue(SuiteMessageList.continues(.message(second, pending: false), after: .message(first, pending: false)))
    var huddle = message("g3", bob, "", "", minute: 3)
    huddle.huddle = MessageHuddle(startedAt: "2026-11-19T14:03:00.000Z", endedAt: nil, people: nil)
    XCTAssertFalse(SuiteMessageList.continues(.message(huddle, pending: false), after: .message(second, pending: false)))
    var deleted = message("g4", bob, "", "", minute: 4)
    deleted.deleted = true
    XCTAssertFalse(SuiteMessageList.continues(.message(message("g5", bob, "<p>x</p>", "x", minute: 5), pending: false), after: .message(deleted, pending: false)))
    // Across midnight, within five minutes, it still follows on.
    var late = first
    late.createdAt = "2026-11-19T23:58:00.000Z"
    var early = second
    early.createdAt = "2026-11-20T00:01:00.000Z"
    XCTAssertTrue(SuiteMessageList.continues(.message(early, pending: false), after: .message(late, pending: false)))
  }

  func testCardTableColumns() {
    let columns = [CardColumn(align: .left, wrap: false), CardColumn(align: .right, wrap: false), CardColumn(align: .center, wrap: true)]
    let lines = IRCTable.lines(["us-east", "ok", "a long note that wraps"], widths: [7, 7, 10], columns: columns)
    XCTAssertEqual(lines, ["us-east |      ok |   a long  ", "        |         | note that ", "        |         |   wraps   "])
  }

  func testPastedLink() {
    XCTAssertEqual(DraftPreviews.pastedLink("see ", "see https://swift.org/blog"), "https://swift.org/blog")
    XCTAssertNil(DraftPreviews.pastedLink("see https://swift.org/blo", "see https://swift.org/blog"))
    XCTAssertNil(DraftPreviews.pastedLink("", "hello there"))
  }

  func testPermalinkOpensInPlace() throws {
    let session = session()
    XCTAssertFalse(session.open(link: URL(string: "https://example.org/rooms/r1/@m2")!))
    XCTAssertFalse(session.open(link: URL(string: "https://chat.example.com/account/edit")!))
  }

  static let account = #"""
    {"name":"Example","tagline":"","hideTranslationButtons":true,"customStyles":"","restrictRoomCreation":false,"joinLink":true,"openSignUp":false,
    "memberfulJoin":false,"memberfulSignIn":false,"ssoJoin":false,"ssoSignIn":false,"emailDomainSignUp":false,"emailDomains":[],"navigationIcons":{},
    "huddles":true,"huddleCameras":true,"huddleScreens":true}
    """#
}
