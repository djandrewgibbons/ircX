import Foundation
import os

/**
 * The emoji the composer's Emoji panel offers, as the web's panel (frimousse over Emojibase) offers them:
 * Emojibase's data, bundled (`Resources/emoji.json`, made from emojibase-data 18.0.0's `en/data.json` and
 * `en/messages.json`), in its groups and order without Components, each with its label, its keywords for
 * search, and its five skin-tone forms where it has them. Sequences, flags and keycaps included.
 */
public enum EmojiCatalog {
  public struct Emoji: Hashable, Sendable, Identifiable {
    public var id: String { glyph }
    public var glyph: String
    /** Its label, capitalised as the web shows it ("Grinning face"). */
    public var name: String
    /** Emojibase's keywords, which search matches as well as the label. */
    public var tags: [String]
    /** Its forms in the light to dark tones, where it takes one. */
    public var skins: [String]

    public var toned: Bool { skins.count == 5 }

    /** The emoji in `tone`, where it takes one. */
    public func glyph(in tone: SkinTone) -> String {
      guard toned, let index = tone.index else { return glyph }
      return skins[index]
    }
  }

  public struct Group: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var emoji: [Emoji]
  }

  /** The web panel's skin tones (`emoji-skin-tone`). */
  public enum SkinTone: String, CaseIterable, Sendable, Identifiable {
    case none, light, mediumLight = "medium-light", medium, mediumDark = "medium-dark", dark

    public var id: String { rawValue }

    /** Its place among an emoji's `skins`. */
    var index: Int? {
      switch self {
      case .none: nil
      case .light: 0
      case .mediumLight: 1
      case .medium: 2
      case .mediumDark: 3
      case .dark: 4
      }
    }

    /** A raised hand in the tone, for the tone picker. */
    public var sample: String {
      switch self {
      case .none: "\u{270B}"
      case .light: "\u{270B}\u{1F3FB}"
      case .mediumLight: "\u{270B}\u{1F3FC}"
      case .medium: "\u{270B}\u{1F3FD}"
      case .mediumDark: "\u{270B}\u{1F3FE}"
      case .dark: "\u{270B}\u{1F3FF}"
      }
    }

    public var label: String {
      switch self {
      case .none: "Default"
      case .light: "Light"
      case .mediumLight: "Medium-light"
      case .medium: "Medium"
      case .mediumDark: "Medium-dark"
      case .dark: "Dark"
      }
    }
  }

  /** The bundled file: `groups` as [order, label], each emoji as [glyph, label, group, tags, skins], tags and skins joined by `|`. */
  private struct File: Decodable {
    var groups: [[String]]
    var emoji: [[String]]
  }

  private static let log = Logger(subsystem: "ai.dxnd.ircX", category: "emoji")

  /** Every group in Emojibase's order, its emoji in Emojibase's order; none, logged, if the bundled data can't be read. */
  public static let groups: [Group] = {
    guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json") else {
      log.error("The emoji data isn't in the bundle")
      return []
    }
    do {
      let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
      var byGroup: [String: [Emoji]] = [:]
      for entry in file.emoji where entry.count == 5 {
        let split = { (joined: String) in joined.isEmpty ? [] : joined.components(separatedBy: "|") }
        byGroup[entry[2], default: []].append(Emoji(glyph: entry[0], name: entry[1], tags: split(entry[3]), skins: split(entry[4])))
      }
      return file.groups.compactMap { pair in
        guard pair.count == 2, let emoji = byGroup[pair[0]] else { return nil }
        return Group(name: pair[1], emoji: emoji)
      }
    } catch {
      log.error("The emoji data didn't read: \(error.localizedDescription, privacy: .public)")
      return []
    }
  }()

  /**
   * The emoji `query` finds, as the web panel's search does: those whose label has it (ten points) or
   * any of whose keywords have it (a point each), best first, ties in Emojibase's order; every emoji for none.
   */
  public static func search(_ query: String) -> [Emoji] {
    let all = groups.flatMap(\.emoji)
    let wanted = query.lowercased().trimmingCharacters(in: .whitespaces)
    guard !wanted.isEmpty else { return all }
    let scored = all.enumerated().compactMap { index, emoji -> (Int, Int, Emoji)? in
      var score = emoji.name.lowercased().contains(wanted) ? 10 : 0
      score += emoji.tags.filter { $0.lowercased().contains(wanted) }.count
      return score > 0 ? (score, index, emoji) : nil
    }
    return scored.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }.map(\.2)
  }
}
