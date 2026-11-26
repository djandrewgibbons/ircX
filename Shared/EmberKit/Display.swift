import Foundation

// packages/richtext/src/display.ts, previews.ts and attachments.ts: what a message's stored body shows,
// as a tree of the elements it can show, the people it mentions and its link previews, which each theme
// draws natively. Bodies that can't be shown throw, and show as "Failed to load message content".

/** A link preview as it shows (`DisplayPreview`). */
public struct DisplayPreview: Sendable, Hashable {
  /** Its title, which links to `href` when it has one. */
  public var title: [DisplayNode]
  public var href: String?
  public var description: [DisplayNode]
  /** Its image's address, on another site: loaded without cookies or a referrer. */
  public var image: String?
  /** Someone's X avatar, which shows small and round. */
  public var avatar: Bool

  public init(title: [DisplayNode], href: String?, description: [DisplayNode], image: String?, avatar: Bool) {
    self.title = title
    self.href = href
    self.description = description
    self.image = image
    self.avatar = avatar
  }

  /** A preview the composer is to add, as it will show. */
  public init(_ preview: LinkPreview) {
    self.init(
      title: [.text(preview.title)], href: preview.url, description: [.text(preview.description)], image: preview.image,
      avatar: Display.isTwitterAvatar(preview.image))
  }
}

/** What a message shows (`DisplayNode`): text, an element it's formatted with, a mention, a link preview. */
public indirect enum DisplayNode: Sendable, Hashable {
  case text(String)
  case element(name: String, attrs: [String: String], children: [DisplayNode])
  case mention(UserID)
  case preview(DisplayPreview)

  /** The text it shows, mentions as `@` and their name from `name`, previews left out. */
  public func plainText(name: (UserID) -> String) -> String {
    switch self {
    case let .text(text): text
    case let .element(element, _, children):
      element == "br" ? "\n" : children.map { $0.plainText(name: name) }.joined()
    case let .mention(id): "@" + name(id)
    case .preview: ""
    }
  }
}

/** A preview whose address Ruby can't read (`RenderError`), which keeps its message from showing. */
public struct DisplayError: Error, Equatable, LocalizedError {
  public var reason: String
  public var errorDescription: String? { reason }
}

public enum Display {
  public static let mentionContentType = "application/vnd.campfire.mention"
  public static let previewContentType = "application/vnd.actiontext.opengraph-embed"
  public static let attachmentTag = "action-text-attachment"
  /** `MISSING_ATTACHABLE`, and what a mention of someone no one knows shows (`UNKNOWN_PERSON`). */
  public static let missingAttachable = "\u{2612}"
  /** What a message whose body can't be shown says in its place. */
  public static let failedToLoad = "Failed to load message content"

  /** `DISPLAYED`: auto_link's allowlist less `img`. */
  static let displayedTags: Set<String> = [
    "a", "abbr", "acronym", "address", "b", "big", "blockquote", "br", "cite", "code", "dd", "del", "dfn", "div", "dl", "dt", "em",
    "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "ins", "kbd", "li", "mark", "ol", "p", "pre", "samp", "small", "span",
    "strong", "sub", "sup", "time", "tt", "ul", "var", "s", "u", "table", "thead", "tbody", "tfoot", "tr", "th", "td",
  ]
  static let displayedAttributes: Set<String> = ["abbr", "cite", "datetime", "height", "href", "lang", "title", "width", "xml:lang", "data-language"]
  static let uriAttributes: Set<String> = ["action", "cite", "href", "longdesc", "poster", "preload", "src", "xlink:href", "xml:base"]
  static let allowedProtocols: Set<String> = [
    "afs", "aim", "callto", "data", "ed2k", "fax", "ftp", "gopher", "http", "https", "irc", "line", "mailto", "modem", "news", "nntp",
    "rsync", "rtsp", "sftp", "sms", "ssh", "tag", "tel", "telnet", "urn", "webcal", "xmpp",
  ]
  static let dataMediatypes: Set<String> = ["image/gif", "image/jpeg", "image/png", "text/css", "text/plain"]

  /** `USER_ID`: a mention's sgid is the user's id. */
  public static func userId(fromSgid sgid: String) -> UserID? {
    if sgid == Assistant.id { return sgid }
    let scalars = sgid.unicodeScalars
    guard scalars.count == 16, scalars.allSatisfy({ HTML.isDigit($0) || ("a"..."z").contains($0) }) else { return nil }
    return sgid
  }

