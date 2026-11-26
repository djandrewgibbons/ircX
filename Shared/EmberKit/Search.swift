import Foundation

// packages/protocol/src/search.ts and reports.ts.

/** A search (`Search`): its words, and the filters on it (`SearchFilters`). */
public struct Search: Codable, Hashable, Sendable {
  public var q: String
  public var `in`: RoomID?
  public var from: UserID?
  public var withMe: Bool?
  public var hasLink: Bool?
  public var hasFile: Bool?
  public var inThread: Bool?

  public init(q: String, in room: RoomID? = nil, from: UserID? = nil, withMe: Bool = false, hasLink: Bool = false, hasFile: Bool = false, inThread: Bool = false) {
    self.q = q
    self.in = room
    self.from = from
    self.withMe = withMe ? true : nil
    self.hasLink = hasLink ? true : nil
    self.hasFile = hasFile ? true : nil
    self.inThread = inThread ? true : nil
  }

  /** `SEARCH_FLAGS`: each flag's query key and value. */
  public enum Flag: String, CaseIterable, Sendable {
    case withMe, hasLink, hasFile, inThread

    public var key: String {
      switch self {
      case .withMe: "with"
      case .hasLink, .hasFile: "has"
      case .inThread: "is"
      }
    }

    public var value: String {
      switch self {
      case .withMe: "me"
      case .hasLink: "link"
      case .hasFile: "file"
      case .inThread: "thread"
      }
    }
  }

  public func has(_ flag: Flag) -> Bool {
    switch flag {
    case .withMe: withMe == true
    case .hasLink: hasLink == true
    case .hasFile: hasFile == true
    case .inThread: inThread == true
    }
  }

  /** `hasFilters` */
  public var hasFilters: Bool { self.in != nil || from != nil || Flag.allCases.contains(where: has) }
  /** `isSearchable`: it has a word, or a filter. */
  public var isSearchable: Bool { Searches.hasWords(q) || hasFilters }
}

public enum SearchSort: String, Codable, Sendable {
  case newest, oldest
}

/** A message a search found, and the words in it that matched (`SearchMatch`). */
public struct SearchMatch: Codable, Hashable, Sendable {
  public var message: Message
  public var words: [String]
}

/** What `GET` and `POST /api/searches` answer (`SearchResults`). */
public struct SearchResults: Codable, Sendable {
  public var search: Search?
  public var matches: [SearchMatch]
  /** The cursor for the next page, or nil after the last. */
  public var next: Int?
  public var rooms: [Room]
  public var recent: [Search]
}

public enum Searches {
  public static let limit = 100
  public static let maxSearchLength = 1_000
  public static let searchTooLong = "Searches can be up to 1,000 characters."
  public static let recentSearches = 10
  public static let path = "/searches"

  /** `sanitizeSearch`: everything but letters, marks, digits, connector punctuation and joiners as spaces. */
  public static func sanitize(_ q: String) -> String {
    String(String.UnicodeScalarView(q.unicodeScalars.map { isSearched($0) ? $0 : " " }))
  }

  /** `hasWords` */
  public static func hasWords(_ q: String) -> Bool { sanitize(q).contains { !$0.isWhitespace } }

  /** `searchWords` */
  public static func words(_ q: String) -> [String] { sanitize(q).split(whereSeparator: \.isWhitespace).map(String.init) }

  /** `searchQuery`: the query string `GET /api/searches` takes, with `+` for spaces. */
  public static func query(_ search: Search, sort: SearchSort = .newest, cursor: Int? = nil) -> String {
    var params: [(String, String)] = [("q", search.q)]
    if let room = search.in { params.append(("in", room)) }
    if let from = search.from { params.append(("from", from)) }
    for flag in Search.Flag.allCases where search.has(flag) { params.append((flag.key, flag.value)) }
    if sort != .newest { params.append(("sort", sort.rawValue)) }
    if let cursor { params.append(("cursor", String(cursor))) }
    return params.map { "\($0.0)=\(URIComponent.encode($0.1).replacingOccurrences(of: "%20", with: "+"))" }.joined(separator: "&")
  }

  private static func isSearched(_ s: Unicode.Scalar) -> Bool {
    let p = s.properties
    if p.isAlphabetic || p.isJoinControl { return true }
    switch p.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .connectorPunctuation: return true
    default: return false
    }
  }
}

// MARK: - Reports

public enum ReportReason: String, Codable, Sendable, CaseIterable {
  case spam, harassment, other

  /** `REPORT_REASON_LABELS` */
  public var label: String {
    switch self {
    case .spam: "Spam"
    case .harassment: "Harassment"
    case .other: "Something else"
    }
  }
}

public enum ReportOutcome: String, Codable, Sendable, CaseIterable {
  case deleted, removed, banned, dismissed
}

