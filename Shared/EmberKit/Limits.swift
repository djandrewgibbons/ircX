import Foundation

/**
 * The limits packages/protocol sets, by their names there. Where the Worker checks the same, a client
 * check only saves a round trip.
 */
public enum EmberLimits {
  // index.ts
  public static let maxMessageLength = 40_000
  public static let maxMessageHTMLLength = 100_000
  public static let maxBoostLength = 16
  /** `MAX_REPORT_NOTE_LENGTH` */
  public static let maxReportNoteLength = 500
  public static let latePreviewMilliseconds = 60_000
  public static let historyPageSize = 40
  /** How long the app is hidden before showing it loads the sidebar and people again (web `RELOAD_AFTER_HIDDEN_MS`). */
  public static let reloadAfterHidden: TimeInterval = 60
  public static let maxCheckedMessages = 50
  public static let maxRoomNameLength = 100
  public static let maxAccountNameLength = 100
  public static let maxTaglineLength = 30
  public static let maxCustomStylesLength = 100_000
  public static let maxListedUsers = 1_000
  public static let maxFavorites = 4_096
  public static let maxSharedOrder = 4_096
  public static let maxBioLength = 200
  public static let maxUserNameLength = 100
  public static let maxEmailAddressLength = 254
  public static let maxUsernameLength = 21
  public static let minPasswordLength = 8
  public static let maxPasswordLength = 72
  public static let maxTurnstileTokenLength = 2048
  public static let maxEmailDomains = 100
  public static let maxOtherAddresses = 5
  public static let parentTextLength = 150
  public static let threadFaces = 4
  public static let invitationsAtOnce = 20
  public static let invitationDays = 7
  public static let emailsPerAddress = 3
  public static let emailLinksPerNetwork = 10
  public static let passwordResetCodeDigits = 8
  public static let passwordResetCodeMinutes = 15
  public static let passwordResetCodeTries = 5
  public static let passwordResetsPerNetwork = 10
  public static let signUpsPerAddress = 5
  public static let signUpsPerHour = 50
  // pages.ts
  public static let maxIdLength = 64
  /** Guest names (`POST /api/session {name}`), the Worker's `MAX_NAME_LENGTH`. */
  public static let maxGuestNameLength = 48
  /** How long a profile's sign-in link works, in hours (`W/transfers.ts`). */
  public static let transferLinkHours = 4
}

/** The words Ember shows, by their names in packages/protocol: the client shows them verbatim. */
public enum EmberText {
  /** What a deleted message that keeps its place for its replies says (web `DeletedMessage`). */
  public static let messageDeleted = "This message was deleted."
  public static let messageTooLong = "Messages can be up to 40,000 characters."
  public static let taglineTooLong = "Tagline must be at most 30 characters"
  public static let nameTooLong = "Name must be at most 100 characters"
  public static let emailAddressTooLong = "Email address must be at most 254 characters"
  public static let nameReserved = "Ember is the AI assistant's name. Choose another."
  public static let usernameRefused = "Usernames have up to 21 lowercase letters, numbers, periods, hyphens and underscores, and start with a letter or number."
  public static let usernameTaken = "That username is taken. Choose another."
  public static let passwordTooShort = "Password must be at least 8 characters."
  public static let passwordTooLong = "Password must be at most 72 characters."
  public static let currentPasswordNeeded = "Enter your current password to change your email address or password."
  public static let currentPasswordWrong = "That isn't your current password."
  public static let passwordWithMemberful = "You sign in with Memberful, so there's no password to set."
  public static let deletedPersonName = "Deleted person"
  public static let deletionPasswordNeeded = "Enter your password to delete your account."
  public static let deletionNameNeeded = "Type your name as your profile has it to delete your account."
  public static let onlyAdministrator = "You're the only administrator. Make someone else an administrator before you delete your account."

  public static let signInRejected = "Incorrect email or password. Please try again."
  public static let signInLimited = "Too many sign-in attempts. Please wait a few minutes and try again."
  public static let signInRefused = "Too many requests or unauthorized."
  public static let guestSignInOff = "Signing in with just a name is turned off"

