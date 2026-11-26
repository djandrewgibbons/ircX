import Foundation
import OSLog

// What the composers write: the web editor's markup (Lexxy, as `packages/richtext/src/sanitize.ts`
// keeps it), built from a document of lines, which the Suite editor edits and IRC Classic's
// Markdown-style input line makes.

let composerLogger = Logger(subsystem: "ai.dxnd.ircX", category: "composer")

/** A mark on a run of text, as the formatting row's inline buttons set them. */
public enum ComposerMark: String, Sendable, Hashable, CaseIterable {
  case bold, italic, underline, strike, code

  var tag: String {
    switch self {
    case .bold: "strong"
    case .italic: "em"
    case .underline: "u"
    case .strike: "s"
    case .code: "code"
    }
  }
}

/** A run of a line's text with the same marks, link or mention. A mention's text is `@` and the name it shows. */
public struct ComposerRun: Sendable, Hashable {
  public var text: String
  public var marks: Set<ComposerMark>
  public var link: String?
  public var mention: UserID?

  public init(_ text: String, marks: Set<ComposerMark> = [], link: String? = nil, mention: UserID? = nil) {
    self.text = text
    self.marks = marks
    self.link = link
    self.mention = mention
  }

  func sameLook(_ other: ComposerRun) -> Bool { marks == other.marks && link == other.link && mention == nil && other.mention == nil }
}

/** What kind of block a line belongs to; consecutive lines of one kind make one block. */
public enum ComposerBlock: Sendable, Hashable {
  case paragraph
  case heading(Int)
  case quote
  case bullet
  case ordered
  case code(language: String?)
  /** A quote's attribution, as Quote writes it. */
  case cite
  case rule
  /** Markup kept as it is, such as a link's preview: it can be taken out, not edited. */
  case attachment(html: String, label: String)

  /** Whether it's a code block, where text formatting doesn't apply (`NOT_IN_CODE_BLOCKS`). */
  public var isCode: Bool { if case .code = self { true } else { false } }
}

public struct ComposerLine: Sendable, Hashable {
  public var block: ComposerBlock
  public var runs: [ComposerRun]

  public init(_ block: ComposerBlock = .paragraph, _ runs: [ComposerRun] = []) {
    self.block = block
    self.runs = runs
  }

  public var text: String { runs.map(\.text).joined() }
}

/**
 * A message as it's being written: lines, each in a block, each a list of runs. `html` writes the
 * markup the web editor would; `init(html:name:)` reads a message's body back to edit it.
 */
public struct ComposerDocument: Sendable, Hashable {
  public var lines: [ComposerLine]

  public init(lines: [ComposerLine] = []) {
    self.lines = lines
  }

  /** A document of plain text, a paragraph line per line. */
  public init(plain text: String) {
    lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { ComposerLine(.paragraph, $0.isEmpty ? [] : [ComposerRun($0)]) }
  }

