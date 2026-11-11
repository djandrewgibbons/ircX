import Foundation

/**
 * Message bodies as the app writes them: the markup Ember's composer would, a `<p>` per line, with
 * `@name` turned into a mention attachment Ember resolves (`packages/richtext/src/mentions.ts`).
 * Messages are shown by their plain text, which Ember works out from the markup, as an IRC client would.
 */
public enum MessageBody {
  public static let mentionContentType = "application/vnd.campfire.mention"

  /** Markup for `text`, mentioning whichever of `people` it names as `@name`, longest names first. */
  public static func markup(for text: String, mentioning people: [User] = []) -> String {
    let byLength = people.filter { !$0.name.isEmpty }.sorted { $0.name.count > $1.name.count }
    var text = text.replacingOccurrences(of: "\r\n", with: "\n")
    // IRC's way of addressing someone, `Ada: hi`, mentions them too.
    if let person = byLength.first(where: { text.lowercased().hasPrefix($0.name.lowercased() + ":") || text.lowercased().hasPrefix($0.name.lowercased() + ",") }) {
      text = "@" + person.name + text.dropFirst(person.name.count)
    }
    let lines = text.components(separatedBy: "\n")
    return lines.map { "<p>\(paragraph($0, byLength))</p>" }.joined()
  }

  /** Markup for `/me waves`: the author's name and the action, in one `<em>`, which IRC clients show as `* nick waves`. */
  public static func actionMarkup(for action: String, by nick: String, mentioning people: [User] = []) -> String {
    let byLength = people.filter { !$0.name.isEmpty }.sorted { $0.name.count > $1.name.count }
    return "<p><em>\(escape(nick)) \(paragraph(action, byLength))</em></p>"
  }

  /** Whether a body is a /me action: one paragraph whose whole content is an `<em>` starting with its author's name. */
  public static func isAction(body: String, plainText: String, author: String) -> Bool {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    let wrapped = (trimmed.hasPrefix("<p><em>") && trimmed.hasSuffix("</em></p>")) || (trimmed.hasPrefix("<div><em>") && trimmed.hasSuffix("</em></div>"))
    return wrapped && plainText.hasPrefix(author + " ") && !trimmed.dropFirst(7).dropLast(9).contains("</em>")
  }

  /** The action of a /me message, after its author's name. */
  public static func actionText(plainText: String, author: String) -> String {
    String(plainText.dropFirst(author.count + 1))
  }

  public static func mention(_ user: User) -> String {
    "<action-text-attachment sgid=\"\(escape(user.id))\" content-type=\"\(mentionContentType)\"></action-text-attachment>"
  }

  public static func escape(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.count)
    for c in text {
      switch c {
      case "&": out += "&amp;"
      case "<": out += "&lt;"
      case ">": out += "&gt;"
      case "\"": out += "&quot;"
      case "'": out += "&#39;"
      default: out.append(c)
      }
    }
    return out
  }

  private static func paragraph(_ line: String, _ people: [User]) -> String {
    guard !line.isEmpty else { return "<br>" }
    guard !people.isEmpty, line.contains("@") else { return escape(line) }
    var out = ""
    var plain = ""
    var i = line.startIndex
    while i < line.endIndex {
      let c = line[i]
      // Only at a word's start, so an email address isn't a mention.
      let startsWord = i == line.startIndex || !isWordCharacter(line[line.index(before: i)])
      if c == "@", startsWord {
        let after = line[line.index(after: i)...]
        if let person = people.first(where: { after.lowercased().hasPrefix($0.name.lowercased()) && endsWord(after.dropFirst($0.name.count)) }) {
          out += escape(plain) + mention(person)
          plain = ""
          i = line.index(i, offsetBy: person.name.count + 1)
          continue
        }
      }
      plain.append(c)
      i = line.index(after: i)
    }
    return out + escape(plain)
  }

  private static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

  private static func endsWord(_ rest: Substring) -> Bool {
    guard let next = rest.first else { return true }
    return !isWordCharacter(next)
  }
}

/** What someone typed in the input line: a message, or one of the IRC commands the app understands. */
public enum InputCommand: Equatable, Sendable {
  case say(String)
  case me(String)
  /** `/join #room`: open, or create, a room by name. */
  case join(String)
  /** `/msg nick text` or `/query nick`: open a DM, and send to it if there's text. */
  case msg(nick: String, text: String?)
  /** `/part`: close the buffer. */
  case part
  /** `/topic`, `/names`, `/whois nick`: things the status line answers. */
  case names
  case whois(String)
  /** `/server host`: add an instance. */
  case server(String)
  case help
  case unknown(String)

  public static func parse(_ input: String) -> InputCommand? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    // `//text` and `/ text` send text that starts with a slash, as irssi does.
    guard text.hasPrefix("/"), !text.hasPrefix("//"), !text.hasPrefix("/ ") else {
      return .say(text.hasPrefix("//") ? String(text.dropFirst()) : input.trimmingCharacters(in: .newlines))
    }
    let parts = text.dropFirst().split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let name = parts.first.map { $0.lowercased() } ?? ""
    let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
    switch name {
    case "me": return rest.isEmpty ? .unknown("/me needs something to do") : .me(rest)
    case "join", "j":
      let room = rest.hasPrefix("#") ? String(rest.dropFirst()) : rest
      return room.isEmpty ? .unknown("/join needs a room") : .join(room)
    case "msg", "query", "q":
      let pieces = rest.split(separator: " ", maxSplits: 1)
      guard let nick = pieces.first else { return .unknown("/\(name) needs a nick") }
      let body = pieces.count > 1 ? String(pieces[1]) : nil
      return .msg(nick: String(nick), text: body)
    case "part", "close", "wc": return .part
    case "names", "who": return .names
    case "whois", "wi": return rest.isEmpty ? .unknown("/whois needs a nick") : .whois(rest)
    case "server", "connect": return rest.isEmpty ? .unknown("/server needs an address") : .server(rest)
    case "help", "?": return .help
    default: return .unknown("Unknown command: /\(name)")
    }
  }

  public static let helpText = """
    /join #room · /msg nick text · /query nick · /me action · /part · /names · /whois nick · /server host · //text sends a slash
    """
}
