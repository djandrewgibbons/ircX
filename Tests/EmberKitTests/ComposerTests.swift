@testable import EmberKit
import XCTest

/** The composers' markup, Quote, snippets, uploads' words and the message actions' rules. */
final class ComposerTests: XCTestCase {
  let grace = User(id: "0123456789abcdef", name: "Grace")
  let ada = User(id: "ada0000000000001", name: "Ada Lovelace")
  let mention = #"<action-text-attachment sgid="0123456789abcdef" content-type="application/vnd.campfire.mention"></action-text-attachment>"#

  func testPlainTextIsOneParagraphOfLines() {
    XCTAssertEqual(ComposerDocument(plain: "a & b\nc < d").html, "<p>a &amp; b<br>c &lt; d</p>")
    XCTAssertEqual(ComposerDocument(plain: "").html, "<p><br></p>")
    XCTAssertTrue(ComposerDocument(plain: " \n ").isBlank)
    XCTAssertEqual(ComposerDocument(plain: "nbsp\u{A0}here").html, "<p>nbsp&nbsp;here</p>")
  }

  func testEachBlockAndMark() {
    let document = ComposerDocument(lines: [
      ComposerLine(.heading(2), [ComposerRun("Plan")]),
      ComposerLine(.paragraph, [ComposerRun("Hi "), ComposerRun("all", marks: [.bold, .italic]), ComposerRun(" see "), ComposerRun("docs", link: "https://x.test/?a=1&b=2")]),
      ComposerLine(.paragraph, [ComposerRun("and "), ComposerRun("@Grace", mention: grace.id)]),
      ComposerLine(.bullet, [ComposerRun("one")]),
      ComposerLine(.bullet, [ComposerRun("two", marks: [.strike])]),
      ComposerLine(.ordered, [ComposerRun("first", marks: [.underline])]),
      ComposerLine(.quote, [ComposerRun("quoted")]),
      ComposerLine(.quote, [ComposerRun("more")]),
      ComposerLine(.code(language: "swift"), [ComposerRun("let x = 1 < 2")]),
      ComposerLine(.code(language: "swift"), []),
      ComposerLine(.code(language: "swift"), [ComposerRun("print(x)")]),
      ComposerLine(.rule),
      ComposerLine(.paragraph, [ComposerRun("x", marks: [.code])]),
    ])
    XCTAssertEqual(
      document.html,
      "<h2>Plan</h2><p>Hi <strong><em>all</em></strong> see <a href=\"https://x.test/?a=1&amp;b=2\">docs</a><br>and \(mention)</p>"
        + "<ul><li>one</li><li><s>two</s></li></ul><ol><li><u>first</u></li></ol><blockquote>quoted<br>more</blockquote>"
        + "<pre data-language=\"swift\">let x = 1 &lt; 2\n\nprint(x)</pre><hr><p><code>x</code></p>")
  }

  func testMarkupReadsBackToTheSameMarkup() throws {
    for html in [
      "<p>Hi <strong>all</strong><br>bye</p>",
      "<h1>T</h1><ul><li>a</li><li>b</li></ul><ol><li>c</li></ol>",
      "<blockquote>q<br>r</blockquote><p>after</p>",
      "<pre data-language=\"ruby\">x = 1\ny = 2</pre>",
      "<p><a href=\"https://example.com\">link</a> and <s>gone</s> <u>under</u> <em>it</em> <code>c</code></p><hr>",
      "<p>Hi \(mention)!</p>",
    ] {
      XCTAssertEqual(try ComposerDocument(html: html, name: { _ in "Grace" }).html, html, html)
    }
    let mentioned = try ComposerDocument(html: "<p>Hi \(mention)</p>", name: { _ in "Grace" })
    XCTAssertEqual(mentioned.lines.first?.runs.last, ComposerRun("@Grace", mention: grace.id))
    XCTAssertEqual(mentioned.plainText, "Hi @Grace")
  }

  func testQuotedParagraphsReadAsQuoteLines() throws {
    let document = try ComposerDocument(html: "<blockquote><p>a</p><p>b</p></blockquote><cite>Ada <a href=\"https://e.test/@m1\">#</a></cite><p><br></p>", name: { _ in "" })
    XCTAssertEqual(document.lines.map(\.block), [.quote, .quote, .cite, .paragraph])
    XCTAssertEqual(document.html, "<blockquote>a<br>b</blockquote><cite>Ada <a href=\"https://e.test/@m1\">#</a></cite><p><br></p>")
  }