  /** `blank`: nothing but whitespace, and no mention, rule or attachment. */
  public var isBlank: Bool {
    lines.allSatisfy { line in
      switch line.block {
      case .rule, .attachment: return false
      default: return line.runs.allSatisfy { $0.mention == nil && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      }
    }
  }

  /** The document without the blank lines before and after what's written. */
  public func trimmed() -> ComposerDocument {
    func blank(_ line: ComposerLine) -> Bool {
      if case .paragraph = line.block { return line.runs.allSatisfy { $0.mention == nil && $0.text.trimmingCharacters(in: .whitespaces).isEmpty } }
      return false
    }
    var lines = lines
    while let first = lines.first, blank(first) { lines.removeFirst() }
    while let last = lines.last, blank(last) { lines.removeLast() }
    return ComposerDocument(lines: lines)
  }

  /** The text as Ember's plain text reads it, near enough to measure: quotes in curly quotes, list items marked. */
  public var plainText: String {
    var out: [String] = []
    var number = 0
    for line in lines {
      let text = line.text
      switch line.block {
      case .bullet: out.append("• " + text)
      case .ordered:
        number += 1
        out.append("\(number). " + text)
      case .quote: out.append("“\(text)”")
      case .rule: out.append("")
      case let .attachment(_, label): out.append(label)
      default: out.append(text)
      }
      if line.block != .ordered { number = 0 }
    }
    return out.joined(separator: "\n")
  }

  /** Whether it's past what a message can be (`isTooLong`): its plain text past 40,000 UTF-16 units or its markup past 100,000. */
  public var isTooLong: Bool {
    EmberRules.isMessageTooLong(plainText) || html.utf16.count > EmberLimits.maxMessageHTMLLength
  }

  // MARK: - Writing markup

  /** The markup the web editor writes for the document. */
  public var html: String {
    var out = ""
    var index = 0
    while index < lines.count {
      let block = lines[index].block
      var end = index + 1
      if Self.groups(block) {
        while end < lines.count, lines[end].block == block { end += 1 }
      }
      let group = lines[index..<end]
      switch block {
      case .paragraph: out += "<p>" + Self.joinedLines(group) + "</p>"
      case let .heading(level):
        let n = min(max(level, 1), 3)
        out += "<h\(n)>\(Self.inline(lines[index].runs))</h\(n)>"
      case .quote: out += "<blockquote>" + Self.joinedLines(group) + "</blockquote>"
      case .cite: out += "<cite>" + Self.joinedLines(group) + "</cite>"
      case .bullet: out += "<ul>" + group.map { "<li>\(Self.inline($0.runs))</li>" }.joined() + "</ul>"
      case .ordered: out += "<ol>" + group.map { "<li>\(Self.inline($0.runs))</li>" }.joined() + "</ol>"
      case let .code(language):
        var open = "<pre"
        if let language { open += " data-language=\"\(HTML.escapeAttribute(language, true))\"" }
        out += open + ">" + group.map { HTML.escapeText($0.text) }.joined(separator: "\n") + "</pre>"
      case .rule: out += "<hr>"
      case let .attachment(html, _): out += html
      }
      index = end
    }
    return out
  }

  private static func groups(_ block: ComposerBlock) -> Bool {
    switch block {
    case .paragraph, .quote, .cite, .bullet, .ordered, .code: true
    default: false
    }
  }

  /** Lines broken by `<br>`; an empty block holds one `<br>`, as the editor's empty paragraph does. */
  private static func joinedLines(_ lines: ArraySlice<ComposerLine>) -> String {
    let inner = lines.map { inline($0.runs) }.joined(separator: "<br>")
    return inner.isEmpty ? "<br>" : inner
  }

  /** A line's runs as markup, neighbours that look the same merged first. */
  static func inline(_ runs: [ComposerRun]) -> String {
    var merged: [ComposerRun] = []
    for run in runs where !run.text.isEmpty || run.mention != nil {
      if let last = merged.last, last.sameLook(run) {
        merged[merged.count - 1].text += run.text
      } else {
        merged.append(run)
      }
    }
    return merged.map { run in
      if let mention = run.mention {
        return "<action-text-attachment sgid=\"\(HTML.escapeAttribute(mention, true))\" content-type=\"\(Display.mentionContentType)\"></action-text-attachment>"
      }
      var html = HTML.escapeText(run.text)
      for mark in ComposerMark.allCases.reversed() where run.marks.contains(mark) { html = "<\(mark.tag)>\(html)</\(mark.tag)>" }
      if let link = run.link { html = "<a href=\"\(HTML.escapeAttribute(link, true))\">\(html)</a>" }
      return html
    }.joined()
  }

  // MARK: - Reading markup

  /**
   * A message's body as a document to edit (`editableBody`): mentions keep their person, with the name
   * `name` gives, link previews stay as they are, and blocks the editor can't make read as the nearest it can.
   */
  public init(html: String, name: (UserID) -> String) throws {
    let nodes = try HTML.parse(html)
    lines = withoutActuallyEscaping(name) { name in
      var reader = Reader(name: name)
      reader.blocks(nodes, as: .paragraph)
      reader.endLine()
      return reader.lines
    }
  }

  private struct Reader {
    let name: (UserID) -> String
    var lines: [ComposerLine] = []
    var current: ComposerLine?

    mutating func endLine() {
      if let current { lines.append(current) }
      current = nil
    }

    mutating func add(_ run: ComposerRun, in block: ComposerBlock) {
      if current == nil { current = ComposerLine(block) }
      current?.runs.append(run)
    }

    mutating func blocks(_ nodes: [HTMLNode], as block: ComposerBlock) {
      for node in nodes {
        switch node {
        case let .text(text):
          if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, current == nil { continue }
          add(ComposerRun(text), in: block)
        case .comment: continue
        case let .element(element):
          switch element.name {
          case "p", "div":
            endLine()
            let before = lines.count
            current = ComposerLine(block)
            inline(element.children, block: block, marks: [], link: nil)
            // A `<br>` that ends a paragraph doesn't start a line, as browsers lay it out.
            if current?.runs.isEmpty == true, lines.count > before { current = nil }
            endLine()
          case "h1", "h2", "h3", "h4", "h5", "h6":
            endLine()
            let level = min(Int(element.name.dropFirst()) ?? 1, 3)
            current = ComposerLine(.heading(level))
            inline(element.children, block: .heading(level), marks: [], link: nil)
            endLine()
          case "blockquote":
            endLine()
            blocks(element.children, as: .quote)
            endLine()
          case "cite":
            endLine()
            current = ComposerLine(.cite)
            inline(element.children, block: .cite, marks: [], link: nil)
            endLine()
          case "ul", "ol":
            endLine()
            let kind: ComposerBlock = element.name == "ul" ? .bullet : .ordered
            for child in element.children {
              guard case let .element(item) = child else { continue }
              if item.name == "li" {
                let nested = item.children.filter { $0.element.map { ["ul", "ol"].contains($0.name) } == true }
                current = ComposerLine(kind)
                inline(item.children.filter { !nested.contains($0) }, block: kind, marks: [], link: nil)
                endLine()
                blocks(nested, as: kind)
              } else {
                blocks([child], as: kind)
              }
            }
          case "pre":
            endLine()
            let language = element.attr("data-language")
            let text = element.children.map(Self.codeText).joined()
            for line in text.components(separatedBy: "\n") {
              lines.append(ComposerLine(.code(language: language), line.isEmpty ? [] : [ComposerRun(line)]))
            }
          case "hr":
            endLine()
            lines.append(ComposerLine(.rule))
          case "br":
            if current == nil { current = ComposerLine(block) }
            endLine()
          case Display.attachmentTag where element.attr("content-type") == Display.mentionContentType:
            mention(element, block: block, marks: [])
          case Display.attachmentTag:
            endLine()
            lines.append(ComposerLine(.attachment(html: HTML.serialize([node]), label: Self.label(element))))
          default:
            if Self.inlineTags.contains(element.name) {
              inline([node], block: block, marks: [], link: nil)
            } else {
              endLine()
              current = ComposerLine(block)
              inline(element.children, block: block, marks: [], link: nil)
              endLine()
            }
          }
        }
      }
    }

    static let inlineTags: Set<String> = [
      "a", "b", "strong", "i", "em", "u", "s", "del", "strike", "code", "span", "mark", "small", "sub", "sup", "kbd", "tt", "var", "samp", "abbr", "time",
      "ins", "big", "dfn", "acronym",
    ]

    static func codeText(_ node: HTMLNode) -> String {
      switch node {
      case let .text(text): text
      case let .element(element): element.name == "br" ? "\n" : element.children.map(codeText).joined()
      case .comment: ""
      }
    }

    /** What an attachment the editor keeps as it is says in the editor: a preview's title and description. */
    static func label(_ element: HTMLElement) -> String {
      guard let content = element.attr("content") else { return "Link preview" }
      let nodes: [HTMLNode]
      do {
        nodes = try HTML.parse(content)
      } catch {
        composerLogger.error("A preview in a message being edited didn't read: \(error.localizedDescription, privacy: .public)")
        return "Link preview"
      }
      let text = nodes.map(\.textContent).joined().trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? "Link preview" : String(text.prefix(120))
    }

    mutating func mention(_ element: HTMLElement, block: ComposerBlock, marks: Set<ComposerMark>) {
      guard let sgid = element.attr("sgid"), let id = Display.userId(fromSgid: sgid) else { return }
      add(ComposerRun("@" + name(id), marks: marks, mention: id), in: block)
    }

    mutating func inline(_ nodes: [HTMLNode], block: ComposerBlock, marks: Set<ComposerMark>, link: String?) {
      for node in nodes {
        switch node {
        case let .text(text):
          add(ComposerRun(text, marks: marks, link: link), in: block)
        case .comment: continue
        case let .element(element):
          var marks = marks
          var link = link
          switch element.name {
          case "br":
            if current == nil { current = ComposerLine(block) }
            endLine()
            current = ComposerLine(block)
            continue
          case "b", "strong": marks.insert(.bold)
          case "i", "em": marks.insert(.italic)
          case "u": marks.insert(.underline)
          case "s", "del", "strike": marks.insert(.strike)
          case "code": marks.insert(.code)
          case "a": link = element.attr("href")
          case Display.attachmentTag where element.attr("content-type") == Display.mentionContentType:
            mention(element, block: block, marks: marks)
            continue
          case Display.attachmentTag, "p", "div", "ul", "ol", "pre", "blockquote", "hr", "h1", "h2", "h3", "h4", "h5", "h6", "cite":
            endLine()
            blocks([node], as: block)
            continue
          default: break
          }
          inline(element.children, block: block, marks: marks, link: link)
        }
      }
    }
  }

  // MARK: - Markdown-style input

  /**
   * The document the Markdown-style shortcuts the web editor takes as you type make of `text`: ``` fences
   * a code block, `#`, `##` and `###` start headings, `> ` quotes a line, `- `, `* ` and `1. ` make lists,
   * `---` a divider; `**bold**`, `__bold__`, `*italic*`, `_italic_`, `~~strike~~` and `` `code` `` mark
   * text. `@Name` mentions whichever of `people` it names, longest names first, and so does IRC's `Name:`
   * at the start.
   */
  public init(markdown text: String, mentioning people: [User] = []) {
    let byLength = people.filter { !$0.name.isEmpty }.sorted { $0.name.count > $1.name.count }
    var text = text.replacingOccurrences(of: "\r\n", with: "\n")
    if let person = byLength.first(where: { text.lowercased().hasPrefix($0.name.lowercased() + ":") || text.lowercased().hasPrefix($0.name.lowercased() + ",") }) {
      text = "@" + person.name + text.dropFirst(person.name.count)
    }
    var lines: [ComposerLine] = []
    var inFence = false
    var language: String?
    for raw in text.components(separatedBy: "\n") {
      let trimmed = raw.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        if inFence {
          inFence = false
          continue
        }
        let named = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        inFence = true
        language = named.isEmpty ? nil : named
        continue
      }
      if inFence {
        lines.append(ComposerLine(.code(language: language), raw.isEmpty ? [] : [ComposerRun(raw)]))
        continue
      }
      let runs = { (rest: Substring) in Self.inlineMarkdown(String(rest), people: byLength) }
      if trimmed == "---" || trimmed == "***" || trimmed == "___" {
        lines.append(ComposerLine(.rule))
      } else if let match = raw.firstMatch(of: #/^(#{1,3}) (.*)$/#) {
        lines.append(ComposerLine(.heading(match.output.1.count), runs(match.output.2)))
      } else if let match = raw.firstMatch(of: #/^> ?(.*)$/#) {
        lines.append(ComposerLine(.quote, runs(match.output.1)))
      } else if let match = raw.firstMatch(of: #/^[-*+] (.*)$/#) {
        lines.append(ComposerLine(.bullet, runs(match.output.1)))
      } else if let match = raw.firstMatch(of: #/^\d+[.)] (.*)$/#) {
        lines.append(ComposerLine(.ordered, runs(match.output.1)))
      } else {
        lines.append(ComposerLine(.paragraph, runs(raw[...])))
      }
    }
    self.lines = lines
  }

