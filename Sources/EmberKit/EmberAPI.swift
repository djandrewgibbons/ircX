import Foundation

public enum EmberError: Error, LocalizedError, Equatable {
  /** Ember answered with a problem: `{ "error": "..." }` and its status. */
  case problem(status: Int, message: String)
  /** The session is gone or was never there: sign in again. */
  case signedOut
  /** Sign-in worked, but Ember gave no session cookie to keep. */
  case noSession
  case notEmber
  case transport(String)

  public var errorDescription: String? {
    switch self {
    case let .problem(_, message): message
    case .signedOut: "Signed out. Sign in again."
    case .noSession: "Ember didn't start a session."
    case .notEmber: "That address doesn't answer like Ember."
    case let .transport(text): text
    }
  }
}

/**
 * Ember's HTTP API for one instance, as its web app calls it, with the session token sent in the
 * cookie Ember expects. Ember refuses writes from other sites by their `Origin` and `Sec-Fetch-Site`
 * headers, which browsers set; a native client is the site itself, so it says so.
 */
public final class EmberAPI: @unchecked Sendable {
  public let instance: Instance
  public let tokens: TokenStore
  public let session: URLSession

  public static let userAgent: String = {
    #if os(iOS)
    "ircX/0.1 (iOS)"
    #else
    "ircX/0.1 (macOS)"
    #endif
  }()

  public init(instance: Instance, tokens: TokenStore) {
    self.instance = instance
    self.tokens = tokens
    let config = URLSessionConfiguration.default
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.httpCookieStorage = nil
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.waitsForConnectivity = true
    config.timeoutIntervalForRequest = 30
    session = URLSession(configuration: config)
  }

  public var token: String? { tokens.token(for: instance.id) }
  public var isSignedIn: Bool { token != nil }

  /** The cookie Ember's session rides: `__Host-session_token` over HTTPS, `session_token` over plain HTTP. */
  public var cookieName: String { instance.isSecure ? "__Host-session_token" : "session_token" }

  public func url(_ path: String) -> URL {
    if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
    return URL(string: path, relativeTo: instance.baseURL)!.absoluteURL
  }

  /** A request to `path` carrying this instance's session and the headers that say it's from Ember itself. */
  public func request(_ path: String, method: String = "GET") -> URLRequest {
    var request = URLRequest(url: url(path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(instance.origin, forHTTPHeaderField: "Origin")
    request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
    if let token { request.setValue("\(cookieName)=\(token)", forHTTPHeaderField: "Cookie") }
    return request
  }

  /** The room or workspace socket at `path`, as an upgrade request from the app's own origin. */
  public func socketRequest(_ path: String) -> URLRequest {
    var request = request(path)
    var parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
    parts.scheme = instance.isSecure ? "wss" : "ws"
    request.url = parts.url
    request.setValue(nil, forHTTPHeaderField: "Accept")
    request.setValue(nil, forHTTPHeaderField: "Sec-Fetch-Site")
    return request
  }

  // MARK: - Sending

  @discardableResult
  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw EmberError.transport(error.localizedDescription)
    }
    guard let http = response as? HTTPURLResponse else { throw EmberError.notEmber }
    keepSession(from: http)
    if http.statusCode == 401, isSignedIn, request.url?.path != "/api/session" {
      throw EmberError.signedOut
    }
    guard (200..<300).contains(http.statusCode) || http.statusCode == 304 else {
      let message = (try? JSONDecoder().decode(Problem.self, from: data))?.error ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw EmberError.problem(status: http.statusCode, message: message)
    }
    return (data, http)
  }

