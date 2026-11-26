import Foundation
import ImageIO
import UniformTypeIdentifiers

// The signed-in person and every way in, as the web's pages behave: links pasted into ircX, the pages
// a browser-held flow (Memberful, SSO, an app's sign-in) ends on, the profile form's changes, and the
// photo variant forms send.

/** Where a pasted link to an Ember instance leads, by the web's routes (`pages.ts`). */
public enum EmberRoute: Equatable, Sendable {
  /** Just the instance's address. */
  case instance
  /** `/join/<code>`: the workspace's join link. */
  case join(code: String)
  /** `/join`: open sign-up. */
  case signUp
  /** `/join/invitation#token=`: an administrator's invitation. */
  case invitation(token: String)
  /** `/join/email`: asking for a link with an email domain's address, or, with `#token=`, the link it sent. */
  case emailSignUp(token: String?)
  /** `/session/transfers#token=`: a sign-in link. */
  case transfer(id: String)
  /** `/passwords/new?email_address=` */
  case passwordReset(emailAddress: String?)
  /** `/session/new`, with an address to fill in and why the web sent someone there. */
  case signIn(emailAddress: String?, problem: String?)
  /** `/first_run#token=`: setting up a new Ember. */
  case firstRun(token: String?)
  /** `/oauth/authorize?...`: an AI app asking to connect as you. */
  case outsideConnect(OutsideAsk)
  /** Any other page, such as a room's permalink or someone's page, which opens once signed in. */
  case page(String)
}

/** A link to an Ember instance, read locally: its secrets are in the fragment so that no server log sees them. */
public struct EmberLink: Equatable, Sendable {
  public var baseURL: URL
  public var route: EmberRoute

  public init(baseURL: URL, route: EmberRoute) {
    self.baseURL = baseURL
    self.route = route
  }

  /** What `text` links to, or nil when it isn't an address at all. A bare host is `.instance`. */
  public static func parse(_ text: String) -> EmberLink? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let baseURL = Instance.baseURL(from: trimmed) else { return nil }
    let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
    guard let parts = URLComponents(string: full) else { return EmberLink(baseURL: baseURL, route: .instance) }
    let path = parts.path.count > 1 && parts.path.hasSuffix("/") ? String(parts.path.dropLast()) : parts.path
    let query = parts.queryItems ?? []
    func value(_ name: String) -> String? {
      guard let found = query.first(where: { $0.name == name })?.value, !found.isEmpty else { return nil }
      return found
    }
    let token = parts.fragment.flatMap(fragmentToken)
    let route: EmberRoute
    switch path {
    case "", "/":
      route = .instance
    case Pages.signUpPath:
      route = .signUp
    case Pages.invitationPath:
      guard let token else { return EmberLink(baseURL: baseURL, route: .instance) }
      route = .invitation(token: token)
    case Pages.emailSignUpPath:
      route = .emailSignUp(token: token)
    case Pages.transferPath:
      guard let token else { return EmberLink(baseURL: baseURL, route: .instance) }
      route = .transfer(id: token)
    case Pages.passwordResetPath:
      route = .passwordReset(emailAddress: value("email_address"))
    case Pages.signInPath:
      route = .signIn(emailAddress: value("email_address"), problem: signInProblem(query))
    case Pages.firstRunPath:
      route = .firstRun(token: token)
    case Outside.authorizePath:
      route = .outsideConnect(OutsideAsk(query: query))
    default:
      if let code = path.wholeMatch(of: #/\/join\/([A-Za-z0-9-]+)/#)?.output.1 {
        route = .join(code: String(code))
      } else {
        var page = parts
        page.scheme = baseURL.scheme
        guard let address = page.url?.absoluteString else { return EmberLink(baseURL: baseURL, route: .instance) }
        route = .page(address)
      }
    }
    return EmberLink(baseURL: baseURL, route: route)
  }

  /** `#token=<t>`'s token. */
  static func fragmentToken(_ fragment: String) -> String? {
    for pair in fragment.split(separator: "&") {
      let parts = pair.split(separator: "=", maxSplits: 1)
      guard parts.count == 2, parts[0] == "token", !parts[1].isEmpty else { continue }
      guard let decoded = String(parts[1]).removingPercentEncoding else { return String(parts[1]) }
      return decoded
    }
    return nil
  }

  /** What the sign-in page says on arriving with `?joining=`, `?memberful=` or `?sso=` (`JOINING_PROBLEMS` and the sign-in problems). */
  public static func signInProblem(_ query: [URLQueryItem]) -> String? {
    for item in query {
      guard let value = item.value else { continue }
      switch item.name {
      case EmberText.joiningParam: if let text = EmberText.joiningProblems[value] { return text }
      case Memberful.problemParam: if let text = Memberful.signInProblems[value] { return text }
      case SSO.problemParam: if let text = SSO.signInProblems[value] { return text }
      default: continue
      }
    }
    return nil
  }
}

extension Pages {
  public static let firstRunPath = "/first_run"
}

/** How a browser-held flow (Memberful, single sign-on, an app's sign-in) ended, by the Ember page it was sent to. */
public enum BrowserFlowEnd: Equatable, Sendable {
  /** Signed in: the session cookie is set. */
  case signedIn
  /** Signed in as someone new, whom the welcome page asks how people see them. */
  case welcome
  /** Back at sign-in, saying why; `passwordForm` when the password form is the way on (`taken`). */
  case problem(String, passwordForm: Bool)
  /** Back at the profile with an account elsewhere connected, and the notice to show. */
  case connected(String)
  /** Back from an app's authorization server, with what to finish its sign-in with. */
  case appSignIn(state: String?, code: String?, iss: String?, error: String?)
}

public enum BrowserFlow {
  /** What a flow that ended back at sign-in without saying why says. */
  public static let failed = "Signing in didn't work. Try again."

  /**
   * Whether the browser's next page, `url`, ends the flow: an Ember page on one of `hosts` (the instance's,
   * and its custom domain) that isn't one of the sign-in's own steps. Nil while the flow goes on.
   */
  public static func end(of url: URL, hosts: Set<String>) -> BrowserFlowEnd? {
    guard let host = url.host()?.lowercased(), hosts.contains(host) else { return nil }
    let path = url.path(percentEncoded: false)
    guard !path.hasPrefix("/auth/"), !path.hasPrefix("/api/"), !path.hasPrefix("/webhooks/"), path != Pages.turnstileCheckPath else { return nil }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? { query.first(where: { $0.name == name })?.value }
    switch path {
    case Pages.welcomePath:
      return .welcome
    case Pages.signInPath:
      let taken = value(Memberful.problemParam) == "taken" || value(SSO.problemParam) == "taken"
      guard let problem = EmberLink.signInProblem(query) else { return .problem(failed, passwordForm: false) }
      return .problem(problem, passwordForm: taken)
    case AppRules.signedInPath:
      return .appSignIn(state: value("state"), code: value("code"), iss: value("iss"), error: value("error"))
    default:
      if path.wholeMatch(of: #/\/users\/[^\/]+\/profile/#) != nil {
        if value(Memberful.problemParam) == Memberful.connected { return .connected(Memberful.connectedNotice) }
        if value(SSO.problemParam) == SSO.connected { return .connected(SSO.connectedNotice) }
        if let problem = EmberLink.signInProblem(query) { return .problem(problem, passwordForm: false) }
      }
      return .signedIn
    }
  }
}
