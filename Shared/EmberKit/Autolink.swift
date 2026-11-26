import Foundation

// packages/richtext/src/autolink.ts: rails_autolink 1.1.8's `auto_link(html, html: { target: "_blank" })`,
// the last step before a message shows, ported as it is. It works on serialized HTML with regular
// expressions, by UTF-16 offsets as JavaScript's do, so it needs the canonical serialization, with `<`
// and `>` escaped in attribute values.

public enum Autolink {
  /** `AUTO_LINK_RE`. Ruby's `\s` is ASCII-only; ICU's `\v` isn't JavaScript's, so it's spelled out. */
  nonisolated(unsafe) static let autoLinkRE = try! NSRegularExpression(
    pattern: #"(?:((?:ed2k|ftp|http|https|irc|mailto|news|gopher|nntp|telnet|webcal|xmpp|callto|feed|svn|urn|aim|rsync|tag|ssh|sftp|rtsp|afs|file):)//|www\.[a-zA-Z0-9_])[^ \t\r\n\x{0B}\x{0C}< "]+"#,
    options: [.caseInsensitive])

  /** `AUTO_EMAIL_RE`, tried at one position at a time. */
  nonisolated(unsafe) static let autoEmailRE = try! NSRegularExpression(
    pattern: #"[a-zA-Z0-9_.!#$%+\-]\.?[a-zA-Z0-9_.!#$%&'*/=?^`{|}~+\-]*@[a-zA-Z0-9_\-]+(?:\.[a-zA-Z0-9_\-]+)+"#)

  /** `LINKABLE`: an address `autoLink` links, anywhere. */
  nonisolated(unsafe) static let linkableRE = try! NSRegularExpression(
    pattern: #"(?:((?:ed2k|ftp|http|https|irc|mailto|news|gopher|nntp|telnet|webcal|xmpp|callto|feed|svn|urn|aim|rsync|tag|ssh|sftp|rtsp|afs|file):)//|www\.[a-zA-Z0-9_])[^ \t\r\n\x{0B}\x{0C}< "]+|(?<![a-zA-Z0-9_.!#$%&'*/=?^`{|}~+\-])[a-zA-Z0-9_.!#$%+\-]\.?[a-zA-Z0-9_.!#$%&'*/=?^`{|}~+\-]*@[a-zA-Z0-9_\-]+(?:\.[a-zA-Z0-9_\-]+)+"#,
    options: [.caseInsensitive])

  /** `AUTO_EMAIL_LOCAL_RE`'s characters, as UTF-16 units. */
  static let emailLocalChars: Set<UInt16> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.!#$%&'*/=?^`{|}~+-".utf16)
  /** The characters an address can start with. */
  static let emailStartChars: Set<UInt16> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.!#$%+-".utf16)

  /** `hasLinkable`: whether plain text has an address in it that `autoLink` links. */
  public static func hasLinkable(_ text: String) -> Bool {
    linkableRE.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
  }

  /** `linkedUrls`: where the links `autoLink` makes in plain text go, but those to email addresses. */
  public static func linkedUrls(_ text: String) -> [String] {
    let ns = text as NSString
    return autoLinkRE.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
      let whole = ns.substring(with: match.range)
      let address = withoutTrailingPunctuation(whole).address
      return match.range(at: 1).location == NSNotFound ? "http://\(address)" : address
    }
  }

  /** `autoLink`: `html` sanitized and serialized already, its addresses in text made links that open in a new tab. */
  public static func autoLink(_ html: String) -> String {
    if isBlank(html) { return "" }
    return autoLinkEmailAddresses(autoLinkUrls(html))
  }