  public static let invitationGone = "This invitation has expired, been used, or been replaced by a newer one. Ask whoever invited you to send another."
  public static let emailLinkGone = "This link has expired, been used, or been replaced by a newer one."
  public static let emailLinksLimited = "Too many links asked for from your network. Try again in an hour."
  public static let cantEmailLinks = "Ember can't email links right now. Try again later, or ask an administrator to invite you."
  public static let cantEmailCodes = "Ember can't email you a code right now. Ask an administrator for help."
  public static let passwordResetsLimited = "Too many codes asked for from your network. Try again in an hour."
  public static let passwordResetCodeNeeded = "Enter the 8-digit code from the email."
  public static let passwordResetCodeWrong = "That code is wrong or no longer works. Check the newest email from Ember, or send another code."
  public static let passwordResetLimited = "Too many tries. Please wait a few minutes and try again."
  public static let passwordResetDone = "Your password has been reset."
  public static let passwordResetSignIn = "Your password has been reset. Sign in with it."
  public static let signUpLimited = "Too many sign-ups from your network. Try again in an hour."
  public static let signUpFull = "Lots of people have signed up in the last hour. Try again later."
  public static let turnstileFailed = "Ember couldn't check that you're a person. Try again."
  public static let emailAddressNeeded = "Enter your email address, such as ann@example.com"
  public static let noEmailAddresses = "Give an email address to invite"
  public static let notAnEmailAddress = "Each must be an email address, such as ann@example.com"
  public static let emailAddressTaken = "That email address has an account already"
  public static let signedInAlready = "You're signed in already"

  /** Why `POST /api/directs` refuses a new DM with someone who blocked whoever starts it (`notTakingDirects`). */
  public static func notTakingDirects(_ name: String) -> String { "\(name) isn't taking direct messages." }
  /** `onlyAddressesAt` */
  public static func onlyAddressesAt(_ domains: [String]) -> String { "Only email addresses at \(domainsInWords(domains)) can join this way." }
  /** `domainsInWords` */
  public static func domainsInWords(_ domains: [String]) -> String {
    switch domains.count {
    case 0: return ""
    case 1: return domains[0]
    default: return "\(domains.dropLast().joined(separator: ", ")) or \(domains[domains.count - 1])"
    }
  }

  // Rooms (W/index.ts)
  public static let roomNotFound = "Room not found or inaccessible"
  public static let roomCreationForbidden = "Only administrators can create rooms"
  public static let roomChangeForbidden = "Only administrators and the room's creator can change it"
  public static let roomHuddlesForbidden = "Only administrators can turn huddles on or off in a room"
  public static let roomDeletionForbidden = "Only administrators and the room's creator can delete it"
  public static let cantLeaveOpenRoom = "Everyone is in an open room, so nobody can leave it"
  public static let cantLeaveOwnRoom = "You can change this room, so take yourself out in its settings"
  public static let cantLeaveLastRoom = "Nobody else could open this room, so you can't leave it"
  public static let cantStar = "You can't star that room"
  public static let notYourStars = "Those aren't the rooms you've starred"
  public static let iconRefused = #"Icon must be one of the room icons, or "" for the default"#

  // Room socket errors (W/chat-room.ts)
  public static let unrecognizedFrame = "Unrecognized frame"
  public static let somethingWentWrong = "Something went wrong"
  public static let outdated = "Ember has been updated. Reload the page to keep chatting."
  public static let banned = "Request failed (429)"
  public static let empty = "Your message is empty."
  public static let unreadable = "That message couldn't be saved."
  public static let messageGone = "That message no longer exists"
  public static let onlyOwnMessages = "You can only delete your own messages"
  public static let ofAHuddle = "A huddle's message can't be edited."
  public static let boostTooLong = "Boosts can be up to 16 characters."
  /** What the typing line says after an agent's name while it searches the room. */
  public static let searchingRoom = "is searching this room"

  // Notices the web shows (A/lib/room-state.ts, A/lib/uploads.ts, report-dialog.tsx)
  /** What a message from someone you've blocked collapses to (web `BLOCKED_MESSAGE`). */
  public static let blockedMessage = "Message from someone you blocked"
  /** What a pending message the room didn't take says under it. */
  public static let notSent = "Not sent"
  /** `NOT_SENT`: what the room says when messages written offline didn't go. */
  public static let notConnectedNotSent = "Not connected. Your message wasn't sent."
  /** What an action says when the socket isn't open (web `messageActionsOf`). */
  public static let notConnected = "Not connected. Try again once you're reconnected."
  public static let messageSentScrollUp = "Your message was sent. Scroll up to see it."
  public static let messagesSentScrollUp = "Your messages were sent. Scroll up to see them."
  public static let uploadFailed = "Upload failed. Please attach the file and try again."
  public static let connectionLost = "Connection lost. Please attach the file and try again."
  public static func tooLargeToAttach(_ name: String) -> String { "\(name) is too large. Choose a file that's 250 MB or smaller." }
  public static let reported = "The administrators will take a look."
  public static let tooManyLinkPreviews = "Too many link previews. Try again in a minute."

