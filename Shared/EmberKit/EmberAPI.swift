import Foundation

/** What Ember answers a failure with: `{ "error", "field"?, "redirect"?, "signIn"?, "client"? }` and its status. */
public struct EmberProblem: Sendable, Equatable {
  public var status: Int
  public var message: String
  /** The form field the message is about, such as `emailAddress` or `code`. */
  public var field: String?
  /** A page to go to, such as `/session/new?email_address=<address>` after "has an account already". */
  public var redirect: String?
  /** An app needs signing in to its server first (`AppRefused.signIn`). */
  public var signIn: Bool
  /** An app's server needs a client ID (`AppRefused.client`). */
  public var client: Bool

  public init(status: Int, message: String, field: String? = nil, redirect: String? = nil, signIn: Bool = false, client: Bool = false) {
    self.status = status
    self.message = message
    self.field = field
    self.redirect = redirect
    self.signIn = signIn
    self.client = client
  }
}

public enum EmberError: Error, LocalizedError, Equatable {
  /** Ember answered with a problem. */
  case problem(EmberProblem)
  /** The session is gone or was never there: sign in again. */
  case signedOut
  /** Sign-in worked, but Ember gave no session cookie to keep. */
  case noSession
  /** The password was right, but the workspace now signs people in elsewhere: connect an account there. */
  case connectElsewhere(ElsewhereConnection, ssoName: String)
  case notEmber
  /** An answer that didn't decode as the protocol says, naming what didn't. */
  case undecodable(String)
  case transport(String)

  public static func refused(_ status: Int, _ message: String) -> EmberError { .problem(EmberProblem(status: status, message: message)) }

  public var errorDescription: String? {
    switch self {
    case let .problem(problem): problem.message
    case .signedOut: "Signed out. Sign in again."
    case .noSession: "Ember didn't start a session."
    case let .connectElsewhere(connection, ssoName): EmberText.nowUses(connection.connections(ssoName: ssoName).map(\.name))
    case .notEmber: "That address doesn't answer like Ember."
    case let .undecodable(detail): "Ember's answer didn't make sense: \(detail)"
    case let .transport(text): text
    }
  }

  /** The problem Ember answered with, if it did. */
  public var problem: EmberProblem? {
    if case let .problem(problem) = self { return problem }
    return nil
  }
}

/** What `POST /api/session` with a password answers: signed in, or where to connect an account. */
public enum PasswordSignInAnswer: Sendable {
  case signedIn(Me)
  case elsewhere(ElsewhereStart)
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

  /** How long a model is given to answer, for the calls that ask one (Ember AI's setup, agents, trials). */
  public static let modelTimeout: TimeInterval = 120

