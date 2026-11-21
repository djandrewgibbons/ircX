import Foundation

// Workspace settings, as administrators change them and members read them: packages/protocol/src/index.ts.

/** What `GET /api/account` answers (`WorkspaceSettings`). The administrators' parts are empty for anyone else. */
public struct WorkspaceSettings: Codable, Sendable {
  public var account: Account
  public var joinCode: String?
  public var canAdminister: Bool
  public var memberfulSite: String?
  public var memberfulWebhooks: Bool
  public var memberfulKeys: KeySource?
  public var memberfulSiteKept: String?
  public var sso: SsoSettings?
  public var turnstile: KeySource?
  public var email: EmailSettings
  public var invitations: [EmailInvitation]
  public var emailDomains: [String]
  public var blockedWords: [String]
  public var addresses: EmberAddresses
  public var assistant: AssistantSettings?
  public var huddles: HuddlesSettings?
  public var outsideAi: Bool
  public var cloudflareAccountId: String?
}

/** `EmailProvider` */
public enum EmailProvider: String, Codable, Sendable {
  case cloudflare, resend
}

/** How Ember sends email (`EmailSettings`). */
public struct EmailSettings: Codable, Hashable, Sendable {
  public var provider: EmailProvider?
  public var resendKey: KeySource?
  public var cloudflare: Bool
  public var from: String?
}

/** An invitation nobody has accepted yet (`EmailInvitation`). */
public struct EmailInvitation: Codable, Hashable, Sendable, Identifiable {
  /** `"sent"`, or why the provider didn't send it; the invitation's is nil while Ember can't send email. */
  public enum Delivery: Codable, Hashable, Sendable {
    case sent
    case refused(String)

    private enum Keys: String, CodingKey { case refusal }

    public init(from decoder: Decoder) throws {
      do {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard text == "sent" else {
          throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown delivery \(text)"))
        }
        self = .sent
      } catch DecodingError.typeMismatch {
        self = .refused(try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .refusal))
      }
    }

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .sent:
        var c = encoder.singleValueContainer()
        try c.encode("sent")
      case let .refused(refusal):
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(refusal, forKey: .refusal)
      }
    }
  }

  public var id: String
  public var emailAddress: String
  public var invitedBy: String
  public var createdAt: String
  public var expiresAt: String
  public var delivery: Delivery?
}

/** What came of inviting an address (`InvitationOutcome`): nothing for a member, else the invitation. */
public struct InvitationOutcome: Codable, Hashable, Sendable {
  public var emailAddress: String
  public var member: Bool?
  public var invitation: EmailInvitation?
  /** The link, when Ember didn't email it, for the administrator to send. */
  public var link: String?
}

/** `Invited` */
public struct Invited: Codable, Sendable {
  public var outcomes: [InvitationOutcome]
}

/** `ResentInvitation` */
public struct ResentInvitation: Codable, Sendable {
  public var invitation: EmailInvitation
  public var link: String?
}

/** `TurnstileKeysChange`: the widget's keys, and a token the widget made with them. */
public struct TurnstileKeysChange: Codable, Sendable {
  public var siteKey: String
  public var secretKey: String
  public var turnstileToken: String

  public init(siteKey: String, secretKey: String, turnstileToken: String) {
    self.siteKey = siteKey
    self.secretKey = secretKey
    self.turnstileToken = turnstileToken
  }
}

/** `TurnstileSettings` */
public struct TurnstileSettings: Codable, Sendable {
  public var turnstile: KeySource?
}

/** `SentTestEmail` */
public struct SentTestEmail: Codable, Sendable {
  public var to: String
}

/** `SendingDomainCheck`: whether Cloudflare Email Service sends from the domain, or nil when unknown. */
public struct SendingDomainCheck: Codable, Sendable {
  public var onboarded: Bool?
}

/** `NewJoinCode` */
public struct NewJoinCode: Codable, Sendable {
  public var joinCode: String
}

/** The switches Membership and Community settings change (`AccountSettings`). */
public struct AccountSettings: Codable, Sendable {
  public var hideTranslationButtons: Bool?
  public var restrictRoomCreation: Bool?
  public var huddleCameras: Bool?
  public var huddleScreens: Bool?
  public var joinLink: Bool?
  public var openSignUp: Bool?
  public var memberfulJoin: Bool?
  public var memberfulSignIn: Bool?
  public var ssoJoin: Bool?
  public var ssoSignIn: Bool?
  public var emailDomainSignUp: Bool?