  private static let delimiters: [(String, ComposerMark)] = [("**", .bold), ("__", .bold), ("~~", .strike), ("*", .italic), ("_", .italic)]

  static func inlineMarkdown(_ text: String, people: [User], marks: Set<ComposerMark> = []) -> [ComposerRun] {
    var runs: [ComposerRun] = []
    var plain = ""
    func flush() {
      if !plain.isEmpty { runs += mentions(in: plain, people: people, marks: marks) }
      plain = ""
    }
    var i = text.startIndex
    scanning: while i < text.endIndex {
      let rest = text[i...]
      // A web address is left as it is, underscores and all; Ember links it.
      if rest.hasPrefix("http://") || rest.hasPrefix("https://") || rest.hasPrefix("www."), i == text.startIndex || !isWord(text[text.index(before: i)]) {
        let end = rest.firstIndex(where: \.isWhitespace) ?? text.endIndex
        plain += text[i..<end]
        i = end
        continue
      }
      if text[i] == "`", let close = text[text.index(after: i)...].firstIndex(of: "`"), close > text.index(after: i) {
        flush()
        runs.append(ComposerRun(String(text[text.index(after: i)..<close]), marks: marks.union([.code])))
        i = text.index(after: close)
        continue
      }
      for (delimiter, mark) in delimiters where rest.hasPrefix(delimiter) {
        let start = text.index(i, offsetBy: delimiter.count)
        guard start < text.endIndex, !text[start].isWhitespace else { continue }
        // `_` within a word, as in snake_case, isn't a mark.
        let wordy = delimiter.first == "_"
        if wordy, i > text.startIndex, isWord(text[text.index(before: i)]) { continue }
        var search = start
        while search < text.endIndex, let range = text[search...].range(of: delimiter) {
          let before = text[text.index(before: range.lowerBound)]
          let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
          let doubled = delimiter.count == 1 && (after == delimiter.first || before == delimiter.first)
          if range.lowerBound > start, !before.isWhitespace, !doubled, !(wordy && after.map(isWord) == true) {
            flush()
            runs += inlineMarkdown(String(text[start..<range.lowerBound]), people: people, marks: marks.union([mark]))
            i = range.upperBound
            continue scanning
          }
          search = range.upperBound
        }
      }
      plain.append(text[i])
      i = text.index(after: i)
    }
    flush()
    return runs
  }