  /**
   * `displayBody`: a stored body as it shows, `plainText` the body's, `host` the instance's, which
   * previews mustn't name. Throws for markup past the parser's limits.
   */
  public static func body(_ html: String, plainText: String, host: String) throws -> [DisplayNode] {
    var stored = try HTML.parse(html)
    try removeSoloUnfurledLinkText(&stored, plainText: plainText, host: host)
    stored = scrub(stored)
    let shown = HTML.serialize(stored)
    return try linked(shown, host: host, parsed: shown == html ? stored : nil)
  }

  static func linked(_ html: String, host: String, parsed: [HTMLNode]? = nil) throws -> [DisplayNode] {
    let autoLinked = Autolink.autoLink(html)
    let tree: [HTMLNode]
    if let parsed, autoLinked == html { tree = parsed } else { tree = try HTML.parse(autoLinked) }
    return try tree.flatMap { try displayed($0, host: host) }
  }

  static func displayed(_ node: HTMLNode, host: String) throws -> [DisplayNode] {
    switch node {
    case let .text(text): return [.text(text)]
    case .comment: return []
    case let .element(element):
      guard element.isHTML else { return [] }
      if isMention(element) {
        guard let sgid = element.attr("sgid"), let id = userId(fromSgid: sgid) else { return [.text(missingAttachable)] }
        return [.mention(id)]
      }
      if isPreview(element) { return [try displayedPreview(element, host: host)] }
      let children = try element.children.flatMap { try displayed($0, host: host) }
      guard displayedTags.contains(element.name) else { return children }
      var attrs: [String: String] = [:]
      for attr in element.attrs where displayedAttributes.contains(attr.name) && attrs[attr.name] == nil { attrs[attr.name] = attr.value }
      return [.element(name: element.name, attrs: attrs, children: children)]
    }
  }

  static func isAttachment(_ element: HTMLElement, _ contentType: String) -> Bool {
    element.name == attachmentTag && element.attr("content-type") == contentType
  }

  static func isMention(_ element: HTMLElement) -> Bool { isAttachment(element, mentionContentType) }
  static func isPreview(_ element: HTMLElement) -> Bool { isAttachment(element, previewContentType) }

  static func displayedPreview(_ element: HTMLElement, host: String) throws -> DisplayNode {
    let embed = try opengraphEmbed(element, host: host)
    func linkedText(_ value: String) throws -> [DisplayNode] { try linked(HTML.escapeText(value), host: host) }
    var titleNodes: [DisplayNode] = []
    if let href = embed.href {
      let title = embed.filename.map { truncate($0, 280) } ?? href
      if !title.isEmpty { titleNodes = [.text(title)] }
    } else if let filename = embed.filename {
      titleNodes = try linkedText(truncate(filename, 280))
    }
    var description: [DisplayNode] = []
    if let text = embed.description { description = try linkedText(truncate(text, 560)) }
    return .preview(DisplayPreview(title: titleNodes, href: embed.href, description: description, image: embed.url, avatar: isTwitterAvatar(embed.url)))
  }

  // MARK: - Scrubbing

  /** `scrub(stored, DISPLAYED, mention or preview)`: what a message can't show taken out, attachments kept as they are. */
  static func scrub(_ nodes: [HTMLNode]) -> [HTMLNode] {
    nodes.flatMap { node -> [HTMLNode] in
      switch node {
      case .text: return [node]
      case .comment: return []
      case let .element(element):
        if element.isHTML, isMention(element) || isPreview(element) { return [node] }
        let children = scrub(element.children)
        guard element.isHTML, displayedTags.contains(element.name) else { return element.isHTML ? children : [] }
        var kept = element
        kept.children = children
        kept.attrs = element.attrs.filter { attr in
          displayedAttributes.contains(attr.name) && !(uriAttributes.contains(attr.name) && !allowedUri(attr.value))
        }
        return [.element(kept)]
      }
    }
  }

  /** `Loofah::HTML5::Scrub.allowed_uri?`, its protocol check. */
  static func allowedUri(_ uri: String) -> Bool {
    let kept = HTML.decodeEntities(uri).unicodeScalars.filter { !($0.value <= 0x20 || $0 == "`" || ($0.value >= 0x7F && $0.value <= 0x101)) }
    let value = String(String.UnicodeScalarView(kept)).lowercased()
    guard let colon = value.firstIndex(of: ":") else { return true }
    let scheme = String(value[..<colon])
    guard let first = scheme.unicodeScalars.first, HTML.isASCIILetter(first),
      scheme.unicodeScalars.allSatisfy({ HTML.isASCIIAlphanumeric($0) || $0 == "+" || $0 == "-" || $0 == "." })
    else { return true }
    guard allowedProtocols.contains(scheme) else { return false }
    guard scheme == "data" else { return true }
    guard let metadata = value.dropFirst(5).split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first,
      let mediatype = metadata.split(separator: ";").first
    else { return false }
    return dataMediatypes.contains(String(mediatype))
  }

