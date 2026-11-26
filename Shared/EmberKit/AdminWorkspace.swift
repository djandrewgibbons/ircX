import Foundation

// Workspace administration as the web's settings pages do it (apps/web/src/components/workspace:
// ways-to-join.tsx, email-settings.tsx, email-domain-settings.tsx, invite-by-email.tsx,
// custom-domain-settings.tsx, ember-version.tsx, memberful-setup.tsx, sso-setup.tsx), and the parsers of
// packages/protocol they run before asking the server.

// MARK: - Ways to join

/** A way to join's switch (`WaySetting`). */
public enum JoinWay: String, CaseIterable, Sendable {
  case openSignUp, joinLink, emailDomainSignUp, memberfulJoin, memberfulSignIn, ssoJoin, ssoSignIn

  /** `{settings: {<way>: on}}`. */
  public func settings(_ on: Bool) -> AccountSettings {
    switch self {
    case .openSignUp: AccountSettings(openSignUp: on)
    case .joinLink: AccountSettings(joinLink: on)
    case .emailDomainSignUp: AccountSettings(emailDomainSignUp: on)
    case .memberfulJoin: AccountSettings(memberfulJoin: on)
    case .memberfulSignIn: AccountSettings(memberfulSignIn: on)
    case .ssoJoin: AccountSettings(ssoJoin: on)
    case .ssoSignIn: AccountSettings(ssoSignIn: on)
    }
  }

  /** Its name, as `SETTING_NAMES` has it. */
  public var name: String { AccountSettings.names[rawValue] ?? rawValue }
}

/**
 * Who can join, as the Membership cards show it (web `WaysToJoin`): each switch where it was moved to
 * while that saves, else as the workspace has it, and why a way is set aside while another overrides it.
 */
public struct WaysToJoin: Sendable {
  public var account: Account
  /** Where each switch was moved to, while that's saved. */
  public var moved: [JoinWay: Bool]
  /** Whether a Memberful site is set up (`settings.memberfulSite !== null`). */
  public var memberfulSetUp: Bool
  /** Whether a single sign-on provider is set up (`settings.sso !== null`). */
  public var ssoSetUp: Bool

  public init(account: Account, moved: [JoinWay: Bool] = [:], memberfulSetUp: Bool, ssoSetUp: Bool) {
    self.account = account
    self.moved = moved
    self.memberfulSetUp = memberfulSetUp
    self.ssoSetUp = ssoSetUp
  }

  public var open: Bool { moved[.openSignUp] ?? account.openSignUp }
  public var link: Bool { moved[.joinLink] ?? account.joinLink }
  public var emailDomain: Bool { moved[.emailDomainSignUp] ?? account.emailDomainSignUp }
  /** Turning an only-switch on turns its way on with it, as the server does. */
  public var memberful: Bool { moved[.memberfulJoin] ?? (moved[.memberfulSignIn] == true || account.memberfulJoin) }
  public var membersOnly: Bool { memberful && (moved[.memberfulSignIn] ?? account.memberfulSignIn) }
  public var sso: Bool { moved[.ssoJoin] ?? (moved[.ssoSignIn] == true || account.ssoJoin) }
  public var ssoOnly: Bool { sso && (moved[.ssoSignIn] ?? account.ssoSignIn) }

  /** A way sets the others aside while it's on, until turning it off is saved. */
  var openOverrides: Bool { open || account.openSignUp }
  var membersOnlyOverrides: Bool { membersOnly || account.memberfulSignIn }
  var ssoOnlyOverrides: Bool { ssoOnly || account.ssoSignIn }

  /** Why the ways people who sign in only elsewhere turn off are greyed out, if they are. */
  var elsewhereOnly: String? {
    if membersOnlyOverrides && ssoOnlyOverrides { return AdminText.eitherOnlyOverrides }
    if membersOnlyOverrides { return AdminText.membersOnlyOverrides }
    if ssoOnlyOverrides { return AdminText.ssoOnlyOverrides }
    return nil
  }

  /** Why each card's switch can't be moved, said in place of what it does, or nil. */
  public var openSetAside: String? { open ? nil : elsewhereOnly }
  public var linkSetAside: String? { elsewhereOnly ?? (openOverrides ? AdminText.openOverrides : nil) }
  public var emailDomainSetAside: String? { linkSetAside }
  public var memberfulSetAside: String? { membersOnly ? nil : openOverrides ? AdminText.openOverrides : nil }
  public var ssoSetAside: String? { ssoOnly ? nil : openOverrides ? AdminText.openOverrides : nil }

  /** Memberful's switch: beside SSO only it's Members only's. */
  public var memberfulChecked: Bool { ssoOnly ? membersOnly : memberful }
  public var ssoChecked: Bool { membersOnly ? ssoOnly : sso }
  /** What the card says in place of its only-switch while the other way is the only way in. */
  public var memberfulBeside: String? { ssoOnly ? AdminText.membersOnlyBesideSso : nil }
  public var ssoBeside: String? { membersOnly ? AdminText.ssoOnlyBesideMemberful : nil }
  /** What the card says while the other way's only-switch closes it. */
  public var memberfulClosed: String? { ssoOnly && !membersOnly ? AdminText.memberfulClosed : nil }
  public var ssoClosed: String? { membersOnly && !ssoOnly ? AdminText.ssoClosed : nil }

  /** Whether each switch waits for a move in flight (web `memberfulSaving`, `ssoSaving`). */
  public var memberfulSaving: Bool { moved[.memberfulJoin] != nil || (ssoOnly && moved[.ssoSignIn] != nil) }
  public var ssoSaving: Bool { moved[.ssoJoin] != nil || (membersOnly && moved[.memberfulSignIn] != nil) }

