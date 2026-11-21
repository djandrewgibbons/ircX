import Foundation

// packages/protocol/src/pages.ts: the web app's pages, which links name and permalinks open.

/** A page of the workspace, as its path names it (`WorkspacePage`). */
public enum WorkspacePage: Sendable, Equatable {
  case home
  case newestRoom
  case room(RoomID, messageId: String? = nil, threadId: String? = nil, replyId: String? = nil, huddle: Bool = false)
  case message(RoomID, messageId: String?)
  case roomOfKind(RoomKind, RoomID)
  case newRoom(RoomKind)
  case roomSettings(RoomKind, RoomID)
  case newDirect
  case directSettings(RoomID)
  case workspaceSettings
  case customStyles
  case bots
  case newBot
  case botSettings(UserID)
  case newAgent
  case agentSettings(UserID)
  case newApp
  case appSettings(String)
  case appSignedIn
  case profile
  case pushSubscriptions
  case person(UserID)
  case search
  case huddles
}

public enum Pages {
  public static let signInPath = "/session/new"
  public static let workspaceSettingsPath = "/account/edit"
  public static let customStylesPath = "/account/custom_styles/edit"
  public static let botsPath = "/account/bots"
  public static let newBotPath = "/account/bots/new"
  public static let newAgentPath = "/account/agents/new"
  public static let newAppPath = "/account/apps/new"
  public static let appSignedInPath = "/account/apps/signed-in"
  public static let newDirectPath = "/rooms/directs/new"
  public static let profilePath = "/users/me/profile"
  public static let pushSubscriptionsPath = "/users/me/push_subscriptions"
  public static let searchesPath = "/searches"
  public static let huddlesPath = "/huddles"
  public static let welcomePath = "/welcome"
  public static let transferPath = "/session/transfers"
  public static let signUpPath = "/join"
  public static let invitationPath = "/join/invitation"
  public static let emailSignUpPath = "/join/email"
  public static let passwordResetPath = "/passwords/new"
  public static let turnstileCheckPath = "/account/turnstile_check"
  /** `WORKSPACE_PRELOADS` */
  public static let workspacePreloads = ["/api/sidebar", "/api/users"]

  /** A room's permalink to one of its messages, as Copy link writes it. */
  public static func messagePath(_ room: RoomID, _ messageId: String) -> String { "/rooms/\(URIComponent.encode(room))/@\(URIComponent.encode(messageId))" }
  /** A room's page. */
  public static func roomPath(_ room: RoomID) -> String { "/rooms/\(URIComponent.encode(room))" }
  /** `threadPath` */
  public static func threadPath(_ room: RoomID, _ parentId: String, replyId: String? = nil) -> String {
    let path = "/rooms/\(URIComponent.encode(room))/threads/\(URIComponent.encode(parentId))"
    guard let replyId else { return path }
    return "\(path)/@\(URIComponent.encode(replyId))"
  }
  /** `huddlePath` */
  public static func huddlePath(_ room: RoomID) -> String { "/rooms/\(URIComponent.encode(room))/huddle" }
  /** `transferLink` */
  public static func transferLink(_ transferId: String) -> String { "\(transferPath)#token=\(transferId)" }
  /** `invitationLink` */
  public static func invitationLink(_ token: String) -> String { "\(invitationPath)#token=\(token)" }
  /** `emailSignUpLink` */
  public static func emailSignUpLink(_ token: String) -> String { "\(emailSignUpPath)#token=\(token)" }
  /** The join link (`/join/<code>`). */
  public static func joinLink(_ code: String) -> String { "\(signUpPath)/\(code)" }
  /** `withEmailAddress` */
  public static func withEmailAddress(_ path: String, _ emailAddress: String) -> String {
    emailAddress.isEmpty ? path : "\(path)?email_address=\(URIComponent.encode(emailAddress))"
  }
  /** `signInSaying`: the sign-in page, saying why joining didn't work. */
  public static func signInSaying(_ problem: String) -> String { "\(signInPath)?\(EmberText.joiningParam)=\(problem)" }

