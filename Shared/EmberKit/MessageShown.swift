import Foundation

// How the web shows parts of a message that aren't its text: a file (attachment.tsx, lib/text-preview.ts),
// a huddle's message (huddle-message.tsx, lib/huddle-people.ts) and a thread's summary (message-item.tsx,
// lib/messages.ts), in the words the web uses.

/** How a message shows its file (`Attachment`), in the web's order of choice. */
public enum AttachmentShown: Equatable, Sendable {
  /** An SVG of up to 5 MiB, above its file card, once it decodes. */
  case svg
  case video
  /** A text file of up to 64 KiB, as a snippet is, above its file card, highlighted in `language`. */
  case text(language: String?)
  /** A picture: its thumbnail, or itself where every browser shows it and it's small enough. */
  case picture(path: String)
  case card

  public init(_ file: StoredFile) {
    if file.contentType == "image/svg+xml", file.byteSize <= Files.maxPreviewSize {
      self = .svg
    } else if file.contentType.hasPrefix("video") {
      self = .video
    } else if TextPreview.showsText(file) {
      self = .text(language: TextPreview.language(of: file.name))
    } else if let preview = file.previewUrl {
      self = .picture(path: preview)
    } else if AttachmentShown.showsItself(file), file.byteSize <= Files.maxPreviewSize {
      self = .picture(path: file.url)
    } else {
      self = .card
    }
  }

  /** `showsItself`: a picture every browser shows, of a known size of up to 250 megapixels. */
  public static func showsItself(_ file: StoredFile) -> Bool {
    Files.isWebImage(file.contentType) && Files.isPreviewableSize(width: file.width, height: file.height)
  }

  /** What the image viewer opens: the file itself where it shows itself, else what the message shows. */
  public static func viewed(_ file: StoredFile, shown path: String) -> String { showsItself(file) ? file.url : path }

  /** `shownSize`: the file's own size, scaled down to fit 1200x800; the web shows it at half that. */
  public static func shownSize(_ file: StoredFile) -> CGSize? {
    guard let width = file.width, let height = file.height, width > 0, height > 0 else { return nil }
    let scale = min(1, Double(Files.previewMaxWidth) / Double(width), Double(Files.previewMaxHeight) / Double(height))
    return CGSize(width: Double(width) * scale, height: Double(height) * scale)
  }
}

/** lib/text-preview.ts */
public enum TextPreview {
  /** `MAX_SHOWN_TEXT_SIZE` */
  public static let maxShownTextSize = 64 * 1024
  /** `FOLD_CHARACTERS`, `FOLD_LINES` */
  public static let foldCharacters = 700
  public static let foldLines = 5

  static let textApplications: Set<String> = ["javascript", "x-sh", "x-bat", "sql", "x-yaml", "yaml", "toml", "x-tex", "x-latex", "json", "xml"]

  /** `showsText`: text, of up to 64 KiB, with something in it. */
  public static func showsText(_ file: StoredFile) -> Bool {
    guard file.byteSize > 0, file.byteSize <= maxShownTextSize else { return false }
    if file.contentType.hasPrefix("text/") { return true }
    guard file.contentType.hasPrefix("application/") else { return false }
    let subtype = String(file.contentType.dropFirst("application/".count))
    if textApplications.contains(subtype) { return true }
    // JSON and XML of any sort: `application/ld+json`, `application/atom+xml`.
    guard let plus = subtype.lastIndex(of: "+") else { return false }
    let prefix = subtype[..<plus]
    let suffix = subtype[subtype.index(after: plus)...]
    return (suffix == "json" || suffix == "xml") && !prefix.isEmpty
      && prefix.unicodeScalars.allSatisfy { HTML.isASCIIAlphanumeric($0) || $0 == "_" || $0 == "." || $0 == "-" }
  }

  static let languages: [String: String] = [
    "sh": "bash", "bash": "bash", "zsh": "bash", "css": "css", "diff": "diff", "patch": "diff", "go": "go", "java": "java", "js": "javascript",
    "mjs": "javascript", "cjs": "javascript", "jsx": "javascript", "json": "json", "py": "python", "rb": "ruby", "rs": "rust", "sql": "sql",
    "html": "xml", "htm": "xml", "xml": "xml",
  ]

  /** `languageOf`: the language a file is written in, by its extension, where a code block highlights it. */
  public static func language(of name: String) -> String? {
    guard let dot = name.lastIndex(of: "."), name.index(after: dot) < name.endIndex else { return nil }
    return languages[name[name.index(after: dot)...].lowercased()]
  }

  /** A file's text as it shows: nil for bytes that aren't text (a NUL) or only spaces; line ends as `\n`, no last newline. */
  public static func shown(_ data: Data) -> (shown: String, copied: String)? {
    guard data.count <= maxShownTextSize, let text = String(data: data, encoding: .utf8), !text.contains("\0") else { return nil }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    var shown = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    if shown.hasSuffix("\n") { shown.removeLast() }
    return (shown, text)
  }

  /** Whether shown text folds behind Show more. */
  public static func isLong(_ shown: String) -> Bool {
    shown.utf16.count > foldCharacters || shown.split(separator: "\n", omittingEmptySubsequences: false).count > foldLines
  }
}

