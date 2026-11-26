import Foundation

// packages/richtext's tree, parser and serializer, as far as showing a message needs them: stored
// bodies are the canonical serialization (`serialize.ts`), so a small tolerant parser reads them, and
// anything it can't read throws, for the message to show "Failed to load message content".

/** An attribute, in the order its start tag gives it. */
public struct HTMLAttribute: Sendable, Hashable {
  public var name: String
  public var value: String

  public init(_ name: String, _ value: String) {
    self.name = name
    self.value = value
  }
}

/** An element, with its attributes and children. Names are lowercase. */
public struct HTMLElement: Sendable, Hashable {
  public var name: String
  public var attrs: [HTMLAttribute]
  public var children: [HTMLNode]
  /** False for an element of SVG or MathML, which a message never shows. */
  public var isHTML: Bool

  public init(name: String, attrs: [HTMLAttribute] = [], children: [HTMLNode] = [], isHTML: Bool = true) {
    self.name = name
    self.attrs = attrs
    self.children = children
    self.isHTML = isHTML
  }

  public func attr(_ name: String) -> String? { attrs.first { $0.name == name }?.value }

  public mutating func removeAttr(_ name: String) { attrs.removeAll { $0.name == name } }
}

public indirect enum HTMLNode: Sendable, Hashable {
  case text(String)
  case element(HTMLElement)
  case comment(String)

  public var element: HTMLElement? {
    if case let .element(element) = self { return element }
    return nil
  }

  /** `textContent` */
  public var textContent: String {
    switch self {
    case let .text(text): text
    case let .element(element): element.children.map(\.textContent).joined()
    case .comment: ""
    }
  }
}

/** Markup past the parser's limits (`ParseLimitError`), which a message can't show. */
public struct RichTextError: Error, Equatable, LocalizedError {
  public var reason: String
  public var errorDescription: String? { reason }
}

public enum HTML {
  /** `MAX_TREE_DEPTH` */
  public static let maxTreeDepth = 400
  /** `MAX_ATTRIBUTES` */
  public static let maxAttributes = 400

  static let voidElements: Set<String> = [
    "area", "base", "basefont", "bgsound", "br", "col", "embed", "frame", "hr", "img", "input", "keygen", "link", "meta", "param", "source", "track", "wbr",
  ]
  static let rawTextElements: Set<String> = ["style", "script", "xmp", "iframe", "noembed", "noframes", "plaintext", "noscript", "textarea", "title"]
  /** Elements whose start closes an open `<p>`, as the HTML parser closes one. */
  static let closesParagraph: Set<String> = [
    "address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer",
    "header", "hgroup", "main", "menu", "nav", "ol", "p", "section", "summary", "ul", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "listing", "table", "hr",
    "form",
  ]
  /** Elements past which an open element isn't closed implicitly. */
  static let scopeBarriers: Set<String> = ["table", "td", "th", "caption", "html", "template", "button", "marquee", "object", "applet"]

  /** Reads markup as the body of a document, tolerantly. Throws past `maxTreeDepth`. */
  public static func parse(_ markup: String) throws -> [HTMLNode] {
    var parser = Parser(markup)
    return try parser.run()
  }

  /** `toHtml(fragment, { escapeAttributeBrackets })` */
  public static func serialize(_ nodes: [HTMLNode], escapeAttributeBrackets: Bool = true) -> String {
    var out = ""
    for node in nodes { serialize(node, parent: nil, escapeAttributeBrackets, into: &out) }
    return out
  }

  private static func serialize(_ node: HTMLNode, parent: String?, _ brackets: Bool, into out: inout String) {
    switch node {
    case let .text(text):
      if let parent, rawTextElements.contains(parent) { out += text } else { out += escapeText(text) }
    case let .comment(text):
      out += "<!--\(text)-->"
    case let .element(element):
      out += "<\(element.name)"
      for attr in element.attrs { out += " \(attr.name)=\"\(escapeAttribute(attr.value, brackets))\"" }
      out += ">"
      if element.isHTML, voidElements.contains(element.name) { return }
      for child in element.children { serialize(child, parent: element.name, brackets, into: &out) }
      out += "</\(element.name)>"
    }
  }