  public func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
    let (data, _) = try await send(request(path))
    return try decode(data)
  }

  public func write<T: Decodable>(_ method: String, _ path: String, json body: some Encodable, as type: T.Type = T.self) async throws -> T {
    let (data, _) = try await send(jsonRequest(method, path, body))
    return try decode(data)
  }

  public func perform(_ method: String, _ path: String) async throws {
    try await send(request(path, method: method))
  }

  public func perform(_ method: String, _ path: String, json body: some Encodable) async throws {
    try await send(jsonRequest(method, path, body))
  }

  private func jsonRequest(_ method: String, _ path: String, _ body: some Encodable) throws -> URLRequest {
    var request = request(path, method: method)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    return request
  }

  private func decode<T: Decodable>(_ data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw EmberError.notEmber
    }
  }

  /** Keeps the session token any answer sets, as sign-in does and later answers do when they extend it, and forgets one Ember expires. */
  private func keepSession(from response: HTTPURLResponse) {
    guard let value = SessionCookie.token(named: cookieName, in: response) else { return }
    tokens.setToken(value.isEmpty ? nil : value, for: instance.id)
  }

  // MARK: - Ember's API

  public func bootstrap() async throws -> Bootstrap {
    try await get("/api/bootstrap")
  }

  public func signIn(emailAddress: String, password: String) async throws -> Me {
    let answer: SignedIn = try await write("POST", "/api/session", json: ["emailAddress": emailAddress, "password": password])
    guard isSignedIn else { throw EmberError.noSession }
    return answer.user
  }

  /** Signs in with just a name, where the instance lets guests in (`Bootstrap.guestSignIn`). */
  public func signIn(name: String) async throws -> Me {
    let answer: SignedIn = try await write("POST", "/api/session", json: ["name": name])
    guard isSignedIn else { throw EmberError.noSession }
    return answer.user
  }

  /**
   * Signs in with a sign-in link from someone's profile, such as `https://irc.dxnd.ai/session/transfers#token=abc`,
   * which the QR code there holds.
   */
  public func signIn(transferLink: String) async throws -> Me {
    guard let id = SessionCookie.transferId(in: transferLink) else { throw EmberError.problem(status: 422, message: "That isn't a sign-in link.") }
    let answer: SignedIn = try await write("POST", "/api/session/transfers", json: ["transferId": id])
    guard isSignedIn else { throw EmberError.noSession }
    return answer.user
  }

  public func signOut() async {
    try? await perform("DELETE", "/api/session")
    tokens.setToken(nil, for: instance.id)
  }

  public func sidebar() async throws -> Sidebar { try await get("/api/sidebar") }
  public func directory() async throws -> Directory { try await get("/api/users") }
  public func people() async throws -> NewRoomForm { try await get("/api/rooms/new") }

  public func startDirect(with userIds: [UserID]) async throws -> Room {
    let answer: StartedDirect = try await write("POST", "/api/directs", json: ["userIds": userIds])
    return answer.room
  }

  public func createRoom(name: String, open: Bool = true) async throws -> Room {
    struct NewRoom: Encodable { let name: String; let kind: String; let memberIds: [String]? }
    let answer: SavedRoom = try await write("POST", "/api/rooms", json: NewRoom(name: name, kind: open ? "open" : "closed", memberIds: open ? nil : []))
    return answer.room
  }

  public func setInvolvement(_ involvement: Involvement, in room: RoomID) async throws {
    try await perform("PUT", "/api/rooms/\(room)/involvement", json: ["involvement": involvement.rawValue])
  }

  public func setFavorite(_ favorite: Bool, room: RoomID) async throws {
    try await perform("PUT", "/api/rooms/\(room)/favorite", json: ["favorite": favorite])
  }

  /** The bytes at `path` on this instance, such as a file's preview or someone's avatar, with the session that may see them. */
  public func data(at path: String) async throws -> Data {
    var request = request(path)
    request.setValue("*/*", forHTTPHeaderField: "Accept")
    return try await send(request).0
  }

  public struct Empty: Codable, Sendable {}
  private struct Problem: Decodable { let error: String }
  private struct SignedIn: Decodable { let user: Me }
  private struct SavedRoom: Decodable { let room: Room }
}

/** Reading Ember's session cookie and sign-in links. */
public enum SessionCookie {
  /** The value `Set-Cookie` gives the cookie `name`, "" when it expires it, or nil when it doesn't name it. */
  public static func token(named name: String, in response: HTTPURLResponse) -> String? {
    var fields: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
      if let key = key as? String, let value = value as? String { fields[key] = value }
    }
    guard let url = response.url else { return nil }
    if let cookie = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).first(where: { $0.name == name }) {
      if let expires = cookie.expiresDate, expires <= Date() { return "" }
      return cookie.value
    }
    // Foundation drops a `__Host-` cookie it judges invalid for the URL; read the header by hand then.
    let header = fields.first { $0.key.caseInsensitiveCompare("Set-Cookie") == .orderedSame }?.value
    return header.flatMap { token(named: name, inHeader: $0) }
  }

  public static func token(named name: String, inHeader header: String) -> String? {
    for cookie in header.components(separatedBy: ",") {
      let pair = cookie.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
      let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      if parts.first == name {
        let value = parts.count > 1 ? parts[1] : ""
        return cookie.lowercased().contains("max-age=0") ? "" : value
      }
    }
    return nil
  }

  /** The transfer id in a sign-in link (`/session/transfers#token=<id>`), or a bare id. */
  public static func transferId(in link: String) -> String? {
    let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
    if let range = text.range(of: "token=") {
      let id = text[range.upperBound...].prefix { $0 != "&" }
      return id.isEmpty ? nil : String(id)
    }
    return text.isEmpty || text.contains("/") || text.contains(" ") ? nil : text
  }
}