  // MARK: - Link previews

  /** A link preview's details (`OpengraphEmbed`). */
  public struct OpengraphEmbed: Sendable, Equatable {
    public var href: String?
    public var url: String?
    public var filename: String?
    public var description: String?
  }

  /** `opengraphEmbedFromNode` */
  static func opengraphEmbed(_ element: HTMLElement, host: String) throws -> OpengraphEmbed {
    if let filename = element.attr("filename"), !Autolink.isBlank(filename) {
      return OpengraphEmbed(href: webUrl(element.attr("href"), host: host), url: webUrl(element.attr("url"), host: host), filename: filename, description: element.attr("caption"))
    }
    guard let markup = element.attr("content") else { return OpengraphEmbed(href: nil, url: nil, filename: nil, description: nil) }
    let content = try HTML.parse(markup)
    let elements = HTML.elements(in: content)
    let title = elements.first { hasClass($0, "og-embed__title") }
    let link = title.flatMap { HTML.elements(in: $0.children).first { $0.name == "a" } }
    let image = firstImage(in: content, within: "og-embed__image")
    let description = elements.first { hasClass($0, "og-embed__description") }
    let named = link ?? title
    return OpengraphEmbed(
      href: webUrl(link?.attr("href"), host: host), url: webUrl(image?.attr("src"), host: host),
      filename: named.map { strip(HTMLNode.element($0).textContent) }, description: description.map { strip(HTMLNode.element($0).textContent) })
  }

  static func firstImage(in nodes: [HTMLNode], within name: String, inside: Bool = false) -> HTMLElement? {
    for node in nodes {
      guard case let .element(element) = node else { continue }
      if inside, element.name == "img" { return element }
      if let found = firstImage(in: element.children, within: name, inside: inside || hasClass(element, name)) { return found }
    }
    return nil
  }

