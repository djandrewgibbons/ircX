import Foundation

/** The revision of the room protocol EmberKit speaks: `ROOM_PROTOCOL` in packages/protocol. */
public let roomProtocol = 4

/** What a room closes its socket with when access ends: `CloseCode` in packages/protocol. */
public enum CloseCode: Int, Sendable {
  /** Connect again, and ask whether still signed in. */
  case reconnect = 4001
  /** Removed from the workspace or banned: don't connect again. */
  case revoked = 4003
  /** The room's gone for this person: don't connect again. */
  case notFound = 4004
}

/** A frame the app sends on a room socket (`ClientFrame`). */
public enum ClientFrame: Sendable, Equatable {
  case messageCreate(clientMessageId: String, body: String, parentId: String? = nil, alsoSend: Bool = false)
  case messageUpdate(messageId: String, body: String)
  case messageDelete(messageId: String)
  case boostCreate(messageId: String, content: String)
  case boostDelete(boostId: String)
  case typingStart
  case typingStop
  case historyBefore(before: String, limit: Int? = nil)
  case historyAround(messageId: String?)
  case messageCheck(clientMessageIds: [String])
  case threadOpen(parentId: String)
  case threadClose(parentId: String)
  case threadBefore(parentId: String, before: String, limit: Int? = nil)
  case presenceVisible(Bool)
  case ping

  public var json: [String: Any] {
    switch self {
    case let .messageCreate(clientMessageId, body, parentId, alsoSend):
      var frame: [String: Any] = ["type": "message.create", "clientMessageId": clientMessageId, "body": body]
      if let parentId {
        frame["parentId"] = parentId
        frame["alsoSend"] = alsoSend
      }
      return frame
    case let .messageUpdate(messageId, body): return ["type": "message.update", "messageId": messageId, "body": body]
    case let .messageDelete(messageId): return ["type": "message.delete", "messageId": messageId]
    case let .boostCreate(messageId, content): return ["type": "boost.create", "messageId": messageId, "content": content]
    case let .boostDelete(boostId): return ["type": "boost.delete", "boostId": boostId]
    case .typingStart: return ["type": "typing.start"]
    case .typingStop: return ["type": "typing.stop"]
    case let .historyBefore(before, limit): return withLimit(["type": "history.before", "before": before], limit)
    case let .historyAround(messageId):
      var frame: [String: Any] = ["type": "history.around"]
      if let messageId { frame["messageId"] = messageId }
      return frame
    case let .messageCheck(ids): return ["type": "message.check", "clientMessageIds": ids]
    case let .threadOpen(parentId): return ["type": "thread.open", "parentId": parentId]
    case let .threadClose(parentId): return ["type": "thread.close", "parentId": parentId]
    case let .threadBefore(parentId, before, limit): return withLimit(["type": "thread.before", "parentId": parentId, "before": before], limit)
    case let .presenceVisible(visible): return ["type": "presence.visible", "visible": visible]
    case .ping: return ["type": "ping"]
    }
  }

  public func encoded() throws -> String {
    let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
  }

  private func withLimit(_ frame: [String: Any], _ limit: Int?) -> [String: Any] {
    guard let limit else { return frame }
    var frame = frame
    frame["limit"] = limit
    return frame
  }
}

/** A page of messages that takes the timeline's place (`TimelinePage`). */
public struct TimelinePage: Sendable, Equatable {
  public var messages: [Message]
  public var hasMore: Bool
  public var hasNewer: Bool
  public var around: String?
}

/** A frame a room sends (`ServerFrame`). Frames this client doesn't know decode as `.unknown`. */
public enum ServerFrame: Sendable, Equatable {
  case welcome(you: User, present: [User], seq: Int, page: TimelinePage)
  case resumed(you: User, messages: [Message], deletedIds: [String], present: [User], seq: Int)
  case messageCreated(Message, seq: Int)
  case messageUpdated(Message, seq: Int)
  case messageDeleted(messageId: String, seq: Int)
  case boostCreated(Boost, seq: Int)
  case boostDeleted(boostId: String, messageId: String, seq: Int)
  case presenceJoined(User)
  case presenceLeft(UserID)
  case typing(user: User, typing: Bool, threadId: String?)
  case history(before: String, messages: [Message], hasMore: Bool)
  case historyAround(TimelinePage)
  case messageChecked(stored: [String], missing: [String])
  case threadOpened(parentId: String, parent: Message?, messages: [Message], hasMore: Bool)
  case threadHistory(parentId: String, before: String, messages: [Message], hasMore: Bool)
  case error(message: String, clientMessageId: String?, failed: String?)
  case pong
  case unknown(String)

  public static func decode(_ data: Data) throws -> ServerFrame {
    try JSONDecoder().decode(Envelope.self, from: data).frame
  }

  public static func decode(_ text: String) throws -> ServerFrame {
    try decode(Data(text.utf8))
  }

  private struct Envelope: Decodable {
    let frame: ServerFrame