  public init(
    hideTranslationButtons: Bool? = nil, restrictRoomCreation: Bool? = nil, huddleCameras: Bool? = nil, huddleScreens: Bool? = nil,
    joinLink: Bool? = nil, openSignUp: Bool? = nil, memberfulJoin: Bool? = nil, memberfulSignIn: Bool? = nil, ssoJoin: Bool? = nil,
    ssoSignIn: Bool? = nil, emailDomainSignUp: Bool? = nil
  ) {
    self.hideTranslationButtons = hideTranslationButtons
    self.restrictRoomCreation = restrictRoomCreation
    self.huddleCameras = huddleCameras
    self.huddleScreens = huddleScreens
    self.joinLink = joinLink
    self.openSignUp = openSignUp
    self.memberfulJoin = memberfulJoin
    self.memberfulSignIn = memberfulSignIn
    self.ssoJoin = ssoJoin
    self.ssoSignIn = ssoSignIn
    self.emailDomainSignUp = emailDomainSignUp
  }

  /** `SETTING_NAMES`: each switch's label. */
  public static let names: [String: String] = [
    "hideTranslationButtons": "Hide translation buttons",
    "restrictRoomCreation": "Must be admin to create new rooms",
    "huddleCameras": "Cameras",
    "huddleScreens": "Screen sharing",
    "joinLink": "Join link",
    "openSignUp": "Open",
    "memberfulJoin": "Memberful",
    "memberfulSignIn": "Members only",
    "ssoJoin": "Single sign-on",
    "ssoSignIn": "SSO only",
    "emailDomainSignUp": "Email domain",
  ]
}

/**
 * What `PATCH /api/account` changes (`AccountChanges`). `customDomain` and `emailFrom` `.some(nil)` clear
 * them; a navigation icon "" goes back to its default.
 */
public struct AccountChanges: Encodable, Sendable {
  public var name: String?
  public var tagline: String?
  public var settings: AccountSettings?
  public var customDomain: String??
  public var navigationIcons: [String: String]?
  public var emailFrom: String??
  public var emailDomains: [String]?
  public var blockedWords: [String]?

  public init(
    name: String? = nil, tagline: String? = nil, settings: AccountSettings? = nil, customDomain: String?? = nil, navigationIcons: [String: String]? = nil,
    emailFrom: String?? = nil, emailDomains: [String]? = nil, blockedWords: [String]? = nil
  ) {
    self.name = name
    self.tagline = tagline
    self.settings = settings
    self.customDomain = customDomain
    self.navigationIcons = navigationIcons
    self.emailFrom = emailFrom
    self.emailDomains = emailDomains
    self.blockedWords = blockedWords
  }

  private enum Keys: String, CodingKey { case name, tagline, settings, customDomain, navigationIcons, emailFrom, emailDomains, blockedWords }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encodeIfPresent(name, forKey: .name)
    try c.encodeIfPresent(tagline, forKey: .tagline)
    try c.encodeIfPresent(settings, forKey: .settings)
    if let customDomain { try c.encode(customDomain, forKey: .customDomain) }
    try c.encodeIfPresent(navigationIcons, forKey: .navigationIcons)
    if let emailFrom { try c.encode(emailFrom, forKey: .emailFrom) }
    try c.encodeIfPresent(emailDomains, forKey: .emailDomains)
    try c.encodeIfPresent(blockedWords, forKey: .blockedWords)
  }
}

/** `CustomStyles` */
public struct CustomStyles: Codable, Sendable {
  public var customStyles: String
}

/** What account changes answer: `{account}`. */
public struct AccountAnswer: Codable, Sendable {
  public var account: Account
}

/** A release, as a release check finds it. */
public struct Release: Codable, Hashable, Sendable {
  public var release: String
  public var version: String
  public var notes: String
  public var newer: Bool
}

/** The fork whose GitHub workflows update Ember (`CopyOnGitHub`). */
public struct CopyOnGitHub: Codable, Hashable, Sendable {
  public var repository: String
  public var branch: String
  public var workflow: Bool
  public var betaWorkflow: Bool
}

/** `ReleaseCheck` */
public struct ReleaseCheck: Codable, Sendable {
  public var release: String
  public var beta: Bool
  public var newest: Release?
  public var checkedAt: String?
  public var newestBeta: Release?
  public var copy: CopyOnGitHub?
}

/** `CustomDomainReach` */
public enum CustomDomainReach: String, Codable, Sendable {
  case ember, elsewhere, nothing
}

/** `CustomDomainCheck` */
public struct CustomDomainCheck: Codable, Sendable {
  public var reaches: CustomDomainReach
}