  static func autoLinkUrls(_ text: String) -> String {
    let ns = text as NSString
    let tags = TagIndex(text)
    var out = ""
    var last = 0
    for match in autoLinkRE.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
      let start = match.range.location
      let end = start + match.range.length
      let whole = ns.substring(with: match.range)
      out += ns.substring(with: NSRange(location: last, length: start - last))
      last = end
      if tags.autoLinked(start, end) {
        out += whole
        continue
      }
      let (address, punctuation) = withoutTrailingPunctuation(whole)
      var href = address
      var trailingGt = ""
      if href.hasSuffix("&gt;") {
        href = String(href.dropLast(4))
        trailingGt = "&gt;"
      }
      let linkText = sanitized(href)
      if match.range(at: 1).location == NSNotFound { href = "http://\(href)" }
      out += "<a target=\"_blank\" href=\"\(sanitized(href).replacingOccurrences(of: "\"", with: "&quot;"))\">\(linkText)</a>"
      out += htmlEscape(punctuation) + trailingGt
    }
    return out + ns.substring(from: last)
  }

  /**
   * An address with the punctuation that ends it taken off: everything after its last word character,
   * `/`, `-`, `=` or `;`, but for a closing bracket the address opened more of.
   */
  static func withoutTrailingPunctuation(_ url: String) -> (address: String, punctuation: String) {
    var chars = Array(url.unicodeScalars)
    var counts: [Unicode.Scalar: Int] = [:]
    for c in chars { counts[c, default: 0] += 1 }
    var removed: [Unicode.Scalar] = []
    let opening: [Unicode.Scalar: Unicode.Scalar] = ["]": "[", ")": "(", "}": "{"]
    while let c = chars.last, !(isWordChar(c) || "/-=;".unicodeScalars.contains(c)) {
      chars.removeLast()
      removed.append(c)
      counts[c, default: 0] -= 1
      if let open = opening[c], counts[open, default: 0] > counts[c, default: 0] {
        chars.append(removed.removeLast())
        break
      }
    }
    return (String(String.UnicodeScalarView(chars)), String(String.UnicodeScalarView(removed.reversed())))
  }

  /** Ruby's `\p{Word}` */
  static func isWordChar(_ c: Unicode.Scalar) -> Bool {
    let p = c.properties
    if p.isAlphabetic || p.isJoinControl { return true }
    switch p.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .connectorPunctuation: return true
    default: return false
    }
  }

  static func autoLinkEmailAddresses(_ text: String) -> String {
    let ns = text as NSString
    let units = Array(text.utf16)
    let tags = TagIndex(text)
    var out = ""
    var copied = 0
    var position = 0
    while position < units.count {
      let preceded = position > 0 && emailLocalChars.contains(units[position - 1])
      guard !preceded, emailStartChars.contains(units[position]),
        let match = autoEmailRE.firstMatch(in: text, options: [.anchored], range: NSRange(location: position, length: units.count - position))
      else {
        position += 1
        continue
      }
      let email = ns.substring(with: match.range)
      let end = position + match.range.length
      out += ns.substring(with: NSRange(location: copied, length: position - copied))
      if tags.autoLinked(position, end) {
        out += email
      } else {
        let clean = sanitized(email)
        // `mail_to` escapes the address it shows, unless sanitizing changed it, which marks it safe.
        let display = clean == email ? htmlEscape(email) : clean
        let href = "mailto:" + urlEncode(clean).replacingOccurrences(of: "%40", with: "@")
        out += "<a target=\"_blank\" href=\"\(htmlEscape(href))\">\(display)</a>"
      }
      copied = end
      position = end
    }
    return out + ns.substring(from: copied)
  }

  /** `sanitize(parse, text, RAILS_DEFAULTS)` of text with no tags in it: its references read and written back as the serializer writes text. */
  static func sanitized(_ text: String) -> String { HTML.escapeText(HTML.decodeEntities(text)) }

  /** `ERB::Util.html_escape` */
  public static func htmlEscape(_ value: String) -> String {
    var out = ""
    for c in value.unicodeScalars {
      switch c {
      case "&": out += "&amp;"
      case "<": out += "&lt;"
      case ">": out += "&gt;"
      case "\"": out += "&quot;"
      case "'": out += "&#39;"
      default: out.unicodeScalars.append(c)
      }
    }
    return out
  }

  /** `ERB::Util.url_encode` */
  static func urlEncode(_ value: String) -> String {
    var out = ""
    for byte in value.utf8 {
      let c = Unicode.Scalar(byte)
      if HTML.isASCIIAlphanumeric(c) || c == "_" || c == "." || c == "~" || c == "-" {
        out.unicodeScalars.append(c)
      } else {
        out += String(format: "%%%02X", byte)
      }
    }
    return out
  }

  /** Active Support's `blank?` */
  static func isBlank(_ value: String) -> Bool { value.unicodeScalars.allSatisfy { $0.properties.isWhitespace } }

  /** `TagIndex`: whether a match is inside a tag, or inside a link, as rails_autolink's `auto_linked?` asks. */
  public struct TagIndex {
    var lts: [Int] = []
    var gts: [Int] = []
    var firstDanglingNewline: Int?
    var openAnchors: [(start: Int, end: Int)] = []
    var closeAnchors: [Int] = []

    public init(_ text: String) {
      let t = Array(text.utf16)
      let lt = UInt16(UInt8(ascii: "<")), gt = UInt16(UInt8(ascii: ">")), newline = UInt16(UInt8(ascii: "\n"))
      var unclosedLt: Int?
      for i in t.indices {
        let c = t[i]
        if c == lt {
          lts.append(i)
          if unclosedLt == nil { unclosedLt = i }
          if i + 3 < t.count, t[i + 1] == UInt16(UInt8(ascii: "/")), t[i + 2] == UInt16(UInt8(ascii: "a")) || t[i + 2] == UInt16(UInt8(ascii: "A")), t[i + 3] == gt {
            closeAnchors.append(i)
          }
          let pastLastAnchor = openAnchors.last.map { $0.end <= i } != false
          if pastLastAnchor, let end = Self.openAnchor(t, at: i) { openAnchors.append((i, end)) }
        } else if c == gt {
          gts.append(i)
          unclosedLt = nil
        } else if c == newline, firstDanglingNewline == nil, let open = unclosedLt, open + 2 <= i {
          firstDanglingNewline = i
        }
      }
    }

    /** `/<a\b.*?>/iy` at `i`: where it ends. */
    static func openAnchor(_ t: [UInt16], at i: Int) -> Int? {
      guard i + 1 < t.count, t[i + 1] == UInt16(UInt8(ascii: "a")) || t[i + 1] == UInt16(UInt8(ascii: "A")) else { return nil }
      if i + 2 < t.count {
        let next = t[i + 2]
        let isWord = (48...57).contains(next) || (65...90).contains(next) || (97...122).contains(next) || next == 95
        if isWord { return nil }
      }
      var j = i + 2
      while j < t.count {
        if t[j] == UInt16(UInt8(ascii: ">")) { return j + 1 }
        if t[j] == UInt16(UInt8(ascii: "\n")) { return nil }
        j += 1
      }
      return nil
    }

    /** `auto_linked?(text[..start], text[end..])` */
    public func autoLinked(_ start: Int, _ end: Int) -> Bool {
      (openTagAtLineEnd(start) && closesTag(end)) || insideAnchor(start)
    }

    func openTagAtLineEnd(_ start: Int) -> Bool {
      if let dangling = firstDanglingNewline, dangling < start { return true }
      let lastGtIndex = Self.partitionPoint(gts) { $0 < start } - 1
      let firstLtIndex = lastGtIndex >= 0 ? Self.partitionPoint(lts) { $0 <= gts[lastGtIndex] } : 0
      guard firstLtIndex < lts.count else { return false }
      return lts[firstLtIndex] + 2 <= start
    }

    func closesTag(_ end: Int) -> Bool {
      guard let last = gts.last else { return false }
      return last >= end
    }

    func insideAnchor(_ start: Int) -> Bool {
      let index = Self.partitionPoint(openAnchors) { $0.end <= start } - 1
      guard index >= 0 else { return false }
      let anchor = openAnchors[index]
      let closeIndex = Self.partitionPoint(closeAnchors) { $0 < anchor.end }
      guard closeIndex < closeAnchors.count else { return true }
      return closeAnchors[closeIndex] + 4 > start
    }

    static func partitionPoint<T>(_ sorted: [T], _ before: (T) -> Bool) -> Int {
      var low = 0
      var high = sorted.count
      while low < high {
        let middle = (low + high) / 2
        if before(sorted[middle]) { low = middle + 1 } else { high = middle }
      }
      return low
    }
  }
}
