import Foundation

// Signing in elsewhere: Memberful (packages/protocol/src/index.ts, memberful.ts) and single sign-on
// (sso.ts).

/** The Memberful or SSO account someone's is connected to (`MemberfulAccount`, `SsoAccount`). */
public struct ElsewhereAccount: Codable, Hashable, Sendable {
  public var name: String?
  public var emailAddress: String?
}

/** `MemberfulStatus`: whether Memberful is members only, and the account yours is connected to. */
public struct MemberfulStatus: Codable, Hashable, Sendable {
  public var membersOnly: Bool
  public var connected: ElsewhereAccount?
}

/** `SsoStatus` */
public struct SsoStatus: Codable, Hashable, Sendable {
  public var name: String
  public var ssoOnly: Bool
  public var connected: ElsewhereAccount?
}

/**
 * Where to connect an account elsewhere to keep signing in (`ElsewhereConnection`): what `POST /api/session`
 * answers with 202 once a workspace has moved to Memberful or SSO, and what starting a connection answers.
 */
public struct ElsewhereConnection: Codable, Hashable, Sendable {
  public var memberfulConnection: String?
  public var ssoConnection: String?

  /** Each place to connect, named as the sign-in page names them: Memberful, and the SSO provider as `ssoName`. */
  public func connections(ssoName: String) -> [(name: String, url: String)] {
    var connections: [(name: String, url: String)] = []
    if let memberfulConnection { connections.append(("Memberful", memberfulConnection)) }
    if let ssoConnection { connections.append((ssoName, ssoConnection)) }
    return connections
  }
}

/** `MemberfulConnectionStart`, `SsoConnectionStart` */
public struct ConnectionStart: Codable, Sendable {
  public var currentPassword: String?

  public init(currentPassword: String? = nil) {
    self.currentPassword = currentPassword
  }
}

/** `MemberfulDisconnection`, `SsoDisconnection` */
public struct Disconnection: Codable, Sendable {
  public var currentPassword: String?
  public var pushSubscriptionEndpoint: String?

  public init(currentPassword: String? = nil, pushSubscriptionEndpoint: String? = nil) {
    self.currentPassword = currentPassword
    self.pushSubscriptionEndpoint = pushSubscriptionEndpoint
  }
}

/** Memberful's keys as Set up Memberful saves them (`MemberfulKeysChange`). */
public struct MemberfulKeysChange: Codable, Sendable {
  public var site: String
  public var apiKey: String
  public var clientId: String
  public var clientSecret: String
  public var webhookSecret: String

  public init(site: String, apiKey: String, clientId: String, clientSecret: String, webhookSecret: String) {
    self.site = site
    self.apiKey = apiKey
    self.clientId = clientId
    self.clientSecret = clientSecret
    self.webhookSecret = webhookSecret
  }
}

/** What saving Memberful's keys answers (`MemberfulSaved`). */
public struct MemberfulSaved: Codable, Sendable {
  public var memberfulSite: String?
  public var memberfulWebhooks: Bool
  public var memberfulKeys: KeySource?
  public var memberfulSiteKept: String?
}

/** Where a secret comes from: the deployment's secrets, or what an administrator saved. */
public enum KeySource: String, Codable, Sendable {
  case secret, saved
}

