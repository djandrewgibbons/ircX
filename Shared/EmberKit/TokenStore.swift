import Foundation
#if canImport(Security)
import Security
#endif

/**
 * Where each instance's session token is kept. The token is what Ember's HttpOnly `session_token`
 * cookie holds; the app sends it back in a Cookie header of its own rather than sharing one cookie
 * jar, so instances never see each other's sessions.
 */
public protocol TokenStore: Sendable {
  func token(for instance: UUID) -> String?
  func setToken(_ token: String?, for instance: UUID)
}

/** Tokens in memory, for tests and previews. */
public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
  private var tokens: [UUID: String] = [:]
  private let lock = NSLock()

  public init() {}

  public func token(for instance: UUID) -> String? {
    lock.withLock { tokens[instance] }
  }

  public func setToken(_ token: String?, for instance: UUID) {
    lock.withLock { tokens[instance] = token }
  }
}

#if canImport(Security)
/** Tokens in the Keychain, one generic password per instance, readable after first unlock so reconnects work in the background. */
public struct KeychainTokenStore: TokenStore {
  public let service: String

  public init(service: String = "ai.dxnd.ircX.session") {
    self.service = service
  }

  private func query(_ instance: UUID) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: instance.uuidString]
  }

  public func token(for instance: UUID) -> String? {
    var q = query(instance)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func setToken(_ token: String?, for instance: UUID) {
    SecItemDelete(query(instance) as CFDictionary)
    guard let token else { return }
    var q = query(instance)
    q[kSecValueData as String] = Data(token.utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(q as CFDictionary, nil)
  }
}
#endif
