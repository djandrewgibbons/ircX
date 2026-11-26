import Foundation
import OSLog

// The icon pickers' catalog (web `icons/picker/catalog.json`, bundled without its drawings as
// `Resources/icon-catalog.json`) and its search (web `icon-catalog.ts`): the catalog's orders do the
// editorial ranking, and a search keeps them, putting the icons named for it before those only tagged for it.

/** What the picker offers an icon for (`IconContext`): a room's purpose, or one of the rail's buttons. */
public enum IconContext: String, Sendable {
  case room, navigation
}

/** Where an icon comes from, or, for the picker's tabs, either (`IconCollection`). */
public enum IconCollection: String, CaseIterable, Identifiable, Sendable {
  case all = "All"
  case lucide = "Lucide"
  case iconoir = "Iconoir"

  public var id: String { rawValue }
}

extension RoomIcons {
  /** An icon as the catalog has it (`CatalogIcon`), without its drawing, which the instance serves. */
  public struct CatalogIcon: Codable, Hashable, Sendable {
    public var name: String
    public var label: String
    /** For an icon suggested for a room, what the room is for, such as Engineering for code-xml. */
    public var roomLabel: String?
    public var collection: String
    public var tags: [String]
  }

  private struct CatalogFile: Decodable {
    var icons: [CatalogIcon]
    /** Indexes into `icons`. */
    var roomOrder: [Int]
    var navigationOrder: [Int]
  }

  /** The catalog ready to search: each icon's words, in each context's order. */
  private struct Prepared: Sendable {
    struct Entry: Sendable {
      let icon: CatalogIcon
      let searchName: String
      let searchRoomName: String
      let searchTags: String
    }

    let room: [Entry]
    let navigation: [Entry]
  }

  private static let log = Logger(subsystem: "ai.dxnd.ircX", category: "icons")

  private static let prepared: Prepared = {
    guard let url = Bundle.module.url(forResource: "icon-catalog", withExtension: "json") else {
      log.error("The icon catalog isn't in the bundle")
      return Prepared(room: [], navigation: [])
    }
    do {
      let file = try JSONDecoder().decode(CatalogFile.self, from: Data(contentsOf: url))
      let entries = file.icons.map { icon in
        Prepared.Entry(
          icon: icon, searchName: searchable("\(icon.name) \(icon.label)"),
          searchRoomName: searchable([icon.name, icon.label, icon.roomLabel].compactMap { $0 }.joined(separator: " ")),
          searchTags: searchable(icon.tags.joined(separator: " ")))
      }
      let ordered = { (order: [Int]) in order.filter(entries.indices.contains).map { entries[$0] } }
      return Prepared(room: ordered(file.roomOrder), navigation: ordered(file.navigationOrder))
    } catch {
      log.error("The icon catalog didn't decode: \(error.localizedDescription, privacy: .public)")
      return Prepared(room: [], navigation: [])
    }
  }()

  /** Text as search compares it: lowercase words between spaces, so a short term can match a whole word. */
  static func searchable(_ text: String) -> String {
    var words: [String] = []
    var word = ""
    for character in text.lowercased() {
      if character.isLetter || character.isNumber {
        word.append(character)
      } else if !word.isEmpty {
        words.append(word)
        word = ""
      }
    }
    if !word.isEmpty { words.append(word) }
    return " \(words.joined(separator: " ")) "
  }

  /** Whether `text` holds `term`, as a whole word when it's two letters or fewer, so "hr" doesn't find thrush. */
  private static func includes(_ text: String, _ term: String) -> Bool {
    text.contains(term.count <= 2 ? " \(term) " : term)
  }

  /** What the picker calls an icon (`displayLabel`): for a room, what the room is for, where the catalog suggests it for one. */
  public static func displayLabel(_ icon: CatalogIcon, context: IconContext) -> String {
    if context == .room, let roomLabel = icon.roomLabel, !roomLabel.isEmpty { return roomLabel }
    return icon.label
  }

  /**
   * The icons of `collection` that match every word of `query`, in `context`'s order (`searchIcons`):
   * first those the search names exactly, then those whose names hold every word, then those whose tags
   * hold the rest. With no words, the whole order.
   */
  public static func search(_ query: String, context: IconContext, collection: IconCollection = .all) -> [CatalogIcon] {
    let all = context == .room ? prepared.room : prepared.navigation
    let ordered = collection == .all ? all : all.filter { $0.icon.collection == collection.rawValue }
    let phrase = searchable(query).trimmingCharacters(in: .whitespaces)
    let terms = phrase.split(separator: " ").map(String.init)
    guard !terms.isEmpty else { return ordered.map(\.icon) }
    let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
    var exact: [CatalogIcon] = []
    var named: [CatalogIcon] = []
    var tagged: [CatalogIcon] = []
    for entry in ordered {
      let name = context == .room ? entry.searchRoomName : entry.searchName
      if displayLabel(entry.icon, context: context).lowercased() == phrase || entry.icon.label.lowercased() == phrase || entry.icon.name == typed {
        exact.append(entry.icon)
      } else if terms.allSatisfy({ includes(name, $0) }) {
        named.append(entry.icon)
      } else if terms.allSatisfy({ includes(name, $0) || includes(entry.searchTags, $0) }) {
        tagged.append(entry.icon)
      }
    }
    return exact + named + tagged
  }
}
