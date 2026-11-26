import Foundation

// What the web says of huddles and who's in them (apps/web/src/lib/huddle-people.ts, huddle-stickers.ts,
// huddle-devices.ts, huddle.ts's ENDINGS, huddle-preview.tsx, huddle-tools.tsx), and who can huddle.

/** Who huddles with whom (lib/huddle-people.ts) and what a huddle is called. */
public enum HuddleRules {
  /**
   * Whether someone joins no huddle (`joinsNoHuddle`): a bot, AI agents among them, or someone who can no
   * longer sign in. Until the directory lists them, only @ember is known to join none.
   */
  public static func joinsNone(_ user: User, listed: DirectoryUser?) -> Bool {
    if listed?.role == .bot || listed?.agent == true || user.id == PeopleList.assistantId { return true }
    if let listed, listed.status != .active { return true }
    return false
  }

  /** Who a DM's huddle is with (`huddledWith`): the others in it, but for whoever joins none. */
  public static func huddledWith(_ room: Room, me: UserID, joinsNone: (User) -> Bool) -> [User] {
    (room.members ?? []).filter { $0.id != me && !joinsNone($0) }
  }

  /** Whether a room has huddles where they're on (`hasHuddles`): a shared room its settings allow them in, a DM with someone to huddle with. */
  public static func hasHuddles(_ room: Room, me: UserID, joinsNone: (User) -> Bool) -> Bool {
    room.isDirect ? !huddledWith(room, me: me, joinsNone: joinsNone).isEmpty : room.allowsHuddles
  }

  /** Who `me` can invite into a huddle they're in (`invitable`), of the room's `members`. */
  public static func invitable(_ members: [User], me: UserID, inIt: Set<UserID>, joinsNone: (User) -> Bool) -> [User] {
    members.filter { $0.id != me && !inIt.contains($0.id) && !joinsNone($0) }
  }

  /** Where a room's huddle is (`huddlePlace`): "in Launch", or "with Priya Patel" for a DM. */
  public static func place(_ room: Room, name: String) -> String { room.isDirect ? "with \(name)" : "in \(name)" }

  /** What the joined huddle is called (`useHuddleName`): "Huddle in Launch", or just Huddle once the room isn't listed. */
  public static func name(_ room: Room?, roomName: String) -> String {
    guard let room else { return "Huddle" }
    return "Huddle \(place(room, name: roomName))"
  }
}

/** The web's sentences about huddles that MessageWords doesn't already have. */
public enum HuddleWords {
  static func invited(_ names: [String]) -> String {
    "\(MessageWords.peopleListed(names, names.count)) \(names.count == 1 ? "is" : "are") invited"
  }

  /** `invitedOnceItStarts`: "Priya is invited once it starts." */
  public static func invitedOnceItStarts(_ names: [String]) -> String { "\(invited(names)) once it starts." }

  /** `invitedNow`: "Priya and Sam are invited." */
  public static func invitedNow(_ names: [String]) -> String { "\(invited(names))." }

  /** `inItNow`: "Sam is in it now." */
  public static func inItNow(_ names: [String], count: Int) -> String {
    "\(MessageWords.peopleListed(names, count)) \(count == 1 ? "is" : "are") in it now."
  }

  /** `sharingScreens`: "Sam is sharing a screen", "You're sharing your screen", "Sam and you are sharing screens"; nil while nobody is. */
  public static func sharingScreens(_ others: [String], you: Bool) -> String? {
    if others.isEmpty { return you ? "You're sharing your screen" : nil }
    if others.count == 1, !you { return "\(MessageWords.firstName(others[0])) is sharing a screen" }
    return "\(MessageWords.sentence(others.map(MessageWords.firstName) + (you ? ["you"] : []))) are sharing screens"
  }

  /** `wereInItsHuddle`: who was in a huddle that's over, where only their ids are known. */
  public static func wereInItsHuddle(_ others: [String], count: Int, you: Bool) -> String {
    if others.count == count { return MessageWords.wereInTheHuddle(others, you: you) }
    let named = you ? [] : others
    let people = you ? count + 1 : count
    return "\(MessageWords.peopleListed(named, people)) \(people == 1 ? "was" : "were") in the huddle"
  }

  /** The preview's description (huddle-preview.tsx): who's in it, who's invited, and what joining here leaves. */
  public static func previewDescription(
    room: Room, roomName: String, others: [String], othersCount: Int, going: Bool, moving: Bool, invited: [String], inAnother: Bool
  ) -> String {
    var lines: [String] = []
    if othersCount > 0 {
      lines.append(inItNow(others, count: othersCount))
    } else if !going {
      lines.append(room.isDirect ? invitedOnceItStarts(invited) : "Everyone in \(roomName) can join once it starts.")
    }
    if moving { lines.append("You're in it in another tab or on another device, and joining here leaves it there.") }
    if inAnother { lines.append("\(going ? "Joining" : "Starting") it leaves the huddle you're in now.") }
    return lines.joined(separator: " ")
  }

  /** The preview's title: "Start a huddle in Launch", "Join the huddle with Priya". */
  public static func previewTitle(place: String, going: Bool) -> String { going ? "Join the huddle \(place)" : "Start a huddle \(place)" }

  /** `waitingToJoin`: what a huddle says in place of who's in it until the room lets the app in, and while its link to the room is down. */
  public static func waitingToJoin(connected: Bool, letIn: Bool) -> String? { connected ? nil : letIn ? "Reconnecting…" : "Connecting…" }

  /** "N people" under the opened huddle's name. */
  public static func people(_ count: Int) -> String { count == 1 ? "1 person" : "\(count) people" }