  func testPreviewsStayAsTheyAre() throws {
    let preview = #"<action-text-attachment content-type="application/vnd.actiontext.opengraph-embed" content="&lt;b&gt;Swift&lt;/b&gt;"></action-text-attachment>"#
    let document = try ComposerDocument(html: "<p>see</p>" + preview, name: { _ in "" })
    guard case let .attachment(_, label) = document.lines.last?.block else { return XCTFail("no attachment") }
    XCTAssertEqual(label, "Swift")
    XCTAssertEqual(document.html, "<p>see</p>" + preview)
  }

  func testMarkdownStyleInput() {
    let document = ComposerDocument(markdown: "# Title\n**bold** and _it_ and *it* and ~~no~~ and `x_y`\n> quoted\n- a\n* b\n1. c\n---\n```js\nlet a = 1\n```\nsnake_case and https://x.test/a_b_c", mentioning: [])
    XCTAssertEqual(
      document.html,
      "<h1>Title</h1><p><strong>bold</strong> and <em>it</em> and <em>it</em> and <s>no</s> and <code>x_y</code></p><blockquote>quoted</blockquote>"
        + "<ul><li>a</li><li>b</li></ul><ol><li>c</li></ol><hr><pre data-language=\"js\">let a = 1</pre><p>snake_case and https://x.test/a_b_c</p>")
  }

  func testMarkdownMentions() {
    XCTAssertEqual(ComposerDocument(markdown: "hi @grace, mail a@grace.test", mentioning: [grace]).html, "<p>hi \(mention), mail a@grace.test</p>")
    XCTAssertEqual(ComposerDocument(markdown: "Grace: look", mentioning: [grace]).html, "<p>\(mention): look</p>")
    XCTAssertEqual(ComposerDocument(markdown: "@Ada Lovelace hi", mentioning: [grace, ada]).lines[0].runs[0].mention, ada.id)
  }

  func testTooLong() {
    XCTAssertFalse(ComposerDocument(plain: String(repeating: "a", count: 40_000)).isTooLong)
    XCTAssertTrue(ComposerDocument(plain: String(repeating: "a", count: 40_001)).isTooLong)
    XCTAssertTrue(ComposerDocument(plain: String(repeating: "<", count: 30_000)).isTooLong)
  }

  func testTrimmed() {
    XCTAssertEqual(ComposerDocument(plain: "\n\nhi\n\n").trimmed().html, "<p>hi</p>")
  }

  // MARK: - Quote (apps/web/src/lib/messages.test.ts)

  func testQuoteCitesTheAuthorWithALink() throws {
    let nodes = try Display.body("<p>Third time's a charm, \(mention) &amp; https://example.com</p>", plainText: "", host: "")
    XCTAssertEqual(
      Quote.markup(nodes, author: "Ada & co", link: "https://ember.test/rooms/general/@m%201", nameOf: { _ in "Grace <3" }),
      "<blockquote><p>Third time's a charm, Grace &lt;3 &amp; <a href=\"https://example.com\">https://example.com</a></p></blockquote>"
        + "<cite>Ada &amp; co <a href=\"https://ember.test/rooms/general/@m%201\">#</a></cite><p><br></p>")
  }

  func testQuoteOfOnlyAPreviewQuotesItsLink() throws {
    let content = HTML.escapeAttribute(Previews.content(href: "https://basecamp.com", url: nil, filename: "Basecamp", description: nil), true)
    let preview = "<action-text-attachment content-type=\"application/vnd.actiontext.opengraph-embed\" content=\"\(content)\"></action-text-attachment>"
    let nodes = try Display.body(preview, plainText: "", host: "")
    XCTAssertEqual(
      Quote.markup(nodes, author: "Ada", link: "https://ember.test/rooms/general/@m1", nameOf: { _ in "Grace" }),
      "<blockquote>https://basecamp.com/</blockquote><cite>Ada <a href=\"https://ember.test/rooms/general/@m1\">#</a></cite><p><br></p>")
  }

  func testCardsQuote() {
    XCTAssertEqual(
      Quote.markup(Quote.cards("a\nb"), author: "Bot", link: "L", nameOf: { _ in "" }), "<blockquote><p>a<br>b</p></blockquote><cite>Bot <a href=\"L\">#</a></cite><p><br></p>")
  }

  // MARK: - Snippets and uploads

  func testSnippetNames() {
    XCTAssertEqual(Snippets.name("  "), "Untitled.txt")
    XCTAssertEqual(Snippets.name("a/b\\c"), "a-b-c.txt")
    XCTAssertEqual(Snippets.name("query.sql"), "query.sql")
    XCTAssertEqual(Snippets.name("v1.2 notes"), "v1.2 notes.txt")
  }

