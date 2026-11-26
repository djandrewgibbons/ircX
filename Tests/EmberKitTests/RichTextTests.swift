@testable import EmberKit
import XCTest

/** Showing a message's body as packages/richtext does: autolink.test.ts, display.test.ts and emoji.test.ts. */
final class RichTextTests: XCTestCase {
  func anchor(_ href: String, _ text: String? = nil) -> String { #"<a target="_blank" href="\#(href)">\#(text ?? href)</a>"# }

  func testFindsLinkableAddresses() {
    let linkable = ["See https://example.com/a.", "www.example.com", "SSH://host", "xmpp://ada@example.com", "Write to ada@example.com.", "o'brien+ember@example.co.uk"]
    let unlinkable = ["no link", "http: and www.", "https:// alone", "javascript://alert(1)", "gopher+evil://x", "@ the cliffs, ada@ them", "ada@example"]
    for text in linkable { XCTAssertTrue(Autolink.hasLinkable(text), text) }
    for text in unlinkable { XCTAssertFalse(Autolink.hasLinkable(text), text) }
    for text in linkable + unlinkable { XCTAssertEqual(Autolink.autoLink("<p>\(text)</p>").contains("<a "), Autolink.hasLinkable(text), text) }
    XCTAssertEqual(
      Autolink.linkedUrls(#"Ours: https://example.com.au/logo.png, www.example.com/forum! (https://en.wikipedia.org/wiki/Fire_(element)) https://example.com/"x""#),
      ["https://example.com.au/logo.png", "http://www.example.com/forum", "https://en.wikipedia.org/wiki/Fire_(element)", "https://example.com/"])
  }

  func testLinksAddresses() {
    XCTAssertEqual(
      Autolink.autoLink("<p>https://example.com and www.example.com</p>"),
      "<p>\(anchor("https://example.com")) and \(anchor("http://www.example.com", "www.example.com"))</p>")
    XCTAssertEqual(Autolink.autoLink("<p>SSH://host and ftp://files.example.com/a.txt</p>"), "<p>\(anchor("SSH://host")) and \(anchor("ftp://files.example.com/a.txt"))</p>")
    XCTAssertEqual(Autolink.autoLink("<p>Write to ada@example.com.</p>"), "<p>Write to \(anchor("mailto:ada@example.com", "ada@example.com")).</p>")
    XCTAssertEqual(Autolink.autoLink("<p>o'brien+ember@example.co.uk</p>"), "<p>\(anchor("mailto:o%27brien%2Bember@example.co.uk", "o&#39;brien+ember@example.co.uk"))</p>")
    XCTAssertEqual(
      Autolink.autoLink("<p>See https://example.com/a, then https://example.com/b!</p>"),
      "<p>See \(anchor("https://example.com/a")), then \(anchor("https://example.com/b"))!</p>")
    XCTAssertEqual(Autolink.autoLink("<p>(https://en.wikipedia.org/wiki/Fire_(element))</p>"), "<p>(\(anchor("https://en.wikipedia.org/wiki/Fire_(element)")))</p>")
    XCTAssertEqual(Autolink.autoLink("<p>https://example.com/?q=1&amp;r=2;</p>"), "<p>\(anchor("https://example.com/?q=1&amp;r=2;"))</p>")
    XCTAssertEqual(Autolink.autoLink(#"<p><a href="https://example.com">https://example.com</a></p>"#), #"<p><a href="https://example.com">https://example.com</a></p>"#)
    XCTAssertEqual(Autolink.autoLink("<pre>curl https://example.com</pre>"), "<pre>curl \(anchor("https://example.com"))</pre>")
    XCTAssertEqual(Autolink.autoLink("<p>javascript://alert(1) and gopher+evil://x</p>"), "<p>javascript://alert(1) and gopher+evil://x</p>")
    XCTAssertEqual(Autolink.autoLink(#"<p>https://example.com/"onmouseover="alert(1)</p>"#), #"<p>\#(anchor("https://example.com/"))"onmouseover="alert(1)</p>"#)
    XCTAssertEqual(Autolink.autoLink("<p>https://example.com/&lt;script&gt;</p>"), "<p>\(anchor("https://example.com/&lt;script"))&gt;</p>")
  }

  /** rails_autolink's `auto_linked?`, by its regular expressions, against `TagIndex` at every position. */
  func testTagIndexAgreesWithRegularExpressions() throws {
    let leftTag = try NSRegularExpression(pattern: #"<[^>]+(?=\n|(?![\s\S]))"#)
    let rightTag = try NSRegularExpression(pattern: #"(?:(?<![\s\S])|(?<=\n))[^>]*>"#)
    let anchorClose = try NSRegularExpression(pattern: "</a>", options: .caseInsensitive)
    func byRegex(_ left: String, _ right: String) -> Bool {
      let l = left as NSString
      let r = right as NSString
      if leftTag.firstMatch(in: left, range: NSRange(location: 0, length: l.length)) != nil, rightTag.firstMatch(in: right, range: NSRange(location: 0, length: r.length)) != nil {
        return true
      }
      let units = Array(left.utf16)
      for i in stride(from: units.count - 1, through: 0, by: -1) where units[i] == UInt16(UInt8(ascii: "<")) {
        if let end = Autolink.TagIndex.openAnchor(units, at: i) {
          let rest = l.substring(from: end)
          return anchorClose.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) == nil
        }
      }
      return false
    }
    for text in ["<p>www.a.com</p><p>b</p>", "<p title=\"a\nb\">x</p> y <p>z</p>", "<a href=\"x\">in <b>link</b></a> out <A\nhref=\"y\">z</A> <a>q</a>", "x<\ny>z<\u{E9}>", "<", "<a>", ""] {
      let index = Autolink.TagIndex(text)
      let ns = text as NSString
      for start in 0...ns.length {
        for end in start...ns.length {
          XCTAssertEqual(index.autoLinked(start, end), byRegex(ns.substring(to: start), ns.substring(from: end)), "\(text) at \(start)..\(end)")
        }
      }
    }
  }

  func display(_ html: String, _ plain: String = "") throws -> [DisplayNode] { try Display.body(html, plainText: plain, host: "") }

  func testShowsOnlyWhatAMessageCan() throws {
    XCTAssertEqual(try display(#"<p class="fixed" style="color: red" onclick="alert(1)" id="x">Hi</p>"#), [.element(name: "p", attrs: [:], children: [.text("Hi")])])
    XCTAssertEqual(try display("<script>alert(1)</script><style>p {}</style>"), [.text("alert(1)p {}")])
    XCTAssertEqual(try display(#"<img src="x" onerror="alert(1)"><iframe src="https://example.com"></iframe>"#), [])
    XCTAssertEqual(try display(#"<a href="javascript:alert(1)" target="_top">x</a>"#), [.element(name: "a", attrs: [:], children: [.text("x")])])
    XCTAssertEqual(try display(#"<svg><a href="https://example.com">x</a></svg><math><mi>y</mi></math>"#), [])
    XCTAssertEqual(try display(#"<pre data-language="ruby" data-turbo="true">puts 1</pre>"#), [.element(name: "pre", attrs: ["data-language": "ruby"], children: [.text("puts 1")])])
    XCTAssertEqual(try display("<p>a<!-- hidden -->b</p>"), [.element(name: "p", attrs: [:], children: [.text("ab")])])
  }

  func testShowsMentions() throws {
    let mention = #"content-type="application/vnd.campfire.mention""#
    XCTAssertEqual(
      try display(#"<p>Hi <action-text-attachment \#(mention) sgid="0123456789abcdef"></action-text-attachment></p>"#),
      [.element(name: "p", attrs: [:], children: [.text("Hi "), .mention("0123456789abcdef")])])
    XCTAssertEqual(try display(#"<action-text-attachment \#(mention) sgid="gid://campfire/User/1"></action-text-attachment>"#), [.text("\u{2612}")])
    XCTAssertEqual(try display(#"<action-text-attachment content-type="text/html" sgid="0123456789abcdef">inside</action-text-attachment>"#), [.text("inside")])
  }

  func testCantShowMarkupPastTheParsersLimits() {
    XCTAssertThrowsError(try display(String(repeating: "<b>", count: HTML.maxTreeDepth + 1)))
  }

  func testLinksAddressesInText() throws {
    XCTAssertEqual(try display("<p>See https://example.com/a?b=1&amp;c=2.</p>"), [
      .element(name: "p", attrs: [:], children: [
        .text("See "), .element(name: "a", attrs: ["href": "https://example.com/a?b=1&c=2"], children: [.text("https://example.com/a?b=1&c=2")]), .text("."),
      ]),
    ])
    XCTAssertEqual(
      try display("<p>feed://example.com/rss</p>"),
      [.element(name: "p", attrs: [:], children: [.element(name: "a", attrs: ["href": "feed://example.com/rss"], children: [.text("feed://example.com/rss")])])])
    XCTAssertEqual(try display(#"<p><a href="feed://example.com/rss">News</a></p>"#), [.element(name: "p", attrs: [:], children: [.element(name: "a", attrs: [:], children: [.text("News")])])])
  }

  let preview = #"<action-text-attachment content-type="application/vnd.actiontext.opengraph-embed" content="&lt;actiontext-opengraph-embed&gt;&lt;div class=&quot;og-embed__title&quot;&gt;&lt;a href=&quot;https://example.com/a&quot;&gt;A page&lt;/a&gt;&lt;/div&gt;&lt;div class=&quot;og-embed__description&quot;&gt;About it&lt;/div&gt;&lt;div class=&quot;og-embed__image&quot;&gt;&lt;img src=&quot;https://img.example.com/a.png&quot;&gt;&lt;/div&gt;&lt;/actiontext-opengraph-embed&gt;"></action-text-attachment>"#

  func testShowsLinkPreviewsAndHidesASoloLink() throws {
    let shown = try display("<p>https://example.com/a</p>\(preview)", "https://example.com/a")
    XCTAssertEqual(shown, [.preview(DisplayPreview(title: [.text("A page")], href: "https://example.com/a", description: [.text("About it")], image: "https://img.example.com/a.png", avatar: false))])
    let withText = try display("<p>Look: https://example.com/a</p>\(preview)", "Look: https://example.com/a")
    XCTAssertEqual(withText.count, 2)
    // A preview can't aim at the instance itself.
    let own = try Display.body(preview, plainText: "", host: "example.com")
    guard case let .preview(ownPreview) = own.first else { return XCTFail("No preview") }
    XCTAssertNil(ownPreview.href)
    XCTAssertEqual(ownPreview.image, "https://img.example.com/a.png")
  }

  func testCardAddresses() {
    XCTAssertEqual(Display.cardAddress("https://example.com/x", host: "chat.example.org"), "https://example.com/x")
    XCTAssertNil(Display.cardAddress("https://chat.example.org/x", host: "chat.example.org"))
    XCTAssertNil(Display.cardAddress("javascript:alert(1)", host: "chat.example.org"))
    XCTAssertNil(Display.cardAddress("https://10.0.0.1/x", host: "chat.example.org"))
    XCTAssertNil(Display.cardAddress("https://localhost/x", host: "chat.example.org"))
  }

  func testAllEmoji() {
    for text in ["\u{1F600}", "\u{1F44D}\u{1F3FD}", "\u{1F1FA}\u{1F1F8}", "\u{2764}\u{FE0F}", "\u{A9}\u{2122}"] { XCTAssertTrue(Display.isAllEmoji(text), text) }
    for text in ["", "a\u{1F600}", "1\u{FE0F}\u{20E3}", "\u{1F468}\u{200D}\u{1F469}", "\u{1F600} "] { XCTAssertFalse(Display.isAllEmoji(text), text) }
  }

  func testCodeFoldsAndHighlights() {
    XCTAssertEqual(Display.codeOf([.text("a"), .element(name: "br", attrs: [:], children: []), .text("b")]), "a\nb")
    XCTAssertNil(Display.codeOf([.element(name: "a", attrs: ["href": "x"], children: [.text("x")])]))
    XCTAssertEqual(Highlight.language(named: "js"), "javascript")
    XCTAssertEqual(Highlight.language(named: "html"), "xml")
    XCTAssertNil(Highlight.language(named: "cobol"))
    let tokens = Highlight.highlight("def hi(name):\n  # greet\n  return \"hi \" + name", language: "python")
    XCTAssertTrue(tokens.contains(HighlightToken("def", .keyword)))
    XCTAssertTrue(tokens.contains(HighlightToken("# greet", .comment)))
    XCTAssertTrue(tokens.contains(HighlightToken("\"hi \"", .string)))
    XCTAssertEqual(tokens.map(\.text).joined(), "def hi(name):\n  # greet\n  return \"hi \" + name")
    XCTAssertEqual(Highlight.detect("<div class=\"a\"><p>x</p></div>"), "xml")
    XCTAssertEqual(Highlight.detect("{\n  \"a\": 1,\n  \"b\": [true, null]\n}"), "json")
    XCTAssertEqual(Highlight.detect("--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new"), "diff")
  }

  func testCardTextFolds() throws {
    XCTAssertFalse(Display.isLong(try display("<p>short</p>")))
    XCTAssertTrue(Display.isLong(try display("<p>" + String(repeating: "a", count: 701) + "</p>")))
    XCTAssertTrue(Display.isLong(try display("<p>1</p><p>2</p><p>3</p><p>4</p><p>5</p><p>6</p><p>7</p>")))
  }

  func file(_ type: String, _ name: String, size: Int = 1000, width: Int? = nil, height: Int? = nil, preview: String? = nil) -> StoredFile {
    StoredFile(id: "f", name: name, contentType: type, byteSize: size, width: width, height: height, url: "/u", downloadUrl: "/d", previewUrl: preview)
  }

  func testHowAFileShows() {
    XCTAssertEqual(AttachmentShown(file("image/svg+xml", "a.svg")), .svg)
    XCTAssertEqual(AttachmentShown(file("image/svg+xml", "a.svg", size: 6_000_000)), .card)
    XCTAssertEqual(AttachmentShown(file("video/mp4", "a.mp4")), .video)
    XCTAssertEqual(AttachmentShown(file("text/plain", "notes.txt")), .text(language: nil))
    XCTAssertEqual(AttachmentShown(file("application/json", "a.json")), .text(language: "json"))
    XCTAssertEqual(AttachmentShown(file("application/ld+json", "a.rb")), .text(language: "ruby"))
    XCTAssertEqual(AttachmentShown(file("text/plain", "big.txt", size: 70_000)), .card)
    XCTAssertEqual(AttachmentShown(file("image/png", "a.png", width: 10, height: 10)), .picture(path: "/u"))
    XCTAssertEqual(AttachmentShown(file("image/png", "a.png")), .card)
    XCTAssertEqual(AttachmentShown(file("image/heic", "a.heic", width: 10, height: 10, preview: "/p")), .picture(path: "/p"))
    XCTAssertEqual(AttachmentShown(file("image/heic", "a.heic", width: 10, height: 10)), .card)
    XCTAssertEqual(AttachmentShown(file("application/pdf", "a.pdf")), .card)
    XCTAssertEqual(TextPreview.shown(Data("a\r\nb\n".utf8))?.shown, "a\nb")
    XCTAssertNil(TextPreview.shown(Data("  \n".utf8)))
    XCTAssertNil(TextPreview.shown(Data([0x61, 0x00])))
  }

  func testHuddleWords() {
    XCTAssertEqual(MessageWords.wereInTheHuddle(["Sam Smith", "Priya"], you: false), "Sam and Priya were in the huddle")
    XCTAssertEqual(MessageWords.wereInTheHuddle(["Sam"], you: true), "Sam and you were in the huddle")
    XCTAssertEqual(MessageWords.wereInTheHuddle([], you: true), "Only you were in the huddle")
    XCTAssertEqual(MessageWords.wereInTheHuddle(["Sam"], you: false), "Sam was in the huddle")
    XCTAssertEqual(MessageWords.wereInTheHuddle(["A", "B", "C", "D", "E"], you: false), "A, B, C, and 2 others were in the huddle")
    XCTAssertEqual(MessageWords.inItsHuddle(["Sam"], count: 1, you: false), "Sam is in the huddle")
    XCTAssertEqual(MessageWords.inItsHuddle(["Sam"], count: 1, you: true), "Sam and you are in the huddle")
    XCTAssertEqual(MessageWords.inItsHuddle([], count: 0, you: true), "Just you in the huddle")
    let start = Date(timeIntervalSince1970: 0)
    XCTAssertEqual(MessageWords.huddleLasted(from: start, to: start.addingTimeInterval(30)), "less than a minute")
    XCTAssertEqual(MessageWords.huddleLasted(from: start, to: start.addingTimeInterval(24 * 60)), "24 minutes")
    XCTAssertEqual(MessageWords.huddleLasted(from: start, to: start.addingTimeInterval(65 * 60)), "1 hour and 5 minutes")
    XCTAssertEqual(MessageWords.huddleLasted(from: start, to: start.addingTimeInterval(120 * 60)), "2 hours")
    XCTAssertEqual(MessageWords.replies(1), "1 reply")
    XCTAssertEqual(MessageWords.replies(3), "3 replies")
  }

  func testErrorFrameRewriteAndClicks() throws {
    let frame = try ServerFrame.decode(#"{"type":"error","message":"This community doesn't allow one of these words.","clientMessageId":"c1","failed":"message.create","rewrite":true}"#)
    guard case let .error(error) = frame else { return XCTFail("Not an error") }
    XCTAssertTrue(error.rewrite)
    var timeline = Timeline()
    let me = User(id: "ada0000000000001", name: "Ada")
    timeline.apply(.welcome(you: me, present: [], seq: 1, page: TimelinePage(messages: [], hasMore: false, hasNewer: false, around: nil)))
    timeline.send(Message(id: "c1", clientMessageId: "c1", roomId: "r", creator: me, body: "<p>x</p>", plainText: "x", createdAt: "2026-11-19T00:00:00.000Z", updatedAt: "2026-11-19T00:00:00.000Z"))
    timeline.apply(frame)
    XCTAssertEqual(timeline.rewrites["c1"], "This community doesn't allow one of these words.")
    timeline.giveBack("c1", taken: true)
    XCTAssertNil(timeline.pending["c1"])
    let clickError = try ServerFrame.decode(#"{"type":"error","message":"That button is no longer there","clickId":"k","failed":"card.click"}"#)
    XCTAssertEqual(clickError, .error(RoomError(message: Cards.buttonGone, clickId: "k", failed: "card.click")))
  }
}