  /** The web's words for an answer to sign-in that says to connect an account elsewhere (`sign-in-page.tsx`). */
  public static func nowUses(_ names: [String]) -> String {
    guard names.count == 1 else {
      return "This workspace now uses \(names.joined(separator: " and ")). Connect your account at either to keep signing in."
    }
    return "This workspace now uses \(names[0]). Connect your \(names[0]) account to keep signing in."
  }

  // Joining (`JOINING_PROBLEMS`, the `joining` query key)
  public static let joiningParam = "joining"
  public static let joiningProblems: [String: String] = [
    "link_off": "Joining by link is off.",
    "closed": "Signing up is closed.",
    "email_off": "Joining with an email address is off.",
  ]
}

/** The reactions offered in the order the tray shows them (`REACTIONS`, `QUICK_REACTION_COUNT`). */
public enum Reactions {
  public static let all: [(emoji: String, name: String)] = [
    ("\u{1F44D}", "Thumbs up"),
    ("\u{1F44F}", "Clapping"),
    ("\u{1F44B}", "Waving hand"),
    ("\u{1F4AA}", "Muscle"),
    ("\u{2764}\u{FE0F}", "Red heart"),
    ("\u{1F602}", "Face with tears of joy"),
    ("\u{1F389}", "Party popper"),
    ("\u{1F525}", "Fire"),
  ]
  public static let quickCount = 3
  public static var quick: [(emoji: String, name: String)] { Array(all.prefix(quickCount)) }
}

/** @ember (`ASSISTANT_ID`, `ASSISTANT_NAME`). */
public enum Assistant {
  public static let id: UserID = "ember"
  public static let name = "Ember"
}

/** The checks packages/protocol makes of what people type, for forms to make before sending. */
public enum EmberRules {
  /** `isMessageTooLong`: by UTF-16 units, as JavaScript's `length` counts. */
  public static func isMessageTooLong(_ plainText: String) -> Bool { plainText.utf16.count > EmberLimits.maxMessageLength }

  /** `isPasswordTooShort`: by characters (code points), as `[...password].length` counts. */
  public static func isPasswordTooShort(_ password: String) -> Bool { password.unicodeScalars.count < EmberLimits.minPasswordLength }

  /** `isPasswordTooLong`: by UTF-16 units, as JavaScript's `length` counts. */
  public static func isPasswordTooLong(_ password: String) -> Bool { password.utf16.count > EmberLimits.maxPasswordLength }

  /** A password cut to `MAX_PASSWORD_LENGTH` UTF-16 units, as an input's `maxLength` stops typing, without splitting a character. */
  public static func capped(password: String) -> String {
    guard isPasswordTooLong(password) else { return password }
    var kept = ""
    var units = 0
    for character in password {
      units += character.utf16.count
      if units > EmberLimits.maxPasswordLength { break }
      kept.append(character)
    }
    return kept
  }

  /** `parentTextOf`: a reply's parent's first 150 characters. */
  public static func parentText(of plainText: String) -> String {
    String(String.UnicodeScalarView(plainText.unicodeScalars.prefix(EmberLimits.parentTextLength)))
  }

  /** `usernameOf`: a typed username as kept: NFKC, no spaces, no leading @, lowercase. */
  public static func username(of typed: String) -> String {
    var text = typed.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
    while text.hasPrefix("@") { text.removeFirst() }
    return text.lowercased()
  }

  /** `isUsername` */
  public static func isUsername(_ username: String) -> Bool {
    guard username.utf16.count <= EmberLimits.maxUsernameLength, let first = username.unicodeScalars.first else { return false }
    return isLowerAlphanumeric(first) && username.unicodeScalars.allSatisfy { isLowerAlphanumeric($0) || $0 == "." || $0 == "_" || $0 == "-" }
  }

