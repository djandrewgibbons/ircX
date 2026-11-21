import Foundation

/**
 * Message bodies as the app writes them: the markup Ember's composer would, a `<p>` per line, with
 * `@name` turned into a mention attachment Ember resolves (`packages/richtext/src/mentions.ts`).
 * Messages are shown by their plain text, which Ember works out from the markup, as an IRC client would.
 */
public enum MessageBody {
  public static let mentionContentType = "application/vnd.campfire.mention"

  /** Markup for `text`, mentioning whichever of `people` it names as `@name`, longest names first. */
  /**
   * As `markup(for:mentioning:)`, with a link's preview attachment below the first paragraph that has
   * `link`, as the web composer inserts one below a pasted link's paragraph, or at the end.
   */
  public static func markup(for text: String, mentioning people: [User] = [], preview: (attachment: String, link: String)?) -> String {
    guard let preview else { return markup(for: text, mentioning: people) }
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    let below = lines.firstIndex { $0.contains(preview.link) } ?? lines.count - 1
    let before = lines[...below].joined(separator: "\n")
    let after = lines[(below + 1)...].joined(separator: "\n")
    return markup(for: before, mentioning: people) + preview.attachment + (below + 1 < lines.count ? markup(for: after, mentioning: people) : "")
  }

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
  /** `/join #room`: open a room by name; it never creates one. */
  case join(String)
  /** `/msg nick text`: open a DM, and send to it if there's text. */
  case msg(nick: String, text: String?)
  /** `/query nick [nick...]`: open, or start, a DM with one or more people. */
  case query([String])
  /** `/part`: close the window, here only. */
  case part
  /** `/leave`: take yourself out of a private room. */
  case leave
  /** `/back`, `/forward`: through the pages visited, as the web's Back and Forward. */
  case back, forward
  /** `/star [#room]`, `/unstar [#room]`: the open room, or the one named. */
  case star(String?, Bool)
  /** `/move up|down|top`: the open starred room among the starred. */
  case move(StarMove)
  /** `/notify [#room] [level]`: a room's notification level (the open one's without #room), or print it. */
  case notify(Involvement?, room: String? = nil)
  /** `/push [on|off|list|test [id]|delete id]`: this device's notifications from this server, and your devices and browsers. */
  case push(PushAction)
  /** `/hide [#room]`, `/unhide #room`: hide a room from the sidebar, or show it again. */
  case hide(String?, Bool)
  /** `/newroom [-p] #name [nick...]` (and `/create`): make a room, private with `-p`. */
  case newRoom(name: String, closed: Bool, nicks: [String])
  /** `/rename name`: rename the open room. */
  case rename(String)
  /** `/room`: print the open room's settings. */
  case room
  /** `/open`: make the open room open to everyone. */
  case makeOpen
  /** `/private [nick...]`: make the open room private, to its members and those named. */
  case makePrivate([String])
  /** `/invite [nick]`: give someone the open private room, or print the join link. */
  case invite(String?)
  /** `/kick nick`: take someone out of the open private room. */
  case kick(String)
  /** `/deleteroom`: delete the open room or DM, after asking. */
  case deleteRoom
  /** `/dismiss`: dismiss the welcome card. */
  case dismiss
  /** `/search words [in:#room from:nick has:link has:file is:thread with:me sort:oldest]`. */
  case search(String)
  /** `/more`: the search's next page. */
  case more
  /** `/searches [clear]`: recent searches, or clear them. */
  case searches(clear: Bool)
  /** `/goto n`: open the nth search result in its room. */
  case goto(Int)
  /** `/activity`: show only unread conversations, or everything again. */
  case activity
  /** `/ban nick`, `/unban nick`: administrators only. */
  case ban(String, Bool)
  /** `/home`: the room last visited. */
  case home
  /** `/topic`, `/names`, `/whois nick`: things the status line answers. */
  case names
  case whois(String)
  /** `/server host`: add an instance. */
  case server(String)
  case help
  /** `/help shortcuts`, `/keys`: the keyboard shortcuts. */
  case shortcuts
  /** `/edit [n] [text]`: replace the text of your nth-newest message (your newest without n), or start editing it. */
  case edit(Int?, String?)
  /** `/quote [n]`: quote the nth-newest message (the newest without n) in the input line. */
  case quote(Int?)
  /** `/del [n]`: delete your nth-newest message, after asking. */
  case delete(Int?)
  /** `/copy [n]`: copy the nth-newest message's text. */
  case copy(Int?)
  /** `/link [n]`: copy the nth-newest message's link. */
  case link(Int?)
  /** `/react content [n]`: react to the nth-newest message with an emoji or a word. */
  case react(String, Int?)
  /** `/thread [n]`: open the nth-newest message's thread. */
  case thread(Int?)
  /** `/upload`: pick files to send. */
  case upload
  /** `/snippet [title]`: write a text snippet. */
  case snippet(String)
  /** `/report [n]`: report the nth-newest message. */
  case report(Int?)
  /** `/report nick`: report someone. */
  case reportPerson(String)
  /** `/ignore nick`, `/unignore nick`: block or unblock someone. */
  case ignore(String, Bool)
  /** `/ignore`: list the people you've blocked. */
  case ignored
  /** `/profile [link]`: open your profile, or copy your sign-in link. */
  case profile(link: Bool)
  /** `/profile connect|disconnect sso|memberful`: connect or disconnect an account elsewhere, on your profile. */
  case profileElsewhere(connect: Bool, memberful: Bool)
  /** `/nick name`, `/username name`, `/bio text`, `/email address`: change one of your profile's fields. */
  case setProfile(ProfileField, String)
  /** `/passwd`: change your password, on your profile, where it's never printed. */
  case passwd
  /** `/avatar [remove]`: choose a photo on your profile, or remove yours. */
  case avatar(remove: Bool)
  /** `/apps [signin|signout name]`: your sign-ins to connected apps. */
  case apps(AppsAction)
  /** `/ai [disconnect name]`: the AI apps connected as you. */
  case ai(disconnect: String?)
  /** `/sounds [music|chimes|ring on|off]`: which huddle sounds you hear. */
  case sounds(HuddleSound?, Bool?)
  /** `/appearance [light|dark|system]`: the Suite theme's appearance. */
  case appearance(String?)
  /** `/quit`, `/logout`: log out of this server. */
  case quit
  /** `/delete-account`: open Delete my account on your profile; it never deletes from here. */
  case deleteAccount
  /** `/end`: back to the newest messages. */
  case end
  /** Workspace settings, for administrators (`AdminCommand`). */
  case admin(AdminCommand)
  /** `/huddle …`, `/mute`, `/unmute`, `/hand`: the room's huddle (`HuddleAction`). */
  case huddle(HuddleAction)
  case unknown(String)

