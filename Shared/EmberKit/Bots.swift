import Foundation

// packages/protocol/src/bots.ts: chat bots, which post to rooms with their key.

/** A room a bot posts to (`BotRoom`), and an agent's (`AgentRoom`). */
public struct NamedRoom: Codable, Hashable, Sendable, Identifiable {
  public var id: RoomID
  public var name: String

  public init(id: RoomID, name: String) {
    self.id = id
    self.name = name
  }
}

/** A bot, as administrators list them (`Bot`). */
public struct Bot: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  public var username: String?
  public var bio: String?
  public var role: Role
  public var status: UserStatus
  public var avatarUrl: String
  public var agent: Bool?
  public var adminsOnly: Bool?
  public var key: String
  public var rooms: [NamedRoom]
}

/** A bot as its settings page shows it (`BotSettings`): `pickedRooms` nil for every open room. */
public struct BotSettings: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  public var username: String?
  public var bio: String?
  public var role: Role
  public var status: UserStatus
  public var avatarUrl: String
  public var agent: Bool?
  public var adminsOnly: Bool?
  public var key: String
  public var rooms: [NamedRoom]
  public var webhookUrl: String?
  public var pickedRooms: [NamedRoom]?
}

/** `Bots` */
public struct Bots: Codable, Sendable {
  public var bots: [Bot]
}

/** `BotAnswer` */
public struct BotAnswer: Codable, Sendable {
  public var bot: BotSettings
}

/** Which rooms a bot or an agent is in: a list of rooms, or every open room (null on the wire). */
public enum PickedRooms: Sendable, Equatable {
  case everyOpenRoom
  case these([RoomID])
}

/** A bot to make, or what changes in one (`NewBot`, `BotChanges`). */
public struct BotChanges: Encodable, Sendable {
  public var name: String?
  public var webhookUrl: String?
  public var rooms: PickedRooms?

  public init(name: String? = nil, webhookUrl: String? = nil, rooms: PickedRooms? = nil) {
    self.name = name
    self.webhookUrl = webhookUrl
    self.rooms = rooms
  }

  private enum Keys: String, CodingKey { case name, webhookUrl, rooms }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encodeIfPresent(name, forKey: .name)
    try c.encodeIfPresent(webhookUrl, forKey: .webhookUrl)
    switch rooms {
    case .everyOpenRoom: try c.encodeNil(forKey: .rooms)
    case let .these(ids): try c.encode(ids, forKey: .rooms)
    case nil: break
    }
  }
}

public enum BotsRules {
  public static let forbidden = "Only administrators can manage bots"
  public static let maxWebhookUrlLength = 2048
  public static let webhookUrlRefused = "Webhook URL must be an https URL, or an http one on localhost"
  public static let roomsRefused = "Rooms must be a list of rooms' IDs, each once, or null for every open room"
  public static let path = "/account/bots"

  /** `botMessagesPath`: where a bot posts with its key. */
  public static func messagesPath(room: RoomID, key: String, threadId: String? = nil) -> String {
    let path = "/rooms/\(URIComponent.encode(room))/\(key)/messages"
    guard let threadId else { return path }
    return "\(path)?thread=\(URIComponent.encode(threadId))"
  }

  /** `botSlackPath` */
  public static func slackPath(room: RoomID, key: String) -> String { "/rooms/\(URIComponent.encode(room))/\(key)/slack" }

  /** `botMessageSlackPath` */
  public static func messageSlackPath(room: RoomID, key: String, messageId: String) -> String {
    "/rooms/\(URIComponent.encode(room))/\(key)/messages/\(URIComponent.encode(messageId))/slack"
  }
}