  /** What turning `way` on asks first, if anything (`questionFor`). */
  public func question(turningOn way: JoinWay) -> String? {
    switch way {
    case .openSignUp: return AdminText.confirmOpen
    case .memberfulSignIn: return AdminText.confirmMembersOnly + (ssoSetUp && !ssoOnly ? AdminText.closesSso : "")
    case .ssoSignIn: return AdminText.confirmSsoOnly + (memberfulSetUp && !membersOnly ? AdminText.closesMemberful : "")
    default: return nil
    }
  }

  /**
   * What flipping the Memberful card's main switch saves (web `switchBeside`): beside SSO only, on turns
   * Members only on and off turns Memberful off; otherwise Memberful itself. Nil while a move it waits for
   * is in flight.
   */
  public func memberfulFlip(_ on: Bool) -> (way: JoinWay, asks: Bool)? {
    guard ssoOnly else { return moved[.memberfulJoin] == nil ? (.memberfulJoin, true) : nil }
    guard moved[.memberfulJoin] == nil, moved[.memberfulSignIn] == nil, moved[.ssoSignIn] == nil else { return nil }
    return on ? (.memberfulSignIn, false) : (.memberfulJoin, true)
  }

  public func ssoFlip(_ on: Bool) -> (way: JoinWay, asks: Bool)? {
    guard membersOnly else { return moved[.ssoJoin] == nil ? (.ssoJoin, true) : nil }
    guard moved[.ssoJoin] == nil, moved[.ssoSignIn] == nil, moved[.memberfulSignIn] == nil else { return nil }
    return on ? (.ssoSignIn, false) : (.ssoJoin, true)
  }
}

// MARK: - Validation and addresses

/** An email address, and the name its email is sent under (`Mailbox`). */
public struct Mailbox: Equatable, Sendable {
  public var name: String?
  public var address: String

  public init(name: String?, address: String) {
    self.name = name
    self.address = address
  }