  func testUploadWords() {
    XCTAssertEqual(UploadWords.size(0), "1 KB")
    XCTAssertEqual(UploadWords.size(1_001), "2 KB")
    XCTAssertEqual(UploadWords.size(12_345_678), "12.3 MB")
    XCTAssertEqual(UploadWords.status(percent: 42, error: nil), "Uploading · 42%")
    XCTAssertEqual(UploadWords.status(percent: 100, error: nil), "Processing…")
    XCTAssertEqual(UploadWords.status(percent: 3, error: "x"), "Upload failed")
    XCTAssertEqual(UploadWords.failure(status: 413, reason: nil), Files.fileTooLarge)
    XCTAssertEqual(UploadWords.failure(status: 422, reason: "No."), "No.")
    XCTAssertEqual(UploadWords.failure(status: 500, reason: "x"), EmberText.uploadFailed)
    XCTAssertEqual(UploadWords.percent(sent: 0, of: 0), 100)
    XCTAssertEqual(UploadWords.percent(sent: 5, of: 10), 50)
  }

  // MARK: - Message actions

  func message(_ creator: User) -> Message {
    Message(id: "m1", clientMessageId: "c1", roomId: "r", creator: creator, body: "<p>x</p>", plainText: "x", mentions: [], createdAt: "2026-11-19T14:00:00.000Z", updatedAt: "2026-11-19T14:00:00.000Z", editedAt: nil)
  }

  func testMessageActions() {
    let mine = MessageAction.Context(mine: true, administrator: false, inThread: false)
    let theirs = MessageAction.Context(mine: false, administrator: false, inThread: true)
    let admin = MessageAction.Context(mine: false, administrator: true, inThread: false)
    XCTAssertEqual(MessageAction.menu(for: message(ada), mine), [.quote, .copyText, .copyLink, .edit, .delete])
    XCTAssertEqual(MessageAction.menu(for: message(grace), theirs), [.quote, .copyText, .copyLink, .block, .report])
    XCTAssertEqual(MessageAction.menu(for: message(grace), admin), [.quote, .copyText, .copyLink, .block, .report, .edit, .delete])
    var file = message(ada)
    file.attachment = StoredFile(id: "f", name: "a.pdf", contentType: "application/pdf", byteSize: 1, url: "/f", downloadUrl: "/d")
    XCTAssertEqual(MessageAction.menu(for: file, mine), [.copyLink, .delete])
    XCTAssertEqual(MessageAction.bar(for: file, mine), [.replyInThread, .download, .share, .edit])
    XCTAssertEqual(MessageAction.bar(for: message(grace), theirs), [])
    XCTAssertTrue(MessageAction.editsFixed(file))
    var huddle = message(grace)
    huddle.huddle = MessageHuddle(startedAt: "2026-11-19T14:00:00.000Z", endedAt: nil, people: nil)
    XCTAssertEqual(MessageAction.menu(for: huddle, theirs), [.copyLink])
    XCTAssertEqual(MessageAction.newest([message(ada), huddle], writtenBy: ada.id)?.id, "m1")
    XCTAssertNil(MessageAction.newest([huddle], writtenBy: grace.id))
  }

  // MARK: - Outbox

  func testQueuedMessagesGoOnceOpenOrShowAsNotSent() {
    var timeline = Timeline()
    let pending = message(ada)
    timeline.send(pending)
    timeline.queue(pending.clientMessageId)
    XCTAssertEqual(timeline.sending, [])
    XCTAssertEqual(timeline.takeQueued().map(\.id), ["m1"])
    XCTAssertEqual(timeline.sending, ["c1"])
    timeline.queue(pending.clientMessageId)
    XCTAssertTrue(timeline.giveUpQueued())
    XCTAssertTrue(timeline.isFailed("c1"))
    guard case let .event(_, _, text, _)? = timeline.events.last else { return XCTFail("no notice") }
    XCTAssertEqual(text, EmberText.notConnectedNotSent)
  }

  func testUploadedReplacesItsCard() {
    var timeline = Timeline()
    var card = message(ada)
    card.body = ""
    timeline.send(card)
    var posted = card
    posted.id = "m9"
    timeline.uploaded(posted)
    XCTAssertTrue(timeline.pending.isEmpty)
    XCTAssertEqual(timeline.messages.map(\.id), ["m9"])
  }