  private static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

  // MARK: - Writing Markdown-style text

  /**
   * The document as the Markdown-style text `init(markdown:mentioning:)` reads (IRC Classic's `/edit`):
   * nil where that text wouldn't read back to the same markup, as for an underline, a link named other
   * than its address, a cite or a preview, or text the shortcuts would read as marks. A link that is its
   * own address is written as the address, which Ember links as it shows the message.
   */
  public func markdown() -> String? {
    let unlinked = ComposerDocument(lines: lines.map { line in
      var line = line
      line.runs = line.runs.map { run in
        var run = run
        if let link = run.link, link == run.text || Autolink.linkedUrls(run.text) == [link] { run.link = nil }
        return run
      }
      return line
    })
    var out: [String] = []
    var number = 0
    var fence: String??
    for line in unlinked.lines {
      if case let .code(language) = line.block {
        if fence == nil || fence != .some(language) {
          if fence != nil { out.append("```") }
          out.append(language.map { "```" + $0 } ?? "```")
          fence = .some(language)
        }
        out.append(line.text)
        continue
      }
      if fence != nil {
        out.append("```")
        fence = nil
      }
      if case .ordered = line.block { number += 1 } else { number = 0 }
      guard let text = Self.markdownInline(line.runs) else { return nil }
      switch line.block {
      case .paragraph: out.append(text)
      case let .heading(level): out.append(String(repeating: "#", count: min(max(level, 1), 3)) + " " + text)
      case .quote: out.append("> " + text)
      case .bullet: out.append("- " + text)
      case .ordered: out.append("\(number). " + text)
      case .rule: out.append("---")
      case .cite, .attachment, .code: return nil
      }
    }
    if fence != nil { out.append("```") }
    let text = out.joined(separator: "\n")
    let people = lines.flatMap(\.runs).compactMap { run in run.mention.map { User(id: $0, name: String(run.text.dropFirst())) } }
    return ComposerDocument(markdown: text, mentioning: people).html == unlinked.html ? text : nil
  }

