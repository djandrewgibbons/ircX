import Foundation

// packages/protocol/src/push.ts (web push subscriptions), and the native device tokens the ircX push
// design adds beside them (specs/push.md 4.3).

/** A browser's push subscription, as `POST /api/push-subscriptions` takes it (`PushSubscriptionKeys`). */
public struct PushSubscriptionKeys: Codable, Hashable, Sendable {
  public var endpoint: String
  /** The browser's P-256 public key, in URL-safe Base64. */
  public var p256dhKey: String
  /** The browser's authentication secret, in URL-safe Base64. */
  public var authKey: String

  public init(endpoint: String, p256dhKey: String, authKey: String) {
    self.endpoint = endpoint
    self.p256dhKey = p256dhKey
    self.authKey = authKey
  }
}

/** What `POST /api/push-subscriptions` takes (`PushSubscriptionSave`): a subscription, and the key of the one it replaces. */
public struct PushSubscriptionSave: Codable, Hashable, Sendable {
  public var endpoint: String
  public var p256dhKey: String
  public var authKey: String
  public var replacing: String?

  public init(_ keys: PushSubscriptionKeys, replacing: String? = nil) {
    endpoint = keys.endpoint
    p256dhKey = keys.p256dhKey
    authKey = keys.authKey
    self.replacing = replacing
  }
}

/** A browser's push subscription, as the subscriptions page lists it (`SavedPushSubscription`). */
public struct SavedPushSubscription: Codable, Hashable, Sendable, Identifiable {
  public var id: Int
  public var endpoint: String
  public var browser: String
  public var version: String
  public var platform: String
}

/** `PushSubscriptions` */
public struct PushSubscriptions: Codable, Sendable {
  public var subscriptions: [SavedPushSubscription]
}

/** What signing out sends (`SignOut`): the push subscription to forget with the session. */
public struct SignOut: Codable, Sendable {
  public var pushSubscriptionEndpoint: String?

  public init(pushSubscriptionEndpoint: String? = nil) {
    self.pushSubscriptionEndpoint = pushSubscriptionEndpoint
  }
}

public enum DevicePlatform: String, Codable, Sendable {
  case ios, macos
}

public enum DeviceEnvironment: String, Codable, Sendable {
  case development, production
}

/** An APNs device token to save (`DeviceTokenSave`), with the address the app knows the server by. */
public struct DeviceTokenSave: Codable, Sendable {
  public var token: String
  public var platform: DevicePlatform
  public var environment: DeviceEnvironment
  public var origin: String
  public var deviceName: String?

  public init(token: String, platform: DevicePlatform, environment: DeviceEnvironment, origin: String, deviceName: String? = nil) {
    self.token = token
    self.platform = platform
    self.environment = environment
    self.origin = origin
    self.deviceName = deviceName
  }
}

/** A saved device token (`SavedDeviceToken`). */
public struct DeviceToken: Codable, Hashable, Sendable, Identifiable {
  public var id: Int
  public var token: String
  public var platform: DevicePlatform
  public var environment: DeviceEnvironment
  /** The address the device knows the server by, which its pushes carry back. */
  public var origin: String
  /** "" when the device gave none. */
  public var deviceName: String
  public var updatedAt: String
}

/** `DeviceTokens` */
public struct DeviceTokens: Codable, Sendable {
  public var deviceTokens: [DeviceToken]
}

public enum Push {
  public static let maxEndpointLength = 2048
  public static let maxKeyLength = 256
  public static let maxSubscriptions = 10
  public static let maxDeviceTokenLength = 200
  public static let maxDeviceTokens = 10
  public static let minDeviceTokenLength = 64
  public static let maxDeviceOriginLength = 256
  public static let maxDeviceNameLength = 100
  /** The page that lists push subscriptions (`PUSH_SUBSCRIPTIONS_PATH`). */
  public static let subscriptionsPath = "/users/me/push_subscriptions"
}

/** What an APNs push to ircX carries beside `aps` (`DevicePushData`): the server, the page, and the room and message it's about. */
public struct DevicePushData: Equatable, Sendable {
  /** The server's address, as this device saved it. */
  public var origin: String
  /** The page opening it opens, such as `/rooms/<id>` or a thread reply's path. */
  public var path: String
  public var roomId: RoomID?
  public var messageId: String?
  /** For a reply in a thread, the message it replies to. */
  public var parentId: String?

  public init(origin: String, path: String, roomId: RoomID? = nil, messageId: String? = nil, parentId: String? = nil) {
    self.origin = origin
    self.path = path
    self.roomId = roomId
    self.messageId = messageId
    self.parentId = parentId
  }

  /** Reads a notification's user info; nil when it isn't one of Ember's (no origin or path). */
  public init?(userInfo: [AnyHashable: Any]) {
    guard let origin = userInfo["origin"] as? String, let path = userInfo["path"] as? String else { return nil }
    self.init(
      origin: origin, path: path, roomId: userInfo["roomId"] as? String, messageId: userInfo["messageId"] as? String,
      parentId: userInfo["parentId"] as? String)
  }

  /** The page's address on its server, which the server's link handling opens. */
  public var link: String { origin + path }
}

extension Push {
  /** An APNs device token as `POST /api/device-tokens` takes it: lower-case hexadecimal. */
  public static func hex(_ token: Data) -> String {
    token.map { String(format: "%02x", $0) }.joined()
  }

  /** How a device is listed: its name and platform. */
  public static func label(_ device: DeviceToken) -> String {
    let platform = device.platform == .ios ? "iOS" : "macOS"
    return device.deviceName.isEmpty ? "ircX on \(platform)" : "\(device.deviceName) (\(platform))"
  }

  /** How a browser's subscription is listed (web `PushSubscriptionsPage`): "<browser> <version> on <platform>". */
  public static func label(_ subscription: SavedPushSubscription) -> String {
    let browser = [subscription.browser, subscription.version].filter { !$0.isEmpty }.joined(separator: " ")
    return subscription.platform.isEmpty ? browser : "\(browser) on \(subscription.platform)"
  }
}