  static func hasClass(_ element: HTMLElement, _ name: String) -> Bool {
    guard let classes = element.attr("class") else { return false }
    return classes.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).contains { $0 == name }
  }

  /** `isTwitterAvatar` */
  public static func isTwitterAvatar(_ url: String?) -> Bool { url?.hasPrefix("https://pbs.twimg.com/profile_images") == true }

  /**
   * `webUrl`: the address, when it's an absolute http or https URL on a named host other than `host`,
   * so that a preview or a card can't aim at the instance, where it would be fetched signed in.
   */
  public static func webUrl(_ value: String?, host: String) -> String? {
    guard let value, !Autolink.isBlank(value), let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https", let uriHost = components.percentEncodedHost, namedHost(uriHost),
      canonicalHost(uriHost) != canonicalHost(host)
    else { return nil }
    return value
  }

  /** `cardAddress`: an address a bot's card may link to or show. */
  public static func cardAddress(_ value: String, host: String) -> String? { webUrl(value, host: host) }

  static func namedHost(_ host: String) -> Bool {
    guard !Autolink.isBlank(host), !host.contains("%"), host.contains(".") else { return false }
    var labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    while labels.last == "" { labels.removeLast() }
    guard let label = labels.last, !label.isEmpty else { return false }
    return label.unicodeScalars.contains(where: HTML.isASCIILetter) && !label.lowercased().hasPrefix("0x")
  }

  static func canonicalHost(_ host: String) -> String {
    let lowered = host.lowercased()
    return lowered.hasSuffix(".") ? String(lowered.dropLast()) : lowered
  }

  /** The preview attachments a composer writes, anywhere in `nodes`. */
  static func unfurledLinks(_ nodes: [HTMLNode]) -> [HTMLElement] { HTML.elements(in: nodes).filter(isPreview) }

  /** `hasPreview`: whether a body has a link's preview. */
  public static func hasPreview(_ html: String) throws -> Bool { !unfurledLinks(try HTML.parse(html)).isEmpty }

  /** `MAX_PREVIEW_COPIES_LENGTH` */
  static let maxPreviewCopiesLength = 100_000

  /** `removeSoloUnfurledLinkText`: a body that's only the link its one preview is of loses the link. */
  static func removeSoloUnfurledLinkText(_ content: inout [HTMLNode], plainText: String, host: String) throws {
    let links = unfurledLinks(content)
    guard links.count == 1, let solo = try opengraphEmbed(links[0], host: host).href, let normalized = normalizeTweetUrl(solo),
      normalized == normalizeTweetUrl(plainText)
    else { return }
    let preview = HTMLNode.element(links[0])
    if HTML.elements(in: content).contains(where: { $0.name == "div" }) {
      let copies = max(1, maxPreviewCopiesLength / max(1, HTML.serialize([preview], escapeAttributeBrackets: false).utf16.count))
      var index = 0
      func fill(_ nodes: [HTMLNode]) -> [HTMLNode] {
        nodes.map { node in
          guard case var .element(element) = node else { return node }
          if element.name == "div" {
            element.children = index < copies ? [preview] : []
            index += 1
            return .element(element)
          }
          element.children = fill(element.children)
          return .element(element)
        }
      }
      content = fill(content)
    } else {
      func drop(_ nodes: [HTMLNode]) -> [HTMLNode] {
        nodes.compactMap { node in
          guard case var .element(element) = node else { return node }
          if element.name == "p", !HTML.elements(in: element.children).contains(where: { $0.name == attachmentTag }) { return nil }
          element.children = drop(element.children)
          return .element(element)
        }
      }
      content = drop(content)
    }
  }

  /** `normalizeTweetUrl`: an X or Twitter address on twitter.com without its query, so a tweet's addresses compare equal. */
  public static func normalizeTweetUrl(_ url: String) -> String? {
    guard !Autolink.isBlank(url), url.contains("x.com") || url.contains("twitter.com") else { return url }
    guard var components = URLComponents(string: url), let scheme = components.scheme?.lowercased() else { return url }
    if scheme == "http" || scheme == "https", components.host?.isEmpty != false { return nil }
    components.user = nil
    components.password = nil
    components.query = nil
    if components.host?.lowercased() == "x.com" { components.host = "twitter.com" }
    return components.string
  }

  // MARK: - Helpers

  /** `String#strip`: NUL and ASCII whitespace off both ends. */
  static func strip(_ value: String) -> String {
    let stripped: Set<Unicode.Scalar> = ["\0", "\t", "\n", "\u{0B}", "\u{0C}", "\r", " "]
    var scalars = Array(value.unicodeScalars)
    while let first = scalars.first, stripped.contains(first) { scalars.removeFirst() }
    while let last = scalars.last, stripped.contains(last) { scalars.removeLast() }
    return String(String.UnicodeScalarView(scalars))
  }

  /** `truncate(value, length, "…")`, in code points. */
  static func truncate(_ value: String, _ length: Int) -> String {
    let scalars = Array(value.unicodeScalars)
    guard scalars.count > length else { return value }
    return String(String.UnicodeScalarView(scalars.prefix(length - 1))) + "\u{2026}"
  }

  /**
   * `isAllEmoji`: one or more emoji and nothing else. Skin tones, flags, a heart, a copyright sign
   * count; a zero-width joiner or a keycap's digit doesn't.
   */
  public static func isAllEmoji(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return text.unicodeScalars.allSatisfy { scalar in
      let p = scalar.properties
      return scalar == "\u{FE0F}" || p.isEmojiPresentation || (p.isEmoji && scalar.value >= 0xA9)
    }
  }

  /** A code block's code when it holds only text and `<br>`s, which then highlights; nil when it holds more. */
  public static func codeOf(_ children: [DisplayNode]) -> String? {
    var code = ""
    for child in children {
      switch child {
      case let .text(text): code += text
      case let .element(name, _, children) where name == "br" && children.isEmpty: code += "\n"
      default: return nil
      }
    }
    return code
  }

  static let blockNames: Set<String> = ["p", "div", "li", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6"]

  /** A card's text folds behind Show more past 700 characters or 5 line breaks (bot-card.tsx `isLong`). */
  public static func isLong(_ nodes: [DisplayNode]) -> Bool {
    var characters = 0
    var lineBreaks = -1
    func count(_ node: DisplayNode) {
      switch node {
      case let .text(text):
        characters += text.utf16.count
        lineBreaks += text.filter { $0 == "\n" }.count
      case let .element(name, _, children):
        var startsWithBlock = false
        if case let .element(first, _, _)? = children.first { startsWithBlock = blockNames.contains(first) }
        if name == "br" || (blockNames.contains(name) && !startsWithBlock) { lineBreaks += 1 }
        children.forEach(count)
      default: break
      }
    }
    nodes.forEach(count)
    return characters > 700 || lineBreaks > 5
  }
}
