import Foundation

// The signed-in person's own account, other people's pages, and every way in: packages/protocol/src/index.ts.

/** `RoleChange` */
public struct RoleChange: Codable, Sendable {
  public var role: PersonRole
}

/** What changing someone's role, removing or banning them answers (`ChangedPerson`). */
public struct ChangedPerson: Codable, Sendable {
  public var user: DirectoryUser
}

/** Someone, as their page shows them (`Person`): administrators see their email address too. */
public struct Person: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  public var username: String?
  public var bio: String?
  public var role: Role
  public var status: UserStatus
  public var avatarUrl: String
  public var agent: Bool?
  public var adminsOnly: Bool?
  /** Administrators only: nil for someone who signed in with just a name. */
  public var emailAddress: String?
}

/** What `GET /api/users/<id>` answers (`PersonAnswer`). */
public struct PersonAnswer: Codable, Sendable {
  public var person: Person
  /** For administrators: a sign-in link's id for that person. */
  public var transferId: String?
  public var agent: AgentProfile?
}

/** The signed-in person's profile (`Profile`). */
public struct Profile: Codable, Hashable, Sendable {
  public var name: String
  public var username: String?
  public var emailAddress: String?
  public var bio: String?
  public var avatarUrl: String
  /** Whether they uploaded a photo. */
  public var avatar: Bool
  /** Whether they have a password, which Current password asks for. */
  public var password: Bool
  public var membershipNeeded: Bool
  public var memberful: MemberfulStatus?
  public var sso: SsoStatus?
  public var assistant: YourAssistant?
  public var apps: [YourApp]
  public var outsideAi: [OutsideConnection]?
}

/** `ProfileAnswer`: the profile, and a fresh sign-in link's id. */
public struct ProfileAnswer: Codable, Sendable {
  public var profile: Profile
  public var transferId: String
}

/** What `PATCH /api/users/me/profile` changes (`ProfileChanges`). A blank password keeps yours. */
public struct ProfileChanges: Codable, Sendable {
  public var name: String?
  public var username: String?
  public var emailAddress: String?
  public var password: String?
  public var bio: String?
  public var currentPassword: String?
  public var pushSubscriptionEndpoint: String?

  public init(
    name: String? = nil, username: String? = nil, emailAddress: String? = nil, password: String? = nil, bio: String? = nil,
    currentPassword: String? = nil, pushSubscriptionEndpoint: String? = nil
  ) {
    self.name = name
    self.username = username
    self.emailAddress = emailAddress
    self.password = password
    self.bio = bio
    self.currentPassword = currentPassword
    self.pushSubscriptionEndpoint = pushSubscriptionEndpoint
  }
}

/** What deleting your account takes (`AccountDeletion`): your password, or your name if you have none. */
public struct AccountDeletion: Codable, Sendable {
  public var currentPassword: String?
  public var name: String?

  public init(currentPassword: String? = nil, name: String? = nil) {
    self.currentPassword = currentPassword
    self.name = name
  }
}

/** An account to create (`SignUp`, `OpenSignUp` with `turnstileToken`). */
public struct SignUp: Codable, Sendable {
  public var name: String
  public var emailAddress: String
  public var password: String
  public var turnstileToken: String?

  public init(name: String, emailAddress: String, password: String, turnstileToken: String? = nil) {
    self.name = name
    self.emailAddress = emailAddress
    self.password = password
    self.turnstileToken = turnstileToken
  }
}

/** An account to create with an emailed link's token (`EmailLinkSignUp`). */
public struct EmailLinkSignUp: Codable, Sendable {
  public var token: String
  public var name: String
  public var password: String

  public init(token: String, name: String, password: String) {
    self.token = token
    self.name = name
    self.password = password
  }
}

/** `EmailLinkKind`: an administrator's invitation, or a link an email domain's address asked for. */
public enum EmailLinkKind: String, Codable, Sendable {
  case invitation
  case emailDomain = "email_domain"

  /** Where its sign-up goes (`EMAIL_LINK_JOINS`). */
  public var joinPath: String {
    switch self {
    case .invitation: "/api/join/invitation"
    case .emailDomain: "/api/join/email"
    }
  }
}