  /** The `Accept` that takes any answer, for images and files. */
  static let anyType = "\u{2A}/\u{2A}"

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
    // Fail fast, so an address that doesn't resolve says so; sockets reconnect on their own backoff.
    config.waitsForConnectivity = false
    config.timeoutIntervalForRequest = 30
    // Long enough for an upload's part or a model's answer, which set their own request timeouts.
    config.timeoutIntervalForResource = 600
    session = URLSession(configuration: config)
  }

  public var token: String? { tokens.token(for: instance.id) }
  public var isSignedIn: Bool { token != nil }

  /** The cookie Ember's session rides: `__Host-session_token` over HTTPS, `session_token` over plain HTTP. */
  public var cookieName: String { instance.isSecure ? "__Host-session_token" : "session_token" }

  public func url(_ path: String) -> URL {
    if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
    guard let url = URL(string: path, relativeTo: instance.baseURL) else { preconditionFailure("Unaddressable path \(path)") }
    return url.absoluteURL
  }

  /** A request to `path` carrying this instance's session and the headers that say it's from Ember itself. */
  public func request(_ path: String, method: String = "GET", timeout: TimeInterval? = nil) -> URLRequest {
    var request = URLRequest(url: url(path))
    request.httpMethod = method
    if let timeout { request.timeoutInterval = timeout }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(instance.origin, forHTTPHeaderField: "Origin")
    request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
    if let token { request.setValue("\(cookieName)=\(token)", forHTTPHeaderField: "Cookie") }
    return request
  }

  /** The room, workspace or huddle socket at `path`, as an upgrade request from the app's own origin. */
  public func socketRequest(_ path: String) -> URLRequest {
    var request = request(path)
    guard let address = request.url, var parts = URLComponents(url: address, resolvingAgainstBaseURL: false) else { preconditionFailure("Unaddressable socket \(path)") }
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
    guard (200..<300).contains(http.statusCode) else { throw Self.problem(status: http.statusCode, data: data) }
    return (data, http)
  }

  /** The problem in a failure's body, or the status's own words when it has none (`ApiError`). */
  static func problem(status: Int, data: Data) -> EmberError {
    struct Body: Decodable {
      let error: String?
      let field: String?
      let redirect: String?
      let signIn: Bool?
      let client: Bool?
    }
    let fallback = "Request failed (\(status))"
    guard !data.isEmpty else { return .refused(status, fallback) }
    do {
      let body = try JSONDecoder().decode(Body.self, from: data)
      guard let message = body.error else { return .refused(status, fallback) }
      return .problem(EmberProblem(status: status, message: message, field: body.field, redirect: body.redirect, signIn: body.signIn == true, client: body.client == true))
    } catch {
      // An HTML failure page, such as a proxy's: the status says what happened, as the web's `dataOf` does.
      return .refused(status, fallback)
    }
  }

  public func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
    let (data, _) = try await send(request(path))
    return try decode(data, from: path)
  }

  public func write<T: Decodable>(_ method: String, _ path: String, json body: some Encodable, timeout: TimeInterval? = nil, as type: T.Type = T.self) async throws -> T {
    let (data, _) = try await send(jsonRequest(method, path, body, timeout: timeout))
    return try decode(data, from: path)
  }

  public func write<T: Decodable>(_ method: String, _ path: String, as type: T.Type = T.self) async throws -> T {
    let (data, _) = try await send(request(path, method: method))
    return try decode(data, from: path)
  }

  public func perform(_ method: String, _ path: String) async throws {
    try await send(request(path, method: method))
  }

  public func perform(_ method: String, _ path: String, json body: some Encodable) async throws {
    try await send(jsonRequest(method, path, body))
  }

  func jsonRequest(_ method: String, _ path: String, _ body: some Encodable, timeout: TimeInterval? = nil) throws -> URLRequest {
    var request = request(path, method: method, timeout: timeout)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    return request
  }

  /** A multipart form, as the web sends forms that carry a photo. */
  public func formRequest(_ method: String, _ path: String, form: MultipartForm, timeout: TimeInterval? = nil) -> URLRequest {
    var request = request(path, method: method, timeout: timeout)
    request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = form.body
    return request
  }

  func decode<T: Decodable>(_ data: Data, from path: String) throws -> T {
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch let error as DecodingError {
      throw EmberError.undecodable("\(path): \(Self.describe(error))")
    } catch {
      throw EmberError.undecodable("\(path): \(error.localizedDescription)")
    }
  }

  static func describe(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String { context.codingPath.map(\.stringValue).joined(separator: ".") }
    switch error {
    case let .keyNotFound(key, context): return "\(path(context)).\(key.stringValue) is missing"
    case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
      return "\(path(context)): \(context.debugDescription)"
    @unknown default: return error.localizedDescription
    }
  }

  /** Keeps the session token any answer sets, as sign-in does and later answers do when they extend it, and forgets one Ember expires. */
  private func keepSession(from response: HTTPURLResponse) {
    guard let value = SessionCookie.token(named: cookieName, in: response) else { return }
    tokens.setToken(value.isEmpty ? nil : value, for: instance.id)
  }

  /** The bytes at `path` on this instance, such as a file's preview or someone's avatar, with the session that may see them. */
  public func data(at path: String) async throws -> Data {
    var request = request(path)
    request.setValue(Self.anyType, forHTTPHeaderField: "Accept")
    return try await send(request).0
  }

  public struct Empty: Codable, Sendable {}
  struct UserAnswer: Decodable { let user: Me }
  struct RoomAnswer: Decodable { let room: Room }
}

/** A `multipart/form-data` body, as the web's `FormData` sends one. */
public struct MultipartForm: Sendable {
  public let boundary = "ircX-\(UUID().uuidString)"
  public private(set) var body = Data()

  public init() {}

  public mutating func add(_ name: String, text: String) {
    body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(text)\r\n".utf8))
  }

  public mutating func add(_ name: String, file data: Data, fileName: String, contentType: String) {
    let escaped = fileName.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(escaped)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
    body.append(data)
    body.append(Data("\r\n".utf8))
  }

  /** The form finished, ready to send. */
  public func finished() -> MultipartForm {
    var form = self
    form.body.append(Data("--\(boundary)--\r\n".utf8))
    return form
  }

  /** `photoForm`: `user` as JSON when there are fields, the photo as `avatar`, and its variant. */
  public static func photo(_ photo: ChosenPhoto, user fields: (any Encodable)? = nil) throws -> MultipartForm {
    var form = MultipartForm()
    if let fields { form.add("user", text: String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)) }
    form.add("avatar", file: photo.data, fileName: photo.fileName, contentType: photo.contentType)
    if let variant = photo.variant { form.add("variant", file: variant, fileName: "variant", contentType: photo.variantContentType) }
    return form.finished()
  }
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
      guard let pair = cookie.split(separator: ";", maxSplits: 1).first else { continue }
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
    token(in: link)
  }

  /** The token in a link's `#token=` (sign-in, invitation and email links), or a bare token. */
  public static func token(in link: String) -> String? {
    let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
    if let range = text.range(of: "token=") {
      let id = text[range.upperBound...].prefix { $0 != "&" }
      return id.isEmpty ? nil : String(id)
    }
    return text.isEmpty || text.contains("/") || text.contains(" ") ? nil : text
  }
}