public enum Memberful {
  public static let signInPath = "/auth/memberful"
  public static let callbackPath = "/auth/memberful/callback"
  public static let webhookPath = "/webhooks/memberful"
  public static let connectionsPath = "/api/users/me/memberful_connections"
  public static let problemParam = "memberful"
  public static let connected = "connected"
  public static let connectedNotice = "Your Memberful account is connected."
  public static let disconnectedNotice = "Your Memberful account is disconnected."
  public static let passwordNeeded = "Enter your password to connect Memberful."
  public static let disconnectPasswordNeeded = "Enter your password to disconnect Memberful."
  public static let disconnectWithoutPassword = "You sign in with Memberful alone, so it can't be disconnected."
  public static let disconnectWithoutEmail = "Add your email address first, so that you can still sign in once Memberful is disconnected."
  public static let notConnected = "Your account isn't connected to a Memberful account."
  public static let signInNeeded = "Members sign in with Memberful. Only administrators and invited people sign in with a password."
  public static let withSso = "You sign in with single sign-on, so Memberful can't be connected too."
  public static let siteRefused = "Give your Memberful site's address, such as yoursite.memberful.com."
  public static let apiKeyRefused = "Copy the API Key from your custom app in Memberful."
  public static let clientIdRefused = "Copy the OAuth Identifier from your custom app in Memberful."
  public static let clientSecretRefused = "Copy the OAuth Secret from your custom app in Memberful."
  public static let webhookSecretRefused = "Copy the secret key from your webhook in Memberful."
  public static let siteUnreachable = "Ember couldn't reach a site at that address. Check your Memberful site's address."
  public static let siteUnknown = "That isn't a Memberful site's address. Give the one your members sign in at, such as yoursite.memberful.com."
  public static let apiKeyUnknown = "Memberful didn't take that API Key. Copy it again from your custom app."
  public static let clientUnknown = "Memberful doesn't know that OAuth Identifier and Secret together. Copy both again from your custom app."
  public static let keysUnchecked = "Ember couldn't check the keys with Memberful. Try again."
  public static func siteKept(_ site: String) -> String { "People here sign in with their accounts at \(site), so Ember keeps that site." }

  /** `MEMBERFUL_SIGN_IN_PROBLEMS`, by the `memberful` query value. */
  public static let signInProblems: [String: String] = [
    "failed": "Signing in with Memberful didn't work. Try again.",
    "membership": "Your Memberful account has no active membership.",
    "taken": "Someone here has your Memberful email address already. If that's you, sign in with your password.",
    "claimed": "That Memberful account is connected to someone else here.",
    "another": "Your account is connected to another Memberful account already.",
    "off": "Joining with Memberful is off.",
    "unneeded": "Memberful isn't members only anymore, so there's nothing to connect. Your password signs you in.",
    "unavailable": "Memberful sign-in isn't set up. Ask an administrator for help.",
    "refused": EmberText.signInRefused,
  ]

  /** `memberfulSignInPath` */
  public static func signInPath(returnTo: String?) -> String {
    guard let returnTo else { return signInPath }
    return "\(signInPath)?return_to=\(URIComponent.encode(returnTo))"
  }

  /** `memberfulKeyOf`: printable ASCII, at most 255. */
  public static func key(of text: String) -> String? {
    let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return !key.isEmpty && key.utf16.count <= 255 && key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) ? key : nil
  }
}

/** The single sign-on provider, as the Single sign-on card shows it (`SsoSettings`). */
public struct SsoSettings: Codable, Hashable, Sendable {
  public var source: KeySource
  public var issuer: String
  public var clientId: String
  public var name: String
  public var scopes: [String]
  public var groupsClaim: String
  public var allowedGroups: [String]
  public var linksVerifiedEmails: Bool
}

/** What Set up single sign-on saves (`SsoSetup`). Left out, the issuer, client ID and secret stay. */
public struct SsoSetup: Codable, Sendable {
  public var issuer: String?
  public var clientId: String?
  public var clientSecret: String?
  public var name: String
  public var scopes: [String]
  public var groupsClaim: String
  public var allowedGroups: [String]
  public var linksVerifiedEmails: Bool

  public init(
    issuer: String? = nil, clientId: String? = nil, clientSecret: String? = nil, name: String, scopes: [String], groupsClaim: String,
    allowedGroups: [String], linksVerifiedEmails: Bool
  ) {
    self.issuer = issuer
    self.clientId = clientId
    self.clientSecret = clientSecret
    self.name = name
    self.scopes = scopes
    self.groupsClaim = groupsClaim
    self.allowedGroups = allowedGroups
    self.linksVerifiedEmails = linksVerifiedEmails
  }
}