  /** `usernameFrom`: a username to suggest from a name. */
  public static func username(from name: String) -> String {
    let unmarked = name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !isMark($0) }
    let letters = String(String.UnicodeScalarView(unmarked)).lowercased().unicodeScalars.filter(isLowerAlphanumeric)
    let kept = String(String.UnicodeScalarView(letters.prefix(EmberLimits.maxUsernameLength - 4)))
    return kept.isEmpty ? "member" : kept
  }

  /** `sameName`: whether two names show the same, by NFKC, without format characters, leading @ and spaces, any case. */
  public static func sameName(_ name: String, _ other: String) -> Bool { nameAsShown(name) == nameAsShown(other) }

  /** `isReservedName`: @ember's. */
  public static func isReservedName(_ name: String) -> Bool { sameName(name, Assistant.name) }

  private static func nameAsShown(_ name: String) -> String {
    let normalized = name.precomposedStringWithCompatibilityMapping.unicodeScalars.filter { $0.properties.generalCategory != .format }
    var text = Substring(String(String.UnicodeScalarView(normalized)))
    while let first = text.first, first.isWhitespace || first == "@" { text.removeFirst() }
    while let last = text.last, last.isWhitespace { text.removeLast() }
    return text.lowercased()
  }

  /** `passwordResetCodeOf`: the 8 digits of a typed code, which may have spaces and dashes. */
  public static func passwordResetCode(of typed: String) -> String? {
    let code = typed.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace && $0 != "-" }
    let digits = code.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    return code.unicodeScalars.count == EmberLimits.passwordResetCodeDigits && digits ? code : nil
  }

  /** `isEmailAddress` */
  public static func isEmailAddress(_ address: String) -> Bool {
    address.utf16.count <= EmberLimits.maxEmailAddressLength && address.wholeMatch(of: mailboxAddress) != nil
  }

  nonisolated(unsafe) private static let mailboxAddress =
    #/[A-Za-z0-9!#$%&'*+\/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+\/=?^_`{|}~-]+)*@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+/#

  /** `emailAddressesIn`: the addresses in pasted text, once each, and the words that aren't addresses. */
  public static func emailAddresses(in text: String) -> (emailAddresses: [String], refused: [String]) {
    let unquoted = text.replacing(#/"[^"]*"/#, with: " ")
    let entries = unquoted.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
    let words = entries.flatMap { wordsOfEntry(String($0)) }
    return (onceEach(words.filter(isEmailAddress)), words.filter { !isEmailAddress($0) })
  }

  private static func wordsOfEntry(_ entry: String) -> [String] {
    // `entry.split(/<([^<>]*)>/)`: text and the bracketed parts alternate.
    var parts: [String] = []
    var rest = Substring(entry)
    while let match = rest.firstMatch(of: #/<([^<>]*)>/#) {
      parts.append(String(rest[..<match.range.lowerBound]))
      parts.append(String(match.output.1))
      rest = rest[match.range.upperBound...]
    }
    parts.append(String(rest))
    return parts.enumerated().flatMap { index, part -> [String] in
      let words = part.split(whereSeparator: \.isWhitespace).map(String.init)
      return index % 2 == 0 && index < parts.count - 1 ? words.filter(isEmailAddress) : words
    }
  }

  private static func onceEach(_ addresses: [String]) -> [String] {
    var given = Set<String>()
    return addresses.filter { given.insert($0.lowercased()).inserted }
  }

  /** `isRoomId` */
  public static func isRoomId(_ value: String) -> Bool { value.wholeMatch(of: #/[a-z0-9][a-z0-9-]{0,62}/#) != nil }

  /** `isRoomIcon` */
  public static func isRoomIcon(_ value: String) -> Bool { RoomIcons.nameSet.contains(value) }

  static func isLowerAlphanumeric(_ s: Unicode.Scalar) -> Bool { ("a"..."z").contains(s) || ("0"..."9").contains(s) }

  static func isMark(_ s: Unicode.Scalar) -> Bool {
    switch s.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark: true
    default: false
    }
  }
}

/** Percent-encoding as JavaScript's `encodeURIComponent` does it. */
public enum URIComponent {
  private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

  public static func encode(_ text: String) -> String {
    guard let encoded = text.addingPercentEncoding(withAllowedCharacters: unreserved) else {
      // Only text with an unpaired surrogate can't be encoded, which a Swift `String` never holds.
      preconditionFailure("Unencodable text")
    }
    return encoded
  }
}
