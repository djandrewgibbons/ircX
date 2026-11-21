import Foundation

// apps/web/src/lib/search.ts: searches as the search box writes them, words and the modifiers Slack names.

extension Search.Flag {
  /** What the box and the results page call each filter (`FLAG_LABELS`). */
  public var label: String {
    switch self {
    case .withMe: "Includes me"
    case .hasLink: "Has a link"
    case .hasFile: "Has a file"
    case .inThread: "Threads only"
    }
  }

  /** The flag `key:value` names, such as `has:link` (`flagNamed`). */
  public static func named(_ key: String, _ value: String) -> Search.Flag? {
    allCases.first { $0.key == key.lowercased() && $0.value == value.lowercased() }
  }
}

extension Search {
  public mutating func set(_ flag: Flag, _ on: Bool) {
    let value: Bool? = on ? true : nil
    switch flag {
    case .withMe: withMe = value
    case .hasLink: hasLink = value
    case .hasFile: hasFile = value
    case .inThread: inThread = value
    }
  }

  /** The same search, its words' spaces made one (`normalizedSearch`). */
  public var normalized: Search {
    var search = self
    search.q = q.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return search
  }
}

/** A modifier being typed at the end of the words (`TypedModifier`). */
public struct TypedModifier: Equatable, Sendable {
  public var key: String
  public var value: String
}

extension Searches {
  /** The modifier being typed at the end of `text`, after a space or at its start (`modifierTyped`). */
  public static func modifierTyped(_ text: String) -> TypedModifier? {
    let last = text.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? text
    guard let colon = last.firstIndex(of: ":") else { return nil }
    let key = last[..<colon].lowercased()
    guard ["in", "from", "has", "is", "with"].contains(key) else { return nil }
    let value = String(last[last.index(after: colon)...])
    guard !value.contains(where: \.isWhitespace) else { return nil }
    return TypedModifier(key: key, value: value)
  }

  /**
   * What a typed search has once the modifiers it names in full are filters (`withTypedFilters`):
   * `has:`, `is:` and `with:` flags, and `from:me`. `resolve` names a room for `in:` and a person for
   * `from:`, which the web's box picks from its lists; one it can't stays a word.
   */
  public static func withTypedFilters(
    _ search: Search, me: UserID, room: (String) -> RoomID? = { _ in nil }, person: (String) -> UserID? = { _ in nil }
  ) -> (search: Search, sort: SearchSort?) {
    var result = search
    var sort: SearchSort?
    var words: [String] = []
    for word in search.q.split(whereSeparator: \.isWhitespace).map(String.init) {
      guard let colon = word.firstIndex(of: ":"), colon != word.startIndex else {
        words.append(word)
        continue
      }
      let key = word[..<colon].lowercased()
      let value = String(word[word.index(after: colon)...])
      if key == "from", ["me", "@me"].contains(value.lowercased()) {
        result.from = me
      } else if let flag = Search.Flag.named(key, value) {
        result.set(flag, true)
      } else if key == "in", let id = room(value) {
        result.in = id
      } else if key == "from", let id = person(value) {
        result.from = id
      } else if key == "sort", let named = SearchSort(rawValue: value.lowercased()) {
        sort = named
      } else {
        words.append(word)
      }
    }
    result.q = words.joined(separator: " ")
    return (result.normalized, sort)
  }

  /**
   * Where `words` match in `text` (`marksFor`): each whole, however it's cased, longest first, never
   * inside a longer word.
   */
  public static func marks(_ words: [String], in text: String) -> [Range<String.Index>] {
    let sought = words.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    guard !sought.isEmpty else { return [] }
    var found: [Range<String.Index>] = []
    var index = text.startIndex
    func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c.unicodeScalars.contains { $0.properties.generalCategory == .nonspacingMark } }
    while index < text.endIndex {
      let startsWord = index == text.startIndex || !isWordCharacter(text[text.index(before: index)])
      var matched: Range<String.Index>?
      if startsWord {
        for word in sought {
          guard let range = text.range(of: word, options: [.caseInsensitive, .anchored], range: index..<text.endIndex) else { continue }
          if range.upperBound == text.endIndex || !isWordCharacter(text[range.upperBound]) {
            matched = range
            break
          }
        }
      }
      if let matched {
        found.append(matched)
        index = matched.upperBound
      } else {
        index = text.index(after: index)
      }
    }
    return found
  }
}