  /** A line's runs as Markdown-style marks; nil for an underline or a named link, which it has no way to write. */
  private static func markdownInline(_ runs: [ComposerRun]) -> String? {
    var merged: [ComposerRun] = []
    for run in runs where !run.text.isEmpty || run.mention != nil {
      if let last = merged.last, last.sameLook(run) { merged[merged.count - 1].text += run.text } else { merged.append(run) }
    }
    var out = ""
    for run in merged {
      if run.link != nil || run.marks.contains(.underline) { return nil }
      var text = run.text
      if run.marks.contains(.code) { text = "`" + text + "`" }
      if run.marks.contains(.strike) { text = "~~" + text + "~~" }
      if run.marks.contains(.italic) { text = "_" + text + "_" }
      if run.marks.contains(.bold) { text = "**" + text + "**" }
      out += text
    }
    return out
  }

  /** Plain text with each `@Name` of `people` (longest first) a mention, at a word's start only, so an email address isn't one. */
  static func mentions(in line: String, people: [User], marks: Set<ComposerMark>) -> [ComposerRun] {
    guard !people.isEmpty, line.contains("@") else { return [ComposerRun(line, marks: marks)] }
    var runs: [ComposerRun] = []
    var plain = ""
    var i = line.startIndex
    while i < line.endIndex {
      let c = line[i]
      if c == "@", i == line.startIndex || !isWord(line[line.index(before: i)]) {
        let after = line[line.index(after: i)...]
        if let person = people.first(where: { after.lowercased().hasPrefix($0.name.lowercased()) && after.dropFirst($0.name.count).first.map(isWord) != true }) {
          if !plain.isEmpty { runs.append(ComposerRun(plain, marks: marks)) }
          plain = ""
          runs.append(ComposerRun("@" + person.name, marks: marks, mention: person.id))
          i = line.index(i, offsetBy: person.name.count + 1)
          continue
        }
      }
      plain.append(c)
      i = line.index(after: i)
    }
    if !plain.isEmpty { runs.append(ComposerRun(plain, marks: marks)) }
    return runs
  }
}