  public enum StarMove: String, Sendable { case up, down, top }
  public enum ProfileField: String, Sendable { case name, username, bio, emailAddress }
  public enum HuddleSound: String, Sendable, CaseIterable { case music, chimes, ring }
  /** What `/huddle` does. */
  public enum HuddleAction: Equatable, Sendable {
    /** `/huddle`: the preview; `/huddle -m`, `/huddle +cam`: joins at once, muted, or with the camera on. */
    case start(muted: Bool, camera: Bool, preview: Bool)
    /** `/huddle join [#room]`: the huddle an invitation rings for, or the room's. */
    case join(String?)
    /** `/huddle decline [#room]` */
    case decline(String?)
    case leave, link, open, close, list, who, thread
    case mute(Bool)
    case camera(Bool)
    case screen(Bool)
    /** `/hand`: raises the hand, or lowers it. */
    case hand
    /** `/huddle sticker name|off` */
    case sticker(HuddleSticker?)
    case react(String)
    /** `/huddle invite [nick…]`: rings them, or with nobody named, the list to pick from. */
    case invite([String])
  }

  /** What `/push` does. */
  public enum PushAction: Equatable, Sendable {
    /** `/push`: whether this device is notified, and why not. */
    case status
    case on, off
    /** `/push list`: your devices and browsers, with their ids. */
    case list
    /** `/push test [id]`: a test notification to this device, or to the device or browser with that id. */
    case test(PushTarget?)
    /** `/push delete id`: forgets a device or browser. */
    case delete(PushTarget)
  }

  /** A device or a browser, as `/push list` numbers them: `d3`, `b5`. */
  public enum PushTarget: Hashable, Sendable, CustomStringConvertible {
    case device(Int)
    case browser(Int)

    init?(_ word: String) {
      guard let kind = word.first, let id = Int(word.dropFirst()) else { return nil }
      switch kind {
      case "d": self = .device(id)
      case "b": self = .browser(id)
      default: return nil
      }
    }

    public var description: String {
      switch self {
      case let .device(id): "d\(id)"
      case let .browser(id): "b\(id)"
      }
    }
  }