    enum Keys: String, CodingKey {
      case type, you, present, seq, messages, hasMore, hasNewer, around, deletedIds, message, messageId
      case boost, boostId, user, userId, typing, threadId, before, stored, missing, parentId, parent
      case clientMessageId, failed
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: Keys.self)
      let type = try c.decode(String.self, forKey: .type)
      func page() throws -> TimelinePage {
        TimelinePage(
          messages: try c.decode([Message].self, forKey: .messages),
          hasMore: try c.decode(Bool.self, forKey: .hasMore),
          hasNewer: try c.decodeIfPresent(Bool.self, forKey: .hasNewer) ?? false,
          around: try c.decodeIfPresent(String.self, forKey: .around)
        )
      }
      switch type {
      case "welcome":
        frame = .welcome(you: try c.decode(User.self, forKey: .you), present: try c.decode([User].self, forKey: .present), seq: try c.decode(Int.self, forKey: .seq), page: try page())
      case "resumed":
        frame = .resumed(
          you: try c.decode(User.self, forKey: .you), messages: try c.decode([Message].self, forKey: .messages),
          deletedIds: try c.decode([String].self, forKey: .deletedIds), present: try c.decode([User].self, forKey: .present),
          seq: try c.decode(Int.self, forKey: .seq))
      case "message.created": frame = .messageCreated(try c.decode(Message.self, forKey: .message), seq: try c.decode(Int.self, forKey: .seq))
      case "message.updated": frame = .messageUpdated(try c.decode(Message.self, forKey: .message), seq: try c.decode(Int.self, forKey: .seq))
      case "message.deleted": frame = .messageDeleted(messageId: try c.decode(String.self, forKey: .messageId), seq: try c.decode(Int.self, forKey: .seq))
      case "boost.created": frame = .boostCreated(try c.decode(Boost.self, forKey: .boost), seq: try c.decode(Int.self, forKey: .seq))
      case "boost.deleted":
        frame = .boostDeleted(boostId: try c.decode(String.self, forKey: .boostId), messageId: try c.decode(String.self, forKey: .messageId), seq: try c.decode(Int.self, forKey: .seq))
      case "presence.joined": frame = .presenceJoined(try c.decode(User.self, forKey: .user))
      case "presence.left": frame = .presenceLeft(try c.decode(String.self, forKey: .userId))
      case "typing":
        frame = .typing(user: try c.decode(User.self, forKey: .user), typing: try c.decode(Bool.self, forKey: .typing), threadId: try c.decodeIfPresent(String.self, forKey: .threadId))
      case "history":
        frame = .history(before: try c.decode(String.self, forKey: .before), messages: try c.decode([Message].self, forKey: .messages), hasMore: try c.decode(Bool.self, forKey: .hasMore))
      case "history.around": frame = .historyAround(try page())
      case "message.checked": frame = .messageChecked(stored: try c.decode([String].self, forKey: .stored), missing: try c.decode([String].self, forKey: .missing))
      case "thread.opened":
        frame = .threadOpened(
          parentId: try c.decode(String.self, forKey: .parentId), parent: try c.decodeIfPresent(Message.self, forKey: .parent),
          messages: try c.decode([Message].self, forKey: .messages), hasMore: try c.decode(Bool.self, forKey: .hasMore))
      case "thread.history":
        frame = .threadHistory(
          parentId: try c.decode(String.self, forKey: .parentId), before: try c.decode(String.self, forKey: .before),
          messages: try c.decode([Message].self, forKey: .messages), hasMore: try c.decode(Bool.self, forKey: .hasMore))
      case "error":
        frame = .error(message: try c.decode(String.self, forKey: .message), clientMessageId: try c.decodeIfPresent(String.self, forKey: .clientMessageId), failed: try c.decodeIfPresent(String.self, forKey: .failed))
      case "pong": frame = .pong
      default: frame = .unknown(type)
      }
    }
  }
}

/** A frame the Workspace sends on the workspace socket (`WorkspaceServerFrame`). */
public enum WorkspaceFrame: Sendable, Equatable {
  case welcome(you: Me, account: Account)
  case roomUnread(RoomID)
  case roomRead(RoomID)
  case userUpdated(DirectoryUser)
  case roomSaved(Room)
  case roomGone(RoomID)
  case roomActive(RoomID, at: String)
  case roomHuddle(RoomID, LiveHuddle?)
  case favoritesChanged(Favorites)
  case roomInvolvement(RoomID, Involvement)
  case roomsReordered
  case accountUpdated(Account)
  case error(String)
  case pong
  case unknown(String)

  public static func decode(_ text: String) throws -> WorkspaceFrame {
    try JSONDecoder().decode(Envelope.self, from: Data(text.utf8)).frame
  }

  private struct Envelope: Decodable {
    let frame: WorkspaceFrame

    enum Keys: String, CodingKey {
      case type, you, account, roomId, user, room, at, huddle, favorites, involvement, message
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: Keys.self)
      let type = try c.decode(String.self, forKey: .type)
      switch type {
      case "welcome": frame = .welcome(you: try c.decode(Me.self, forKey: .you), account: try c.decode(Account.self, forKey: .account))
      case "room.unread": frame = .roomUnread(try c.decode(String.self, forKey: .roomId))
      case "room.read": frame = .roomRead(try c.decode(String.self, forKey: .roomId))
      case "user.updated": frame = .userUpdated(try c.decode(DirectoryUser.self, forKey: .user))
      case "room.saved": frame = .roomSaved(try c.decode(Room.self, forKey: .room))
      case "room.gone": frame = .roomGone(try c.decode(String.self, forKey: .roomId))
      case "room.active": frame = .roomActive(try c.decode(String.self, forKey: .roomId), at: try c.decode(String.self, forKey: .at))
      case "room.huddle": frame = .roomHuddle(try c.decode(String.self, forKey: .roomId), try c.decodeIfPresent(LiveHuddle.self, forKey: .huddle))
      case "favorites.changed": frame = .favoritesChanged(try c.decode(Favorites.self, forKey: .favorites))
      case "room.involvement": frame = .roomInvolvement(try c.decode(String.self, forKey: .roomId), try c.decode(Involvement.self, forKey: .involvement))
      case "rooms.reordered": frame = .roomsReordered
      case "account.updated": frame = .accountUpdated(try c.decode(Account.self, forKey: .account))
      case "error": frame = .error(try c.decode(String.self, forKey: .message))
      case "pong": frame = .pong
      default: frame = .unknown(type)
      }
    }
  }
}