// MARK: - Quote

/** What Quote writes in the composer (web `replyQuote`). */
public enum Quote {
  /**
   * What the message shows but its link previews, quoted, with each mention as the bare name `nameOf`
   * gives, then its author with a link to it, and a line to reply on.
   */
  public static func markup(_ nodes: [DisplayNode], author: String, link: String, nameOf: (UserID) -> String) -> String {
    let quote: [HTMLNode] = [
      .element(HTMLElement(name: "blockquote", children: quoted(nodes).flatMap { tree($0, nameOf) })),
      .element(HTMLElement(name: "cite", children: [.text("\(author) "), .element(HTMLElement(name: "a", attrs: [HTMLAttribute("href", link)], children: [.text("#")]))])),
      .element(HTMLElement(name: "p", children: [.element(HTMLElement(name: "br"))])),
    ]
    return HTML.serialize(quote, escapeAttributeBrackets: true)
  }

  /** `cardsQuote`: a bot's cards-only message, quoted by its plain text, its lines broken as they are. */
  public static func cards(_ plainText: String) -> [DisplayNode] {
    var children: [DisplayNode] = []
    for (index, line) in plainText.components(separatedBy: "\n").enumerated() {
      if index > 0 { children.append(.element(name: "br", attrs: [:], children: [])) }
      children.append(.text(line))
    }
    return [.element(name: "p", attrs: [:], children: children)]
  }

  private static func tree(_ node: DisplayNode, _ nameOf: (UserID) -> String) -> [HTMLNode] {
    switch node {
    case let .text(text): return [.text(text)]
    case let .mention(id): return [.text(nameOf(id))]
    case .preview: return []
    case let .element(name, attrs, children):
      let attributes = attrs.sorted { $0.key < $1.key }.map { HTMLAttribute($0.key, $0.value) }
      return [.element(HTMLElement(name: name, attrs: attributes, children: children.flatMap { tree($0, nameOf) }))]
    }
  }

  private static func quoted(_ nodes: [DisplayNode]) -> [DisplayNode] {
    guard let link = firstPreviewLink(nodes), !hasText(nodes) else { return nodes }
    return [.text(link)]
  }

  private static func hasText(_ nodes: [DisplayNode]) -> Bool {
    nodes.contains { node in
      switch node {
      case .mention: true
      case let .text(text): !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      case let .element(_, _, children): hasText(children)
      case .preview: false
      }
    }
  }

  private static func firstPreviewLink(_ nodes: [DisplayNode]) -> String? {
    for node in nodes {
      switch node {
      case let .element(_, _, children): if let link = firstPreviewLink(children) { return link }
      case let .preview(preview):
        if let href = preview.href { return absolute(href) }
        return firstLink(preview.title + preview.description).map(absolute)
      default: continue
      }
    }
    return nil
  }

  private static func firstLink(_ nodes: [DisplayNode]) -> String? {
    for case let .element(name, attrs, children) in nodes {
      if name == "a" {
        // A link without an address goes nowhere, as the browser reads it (`hrefOf`).
        guard let href = attrs["href"] else { return String() }
        return href
      }
      if let link = firstLink(children) { return link }
    }
    return nil
  }