  /** `workspacePageOf`: the page a path names, or nil for none. */
  public static func page(of pathname: String) -> WorkspacePage? {
    switch pathname {
    case "/": return .home
    case newDirectPath: return .newDirect
    case workspaceSettingsPath: return .workspaceSettings
    case customStylesPath: return .customStyles
    case botsPath: return .bots
    case newBotPath: return .newBot
    case newAgentPath: return .newAgent
    case newAppPath: return .newApp
    case appSignedInPath: return .appSignedIn
    case searchesPath: return .search
    case huddlesPath: return .huddles
    case "/rooms": return .newestRoom
    default: break
    }
    if let m = pathname.wholeMatch(of: #/\/account\/bots\/([^\/]+)\/edit/#), let id = decoded(m.output.1) { return .botSettings(id) }
    if let m = pathname.wholeMatch(of: #/\/account\/agents\/([^\/]+)\/edit/#), let id = decoded(m.output.1) { return .agentSettings(id) }
    if let m = pathname.wholeMatch(of: #/\/account\/apps\/([^\/]+)\/edit/#), let id = decoded(m.output.1) { return .appSettings(id) }
    if pathname.wholeMatch(of: #/\/users\/[^\/]+\/profile/#) != nil { return .profile }
    if pathname.wholeMatch(of: #/\/users\/[^\/]+\/push_subscriptions/#) != nil { return .pushSubscriptions }
    if let m = pathname.wholeMatch(of: #/\/users\/([^\/]+)/#), let id = decoded(m.output.1) { return .person(id) }
    if let m = pathname.wholeMatch(of: #/\/rooms\/(opens|closeds)\/new/#) { return .newRoom(access(m.output.1)) }
    if let m = pathname.wholeMatch(of: #/\/rooms\/(opens|closeds)\/([^\/]+)\/edit/#), let id = decoded(m.output.2) { return .roomSettings(access(m.output.1), id) }
    if let m = pathname.wholeMatch(of: #/\/rooms\/directs\/([^\/]+)\/edit/#), let id = decoded(m.output.1) { return .directSettings(id) }
    if let m = pathname.wholeMatch(of: #/\/rooms\/([^\/]+)\/threads\/([^\/]+)(?:\/@([^\/]+))?/#) {
      return threadPage(String(m.output.1), String(m.output.2), m.output.3.map(String.init))
    }
    if let m = pathname.wholeMatch(of: #/\/rooms\/([^\/]+)\/huddle/#) {
      guard m.output.1 != "new", let id = decoded(m.output.1) else { return nil }
      return .room(id, huddle: true)
    }
    if let m = pathname.wholeMatch(of: #/\/rooms\/(opens|closeds|directs)\/([^\/]+)/#), let id = decoded(m.output.2) {
      return .roomOfKind(m.output.1 == "directs" ? .direct : access(m.output.1), id)
    }
    guard let m = pathname.wholeMatch(of: #/\/rooms\/([^\/]+)(?:\/@([^\/]+)|\/messages\/([^\/]+))?/#), m.output.1 != "new", let room = decoded(m.output.1) else {
      return nil
    }
    let isMessage = m.output.3 != nil
    let messageId = (m.output.2 ?? m.output.3).flatMap(decoded)
    let kept = messageId.flatMap { $0.utf16.count <= EmberLimits.maxIdLength ? $0 : nil }
    return isMessage ? .message(room, messageId: kept) : .room(room, messageId: kept)
  }

  /** The page a link to this instance opens, such as a pasted permalink, or nil for another site's. */
  public static func page(ofLink link: String, origin: String) -> WorkspacePage? {
    guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme, let host = url.host() else { return nil }
    var linkOrigin = "\(scheme)://\(host)"
    if let port = url.port { linkOrigin += ":\(port)" }
    guard linkOrigin == origin else { return nil }
    let path = url.path(percentEncoded: true)
    return page(of: path.isEmpty ? "/" : path)
  }

  private static func access(_ segment: Substring) -> RoomKind { segment == "opens" ? .open : .closed }

  private static func decoded(_ segment: Substring) -> String? {
    guard let text = String(segment).removingPercentEncoding, !text.isEmpty else { return nil }
    return text
  }

  private static func threadPage(_ roomSegment: String, _ threadSegment: String, _ replySegment: String?) -> WorkspacePage? {
    guard roomSegment != "new", let room = decoded(Substring(roomSegment)) else { return nil }
    let messageId = { (id: String?) -> String? in id.flatMap { $0.utf16.count <= EmberLimits.maxIdLength ? $0 : nil } }
    guard let thread = messageId(decoded(Substring(threadSegment))) else { return .room(room) }
    return .room(room, threadId: thread, replyId: messageId(replySegment.flatMap { decoded(Substring($0)) }))
  }
}