/** `DNS_PROVIDERS` */
public enum DnsProvider: String, Codable, Sendable, CaseIterable {
  case cloudflare, godaddy, namecheap, squarespace, porkbun, route53, hover, ionos, other
}

/** `CustomDomainLookup` */
public struct CustomDomainLookup: Codable, Sendable {
  public var zone: String?
  public var provider: DnsProvider?

  public init(zone: String?, provider: DnsProvider?) {
    self.zone = zone
    self.provider = provider
  }
}

/** `EmberAddresses`: where a deploy put Ember, and the other addresses known to reach it. */
public struct EmberAddresses: Codable, Hashable, Sendable {
  public var deployed: String?
  public var others: [String]
}

/** A domain to check (`{domain}` for custom domain and sending domain checks). */
public struct DomainQuery: Codable, Sendable {
  public var domain: String
}

public enum WorkspaceRules {
  public static let settingsPath = "/account/edit"
  public static let customStylesPath = "/account/custom_styles/edit"
  public static let emberRepository = "https://github.com/NYLLON-SOFTWARE/ember-cloudflare"
  public static let updatingEmber = "\(emberRepository)/blob/main/docs/self-hosting.md#updating"
  public static let tryingBetas = "\(emberRepository)/blob/main/docs/self-hosting.md#betas"
  public static let cantSendEmail = "Ember can't send email yet. An administrator can set it up under Email in Membership."
  public static let openWithMemberful = "Open and Members only can't both be on. Turn one off first."
  public static let emailDomainsRefused = "Email domains must be a list of at most 100 domains, such as example.com"
  public static let noEmailDomains = "Add a domain whose email addresses can join."
  public static let emailDomainNeedsEmail = "Email domain emails people a link to join with, so Ember has to send email first. Set up email in Membership."
  public static let customDomainNotAHost = "Custom domain must be a host name, such as chat.example.com"
  public static let notACustomDomain = "A workers.dev or localhost address can't be a custom domain"
  public static let navigationIconsRefused = #"Navigation icons must give the rail's buttons and the appearance modes one of the room icons each, or "" for the default"#
  public static let emailFromRefused = "From must be an email address, such as ember@example.com, or a name and one, such as Ember <ember@example.com>"
  public static let sendingDomainRefused = "Expected a domain, such as example.com"
  public static let resendApiKeyRefused = "A Resend API key starts with re_. Copy it from API Keys in Resend."
  public static let turnstileSiteKeyRefused = "A site key starts with 0x. Copy it from your widget in Cloudflare Turnstile."
  public static let turnstileSecretKeyRefused = "A secret key starts with 0x. Copy it from your widget in Cloudflare Turnstile."
  public static let turnstileSecretKeyUnknown = "Cloudflare doesn't know that secret key. Copy it again from your widget in Cloudflare Turnstile."
  public static let turnstileKeysUnmatched = "That secret key isn't the site key's. Copy both keys from the same widget."
  public static let turnstileCheckExpired = "That check has expired. Pass it again."
  public static let turnstileKeysUnchecked = "Ember couldn't reach Cloudflare to check the keys. Try again."
  /** The page that hosts the Turnstile widget for checking keys (`TURNSTILE_CHECK_PATH`). */
  public static let turnstileCheckPath = "/account/turnstile_check"

  /** `FREE_EMAIL_DOMAINS`: domains anyone can have an address at, which Email domain warns about. */
  public static let freeEmailDomains = [
    "aol.com", "duck.com", "fastmail.com", "gmail.com", "gmx.com", "gmx.net", "googlemail.com", "hey.com", "hotmail.com", "icloud.com",
    "live.com", "mac.com", "mail.com", "me.com", "msn.com", "outlook.com", "pm.me", "proton.me", "protonmail.com", "qq.com", "tuta.com",
    "tutanota.com", "yahoo.com", "yandex.com", "zoho.com",
  ]

  /** `turnstileKeyOf` */
  public static func turnstileKey(of text: String) -> String? {
    let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return key.utf16.count <= 100 && key.wholeMatch(of: #/[0-9]x[\w-]{16,}/#) != nil ? key : nil
  }

  /** `resendApiKeyOf` */
  public static func resendApiKey(of text: String) -> String? {
    let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard key.utf16.count <= 256, key.hasPrefix("re_"), key.count > 3 else { return nil }
    return key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) ? key : nil
  }