  /** An address as a browser reads it, with the `/` of an empty path. */
  static func absolute(_ href: String) -> String {
    guard var components = URLComponents(string: href), components.scheme != nil, components.host != nil else { return href }
    if components.path.isEmpty { components.path = "/" }
    return components.string ?? href
  }
}

// MARK: - Snippets, uploads and message actions

public enum Snippets {
  /** `snippetName`: the title trimmed, slashes made dashes, `Untitled` for none, `.txt` unless it has an extension. */
  public static func name(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
    let name = trimmed.isEmpty ? "Untitled" : trimmed
    return name.firstMatch(of: #/\.[a-zA-Z][a-zA-Z0-9]{0,7}$/#) != nil ? name : name + ".txt"
  }

  /** `MAX_FILE_NAME_LENGTH - 4`: a title leaves room for `.txt`. */
  public static let maxTitleLength = Files.maxFileNameLength - 4
}

public enum UploadWords {
  /** `uploadSize`: whole KB, at least 1, under a megabyte, and MB to one place from there. */
  public static func size(_ bytes: Int) -> String {
    bytes < 1_000_000 ? "\(max(1, Int((Double(bytes) / 1000).rounded(.up)))) KB" : String(format: "%.1f MB", Double(bytes) / 1_000_000)
  }

  /** What an upload card says of where it is. */
  public static func status(percent: Int, error: String?) -> String {
    error != nil ? "Upload failed" : percent >= 100 ? "Processing…" : "Uploading · \(percent)%"
  }

  /** What a failed upload says: 413's own words, 422's reason from Ember, a dropped connection's, else that it failed. */
  public static func failure(status: Int?, reason: String?) -> String {
    switch status {
    case 413: Files.fileTooLarge
    case 422: reason ?? EmberText.uploadFailed
    case nil: EmberText.connectionLost
    default: EmberText.uploadFailed
    }
  }

  /** How much of `size` has gone, whole, 100 for an empty file. */
  public static func percent(sent: Int, of size: Int) -> Int {
    size == 0 ? 100 : min(100, Int(Double(sent) / Double(size) * 100))
  }
}

/** What can be done to a message from its actions (web `message-actions-menu.tsx`), by who's looking where. */
public enum MessageAction: String, CaseIterable, Sendable {
  case replyInThread, quote, copyText, copyLink, block, report, edit, delete, download, share

  public struct Context: Sendable {
    public var mine: Bool
    public var administrator: Bool
    public var inThread: Bool

    public init(mine: Bool, administrator: Bool, inThread: Bool) {
      self.mine = mine
      self.administrator = administrator
      self.inThread = inThread
    }
  }

  /** The More actions menu's items, in its order, for `message`. */
  public static func menu(for message: Message, _ context: Context) -> [MessageAction] {
    let file = message.attachment != nil
    let huddle = message.huddle != nil
    let editable = context.mine || context.administrator
    var actions: [MessageAction] = []
    if !file, !huddle { actions += [.quote, .copyText] }
    actions.append(.copyLink)
    if !context.mine, !huddle { actions += [.block, .report] }
    if editable {
      if !editsFixed(message) { actions.append(.edit) }
      actions.append(.delete)
    }
    return actions
  }

  /** The bar's buttons besides reactions and Message options. */
  public static func bar(for message: Message, _ context: Context) -> [MessageAction] {
    var actions: [MessageAction] = []
    if !context.inThread { actions.append(.replyInThread) }
    if message.attachment != nil { actions += [.download, .share] }
    if context.mine || context.administrator { actions.append(.edit) }
    return actions
  }

  /** Whether Edit opens the editor that only deletes: a file's, a bot's cards' or a huddle's message. */
  public static func editsFixed(_ message: Message) -> Bool {
    message.attachment != nil || message.cards?.isEmpty == false || message.huddle != nil
  }

  /** `newestWrittenBy`: the newest of `messages` that `userId` wrote, which Up Arrow edits; a huddle's is nobody's. */
  public static func newest(_ messages: [Message], writtenBy userId: UserID) -> Message? {
    messages.last { $0.creator.id == userId && $0.huddle == nil && $0.deleted != true }
  }

  /** What deleting asks first. */
  public static let deleteQuestion = "Are you sure you want to delete this message?"
}