  /** The invitation card's words after the inviter (`invites`). */
  public static func invites(_ room: Room?) -> String {
    guard let room, !room.isDirect, let name = room.name else { return "invites you to a huddle" }
    return "invites you to a huddle in \(name)"
  }

  /** The invite dialog's words (huddle-invite-dialog.tsx). */
  public static func inviteExplained(_ room: Room, name: String) -> String {
    room.isDirect
      ? "People in this conversation who aren't in the huddle. Ember rings whoever you invite, unless they've turned its notifications off."
      : "People in \(name) who aren't in the huddle. Ember rings whoever you invite, unless they've turned the room's notifications off."
  }

  public static func nobodyToInvite(_ room: Room, name: String) -> String {
    "There's nobody else in \(room.isDirect ? "this conversation" : name) to invite."
  }

  public static func selected(_ count: Int) -> String {
    if count == 0 { return "Choose one or more people." }
    if count >= Huddles.maxInvited { return "\(count) people selected, the most one invitation takes." }
    return count == 1 ? "1 person selected." : "\(count) people selected."
  }

  public static let loadingPeople = "Loading people…"
  public static let couldNotLoadPeople = "Couldn't load people. Please try again."
  public static let noPeopleFound = "No people found. Try another name."
  public static let inviteWhileReconnecting = "Ember couldn't send the invitation while the huddle reconnects. Try again in a moment."
  /** People the invite dialog shows at a time (`PAGE`). */
  public static let invitePage = 20

  /** The thread beside the huddle (huddle-thread.tsx). */
  public static let threadTitle = "Every huddle has a thread"
  public static func threadExplained(place: String) -> String {
    "Messages, files and links sent here reach everyone in the huddle, and stay as a thread in \(place) once it ends."
  }
  public static func threadGone(place: String) -> String { "This huddle's message isn't in \(place), so it has no thread." }

  /** What the app's person is told as the room ends the huddle for them (`ENDINGS`). */
  public static func ending(_ code: HuddleCloseCode) -> String {
    switch code {
    case .full: "That huddle is full. A huddle takes \(Huddles.maxPeople) people."
    case .off: "Huddles have been turned off."
    case .moved: "You joined the huddle somewhere else, so it left this tab."
    }
  }

  public static let roomGone = "You left the huddle, since its room is no longer there for you."
  public static let offInRoom = "Huddles have been turned off in this room."
  public static let off = "Huddles are turned off."
  public static let offInThisRoom = "Huddles are turned off in this room."

  // The preview's and the devices' words, in the app's terms (huddle-preview.tsx, huddle-devices.ts).
  public static let askingForMicrophone = "Waiting for permission to use your microphone…"
  /** Where the person lets ircX use a device: a Mac's System Settings, or an iPhone's or iPad's Settings. */
  public static var privacySettings: String {
    #if os(iOS)
    "Settings, under ircX"
    #else
    "System Settings, under Privacy & Security"
    #endif
  }
  public static var noMicrophone: String {
    "ircX has no microphone to use, so you'll only listen. To speak, let ircX use your microphone in \(privacySettings), then join again."
  }
  public static var noCamera: String {
    "ircX has no camera to use. To show yours, let ircX use your camera in \(privacySettings), then turn it on again."
  }
  public static var stillNoMicrophone: String {
    "ircX has no microphone to use. To speak, let ircX use your microphone in \(privacySettings), then choose it again."
  }
  public static let microphoneGone = "Your microphone went away, so you only listen now."
  public static let noOtherMicrophone = "ircX couldn't use that microphone. Nothing has changed."
  public static let noOtherSpeaker = "ircX couldn't use that speaker. Nothing has changed."
  public static let noOtherCamera = "ircX couldn't use that camera. Nothing has changed."
  public static let cameraWentOff = "ircX couldn't use that camera, and your camera is off now. Turn it on again to show yours."
  public static var noScreen: String {
    "ircX couldn't share your screen. To share it, let ircX record the screen in \(privacySettings), then share it again."
  }
  public static let microphoneInterrupted = "Your microphone is muted, since another call took it."
}

/** A sticker as a huddle draws it and names it (lib/huddle-stickers.ts). */
extension HuddleSticker {
  public var emoji: String {
    switch self {
    case .hand: "\u{270B}"
    case .brb: "\u{2615}"
    case .thumbsUp: "\u{1F44D}"
    case .thumbsDown: "\u{1F44E}"
    case .done: "\u{2705}"
    }
  }

  /** What it's called where it's chosen. */
  public var name: String {
    switch self {
    case .hand: "Raise hand"
    case .brb: "Be right back"
    case .thumbsUp: "Yes"
    case .thumbsDown: "No"
    case .done: "Done"
    }
  }

  /** What a tile that shows it says of its person. */
  public var shown: String {
    switch self {
    case .hand: "Hand raised"
    case .brb: "Be right back"
    case .thumbsUp: "Yes"
    case .thumbsDown: "No"
    case .done: "Done"
    }
  }

  /** What `/sticker` takes: its own name, or yes and no for the thumbs. */
  public init?(word: String) {
    switch word.lowercased() {
    case "hand", "raise": self = .hand
    case "brb", "away": self = .brb
    case "yes", "thumbs-up", "+1": self = .thumbsUp
    case "no", "thumbs-down", "-1": self = .thumbsDown
    case "done": self = .done
    default: return nil
    }
  }

  /** The raise-hand button's label for the sticker shown (`RaiseHandTool`). */
  public static func raiseHandLabel(_ shown: HuddleSticker?) -> String {
    switch shown {
    case nil: "Raise hand"
    case .hand: "Lower hand"
    default: "Remove sticker"
    }
  }
}