  /** `mailboxOf`: an address, or a name, in quotes or not, and an address in angle brackets. */
  public init?(_ text: String) {
    let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var given = ""
    var address = typed
    if let open = typed.lastIndex(of: "<"), typed.hasSuffix(">") {
      let inside = typed[typed.index(after: open)..<typed.index(before: typed.endIndex)]
      if !inside.contains(">") {
        given = typed[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        address = inside.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    var name = given
    if name.count >= 2, name.hasPrefix("\""), name.hasSuffix("\"") { name = String(name.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
    guard EmberRules.isEmailAddress(address) else { return nil }
    guard name.utf16.count <= EmberLimits.maxUserNameLength,
          !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || "\"\\<>".unicodeScalars.contains($0) })
    else { return nil }
    self.name = name.isEmpty ? nil : name
    self.address = address
  }

  /** `mailboxText`: as a From line writes it. */
  public var text: String {
    guard let name else { return address }
    let quoted = name.contains(where: { "()[]:;@,.".contains($0) })
    return "\(quoted ? "\"\(name)\"" : name) <\(address)>"
  }

  /** The domain of the address, which Cloudflare Email Sending onboards. */
  public var domain: String { address.split(separator: "@").last.map(String.init) ?? address }
}

extension WorkspaceRules {
  /** `isHost`: a host as `location.host` writes one, lowercase labels and maybe a port. */
  public static func isHost(_ host: String) -> Bool {
    guard host.utf16.count <= 253 + ":65535".count,
          let match = host.wholeMatch(of: #/([a-z0-9-]+(?:\.[a-z0-9-]+)*)(?::([1-9][0-9]{0,4}))?/#),
          match.output.1.utf16.count <= 253
    else { return false }
    if let port = match.output.2 {
      guard let number = Int(port), number <= 65_535 else { return false }
    }
    return true
  }

  /** `canBeCustomDomain`: any host name but where a deploy or `wrangler dev` puts Ember. */
  public static func canBeCustomDomain(_ hostname: String) -> Bool {
    hostname.lowercased().firstMatch(of: #/(?:^|\.)workers\.dev$|^localhost$|^127(?:\.[0-9]{1,3}){3}$|^\[::1\]$/#) == nil
  }

  /** `isCustomDomainHost` */
  public static func isCustomDomainHost(_ host: String) -> Bool { isHost(host) && canBeCustomDomain(hostname(of: host)) }

  /** The host name of `host`, without its port, as Cloudflare takes a domain. */
  public static func hostname(of host: String) -> String { host.replacing(#/:\d+$/#, with: "") }

  /** `othersAfterMove`: the addresses Ember moved away from, newest first, at most five, without where it went. */
  public static func othersAfterMove(_ others: [String], left: [String?], to: String?) -> [String] {
    var seen = Set<String>()
    let moved = left.compactMap { $0 }.filter(isCustomDomainHost)
    return Array((moved + others).filter { seen.insert($0).inserted && $0 != to }.prefix(EmberLimits.maxOtherAddresses))
  }

  /** `domainTyped`: the host typed, with or without its scheme and path, or why it can't be a custom domain. */
  public static func domainTyped(_ text: String) -> Result<String, CustomDomainRefusal> {
    let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasScheme = typed.firstMatch(of: #/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//#) != nil
    guard !typed.isEmpty, let url = URL(string: hasScheme ? typed : "https://\(typed)"), let name = url.host(percentEncoded: true)?.lowercased() else {
      return .failure(CustomDomainRefusal(message: customDomainNotAHost))
    }
    var host = name
    if let port = url.port { host += ":\(port)" }
    guard isHost(host) else { return .failure(CustomDomainRefusal(message: customDomainNotAHost)) }
    return canBeCustomDomain(name) ? .success(host) : .failure(CustomDomainRefusal(message: notACustomDomain))
  }

  /** The domain a host name was most likely registered as (`registeredGuess`). */
  public static func registeredGuess(_ hostname: String) -> String {
    let labels = hostname.split(separator: ".").map(String.init)
    let secondLevels: Set<String> = ["ac", "co", "com", "edu", "gov", "net", "org"]
    let kept = labels.count > 2 && labels[labels.count - 1].count == 2 && secondLevels.contains(labels[labels.count - 2]) ? 3 : 2
    return labels.suffix(kept).joined(separator: ".")
  }

  /** The name of the Worker at a workers.dev address (`workerAt`). */
  public static func worker(at host: String) -> String? {
    host.lowercased().wholeMatch(of: #/([a-z0-9-]+)\.[a-z0-9-]+\.workers\.dev/#).map { String($0.output.1) }
  }

  /** `domainsInWords`: "a.com, b.com or c.com". */
  public static func domainsInWords(_ domains: [String]) -> String {
    guard domains.count >= 2, let last = domains.last else { return domains.joined() }
    return "\(domains.dropLast().joined(separator: ", ")) or \(last)"
  }

  /** The domains typed in Email domain's field, as kept, and the words that aren't domains (web `add`). */
  public static func emailDomainsTyped(_ text: String) -> (domains: [String], refused: [String]) {
    let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" }).map(String.init)
    return (words.compactMap(emailDomain(of:)), words.filter { emailDomain(of: $0) == nil })
  }

  /** `sendsEmail`: whether Ember can send email, with a provider and a From address. */
  public static func sendsEmail(_ email: EmailSettings) -> Bool { email.provider != nil && email.from != nil }
}

/** Why a typed custom domain was refused. */
public struct CustomDomainRefusal: Error, Equatable, Sendable {
  public var message: String
}

extension Memberful {
  /** `memberfulSiteOf`: a Memberful site's origin from `yoursite`, `yoursite.memberful.com` or an address. */
  public static func site(of text: String) -> String? {
    let given = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !given.isEmpty, given.utf16.count <= 2048 else { return nil }
    let address: String
    if given.wholeMatch(of: #/[a-zA-Z\d](?:[a-zA-Z\d-]*[a-zA-Z\d])?/#) != nil {
      address = "https://\(given).memberful.com"
    } else if given.firstMatch(of: #/^[a-zA-Z][a-zA-Z\d+.-]*:\/\//#) != nil {
      address = given
    } else {
      address = "https://\(given)"
    }
    guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: true)?.lowercased(),
          url.user == nil, url.password == nil,
          host.wholeMatch(of: #/(?:[a-z\d](?:[a-z\d-]*[a-z\d])?\.)*[a-z\d](?:[a-z\d-]*[a-z\d])?\.?|\[[\da-f:.]+\]/#) != nil
    else { return nil }
    let loopback = host == "localhost" || host.hasSuffix(".localhost") || host.hasPrefix("127.") || host == "[::1]"
    guard scheme == "https" || (scheme == "http" && loopback) else { return nil }
    var origin = "\(scheme)://\(host)"
    if let port = url.port, port != (scheme == "https" ? 443 : 80) { origin += ":\(port)" }
    return origin
  }

  /** Where Memberful's form for a new custom app is, for a site at memberful.com (`memberfulNewApp`). */
  public static func newAppPage(_ site: String) -> String? {
    site.hasSuffix(".memberful.com") ? "\(site)/admin/settings/custom_applications/new" : nil
  }

  public static func newWebhookPage(_ site: String) -> String? {
    site.hasSuffix(".memberful.com") ? "\(site)/admin/settings/webhooks/new" : nil
  }

  /** `parseMemberfulKeysChange`'s client half: each field's refusal, top to bottom. */
  public static func refusal(site: String, apiKey: String, clientId: String, clientSecret: String, webhookSecret: String)
    -> (field: String, message: String)?
  {
    if self.site(of: site) == nil { return ("site", siteRefused) }
    if key(of: apiKey) == nil { return ("apiKey", apiKeyRefused) }
    if key(of: clientId) == nil { return ("clientId", clientIdRefused) }
    if key(of: clientSecret) == nil { return ("clientSecret", clientSecretRefused) }
    if key(of: webhookSecret) == nil { return ("webhookSecret", webhookSecretRefused) }
    return nil
  }
}

extension SSO {
  /** `isToken` */
  static func isToken(_ text: String) -> Bool {
    !text.isEmpty && text.utf16.count <= maxTokenLength && !text.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.value < 0x20 || $0.value == 0x7F })
  }

  /** The words of `text`, apart by spaces or lines, trimmed, without blanks or repeats (`wordsOf`). */
  static func words(_ text: String, lines: Bool) -> [String] {
    let items = lines ? text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) : text.split(whereSeparator: \.isWhitespace).map(String.init)
    var seen = Set<String>()
    return items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  /**
   * `parseSsoSetup`: what Set up single sign-on sends, or the refusal and its field. Blank issuer, client
   * ID and secret are left out, as while the deployment's secrets give them.
   */
  public static func setup(
    issuer: String?, clientId: String?, clientSecret: String?, name: String, scopes: String, groupsClaim: String, allowedGroups: String,
    linksVerifiedEmails: Bool
  ) -> Result<SsoSetup, SsoRefusal> {
    let issuer = issuer?.trimmingCharacters(in: .whitespacesAndNewlines)
    let clientId = clientId?.trimmingCharacters(in: .whitespacesAndNewlines)
    let clientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let groupsClaim = groupsClaim.trimmingCharacters(in: .whitespacesAndNewlines)
    if let issuer, issuer.utf16.count > maxIssuerLength || issuer.wholeMatch(of: #/[hH][tT][tT][pP][sS]?:\/\/[^\s\/?#]+[^\s?#]*/#) == nil {
      return .failure(SsoRefusal(field: "issuer", message: issuerRefused))
    }
    if let clientId, clientId.isEmpty || clientId.utf16.count > maxClientIdLength { return .failure(SsoRefusal(field: "clientId", message: clientIdRefused)) }
    if let clientSecret, clientSecret.utf16.count > maxClientSecretLength {
      return .failure(SsoRefusal(field: "clientSecret", message: clientSecretRefused))
    }
    if name.utf16.count > maxNameLength { return .failure(SsoRefusal(field: "name", message: nameRefused)) }
    if !groupsClaim.isEmpty, !isToken(groupsClaim) { return .failure(SsoRefusal(field: "groupsClaim", message: groupsClaimRefused)) }
    let scopeWords = words(scopes, lines: false)
    if scopeWords.count > maxScopes || !scopeWords.allSatisfy(isToken) { return .failure(SsoRefusal(field: "scopes", message: scopesRefused)) }
    let groups = words(allowedGroups, lines: true)
    if groups.count > maxGroups || !groups.allSatisfy({ $0.utf16.count <= maxTokenLength }) {
      return .failure(SsoRefusal(field: "allowedGroups", message: groupsRefused))
    }
    return .success(SsoSetup(
      issuer: issuer.flatMap { $0.isEmpty ? nil : $0 }, clientId: clientId.flatMap { $0.isEmpty ? nil : $0 },
      clientSecret: clientSecret.flatMap { $0.isEmpty ? nil : $0 }, name: name.isEmpty ? defaultName : name, scopes: scopeWords,
      groupsClaim: groupsClaim.isEmpty ? defaultGroupsClaim : groupsClaim, allowedGroups: groups, linksVerifiedEmails: linksVerifiedEmails))
  }
}

/** Why Set up single sign-on can't save, on the field it's about. */
public struct SsoRefusal: Error, Equatable, Sendable {
  public var field: String
  public var message: String

  public init(field: String, message: String) {
    self.field = field
    self.message = message
  }
}

// MARK: - Invitations

public enum Invitations {
  /** The addresses in `INVITATIONS_AT_ONCE`s, as Send invitations sends them, one request after another. */
  public static func batches(_ addresses: [String]) -> [[String]] {
    stride(from: 0, to: addresses.count, by: EmberLimits.invitationsAtOnce).map {
      Array(addresses[$0..<min($0 + EmberLimits.invitationsAtOnce, addresses.count)])
    }
  }

  /** `refusalOf`: why nothing was sent. */
  public static func refusal(_ refused: [String]) -> String {
    guard !refused.isEmpty else { return "\(EmberText.noEmailAddresses)." }
    let one = refused.count == 1
    return "\(one ? "This isn't an email address" : "These aren't email addresses"): \(refused.joined(separator: ", ")). Fix or remove \(one ? "it" : "them"), then send again."
  }

  /** `summaryOf`: what came of each address invited, in a sentence or three. */
  public static func summary(_ outcomes: [InvitationOutcome]) -> String {
    let invited = outcomes.compactMap(\.invitation)
    let emailed = invited.filter { $0.delivery == .sent }.count
    let notEmailed = invited.filter { $0.delivery != .sent }
    let members = outcomes.filter { $0.member == true }.map(\.emailAddress)
    var parts: [String] = []
    if emailed > 0 { parts.append("Sent \(counted(emailed, "invitation")).") }
    if !notEmailed.isEmpty {
      if notEmailed.contains(where: { $0.delivery != nil }) {
        parts.append("\(counted(notEmailed.count, "invitation")) couldn't be emailed. Copy \(notEmailed.count == 1 ? "its link" : "their links") below to send yourself.")
      } else {
        parts.append("Made \(counted(notEmailed.count, "invite link")). Copy each below and send it yourself.")
      }
    }
    if !members.isEmpty { parts.append("\(members.joined(separator: ", ")) \(members.count == 1 ? "has an account" : "have accounts") already.") }
    return parts.joined(separator: " ")
  }

  /** Newest first, by when their links were made, then by id (`newestFirst`). */
  public static func newestFirst(_ invitations: [EmailInvitation]) -> [EmailInvitation] {
    invitations.sorted { a, b in a.createdAt == b.createdAt ? a.id > b.id : a.createdAt > b.createdAt }
  }

  /** `invitations` with each of `saved` in its place, newest first (`withSaved`). */
  public static func withSaved(_ invitations: [EmailInvitation], _ saved: [EmailInvitation]) -> [EmailInvitation] {
    let ids = Set(saved.map(\.id))
    return newestFirst(saved + invitations.filter { !ids.contains($0.id) })
  }

  /** What a pending invitation's row says of it: emailed or not, who invited, when it expires. */
  public static func status(_ invitation: EmailInvitation, inviter: String, now: Date = Date()) -> String {
    let delivery: String
    switch invitation.delivery {
    case .sent: delivery = "Emailed"
    case let .refused(refusal): delivery = "Not emailed: \(refusal)"
    case nil: delivery = "Not emailed"
    }
    guard let expires = EmberDate.parse(invitation.expiresAt) else { return "\(delivery) · Invited by \(inviter)" }
    return "\(delivery) · Invited by \(inviter) · \(expires < now ? "Expired" : "Expires") \(expires.formatted(date: .abbreviated, time: .omitted))"
  }

  static func counted(_ count: Int, _ thing: String) -> String { "\(count) \(thing)\(count == 1 ? "" : "s")" }
}

// MARK: - Release checks

/** How the release card links on: what it says, the link's label, and where it goes. */
public struct ReleaseLink: Equatable, Sendable {
  public var says: String
  public var label: String
  public var url: String
}

extension ReleaseCheck {
  /** `betaToTryOf`: the beta a release is offered to try, once it has nothing newer to update to. */
  public var betaToTry: Release? {
    guard !beta, update == nil, let newestBeta, newestBeta.newer else { return nil }
    return newestBeta
  }

  /** `noteOf`: what the card says of this Ember under its heading. */
  public var note: String {
    if update != nil { return "This is Ember \(release)." }
    if beta {
      guard let newest else { return "This is a beta. GitHub didn't say whether its release is out." }
      return "This is \(newestBeta != nil ? "the newest beta" : "a beta"), ahead of Ember \(newest.release), the newest release."
    }
    return newest != nil ? "This is the newest release." : "GitHub didn't say whether a newer release is out."
  }

  /** The card's heading. */
  public var heading: String { update.map { "Ember \($0.release) is available" } ?? "Ember \(release)" }

  /** `updating(copy)` */
  public var updating: ReleaseLink {
    guard let copy else { return ReleaseLink(says: AdminText.howCopiesUpdate, label: "How to update", url: WorkspaceRules.updatingEmber) }
    if copy.workflow {
      return ReleaseLink(says: AdminText.howThisCopyUpdates, label: "Open GitHub action to update", url: "https://github.com/\(copy.repository)/actions/workflows/update-ember.yml")
    }
    return ReleaseLink(says: AdminText.howToAddTheWorkflow, label: "Add GitHub action to update", url: UpdateWorkflows.newFileLink(copy, beta: false))
  }

  /** `trying(copy)` */
  public var trying: ReleaseLink {
    guard let copy else { return ReleaseLink(says: AdminText.howCopiesTryBetas, label: "How to try a beta", url: WorkspaceRules.tryingBetas) }
    if copy.betaWorkflow {
      return ReleaseLink(
        says: AdminText.howThisCopyTriesBetas, label: "Open GitHub action to try it", url: "https://github.com/\(copy.repository)/actions/workflows/update-ember-beta.yml")
    }
    return ReleaseLink(says: AdminText.howToAddTheBetaWorkflow, label: "Add GitHub action to try betas", url: UpdateWorkflows.newFileLink(copy, beta: true))
  }

  /**
   * Two answers from different Worker isolates together (`together`): a different release replaces the
   * older answer; otherwise the later newest release and beta win.
   */
  public static func together(_ older: ReleaseCheck?, _ newer: ReleaseCheck) -> ReleaseCheck {
    guard let older, older.release == newer.release else { return newer }
    var merged = newer
    if let kept = older.newest, newer.newest.map({ WorkspaceRules.isNewer(kept.release, than: $0.release) }) ?? true { merged.newest = kept }
    if let kept = older.newestBeta, newer.newestBeta.map({ WorkspaceRules.isNewer(kept.release, than: $0.release) }) ?? true { merged.newestBeta = kept }
    if let kept = older.checkedAt, newer.checkedAt.map({ kept > $0 }) ?? true { merged.checkedAt = kept }
    return merged
  }
}

// MARK: - Words

/** The words of the workspace settings pages, verbatim. */
public enum AdminText {
  // Ways to join
  public static let confirmOpen = "Are you sure you want to let anyone create an account? Ember doesn't check that the email addresses people sign up with are theirs."
  public static let confirmMembersOnly =
    "Are you sure only Memberful's members should sign in? Everyone but administrators and the people they invite will need a Memberful membership to sign in."
  public static let confirmSsoOnly = "Turn on SSO only? Everyone except administrators and people you invite will need an account with your provider to sign in."
  public static let openOverrides = "Set aside while Open lets anyone join."
  public static let membersOnlyOverrides = "Off while Memberful is members only."
  public static let ssoOnlyOverrides = "Off while SSO only is on."
  public static let eitherOnlyOverrides = "Off while Memberful and single sign-on are the only ways in."
  public static let closesMemberful =
    " Nobody will be able to sign in with Memberful either, even members who joined with it, unless Members only is on as well. Those without a password will need a sign-in link from an administrator to get back in."
  public static let closesSso =
    " Nobody will be able to sign in with single sign-on either, even people who joined with it, unless SSO only is on as well. Those without a password will need a sign-in link from an administrator to get back in."
  public static let memberfulClosed = "Off while SSO only is on, even for members who joined with it. Turn it on to let Memberful's members in alongside the provider's people."
  public static let ssoClosed = "Off while Memberful is members only, even for people who joined with it. Turn it on to let the provider's people in alongside Memberful's members."
  public static let membersOnlyBesideSso =
    "SSO only is on, so Memberful's members join and sign in alongside the provider's people. Nobody else can join but the people you invite, and only they and administrators sign in with a password."
  public static let ssoOnlyBesideMemberful =
    "Memberful is members only, so the provider's people join and sign in alongside Memberful's members. Nobody else can join but the people you invite, and only they and administrators sign in with a password."
  public static let whoCanJoin = "Choose how new people can make an account."
  public static let openDescription = "Anyone can create an account at Ember's sign-up page."
  public static let joinLinkDescription = "Anyone with the link can create an account."
  public static let shareSignUp = "Share so anyone can sign up"
  public static let shareJoinLink = "Share to invite more people"
  public static let roomCreationHint = "Anyone who signs up can create rooms. To keep that to administrators, turn on Must be admin to create new rooms."
  public static let turnstileSignUps = "Cloudflare Turnstile checks that whoever signs up is a person."
  public static let signUpLimits =
    "Until Cloudflare Turnstile checks that whoever signs up is a person, \(EmberLimits.signUpsPerAddress) people can sign up from a network in an hour, and signing up waits once \(EmberLimits.signUpsPerHour) people have joined in an hour. Setting up Turnstile lifts these limits."

  // Email domain
  public static let emailDomainDescription = "People with an email address at your domains join with a link Ember emails them."
  public static let emailDomainOnWithoutEmail = "It's on, but Ember can't send email, so nobody gets a link to join with until email is set up."
  public static let emailDomainOffWithoutEmail =
    "People with an email address at your domains join with a link Ember emails them. Ember can't send email yet, so turning this on sets that up first."
  public static let shareEmailSignUp = "Share with people at your domains"
  public static func notADomain(_ typed: String) -> String { "\(typed) isn't a domain, such as example.com." }
  public static let tooManyDomains = "Email domain lets in at most \(EmberLimits.maxEmailDomains) domains."
  public static func freeDomains(_ free: [String]) -> String {
    "Anyone can get an address at \(WorkspaceRules.domainsInWords(free)), so listing \(free.count == 1 ? "it" : "them") lets almost anyone join."
  }
  public static let emailLinkLimit = "Ember emails an address at most \(EmberLimits.emailsPerAddress) links an hour, whoever asks, so nobody can use it to fill someone's inbox."
  public static let turnstileEmailLinks = "Cloudflare Turnstile checks that whoever asks for a link is a person."
  public static let emailLinksPerNetwork =
    "Until Cloudflare Turnstile checks that whoever asks is a person, \(EmberLimits.emailLinksPerNetwork) links can be asked for from a network in an hour. Setting up Turnstile lifts that limit."

  // Members' view
  public static let membersSignInElsewhere = "Members sign in with Memberful or single sign-on, so the join link is off."
  public static let membersSignInWithMemberful = "Members sign in with Memberful, so the join link is off."
  public static let workspaceUsesSso = "This workspace uses single sign-on, so the join link is off."
  public static func membersOf(_ site: String, sso: Bool) -> String { "Members of \(site) join by signing in with Memberful\(sso ? ", and others with single sign-on." : ".")" }
  public static let newPeopleJoinWithSso = "New people join with single sign-on."
  public static let onlyInvited = "Only the people administrators invite can join."
  public static func shareWithPeopleAt(_ domains: [String]) -> String { "Share with people at \(WorkspaceRules.domainsInWords(domains))" }

  // Invite by email
  public static let inviteEmails = "Ember emails each person a link to join with their address, whichever ways to join are on. A link works once, for \(EmberLimits.invitationDays) days."
  public static let inviteWithoutEmail =
    "Ember can't send email yet, so you'll get each person's link to send them yourself. A link works once, for \(EmberLimits.invitationDays) days. Set up email to have Ember send them."
  public static let confirmRevoke = "Are you sure you want to revoke this invitation? Its link will stop working."

  // Email
  public static let cantSendEmail =
    "Ember can't send email yet, so it can't email invitations, the links people at your email domains join with, or codes to reset a forgotten password."
  public static let confirmStopEmail =
    "Are you sure you want Ember to stop sending email? It will forget its From address, and won't email invitations, the links people at your email domains join with, or codes to reset a forgotten password, until email is set up again."
  public static func sentWith(_ email: EmailSettings) -> String {
    guard let from = email.from, let provider = email.provider else { return cantSendEmail }
    switch provider {
    case .cloudflare: return "Ember sends email from \(from) with Cloudflare Email Service."
    case .resend: return "Ember sends email from \(from) with Resend\(email.resendKey == .secret ? ", with the API key in RESEND_API_KEY" : "")."
    }
  }
  public static func testSent(_ to: String) -> String { "Sent to \(to). If it isn't in your inbox, look in spam." }
  public static let sendingTest = "Sending a test email…"
  public static let resendExplained = "Free for up to 100 emails a day, and 3,000 a month, whatever your Cloudflare plan. It takes a Resend account, and a domain to send from."
  public static let cloudflareExplained = "Needs the Workers Paid plan ($5 a month) on the Cloudflare account that runs Ember."
  public static let noEmailBinding = "This Worker has no EMAIL binding, which Cloudflare Email Service sends with."
  public static let resendDomainStep = "In Resend, add and verify a domain to send from, under Domains."
  public static let resendKeyStep = "Create an API key with Sending access, under API Keys, and paste it here."
  public static let resendDomains = "https://resend.com/domains"
  public static let resendApiKeys = "https://resend.com/api-keys"
  public static let workersPlans = "https://dash.cloudflare.com/?to=/:account/workers/plans"
  public static let emailSendingDashboard = "https://dash.cloudflare.com/?to=/:account/email-service/sending"
  public static let workersPaidStep = "Put the Cloudflare account that runs Ember on the Workers Paid plan."
  public static let onboardStep = "In the Cloudflare dashboard, open Email Service, Email Sending, choose Onboard Domain, and pick a domain on Cloudflare DNS."
  public static let stopsResend = "Ember will stop sending with Resend, and forget its API key."
  public static func fromExplained(cloudflare: Bool) -> String {
    "The address Ember's email comes from, on the domain you \(cloudflare ? "onboarded to Email Sending" : "verified in Resend"). Email comes under the community's name, unless you put another name before the address."
  }
  public static func checkingOnboarded(_ domain: String) -> String { "Checking that \(domain) is onboarded to Cloudflare Email Sending…" }
  public static func onboarded(_ domain: String) -> String { "\(domain) is onboarded to Cloudflare Email Sending." }
  public static func notOnboarded(_ domain: String) -> String {
    "\(domain) isn't onboarded to Cloudflare Email Sending yet, as its DNS doesn't have the records Onboard Domain adds."
  }
  public static func onboardingUnknown(_ domain: String) -> String { "Ember couldn't look up \(domain) just now. The test email will say whether Cloudflare sends from it." }

  // Turnstile
  public static let turnstileOff =
    "Cloudflare Turnstile can check that whoever signs up, or asks Ember to email them a link to join or a code to reset a password, is a person. Until it does, limits on each network stand in for its check."
  public static func turnstileOn(secret: Bool) -> String {
    "Cloudflare Turnstile checks that whoever signs up, or asks Ember to email them a link to join or a code to reset a password, is a person\(secret ? ", with the widget whose keys are in TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY" : "")."
  }
  public static let confirmStopTurnstile =
    "Are you sure you want to turn off Turnstile? Ember will forget the widget's keys, and limits on each network will stand in for its check until Turnstile is set up again."
  public static func turnstileKeysStep(_ host: String) -> String {
    "In the Cloudflare dashboard, open Turnstile and choose Add widget. Name it, add \(host) under Hostname Management, leave the mode Managed, and create it. Copy the widget's site key and secret key here."
  }
  public static let turnstileDashboard = "https://dash.cloudflare.com/?to=/:account/turnstile"
  public static let turnstileKeysKept = "Ember has a widget's keys already. Give another widget's to check people with it instead."
  public static let turnstileChecking = "Checking the keys with Cloudflare…"
  public static let turnstileDone =
    "Turnstile now checks that whoever signs up, or asks Ember to email them a link to join or a code to reset a password, is a person, in place of the limits on each network."
  public static let turnstileSiteKeyUnknown = "Turnstile doesn't know that site key. Copy it again from your widget in Cloudflare Turnstile."
  public static func turnstileHostUnlisted(_ host: String) -> String { "This widget doesn't list \(host). Add it under Hostname Management in Cloudflare Turnstile, then try again." }
  public static let turnstileUnavailable = "Turnstile's check didn't load. Make sure nothing in this browser blocks challenges.cloudflare.com, then try again."
  public static func turnstileFailed(_ code: String) -> String { "Turnstile's check didn't pass (error \(code)). Try again, or in another browser." }

  /** What a Turnstile frame error code means for the keys (`turnstile-setup.tsx`): whether it's the site key's, and what to say. */
  public static func turnstileProblem(code: String?, unavailable: Bool, host: String) -> (siteKey: Bool, message: String) {
    if unavailable { return (false, turnstileUnavailable) }
    switch code {
    case "110100", "110110", "400020", "400070": return (true, turnstileSiteKeyUnknown)
    case "110200": return (false, turnstileHostUnlisted(host))
    case let code?: return (false, turnstileFailed(code))
    case nil: return (false, turnstileUnavailable)
    }
  }

  // Memberful
  public static let memberfulOff = "Members of a Memberful site join and sign in with their Memberful account. Turning this on sets up Memberful first."
  public static let memberfulKeysGone =
    "It's on, but Ember no longer has your Memberful site's keys, so nobody can sign in with Memberful until it's set up again."
  public static func memberfulOn(_ site: String, webhooks: Bool) -> String {
    "Members of \(site) join and sign in with their Memberful account. Turned off, it lets nobody new join, but those who did keep signing in with it.\(webhooks ? " A member whose membership lapses is signed out until it's renewed." : "")"
  }
  public static let membersOnlyDescription =
    "Nobody else can join but the people you invite, and only they and administrators sign in with a password. Members who have one connect their Memberful account as they next sign in."
  public static func memberfulAddresses(_ origin: String) -> String {
    "Memberful sends people back to \(origin)\(Memberful.callbackPath), the OAuth Redirect URL of its custom app, and its webhook to \(origin)\(Memberful.webhookPath). If Ember's address changes, change both there too."
  }
  public static let memberfulWebhookSecrets =
    "To sign out members whose membership lapses, add a webhook in Memberful for every event under Member, Order, Subscription, and Plan, and give the Worker its secret key as MEMBERFUL_WEBHOOK_SECRET and Memberful's API key as MEMBERFUL_API_KEY."
  public static let memberfulSiteHint = "It's the address in your browser when you're signed in to Memberful's admin, such as yoursite.memberful.com."
  public static let memberfulAppSteps = "Name it Ember, check Include OAuth tokens with this application, and choose Server-side Application."
  public static let memberfulWebhookSteps = "Select every event under Member, Order, Subscription, and Plan. Download isn't needed."
  public static let memberfulKeysChecked = "Ember checks the keys with Memberful, then keeps the secrets encrypted."
  public static let memberfulKeysKept = "Ember has your site's keys already. Give them all again to change any of them."
  public static let memberfulAsking = "Asking Memberful about the keys…"
  public static func memberfulTook(_ site: String) -> String {
    "Memberful took the keys. While Memberful is on, members of \(site) join and sign in with their Memberful account, and a member whose membership lapses is signed out until it's renewed."
  }

  // Single sign-on
  public static let ssoOff = "Let people join and sign in with Okta, Entra ID, Google Workspace, or another identity provider."
  public static let ssoOnWithoutProvider = "No provider is set up, so no one can sign in with single sign-on. Turn it off, then on again to set it up."
  public static func ssoSetUp(_ sso: SsoSettings, besideMembersOnly: Bool) -> String {
    let groups = sso.allowedGroups.isEmpty ? "" : " Only allowed groups have access."
    let off = besideMembersOnly
      ? " When this is off, nobody signs in with it while Memberful is members only, not even those who joined with it."
      : " When this is off, new people can't join, but members can still sign in."
    return "People sign in at \(sso.issuer) using the Sign in with \(sso.name) button.\(groups)\(off)"
  }
  public static let ssoOnlyDescription =
    "Everyone signs in with single sign-on, except administrators and people you invite. Members with a password connect their account the next time they sign in."
  public static let confirmForgetSso = "Remove single sign-on? No one will be able to sign in with your provider until you set it up again."
  public static let ssoAppStep =
    "At your provider, create a web app that uses the authorization code flow with PKCE, with refresh tokens (offline_access), so Ember can check each hour that people still have access."
  public static func ssoRedirectStep(_ origin: String) -> String { "Give it the redirect URI \(origin)\(SSO.callbackPath)." }
  public static func ssoLogoutStep(_ origin: String) -> String { "Optionally, give it the back-channel logout URI \(origin)\(SSO.logoutPath)." }
  public static let ssoDetailsStep = "Enter the app's details below."
  public static let ssoSecretsStep = "Choose a button name and who can sign in."
  public static let ssoSecretsSet = "Set by your deployment's SSO_ISSUER, SSO_CLIENT_ID and SSO_CLIENT_SECRET secrets."
  public static let ssoSecretKept = "Stored encrypted. Leave blank to keep the current one."
  public static let ssoSecretStored = "Stored encrypted."
  public static let ssoNameHelp = "Shown as Sign in with <name>."
  public static let ssoScopesHelp = "Separate with spaces. openid, profile and email are always included."
  public static let ssoGroupsClaimHelp = "The claim in the ID token or userinfo that lists someone's groups."
  public static let ssoGroupsHelp =
    "One per line. Leave empty to let everyone at your provider sign in. With Zitadel, use the claim urn:zitadel:iam:org:project:roles and list role keys."
  public static let ssoLinkHelp =
    "Connects someone who signs in with your provider to the account here with the same email address. Turn this on only if your provider verifies email addresses and doesn't let people change their own."
  public static let ssoContacting = "Contacting your provider…"
  public static let ssoDone =
    "Ember found your provider, but it first uses the Client ID and secret as someone signs in. Once Single sign-on is on, sign in with your provider in a private window to check them."

  // Blocked words
  public static let blockedWordsExplained =
    "Nobody can use these in a message, a reaction, a file's or a room's name, or their own name, username or bio. They match whole words, ignoring case and accents, so a short word doesn't block longer ones. Only administrators see this list."
  public static let blockedWordsField = "Words and phrases, one a line or apart by commas"

  // Reports
  public static let reportsExplained = "Anyone can report someone else's message, from its More actions, or someone, from their page. Nobody is told who reported them."
  public static let noOpenReports = "No open reports."
  public static let showingNewest = "Showing the newest 100. The rest come as these are handled."
  public static let confirmDeleteMessage = "Are you sure you want to delete this message?"

  // General
  public static let saved = "Changes saved."
  public static let taglineHelp = "Shown under the community name in the sidebar, up to 30 characters. Leave it empty for none."
  public static let hideTranslationsHelp = "Hide language help throughout the app for everyone."
  public static let checkingForUpdates = "Checking for updates…"

  // Styles
  public static let navigationIconsExplained = "Choose the icons in your community's left navigation. Changes apply to everyone."
  public static let navigationIconsRecommended = "Recommendations for your navigation buttons and appearance modes."
  // Chat bots, AI assistant and Huddles (web `bots-page.tsx`, `assistant-settings.tsx`, `huddles-settings.tsx`).
  public static let botsExplained =
    "Chat bots let other apps and services post in your rooms, and reply when people talk to them. Each of a bot's rooms gets two addresses, one for posting text or a file and one that takes a Slack incoming webhook's payload. Give a bot a webhook URL, and Ember sends it every message that @mentions it or is sent to it in a DM, then posts whatever it answers within 30 seconds."
  public static let noRooms = "No rooms"
  public static let assistantExplained =
    "Ember AI adds AI agents people can mention in the chat: @ember, and any you make for a task, each running on a model you choose through Cloudflare AI Gateway."
  public static let agentsAnswer = "Ember's agents answer through Cloudflare AI Gateway, each on the model you choose for it."
  public static let whatAgentsSend =
    "Mention an agent, or write to it directly, and it answers, sending the thread, or the room's latest messages, through Cloudflare to its model."
  public static let huddlesExplained =
    "Huddles let people in a room talk to each other live. They run through Cloudflare's Realtime SFU, with an app in your Cloudflare account."
  public static func huddlesRunThrough(_ appId: String) -> String { "Huddles run through the Realtime SFU app \(appId) in your Cloudflare account." }
  public static let camerasExplained = "People can turn their camera on in a huddle."
  public static let screensExplained = "People can share their screen in a huddle, from a computer."
  public static let customStylesCaution = "Use Caution: you could break things."
  public static let customStylesTooLong = "Custom CSS must be at most 100,000 characters"

  // Domain
  public static let adminsManageDomain = "Community admins manage the community's domain."
  public static let signsInAgain = "Everyone signs in again there."
  public static let workersDashboard = "https://dash.cloudflare.com/?to=/:account/workers-and-pages"
  public static func workerDomains(_ worker: String) -> String { "https://dash.cloudflare.com/?to=/:account/workers/services/view/\(worker)/production/domains" }
  public static let cloudflareDomains = "https://dash.cloudflare.com/?to=/:account/domains/overview"
  public static let cloudflareDnsRecords = "https://dash.cloudflare.com/?to=/:account/:zone/dns/records"
  public static let cloudflareCustomHostnames = "https://dash.cloudflare.com/?to=/:account/:zone/ssl-tls/custom-hostnames"
  public static let saasOrigin = "ember-saas"

  // Release card
  public static let howCopiesUpdate =
    "A copy made with Deploy to Cloudflare gets a pull request for each release from its Update Ember workflow, every Monday or when it's run from the repository's Actions tab, once the workflow is added to the copy, as How to update says. Merging it updates Ember."
  static let unlessItCant =
    "Where GitHub doesn't yet let it open pull requests, as in a new repository, it opens an issue instead, with a link that opens the pull request for you to merge."
  public static let howThisCopyUpdates =
    "This copy gets a pull request for each release from its Update Ember workflow every Monday. To update now, open the workflow on GitHub, choose Run workflow, and merge the pull request it opens. \(unlessItCant)"
  public static let howToAddTheWorkflow =
    "This copy has no Update Ember workflow yet, which brings each release as a pull request. Add it on GitHub, where it's filled in for you to commit, then run it from the repository's Actions tab and merge the pull request it opens. \(unlessItCant)"
  public static let howCopiesTryBetas =
    "A copy made with Deploy to Cloudflare takes a beta only when asked, from its beta workflow, Update Ember to its newest beta, once that's added to the copy, as How to try a beta says. Once the beta's release is out, Update Ember brings that, and releases alone after it."
  public static let howThisCopyTriesBetas =
    "This copy takes a beta only when asked. To try this one, open the beta workflow on GitHub, choose Run workflow, and merge the pull request it opens. Update Ember then brings the betas after it, then its release, and releases alone after that. \(unlessItCant)"
  public static let howToAddTheBetaWorkflow =
    "This copy takes a beta only when asked, from its beta workflow, Update Ember to its newest beta, which it hasn't yet. Add it on GitHub, where it's filled in for you to commit, then run it from the repository's Actions tab and merge the pull request it opens. \(unlessItCant)"
  public static func betaToTry(_ release: String) -> String { "Ember \(release) is out to try" }
}