/** `SsoSaved` / `SsoForgotten` */
public struct SsoAnswer: Codable, Sendable {
  public var sso: SsoSettings?
}

public enum SSO {
  public static let defaultName = "SSO"
  public static let defaultGroupsClaim = "groups"
  public static let maxIssuerLength = 2048
  public static let maxClientIdLength = 255
  public static let maxClientSecretLength = 1024
  public static let maxNameLength = 40
  public static let maxScopes = 20
  public static let maxGroups = 50
  public static let maxTokenLength = 255
  public static let signInPath = "/auth/sso"
  public static let callbackPath = "/auth/sso/callback"
  public static let logoutPath = "/auth/sso/backchannel_logout"
  public static let settingsPath = "/api/account/sso"
  public static let connectionsPath = "/api/users/me/sso_connections"
  public static let problemParam = "sso"
  public static let connected = "connected"
  public static let connectedNotice = "Single sign-on connected."
  public static let disconnectedNotice = "Single sign-on disconnected."
  public static let signInNeeded = "This workspace uses single sign-on. Only administrators and invited people can sign in with a password."
  public static let memberfulOrSsoSignInNeeded = "Members sign in with Memberful or single sign-on. Only administrators and invited people can sign in with a password."
  public static let passwordNeeded = "Enter your password to connect single sign-on."
  public static let disconnectPasswordNeeded = "Enter your password to disconnect single sign-on."
  public static let disconnectWithoutPassword = "You sign in with single sign-on alone, so it can't be disconnected."
  public static let disconnectWithoutEmail = "Add an email address before you disconnect, so you can still sign in."
  public static let notConnected = "Single sign-on isn't connected."
  public static let passwordWithSso = "You sign in with single sign-on, so there's no password to set."
  public static let withMemberful = "You sign in with Memberful, so single sign-on can't be connected too."
  public static let setupNeeded = "Set up single sign-on first."
  public static let openWithSso = "Open and SSO only can't be on at the same time."
  public static let forbidden = "Only administrators can set up single sign-on"
  public static let issuerRefused = "Enter your provider's issuer URL, like https://auth.example.com."
  public static let clientIdRefused = "Enter the Client ID from your provider."
  public static let clientSecretRefused = "Enter the Client Secret from your provider."
  public static let nameRefused = "Use 40 characters or fewer."
  public static let scopesRefused = "Enter up to 20 scopes, separated by spaces."
  public static let groupsClaimRefused = "Enter a claim name without spaces, like groups."
  public static let groupsRefused = "Enter up to 50 groups, one per line."
  public static let issuerUnreachable = "Couldn't reach your provider. Check the issuer URL and try again."
  public static let issuerMismatch = "This issuer URL doesn't match your provider's. Enter it exactly as your provider shows it."
  public static let clientUnchecked = "Enter a Client ID and Client Secret first."
  public static let issuerUnsupported = "This provider doesn't support the authorization code flow with PKCE (S256)."

  /** `SSO_SIGN_IN_PROBLEMS`, by the `sso` query value. */
  public static let signInProblems: [String: String] = [
    "failed": "Couldn't sign in with single sign-on. Try again.",
    "membership": "Your account doesn't have access to this workspace. Contact an administrator.",
    "taken": "An account with your email address already exists. Sign in with your password instead.",
    "claimed": "This account is already connected to another member.",
    "another": "Your account is already connected to a different single sign-on account.",
    "off": "New members can't join with single sign-on.",
    "unneeded": "Single sign-on is no longer required. Sign in with your password.",
    "refused": "Too many requests or unauthorized.",
    "unavailable": "Single sign-on isn't set up. Contact an administrator.",
  ]

  /** `ssoSignInPath` */
  public static func signInPath(returnTo: String?) -> String {
    guard let returnTo else { return signInPath }
    return "\(signInPath)?return_to=\(URIComponent.encode(returnTo))"
  }
}