/** The web's words for huddles and threads. */
public enum MessageWords {
  /** `MAX_FACES`: how many faces a huddle's message shows. */
  public static let huddleFaces = 4
  static let maxNamed = 3

  /** `repliesLabel` */
  public static func replies(_ count: Int) -> String { count == 1 ? "1 reply" : "\(count) replies" }

  /** `toSentence`: "a and b", "a, b, and c". */
  public static func sentence(_ names: [String]) -> String {
    names.count <= 2 ? names.joined(separator: " and ") : names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
  }

  static func firstName(_ name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
  }

  static func othersCounted(_ count: Int) -> String { count == 1 ? "1 other" : "\(count) others" }

  /** `peopleListed` */
  static func peopleListed(_ names: [String], _ count: Int) -> String {
    if names.isEmpty { return count == 1 ? "1 person" : "\(count) people" }
    let named = names.prefix(maxNamed).map(firstName)
    return sentence(count > named.count ? named + [othersCounted(count - named.count)] : Array(named))
  }

  /** `inTheHuddle` */
  public static func inTheHuddle(_ others: [String]) -> String {
    if others.isEmpty { return "Just you in the huddle" }
    let everyone = others.count <= maxNamed ? sentence(others.map(firstName) + ["you"]) : peopleListed(others, others.count)
    return "\(everyone) are in the huddle"
  }

  /** `inItsHuddle` */
  public static func inItsHuddle(_ others: [String], count: Int, you: Bool) -> String {
    if you, others.count == count { return inTheHuddle(others) }
    let named = you ? [] : others
    let people = you ? count + 1 : count
    return "\(peopleListed(named, people)) \(people == 1 ? "is" : "are") in the huddle"
  }

  /** `wereInTheHuddle` */
  public static func wereInTheHuddle(_ others: [String], you: Bool) -> String {
    if others.isEmpty { return you ? "Only you were in the huddle" : "Nobody was in the huddle" }
    if others.count == 1, !you { return "\(firstName(others[0])) was in the huddle" }
    let everyone = you && others.count <= maxNamed ? sentence(others.map(firstName) + ["you"]) : peopleListed(others, others.count)
    return "\(everyone) were in the huddle"
  }

  static func counted(_ count: Int, _ one: String) -> String { count == 1 ? "1 \(one)" : "\(count) \(one)s" }

  /** `huddleLasted`: "less than a minute", "24 minutes", "1 hour and 5 minutes". */
  public static func huddleLasted(from start: Date, to end: Date) -> String {
    let minutes = Int((end.timeIntervalSince(start) / 60).rounded(.down))
    if minutes < 1 { return "less than a minute" }
    let hours = minutes / 60
    let left = minutes % 60
    if hours == 0 { return counted(left, "minute") }
    return left == 0 ? counted(hours, "hour") : "\(counted(hours, "hour")) and \(counted(left, "minute"))"
  }

  /** "A huddle is happening" or "A huddle happened". */
  public static func huddleTitle(_ huddle: MessageHuddle) -> String { huddle.endedAt == nil ? "A huddle is happening" : "A huddle happened" }

  /**
   * What a huddle's message says of it: who's in a live one (from the sidebar's last word of the room's
   * huddle, while it's the one that started when the message says), or who was in one that's over, and
   * for how long. Nil where a live one has nobody known in it.
   */
  public static func huddleSummary(_ huddle: MessageHuddle, live: LiveHuddle?, me: UserID?, name: (UserID) -> String?) -> String? {
    if huddle.endedAt == nil {
      let inIt = live?.startedAt == huddle.startedAt ? (live?.userIds ?? []) : []
      guard !inIt.isEmpty else { return nil }
      let others = inIt.filter { $0 != me }
      return inItsHuddle(others.compactMap(name), count: others.count, you: others.count < inIt.count)
    }
    let inIt = huddle.people ?? []
    let others = inIt.filter { $0.id != me }
    let names = others.map { name($0.id) ?? $0.name }
    var lasted = ""
    if let endedAt = huddle.endedAt, let end = EmberDate.parse(endedAt), let start = EmberDate.parse(huddle.startedAt) {
      lasted = " for " + huddleLasted(from: start, to: end)
    }
    return wereInTheHuddle(names, you: others.count < inIt.count) + lasted
  }

  /** `lastReplyLabel`: "today at 3:04 PM", "yesterday at 3:04 PM", "on Oct 12", "on Oct 12, 2025". */
  public static func lastReply(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    let time = date.formatted(date: .omitted, time: .shortened)
    if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday at \(time)" }
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    return "on " + (sameYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.month(.abbreviated).day().year()))
  }

  /** `huddleStartedLabel`: "Today at 3:04 PM", "Yesterday at 3:04 PM", "Oct 12", or "Oct 12, 2025" in another year. */
  public static func huddleStarted(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    let time = date.formatted(date: .omitted, time: .shortened)
    if calendar.isDate(date, inSameDayAs: now) { return "Today at \(time)" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday at \(time)" }
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    return sameYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.month(.abbreviated).day().year())
  }

  /** `dateTimeLabel`: a moment's date and time, as a card's footer and a message's time say it on hover. */
  public static func dateTime(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
}
