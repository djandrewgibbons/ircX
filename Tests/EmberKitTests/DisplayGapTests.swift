import XCTest
@testable import EmberKit

// The messages-display unit's audit gaps: the composer's link preview, and a thread's own notice.

final class ComposerPreviewTests: XCTestCase {
  func testPreviewContentAsTheWebComposerWritesIt() {
    let content = Previews.content(href: "https://example.com/page", url: "https://example.com/i.png", filename: "Title", description: "")
    XCTAssertEqual(
      content,
      #"<actiontext-opengraph-embed><div class="og-embed gap"><div class="og-embed__content"><div class="og-embed__title"><a href="https://example.com/page" rel="noreferrer" target="_blank">Title</a></div><div class="og-embed__description"></div></div><div class="og-embed__image"><img src="https://example.com/i.png" class="image center" alt=""></div></div></actiontext-opengraph-embed>"#
    )
    XCTAssertEqual(
      Previews.content(href: nil, url: nil, filename: "  A & B  ", description: "<x>"),
      #"<actiontext-opengraph-embed><div class="og-embed gap"><div class="og-embed__content"><div class="og-embed__title">A &amp; B</div><div class="og-embed__description">&lt;x&gt;</div></div></div></actiontext-opengraph-embed>"#
    )
  }

  func testPreviewGoesBelowTheLinksParagraphAndShows() throws {
    let preview = LinkPreview(title: "Swift Blog", url: "https://swift.org/blog", image: nil, description: "News")
    let attachment = Previews.attachment(preview)
    let body = MessageBody.markup(for: "look\nhttps://swift.org/blog\nthanks", preview: (attachment, "https://swift.org/blog"))
    XCTAssertEqual(body, "<p>look</p><p>https://swift.org/blog</p>\(attachment)<p>thanks</p>")
    XCTAssertTrue(try Display.hasPreview(body))
    let shown = try XCTUnwrap(try Display.body(body, plainText: "look\nhttps://swift.org/blog\nthanks", host: "chat.example.com"))
    let previews = shown.flatMap(Self.previews)
    XCTAssertEqual(previews.map(\.href), ["https://swift.org/blog"])
  }

  static func previews(_ node: DisplayNode) -> [DisplayPreview] {
    switch node {
    case let .preview(preview): [preview]
    case let .element(_, _, children): children.flatMap(previews)
    default: []
    }
  }
}

final class ThreadNoticeTests: XCTestCase {
  func reply(_ id: String) throws -> Message {
    try JSONDecoder().decode(Message.self, from: Data(#"""
      {"id":"\#(id)","clientMessageId":"c-\#(id)","roomId":"r1","creator":{"id":"u1","name":"Ada"},"body":"<p>hi</p>","plainText":"hi",
      "mentions":[],"createdAt":"2026-11-19T14:00:00.000Z","updatedAt":"2026-11-19T14:00:00.000Z","editedAt":null,"boosts":[],"parentId":"p1"}
      """#.utf8))
  }

  func testThreadErrorsAreTheThreadsNoticeAndLine() throws {
    var thread = ThreadTimeline(parentId: "p1")
    thread.apply(try ServerFrame.decode(#"{"type":"error","message":"That thread is gone.","failed":"thread.open"}"#))
    XCTAssertEqual(thread.notice, "That thread is gone.")
    XCTAssertEqual(thread.lines.count, 1)
    thread.dismissNotice()
    XCTAssertNil(thread.notice)
  }

  func testRefusedReplyGivesItsNoticeBackWithIt() throws {
    var thread = ThreadTimeline(parentId: "p1")
    thread.send(try reply("a"))
    thread.apply(try ServerFrame.decode(#"{"type":"error","message":"Not that word.","clientMessageId":"c-a","failed":"message.create","rewrite":true}"#))
    XCTAssertEqual(thread.notice, "Not that word.")
    XCTAssertEqual(thread.rewrites["c-a"], "Not that word.")
    thread.giveBack("c-a", taken: true)
    XCTAssertNil(thread.notice, "the composer says why")
    XCTAssertTrue(thread.pending.isEmpty)
  }

  func testRoomTimelineLeavesThreadErrorsToTheThread() throws {
    var timeline = Timeline()
    XCTAssertFalse(timeline.apply(try ServerFrame.decode(#"{"type":"error","message":"Gone.","failed":"thread.before"}"#)))
    XCTAssertTrue(timeline.events.isEmpty)
  }
}