  func testEmojiCatalog() {
    XCTAssertEqual(EmojiCatalog.groups.map(\.name), [
      "Smileys & emotion", "People & body", "Animals & nature", "Food & drink", "Travel & places", "Activities", "Objects", "Symbols", "Flags",
    ])
    XCTAssertTrue(EmojiCatalog.search("grinning").contains { $0.glyph == "\u{1F600}" })
    let wave = EmojiCatalog.search("waving hand").first { $0.toned }
    XCTAssertEqual(wave?.glyph(in: .dark), "\u{1F44B}\u{1F3FF}")
    // Sequences, keycaps and flags, and Emojibase's keywords, as the web panel has them.
    let all = EmojiCatalog.groups.flatMap(\.emoji).map(\.glyph)
    XCTAssertTrue(all.contains("\u{2764}\u{FE0F}\u{200D}\u{1F525}"))
    XCTAssertTrue(all.contains("1\u{FE0F}\u{20E3}"))
    XCTAssertEqual(EmojiCatalog.groups.last?.emoji.contains { $0.glyph == "\u{1F1EB}\u{1F1F7}" }, true)
    // Keywords find what labels don't, after what labels do, as frimousse ranks them.
    let lol = EmojiCatalog.search("lol").map(\.glyph)
    XCTAssertEqual(lol.first, "\u{1F36D}")
    XCTAssertTrue(lol.contains("\u{1F602}"))
    // A label match outranks keyword matches.
    XCTAssertEqual(EmojiCatalog.search("heart on fire").first?.glyph, "\u{2764}\u{FE0F}\u{200D}\u{1F525}")
  }

  // MARK: - IRC Classic's /edit and /react

  func testMarkdownWritesBackTheSameMarkup() throws {
    for html in [
      "<p>Hi <strong>all</strong><br>bye</p>",
      "<h1>T</h1><ul><li>a</li><li>b</li></ul><ol><li>c</li><li>d</li></ol>",
      "<blockquote>q<br>r</blockquote><p>after</p>",
      "<pre data-language=\"ruby\">x = 1\ny = 2</pre><p>then <code>z</code> and <s>gone</s> <em>it</em></p><hr>",
      "<p>Hi \(mention)!</p>",
    ] {
      let document = try ComposerDocument(html: html, name: { _ in "Grace" })
      let text = try XCTUnwrap(document.markdown(), html)
      XCTAssertEqual(ComposerDocument(markdown: text, mentioning: [grace]).html, html, text)
    }
    XCTAssertEqual(try ComposerDocument(html: "<p>Hi \(mention)</p>", name: { _ in "Grace" }).markdown(), "Hi @Grace")
    // A link that is its own address is written as the address, which Ember links.
    XCTAssertEqual(try ComposerDocument(html: "<p>see <a href=\"https://x.test/a\">https://x.test/a</a></p>", name: { _ in "" }).markdown(), "see https://x.test/a")
    // What the line can't write the same comes back nil, so /edit doesn't lose it.
    for html in ["<p><u>under</u></p>", "<p><a href=\"https://x.test\">named</a></p>", "<p>2 * 3 * 4 is *not* italic</p>"] {
      XCTAssertNil(try ComposerDocument(html: html, name: { _ in "" }).markdown(), html)
    }
  }

  func testReactTakesTheRestOfTheLine() {
    XCTAssertEqual(InputCommand.parse("/react \u{1F44D}"), .react("\u{1F44D}", nil))
    XCTAssertEqual(InputCommand.parse("/react ship it 3"), .react("ship it", 3))
    XCTAssertEqual(InputCommand.parse("/react well done"), .react("well done", nil))
    XCTAssertEqual(InputCommand.parse("/react 42"), .react("42", nil))
    XCTAssertEqual(InputCommand.parse("/react this is far too long a boost"), .unknown(EmberText.boostTooLong))
  }

  func testThreadRepliesAskedAboutAfterAReconnect() {
    var thread = ThreadTimeline(parentId: "p1")
    var sent = message(ada)
    sent.parentId = "p1"
    var lost = sent
    lost.clientMessageId = "c2"
    lost.id = "c2"
    thread.send(sent)
    thread.send(lost)
    XCTAssertTrue(thread.apply(.messageChecked(stored: ["c1"], missing: ["c2"])))
    XCTAssertNil(thread.pending["c1"])
    XCTAssertTrue(thread.isFailed("c2"))
    XCTAssertFalse(thread.apply(.messageChecked(stored: ["x"], missing: ["y"])))
  }
}