  /** `emailDomainOf`: a domain as Email domain keeps it, lowercase, without a leading @. */
  public static func emailDomain(of text: String) -> String? {
    var typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if typed.hasPrefix("@") { typed.removeFirst() }
    guard !typed.isEmpty, typed.firstMatch(of: #/[\s\/\\?#@:\[\]%]/#) == nil,
          let host = URL(string: "http://\(typed)")?.host(percentEncoded: true)?.lowercased()
    else { return nil }
    let domain = #/(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?=[a-z0-9-]*[a-z])[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?/#
    return host.utf16.count <= 253 && host.wholeMatch(of: domain) != nil ? host : nil
  }

  /** `isNewer`: whether release `a` comes after `b`, betas before their release. */
  public static func isNewer(_ a: String, than b: String) -> Bool {
    let later = numbers(of: a)
    let earlier = numbers(of: b)
    guard let differs = later.indices.first(where: { $0 >= earlier.count || later[$0] != earlier[$0] }) else { return false }
    return later[differs] > (differs < earlier.count ? earlier[differs] : -1)
  }

  private static func numbers(of version: String) -> [Double] {
    guard let match = version.wholeMatch(of: #/(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?/#) else { return [] }
    let parts = [match.output.1, match.output.2, match.output.3].compactMap { Double(String($0)) }
    guard let beta = match.output.4 else { return parts + [.infinity] }
    return parts + [Double(String(beta))].compactMap { $0 }
  }
}

/** packages/protocol/src/blocked-words.ts: the words Blocked words keeps out, checked as the Worker does. */
public enum BlockedWords {
  public static let maxWords = 500
  public static let maxWordLength = 60
  public static let refused = "This community doesn't allow one of these words."
  public static let notAList = "Blocked words must be a list of words and phrases."
  public static let tooMany = "Blocked words can list at most 500 words and phrases."
  public static func tooLong(_ word: String) -> String { "\u{201C}\(word)\u{201D} is longer than 60 characters." }
  public static func unmatchable(_ word: String) -> String { "\u{201C}\(word)\u{201D} has no letters, numbers or emoji to match." }

  /** `wordsOf`: the words a text is matched by, folded as the Worker folds them. */
  public static func words(of text: String) -> [String] {
    let lower = text.decomposedStringWithCompatibilityMapping.lowercased().replacingOccurrences(of: "\u{03C2}", with: "\u{03C3}")
      .replacingOccurrences(of: "\u{00DF}", with: "ss")
    let kept = lower.unicodeScalars.filter { !isIgnoredMark($0) && $0.properties.generalCategory != .format }
    let folded = String(String.UnicodeScalarView(kept)).precomposedStringWithCanonicalMapping
    let range = NSRange(folded.startIndex..., in: folded)
    return wordPattern.matches(in: folded, range: range).compactMap { Range($0.range, in: folded).map { String(folded[$0]) } }
  }

  /** `blockedWordsTyped`: the list as typed, one per line or comma, once each. */
  public static func typed(_ text: String) -> [String] {
    var kept: [String: String] = [:]
    var order: [String] = []
    for word in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "," }).map(keptWord) where !word.isEmpty {
      let key = words(of: word).joined(separator: " ")
      let index = key.isEmpty ? word : key
      if kept[index] == nil {
        kept[index] = word
        order.append(index)
      }
    }
    return order.compactMap { kept[$0] }
  }

  /** `blockedWordsRefusal`: why the list can't be saved, or nil. */
  public static func refusal(_ words: [String]) -> String? {
    if words.count > maxWords { return tooMany }
    if let long = words.first(where: { $0.unicodeScalars.count > maxWordLength }) { return tooLong(long) }
    if let word = words.first(where: { self.words(of: $0).isEmpty }) { return unmatchable(word) }
    return nil
  }

  private static func keptWord(_ word: Substring) -> String {
    word.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  // `IGNORED_MARKS`: combining marks and variation selectors, which don't change a word.
  private static func isIgnoredMark(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 0x0300...0x036F, 0x1AB0...0x1AFF, 0x1DC0...0x1DFF, 0x20D0...0x20FF, 0xFE00...0xFE0F, 0xFE20...0xFE2F, 0xE0100...0xE01EF: true
    default: false
    }
  }

  private static let ownWord = #"[\p{Extended_Pictographic}\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Thai}\p{Script=Lao}\p{Script=Khmer}\p{Script=Myanmar}]"#
  private static let flag = #"\p{Regional_Indicator}{1,2}"#
  private static let wordPattern: NSRegularExpression = {
    do {
      return try NSRegularExpression(pattern: "(?:\(flag)|\(ownWord))\\p{M}*|(?:(?!\(ownWord))[\\p{L}\\p{N}\\p{M}])+")
    } catch {
      preconditionFailure("Blocked words' pattern: \(error)")
    }
  }()
}