  public static func escapeText(_ value: String) -> String {
    var out = ""
    out.reserveCapacity(value.utf8.count)
    for scalar in value.unicodeScalars {
      switch scalar {
      case "&": out += "&amp;"
      case "\u{A0}": out += "&nbsp;"
      case "<": out += "&lt;"
      case ">": out += "&gt;"
      default: out.unicodeScalars.append(scalar)
      }
    }
    return out
  }

  static func escapeAttribute(_ value: String, _ brackets: Bool) -> String {
    var out = ""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "&": out += "&amp;"
      case "\u{A0}": out += "&nbsp;"
      case "\"": out += "&quot;"
      case "<": out += brackets ? "&lt;" : "<"
      case ">": out += brackets ? "&gt;" : ">"
      default: out.unicodeScalars.append(scalar)
      }
    }
    return out
  }

  /** Every element under `nodes`, depth first, in document order. */
  public static func elements(in nodes: [HTMLNode]) -> [HTMLElement] {
    var found: [HTMLElement] = []
    func walk(_ nodes: [HTMLNode]) {
      for node in nodes {
        guard case let .element(element) = node else { continue }
        found.append(element)
        walk(element.children)
      }
    }
    walk(nodes)
    return found
  }

  // MARK: - Character references

  static let namedEntities: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}", "copy": "\u{A9}", "reg": "\u{AE}", "trade": "\u{2122}",
    "hellip": "\u{2026}", "mdash": "\u{2014}", "ndash": "\u{2013}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}",
    "rdquo": "\u{201D}", "laquo": "\u{AB}", "raquo": "\u{BB}", "middot": "\u{B7}", "bull": "\u{2022}", "times": "\u{D7}", "divide": "\u{F7}",
    "deg": "\u{B0}", "plusmn": "\u{B1}", "para": "\u{B6}", "sect": "\u{A7}", "euro": "\u{20AC}", "pound": "\u{A3}", "yen": "\u{A5}",
    "cent": "\u{A2}", "larr": "\u{2190}", "rarr": "\u{2192}", "uarr": "\u{2191}", "darr": "\u{2193}", "Tab": "\t", "NewLine": "\n",
    "colon": ":", "shy": "\u{AD}", "zwj": "\u{200D}", "zwnj": "\u{200C}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
  ]

  /** Text with its character references read, as the HTML parser reads them in text and attribute values. */
  public static func decodeEntities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    let scalars = Array(text.unicodeScalars)
    var out = String.UnicodeScalarView()
    var i = 0
    while i < scalars.count {
      let c = scalars[i]
      guard c == "&" else {
        out.append(c)
        i += 1
        continue
      }
      var j = i + 1
      if j < scalars.count, scalars[j] == "#" {
        j += 1
        var hex = false
        if j < scalars.count, scalars[j] == "x" || scalars[j] == "X" {
          hex = true
          j += 1
        }
        let start = j
        while j < scalars.count, hex ? isHexDigit(scalars[j]) : isDigit(scalars[j]) { j += 1 }
        if j > start, j - start <= 8, let code = UInt32(String(String.UnicodeScalarView(scalars[start..<j])), radix: hex ? 16 : 10) {
          out.append(code == 0 || code > 0x10FFFF ? replacement : (Unicode.Scalar(code) ?? replacement))
          if j < scalars.count, scalars[j] == ";" { j += 1 }
          i = j
          continue
        }
      } else {
        let start = j
        while j < scalars.count, j - start < 32, isASCIIAlphanumeric(scalars[j]) { j += 1 }
        let name = String(String.UnicodeScalarView(scalars[start..<j]))
        if let value = namedEntities[name] {
          out.append(contentsOf: value.unicodeScalars)
          if j < scalars.count, scalars[j] == ";" { j += 1 }
          i = j
          continue
        }
      }
      out.append(c)
      i += 1
    }
    return String(out)
  }

  private static let replacement: Unicode.Scalar = "\u{FFFD}"
  static func isDigit(_ s: Unicode.Scalar) -> Bool { ("0"..."9").contains(s) }
  static func isHexDigit(_ s: Unicode.Scalar) -> Bool { isDigit(s) || ("a"..."f").contains(s) || ("A"..."F").contains(s) }
  static func isASCIILetter(_ s: Unicode.Scalar) -> Bool { ("a"..."z").contains(s) || ("A"..."Z").contains(s) }
  static func isASCIIAlphanumeric(_ s: Unicode.Scalar) -> Bool { isASCIILetter(s) || isDigit(s) }
  static func isSpace(_ s: Unicode.Scalar) -> Bool { s == " " || s == "\t" || s == "\n" || s == "\r" || s == "\u{0C}" }

  // MARK: - Parser

  private struct Parser {
    let s: [Unicode.Scalar]
    var i = 0
    /** The open elements, innermost last; the first is the fragment. */
    var stack: [HTMLElement] = [HTMLElement(name: "#fragment")]
    var text = ""

    init(_ markup: String) {
      var scalars = Array(markup.unicodeScalars)
      if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
      s = scalars
    }

    mutating func run() throws -> [HTMLNode] {
      while i < s.count {
        if s[i] == "<", let next = peek(1) {
          if next == "!", starts(with: "<!--") {
            flushText()
            readComment()
            continue
          }
          if next == "/", let after = peek(2), HTML.isASCIILetter(after) {
            flushText()
            readEndTag()
            continue
          }
          if HTML.isASCIILetter(next) {
            flushText()
            try readStartTag()
            continue
          }
          if next == "!" || next == "?" || next == "/" {
            // A bogus comment, as `<!doctype>` or `</ >`, which shows nothing.
            flushText()
            while i < s.count, s[i] != ">" { i += 1 }
            i += 1
            continue
          }
        }
        text.unicodeScalars.append(s[i])
        i += 1
      }
      flushText()
      while stack.count > 1 { closeTop() }
      return stack[0].children
    }

    func peek(_ n: Int) -> Unicode.Scalar? { i + n < s.count ? s[i + n] : nil }

    func starts(with prefix: String) -> Bool {
      var j = i
      for p in prefix.unicodeScalars {
        guard j < s.count, s[j] == p else { return false }
        j += 1
      }
      return true
    }

    mutating func flushText() {
      guard !text.isEmpty else { return }
      append(.text(decodeEntities(text)))
      text = ""
    }

    mutating func append(_ node: HTMLNode) {
      let top = stack.count - 1
      // Adjacent text joins, as the DOM's does.
      if case let .text(new) = node, case let .text(old)? = stack[top].children.last {
        stack[top].children[stack[top].children.count - 1] = .text(old + new)
      } else {
        stack[top].children.append(node)
      }
    }

    mutating func closeTop() {
      let element = stack.removeLast()
      append(.element(element))
    }

    mutating func readComment() {
      i += 4
      var body = String.UnicodeScalarView()
      while i < s.count, !starts(with: "-->") {
        body.append(s[i])
        i += 1
      }
      i = min(s.count, i + 3)
      append(.comment(String(body)))
    }

    mutating func readName() -> String {
      var name = String.UnicodeScalarView()
      while i < s.count, !HTML.isSpace(s[i]), s[i] != "/", s[i] != ">" {
        name.append(s[i])
        i += 1
      }
      return String(name).lowercased()
    }

    mutating func skipSpace() {
      while i < s.count, HTML.isSpace(s[i]) { i += 1 }
    }

    mutating func readEndTag() {
      i += 2
      let name = readName()
      while i < s.count, s[i] != ">" { i += 1 }
      i += 1
      // Closes the innermost open element of the name, and those inside it, unless a barrier stands between.
      guard let index = stack.indices.dropFirst().last(where: { stack[$0].name == name }) else {
        // `</p>` with no `<p>` open makes an empty one; `</br>` a `<br>`.
        if name == "p" { append(.element(HTMLElement(name: "p"))) }
        if name == "br" { append(.element(HTMLElement(name: "br"))) }
        return
      }
      if stack[(index + 1)...].contains(where: { HTML.scopeBarriers.contains($0.name) }) { return }
      while stack.count > index { closeTop() }
    }

    mutating func readStartTag() throws {
      i += 1
      let name = readName()
      var attrs: [HTMLAttribute] = []
      var selfClosing = false
      while i < s.count {
        skipSpace()
        guard i < s.count else { break }
        if s[i] == ">" {
          i += 1
          break
        }
        if s[i] == "/" {
          selfClosing = peek(1) == ">"
          i += 1
          continue
        }
        var attrName = String.UnicodeScalarView()
        attrName.append(s[i])
        i += 1
        while i < s.count, !HTML.isSpace(s[i]), s[i] != "/", s[i] != ">", s[i] != "=" {
          attrName.append(s[i])
          i += 1
        }
        skipSpace()
        var value = ""
        if i < s.count, s[i] == "=" {
          i += 1
          skipSpace()
          var raw = String.UnicodeScalarView()
          if i < s.count, s[i] == "\"" || s[i] == "'" {
            let quote = s[i]
            i += 1
            while i < s.count, s[i] != quote {
              raw.append(s[i])
              i += 1
            }
            i += 1
          } else {
            while i < s.count, !HTML.isSpace(s[i]), s[i] != ">" {
              raw.append(s[i])
              i += 1
            }
          }
          value = decodeEntities(String(raw))
        }
        let lowered = String(attrName).lowercased()
        // The first of an attribute's names wins.
        if !attrs.contains(where: { $0.name == lowered }) { attrs.append(HTMLAttribute(lowered, value)) }
        if attrs.count > HTML.maxAttributes { throw RichTextError(reason: "Too many attributes") }
      }
      let foreignParent = !stack[stack.count - 1].isHTML
      let isHTML = !(foreignParent || name == "svg" || name == "math")
      if isHTML { openImplied(by: name) }
      let element = HTMLElement(name: name, attrs: attrs, isHTML: isHTML)
      if (isHTML && HTML.voidElements.contains(name)) || (!isHTML && selfClosing) {
        append(.element(element))
        return
      }
      if stack.count > HTML.maxTreeDepth { throw RichTextError(reason: "Markup nests too deep") }
      stack.append(element)
      if isHTML, HTML.rawTextElements.contains(name) {
        var raw = String.UnicodeScalarView()
        while i < s.count, !(s[i] == "<" && peek(1) == "/" && closesRaw(name)) {
          raw.append(s[i])
          i += 1
        }
        if !raw.isEmpty { stack[stack.count - 1].children.append(.text(name == "textarea" || name == "title" ? decodeEntities(String(raw)) : String(raw))) }
        if i < s.count { readEndTag() } else { closeTop() }
      } else if isHTML, name == "pre" || name == "listing", i < s.count, s[i] == "\n" {
        // The parser drops the newline that starts a `pre`.
        i += 1
      }
    }

    func closesRaw(_ name: String) -> Bool {
      var j = i + 2
      for p in name.unicodeScalars {
        guard j < s.count, String(s[j]).lowercased() == String(p) else { return false }
        j += 1
      }
      return j >= s.count || s[j] == ">" || HTML.isSpace(s[j]) || s[j] == "/"
    }

    /** Closes what the start of `name` closes, as the HTML parser does: an open `p`, a list item, a table cell. */
    mutating func openImplied(by name: String) {
      if HTML.closesParagraph.contains(name) { close("p", within: HTML.scopeBarriers) }
      switch name {
      case "li": close("li", within: HTML.scopeBarriers.union(["ul", "ol"]))
      case "dt", "dd":
        close("dt", within: HTML.scopeBarriers.union(["dl"]))
        close("dd", within: HTML.scopeBarriers.union(["dl"]))
      case "tr":
        close("td", within: ["table"])
        close("th", within: ["table"])
        close("tr", within: ["table"])
      case "td", "th":
        close("td", within: ["table", "tr"])
        close("th", within: ["table", "tr"])
      case "tbody", "thead", "tfoot":
        close("tr", within: ["table"])
        close("tbody", within: ["table"])
        close("thead", within: ["table"])
        close("tfoot", within: ["table"])
      default: break
      }
    }

    mutating func close(_ name: String, within barriers: Set<String>) {
      for index in stack.indices.dropFirst().reversed() {
        if stack[index].name == name {
          while stack.count > index { closeTop() }
          return
        }
        if barriers.contains(stack[index].name) { return }
      }
    }
  }
}