/** What looking up an emailed link answers (`EmailLinkFor`). */
public struct EmailLinkFor: Codable, Sendable {
  public var kind: EmailLinkKind
  public var emailAddress: String
}

/** `EmailLinkRequest`, `PasswordResetRequest` */
public struct EmailRequest: Codable, Sendable {
  public var emailAddress: String
  public var turnstileToken: String?

  public init(emailAddress: String, turnstileToken: String? = nil) {
    self.emailAddress = emailAddress
    self.turnstileToken = turnstileToken
  }
}

/** `PasswordResetWithCode` */
public struct PasswordResetWithCode: Codable, Sendable {
  public var emailAddress: String
  public var code: String
  public var password: String

  public init(emailAddress: String, code: String, password: String) {
    self.emailAddress = emailAddress
    self.code = code
    self.password = password
  }
}

/** `PasswordResetDone`: who's signed in now, or nil for someone who signs in elsewhere. */
public struct PasswordResetDone: Codable, Sendable {
  public var user: Me?
}

/** What first run answers (`NewWorkspace`): its first administrator and room. */
public struct NewWorkspace: Codable, Sendable {
  public var user: Me
  public var room: Room
}

/** `PasswordSignIn` */
public struct PasswordSignIn: Codable, Sendable {
  public var emailAddress: String
  public var password: String
  public var returnTo: String?

  public init(emailAddress: String, password: String, returnTo: String? = nil) {
    self.emailAddress = emailAddress
    self.password = password
    self.returnTo = returnTo
  }
}

/** `LinkSignIn` */
public struct LinkSignIn: Codable, Sendable {
  public var transferId: String
}

/** A photo to send with a form: the file as chosen, and the square variant within 512 px Ember shows. */
public struct ChosenPhoto: Sendable {
  public var data: Data
  public var fileName: String
  public var contentType: String
  public var variant: Data?
  public var variantContentType: String

  public init(data: Data, fileName: String, contentType: String, variant: Data?, variantContentType: String) {
    self.data = data
    self.fileName = fileName
    self.contentType = contentType
    self.variant = variant
    self.variantContentType = variantContentType
  }
}

/** A logo to send: the file as chosen, and its 512 and 192 px variants. */
public struct ChosenLogo: Sendable {
  public var data: Data
  public var fileName: String
  public var contentType: String
  public var large: Data?
  public var small: Data?
  public var variantContentType: String

  public init(data: Data, fileName: String, contentType: String, large: Data?, small: Data?, variantContentType: String) {
    self.data = data
    self.fileName = fileName
    self.contentType = contentType
    self.large = large
    self.small = small
    self.variantContentType = variantContentType
  }
}

/** One of the people the composer's @ prompt offers, as `/api/autocompletable/users` lists them. */
public struct MentionPromptItem: Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  public var username: String?
  public var agent: Bool
  public var avatarUrl: String?
}

/** Reads the `<lexxy-prompt-item>` list `/api/autocompletable/users` answers (`mentionPromptItem`). */
public enum MentionPrompt {
  public static func items(in html: String) throws -> [MentionPromptItem] {
    var items: [MentionPromptItem] = []
    for match in html.matches(of: #/<lexxy-prompt-item search="([^"]*)" sgid="([^"]*)">([\s\S]*?)<\/lexxy-prompt-item>/#) {
      let menu = String(match.output.3)
      let username = menu.firstMatch(of: #/class="autocompletable__username">@([^<]*)<\/span>/#).map { unescape(String($0.output.1)) }
      let avatar = menu.firstMatch(of: #/<img class="avatar"[^>]* src="([^"]*)"/#).map { unescape(String($0.output.1)) }
      let id = unescape(String(match.output.2))
      guard !id.isEmpty else { throw EmberError.notEmber }
      items.append(MentionPromptItem(
        id: id, name: unescape(String(match.output.1)), username: username, agent: menu.contains("autocompletable__badge"), avatarUrl: avatar))
    }
    if items.isEmpty, html.contains("<lexxy-prompt-item") { throw EmberError.notEmber }
    return items
  }

  /** `htmlEscape` undone. */
  static func unescape(_ text: String) -> String {
    text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
  }
}