/** A report to send of a message or someone (`NewReport`). */
public struct NewReport: Codable, Sendable {
  public var reason: ReportReason
  public var note: String

  public init(reason: ReportReason, note: String) {
    self.reason = reason
    self.note = note
  }
}

/** A reported message as administrators see it (`ReportedMessage`). */
public struct ReportedMessage: Codable, Hashable, Sendable {
  public struct File: Codable, Hashable, Sendable {
    public var name: String
    public var contentType: String
    public var byteSize: Int
  }

  public var id: String
  public var creator: User
  public var body: String
  public var plainText: String
  public var mentions: [User]
  public var createdAt: String
  public var editedAt: String?
  public var attachment: File?
  public var cards: [Card]?
  public var parentId: String?
  public var accountDeleted: Bool?
}

/** A reported person as administrators see them (`ReportedPerson`). */
public struct ReportedPerson: Codable, Hashable, Sendable {
  public var id: UserID
  public var name: String
  public var bio: String?
  public var accountDeleted: Bool?
}

/** What a report is of (`ReportSubject`, by its `kind`). */
public enum ReportSubject: Codable, Hashable, Sendable {
  public struct RoomOf: Codable, Hashable, Sendable {
    public var kind: RoomKind
    public var name: String?
  }

  case message(roomId: RoomID, room: RoomOf, message: ReportedMessage)
  case person(ReportedPerson)

  private enum Keys: String, CodingKey { case kind, roomId, room, message, person }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    switch try c.decode(String.self, forKey: .kind) {
    case "message":
      self = .message(roomId: try c.decode(String.self, forKey: .roomId), room: try c.decode(RoomOf.self, forKey: .room), message: try c.decode(ReportedMessage.self, forKey: .message))
    case "person": self = .person(try c.decode(ReportedPerson.self, forKey: .person))
    case let kind: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown report subject \(kind)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    switch self {
    case let .message(roomId, room, message):
      try c.encode("message", forKey: .kind)
      try c.encode(roomId, forKey: .roomId)
      try c.encode(room, forKey: .room)
      try c.encode(message, forKey: .message)
    case let .person(person):
      try c.encode("person", forKey: .kind)
      try c.encode(person, forKey: .person)
    }
  }
}

public struct Report: Codable, Hashable, Sendable, Identifiable {
  public struct Handled: Codable, Hashable, Sendable {
    public var by: UserID
    public var at: String
    public var outcome: ReportOutcome
  }

  public var id: String
  public var reporterId: UserID
  public var reason: ReportReason
  public var note: String
  public var reportedAt: String
  public var subject: ReportSubject
  public var handled: Handled?

  /** `isOfDeletedAccount` */
  public var isOfDeletedAccount: Bool {
    switch subject {
    case let .message(_, _, message): message.accountDeleted == true
    case let .person(person): person.accountDeleted == true
    }
  }
}

/** What `GET /api/reports` answers (`Reports`). */
public struct Reports: Codable, Sendable {
  public var open: [Report]
  public var handled: [Report]
}

/** `HandledReports` */
public struct HandledReports: Codable, Sendable {
  public var reports: [Report]
}

public enum Reporting {
  public static let maxNoteLength = 500
  public static let openReportsListed = 100
  public static let handledReportsListed = 50
  public static let reasonRefused = "Choose why you're reporting it."
  public static let noteRefused = "Say why in 500 characters or fewer."
  /** Where administrators handle reports (`REPORTS_PATH`). */
  public static let path = "/account/edit#membership-settings"
}

extension Searches {
  /**
   * The search a results page's address holds (`searchOfQuery`): its words, a room and a person that are
   * ids, the flags it names, and its sort, from a query string such as `q=lunch+plans&has=link`.
   */
  public static func search(ofQuery query: String) -> (search: Search, sort: SearchSort) {
    var params: [(String, String)] = []
    for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let decode = { (raw: Substring) -> String in
        let spaced = raw.replacingOccurrences(of: "+", with: " ")
        guard let decoded = spaced.removingPercentEncoding else { return spaced }
        return decoded
      }
      guard let key = parts.first else { continue }
      params.append((decode(key), parts.count > 1 ? decode(parts[1]) : String()))
    }
    let first = { (key: String) -> String? in params.first { $0.0 == key }?.1 }
    let isId = { (text: String?) -> String? in
      guard let text, !text.isEmpty, text.utf16.count <= EmberLimits.maxIdLength else { return nil }
      return text
    }
    var search = Search(q: first("q") ?? String(), in: isId(first("in")), from: isId(first("from")))
    for flag in Search.Flag.allCases where params.contains(where: { $0.0 == flag.key && $0.1 == flag.value }) { search.set(flag, true) }
    return (search, first("sort") == SearchSort.oldest.rawValue ? .oldest : .newest)
  }
}