  public enum AppsAction: Equatable, Sendable {
    case list
    case signIn(String)
    case signOut(String)
  }

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
    case "msg", "m":
      let pieces = rest.split(separator: " ", maxSplits: 1)
      guard let nick = pieces.first else { return .unknown("/\(name) needs a nick") }
      let body = pieces.count > 1 ? String(pieces[1]) : nil
      return .msg(nick: String(nick), text: body)
    case "query", "q":
      let nicks = rest.split(separator: " ").map(String.init)
      return nicks.isEmpty ? .unknown("/\(name) needs a nick") : .query(nicks)
    case "part", "close", "wc": return .part
    case "leave": return .leave
    case "back", "b": return .back
    case "forward", "f": return .forward
    case "home": return .home
    case "star", "fav": return .star(roomName(rest), true)
    case "unstar", "unfav": return .star(roomName(rest), false)
    case "move":
      guard let move = StarMove(rawValue: rest.lowercased()) else { return .unknown("/move needs up, down or top") }
      return .move(move)
    case "push":
      let words = rest.split(separator: " ").map { $0.lowercased() }
      let target = words.count == 2 ? PushTarget(words[1]) : nil
      let usage = InputCommand.unknown("/push takes on, off, list, test [id] or delete id, where an id is d1 for a device or b1 for a browser")
      switch (words.first, words.count) {
      case (nil, _): return .push(.status)
      case ("on", 1): return .push(.on)
      case ("off", 1): return .push(.off)
      case ("list", 1): return .push(.list)
      case ("test", 1): return .push(.test(nil))
      case ("test", 2):
        guard let target else { return usage }
        return .push(.test(target))
      case ("delete", 2):
        guard let target else { return usage }
        return .push(.delete(target))
      default: return usage
      }
    case "notify", "level":
      var words = rest.split(separator: " ").map(String.init)
      var room: String?
      if let first = words.first, first.hasPrefix("#") || first.hasPrefix("&") {
        room = roomName(first)
        words.removeFirst()
      }
      guard let level = words.first else { return .notify(nil, room: room) }
      switch level.lowercased() {
      case "everything", "all": return .notify(.everything, room: room)
      case "mentions", "mention": return .notify(.mentions, room: room)
      case "off", "nothing", "none": return .notify(.nothing, room: room)
      case "hide", "hidden", "invisible": return .notify(.invisible, room: room)
      default: return .unknown("/notify takes everything, mentions, off or hide")
      }
    case "hide": return .hide(roomName(rest), true)
    case "unhide", "show":
      guard let room = roomName(rest) else { return .unknown("/\(name) needs a room") }
      return .hide(room, false)
    case "newroom", "create", "mkroom":
      var words = rest.split(separator: " ").map(String.init)
      let closed = words.first == "-p"
      if closed { words.removeFirst() }
      guard let first = words.first, let room = roomName(first) else { return .unknown("/\(name) needs a room name") }
      return .newRoom(name: room, closed: closed, nicks: Array(words.dropFirst()))
    case "rename": return rest.isEmpty ? .unknown("/rename needs a name") : .rename(roomName(rest) ?? rest)
    case "room", "settings", "info": return .room
    case "open": return .makeOpen
    case "private": return .makePrivate(rest.split(separator: " ").map(String.init))
    case "invite": return .invite(rest.isEmpty ? nil : rest)
    case "kick", "remove": return rest.isEmpty ? .unknown("/\(name) needs a nick") : .kick(rest)
    case "deleteroom", "destroy": return .deleteRoom
    case "dismiss": return .dismiss
    case "search", "s", "grep": return rest.isEmpty ? .unknown("/search needs words or a filter") : .search(rest)
    case "more": return .more
    case "searches": return .searches(clear: rest.lowercased() == "clear")
    case "goto", "go":
      guard let n = Int(rest), n > 0 else { return .unknown("/goto needs a result's number") }
      return .goto(n)
    case "activity", "act": return .activity
    case "ban": return rest.isEmpty ? .unknown("/ban needs a nick") : .ban(rest, true)
    case "unban": return rest.isEmpty ? .unknown("/unban needs a nick") : .ban(rest, false)
    case "names", "who": return .names
    case "whois", "wi": return rest.isEmpty ? .unknown("/whois needs a nick") : .whois(rest)
    case "server", "connect": return rest.isEmpty ? .unknown("/server needs an address") : .server(rest)
    case "help", "?": return rest.lowercased() == "shortcuts" || rest.lowercased() == "keys" ? .shortcuts : .help
    case "keys", "shortcuts": return .shortcuts
    case "edit", "e":
      let (n, text) = numbered(rest)
      return .edit(n, text.isEmpty ? nil : text)
    case "quote": return .quote(numbered(rest).0)
    case "del", "delete", "rm": return .delete(numbered(rest).0)
    case "copy": return .copy(numbered(rest).0)
    case "link", "permalink": return .link(numbered(rest).0)
    case "react", "boost":
      // The boost is the rest of the line, words and all; a number after it says which message.
      var pieces = rest.split(separator: " ")
      var n: Int?
      if pieces.count > 1, let last = pieces.last, let number = Int(last), number > 0 {
        n = number
        pieces.removeLast()
      }
      let content = pieces.joined(separator: " ")
      guard !content.isEmpty else { return .unknown("/react needs an emoji or a word") }
      guard content.count <= EmberLimits.maxBoostLength else { return .unknown(EmberText.boostTooLong) }
      return .react(content, n)
    case "thread", "t": return .thread(numbered(rest).0)
    case "upload", "attach": return .upload
    case "snippet": return .snippet(rest)
    case "report":
      // A number, or nothing, is a message; anything else names someone.
      if rest.isEmpty || numbered(rest).0 != nil { return .report(numbered(rest).0) }
      return .reportPerson(rest)
    case "ignore", "block": return rest.isEmpty ? .ignored : .ignore(rest, true)
    case "profile":
      let words = rest.lowercased().split(separator: " ").map(String.init)
      guard let first = words.first, first == "connect" || first == "disconnect" else { return .profile(link: rest.lowercased() == "link") }
      guard words.count == 2, let provider = words.last, provider == "sso" || provider == "memberful" else {
        return .unknown("/profile \(first) takes sso or memberful")
      }
      return .profileElsewhere(connect: first == "connect", memberful: provider == "memberful")
    case "nick": return rest.isEmpty ? .unknown("/nick needs a name") : .setProfile(.name, rest)
    case "username": return .setProfile(.username, rest)
    case "bio": return .setProfile(.bio, rest)
    case "email": return rest.isEmpty ? .unknown("/email needs an address") : .setProfile(.emailAddress, rest)
    case "passwd", "password": return .passwd
    case "avatar": return .avatar(remove: rest.lowercased() == "remove")
    case "apps", "app":
      let pieces = rest.split(separator: " ", maxSplits: 1).map(String.init)
      guard let verb = pieces.first?.lowercased() else { return .apps(.list) }
      if AdminCommand.appVerbs.contains(verb), let command = AdminCommand.parse(name, rest) { return command }
      guard pieces.count > 1 else { return .unknown("/apps \(verb) needs an app's name") }
      switch verb {
      case "signin": return .apps(.signIn(pieces[1]))
      case "signout": return .apps(.signOut(pieces[1]))
      default: return .unknown("/apps takes signin or signout")
      }
    case "ai":
      let pieces = rest.split(separator: " ", maxSplits: 1).map(String.init)
      guard let verb = pieces.first else { return .ai(disconnect: nil) }
      if AdminCommand.aiVerbs.contains(verb.lowercased()), let command = AdminCommand.parse(name, rest) { return command }
      guard verb.lowercased() == "disconnect", pieces.count > 1 else { return .unknown("/ai takes disconnect and an AI app's name") }
      return .ai(disconnect: pieces[1])
    case "sounds":
      let words = rest.lowercased().split(separator: " ").map(String.init)
      guard let first = words.first else { return .sounds(nil, nil) }
      guard let sound = HuddleSound(rawValue: first), words.count == 2, words[1] == "on" || words[1] == "off" else {
        return .unknown("/sounds takes music, chimes or ring, then on or off")
      }
      return .sounds(sound, words[1] == "on")
    case "appearance": return .appearance(rest.isEmpty ? nil : rest.lowercased())
    case "quit", "logout", "signout": return .quit
    case "delete-account", "deleteaccount": return .deleteAccount
    case "unignore", "unblock": return rest.isEmpty ? .unknown("/\(name) needs a nick") : .ignore(rest, false)
    case "end", "newest": return .end
    case "huddle", "call": return huddle(rest)
    case "mute": return .huddle(.mute(true))
    case "unmute": return .huddle(.mute(false))
    case "hand": return .huddle(.hand)
    default: return AdminCommand.parse(name, rest) ?? .unknown("Unknown command: /\(name)")
    }
  }

  /** `/huddle`'s words. */
  static func huddle(_ rest: String) -> InputCommand {
    let words = rest.split(separator: " ").map(String.init)
    guard let verb = words.first?.lowercased() else { return .huddle(.start(muted: false, camera: false, preview: true)) }
    let tail = Array(words.dropFirst())
    func onOff() -> Bool? {
      switch tail.first?.lowercased() {
      case nil, "on": true
      case "off": false
      default: nil
      }
    }
    switch verb {
    case "-m", "+cam", "-mute", "+camera":
      let flags = Set(words.map { $0.lowercased() })
      return .huddle(.start(muted: flags.contains("-m") || flags.contains("-mute"), camera: flags.contains("+cam") || flags.contains("+camera"), preview: false))
    case "join", "j": return .huddle(.join(tail.first.flatMap(roomName)))
    case "decline", "no": return .huddle(.decline(tail.first.flatMap(roomName)))
    case "leave", "end", "hangup": return .huddle(.leave)
    case "link": return .huddle(.link)
    case "open", "show": return .huddle(.open)
    case "close", "min", "minimize": return .huddle(.close)
    case "list", "ls": return .huddle(.list)
    case "who", "names": return .huddle(.who)
    case "thread": return .huddle(.thread)
    case "mute": return .huddle(.mute(true))
    case "unmute": return .huddle(.mute(false))
    case "cam", "camera", "video":
      guard let on = onOff() else { return .unknown("/huddle cam takes on or off") }
      return .huddle(.camera(on))
    case "screen", "share":
      guard let on = onOff() else { return .unknown("/huddle screen takes on or off") }
      return .huddle(.screen(on))
    case "hand": return .huddle(.hand)
    case "sticker":
      guard let word = tail.first else { return .unknown("/huddle sticker takes hand, brb, yes, no, done or off") }
      if word.lowercased() == "off" { return .huddle(.sticker(nil)) }
      guard let sticker = HuddleSticker(word: word) else { return .unknown("/huddle sticker takes hand, brb, yes, no, done or off") }
      return .huddle(.sticker(sticker))
    case "react":
      let emoji = tail.joined(separator: " ")
      guard !emoji.isEmpty, emoji.count <= Huddles.maxReactionLength else { return .unknown("/huddle react takes one emoji") }
      return .huddle(.react(emoji))
    case "invite": return .huddle(.invite(tail))
    default: return .unknown("/huddle takes join, leave, link, open, close, list, who, thread, mute, unmute, cam, screen, hand, sticker, react, invite or decline")
    }
  }

  /** A room's name as typed, without its `#` or `&`; nil when nothing's typed. */
  public static func roomName(_ text: String) -> String? {
    var name = Substring(text.trimmingCharacters(in: .whitespaces))
    if name.first == "#" || name.first == "&" { name = name.dropFirst() }
    return name.isEmpty ? nil : String(name)
  }

  /** A leading message number, counted back from the newest, and the rest. */
  static func numbered(_ rest: String) -> (Int?, String) {
    let pieces = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let first = pieces.first, let n = Int(first), n > 0 else { return (nil, rest) }
    return (n, pieces.count > 1 ? String(pieces[1]) : "")
  }

  public static let helpText = """
    /join #room · /msg nick text · /query nick [nick...] · /me action · /part · /leave · /names · /whois nick · /server host · //text sends a slash
    Rooms: /newroom [-p] #name [nick...] · /room · /rename name · /open · /private [nick...] · /invite [nick] · /kick nick · /deleteroom
    /star · /unstar · /move up|down|top · /notify [everything|mentions|off|hide] · /hide · /unhide #room · /activity · /back · /forward · /home
    /search words in:#room from:nick has:link has:file is:thread with:me sort:oldest · /more · /goto n · /searches [clear] · /ban nick · /unban nick
    Messages: /edit [n] [text] · /del [n] · /quote [n] · /copy [n] · /link [n] · /react emoji [n] · /thread [n] · /report [n] · /report nick · n counts back from the newest
    /upload · /snippet [title] · /ignore [nick] · /unignore nick · /end · /help shortcuts
    You: /profile [link] · /profile connect|disconnect sso|memberful · /nick name · /username name · /bio text · /email address · /passwd · /avatar [remove] · /apps [signin|signout app] · /ai [disconnect app]
    /notify [#room] level · /push [on|off|list|test [id]|delete id] · /sounds [music|chimes|ring on|off] · /appearance [light|dark|system] · /quit · /delete-account
    Huddles: /huddle [-m] [+cam] · /huddle join|decline [#room] · /huddle leave|link|open|close|list|who|thread · /mute · /unmute · /hand · /huddle cam|screen on|off · /huddle sticker hand|brb|yes|no|done|off · /huddle react emoji · /huddle invite [nick…]
    \(AdminCommand.help)
    Formatting: **bold** _italic_ ~~strike~~ `code` · lines starting > quote, - list, 1. list, # heading · ``` fences code · Shift+Return for a new line
    """
}
