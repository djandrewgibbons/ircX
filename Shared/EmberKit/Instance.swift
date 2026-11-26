import Foundation

/**
 * An Ember deployment the app signs in to, such as irc.dxnd.ai. Each keeps its own session, so the
 * app can be signed in to many at once, as Slack is to many workspaces.
 */
public struct Instance: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  /** The deployment's origin, such as https://irc.dxnd.ai. */
  public var baseURL: URL
  /** The workspace's name, as its account last said, which the rail and title show. */
  public var name: String
  /** The person signed in, as the instance last said, to show before it's reachable. */
  public var nick: String?

  public init(id: UUID = UUID(), baseURL: URL, name: String? = nil, nick: String? = nil) {
    self.id = id
    self.baseURL = baseURL
    self.name = name ?? baseURL.host() ?? baseURL.absoluteString
    self.nick = nick
  }

  public var host: String { baseURL.host() ?? baseURL.absoluteString }

  /** The origin Ember checks writes and socket upgrades against: scheme, host and any port. */
  public var origin: String {
    var origin = "\(baseURL.scheme ?? "https")://\(host)"
    if let port = baseURL.port { origin += ":\(port)" }
    return origin
  }

  public var isSecure: Bool { baseURL.scheme == "https" }

  /**
   * The address someone typed, such as `irc.dxnd.ai`, `chat.example.com/` or `http://localhost:8787`,
   * as an origin: https unless they said otherwise, with any path dropped.
   */
  public static func baseURL(from typed: String) -> URL? {
    var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if !text.contains("://") { text = "https://" + text }
    guard var parts = URLComponents(string: text), let host = parts.host, !host.isEmpty,
      parts.scheme == "https" || parts.scheme == "http"
    else { return nil }
    parts.path = ""
    parts.query = nil
    parts.fragment = nil
    parts.user = nil
    parts.password = nil
    return parts.url
  }
}

/** The instances the app knows, in the rail's order, kept in UserDefaults. Their sessions are in the Keychain. */
public struct InstanceList: Codable, Sendable {
  public var instances: [Instance]

  public init(instances: [Instance]) {
    self.instances = instances
  }

  public static let defaultsKey = "ember.instances"

  /** irc.dxnd.ai, which the app starts with. */
  public static let home = Instance(baseURL: URL(string: "https://irc.dxnd.ai")!, name: "dxnd")

  public static func load(from defaults: UserDefaults = .standard) -> InstanceList {
    guard let data = defaults.data(forKey: defaultsKey), let list = try? JSONDecoder().decode(InstanceList.self, from: data) else {
      return InstanceList(instances: [home])
    }
    return list
  }

  public func save(to defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
  }
}
