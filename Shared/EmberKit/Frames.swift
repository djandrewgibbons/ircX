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

/** A frame the app sends on a socket, as one JSON object with a `type`. */
public protocol SocketFrame: Sendable {
  var json: [String: Any] { get }
}

extension SocketFrame {
  public func encoded() throws -> String {
    let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
  }
}

/** What a room socket's address says (`RoomSocketParams`, `roomSocketQuery`). */
public struct RoomSocketParams: Sendable, Equatable {
  /** Whether the room shows: 1 reads the room as the socket connects. */
  public var visible: Bool
  /** The latest change seen, so the room answers `resumed` with what's changed since. */
  public var since: Int?
  /** A message to open the room at, as a permalink does, on the first connection only. */
  public var around: String?
  /** A thread shown apart from the timeline, as a huddle's: not counted here, reads nothing. */
  public var apart: Bool

  public init(visible: Bool, since: Int? = nil, around: String? = nil, apart: Bool = false) {
    self.visible = visible
    self.since = since
    self.around = around
    self.apart = apart
  }

  /** `roomSocketQuery` */
  public var query: String {
    var query = "?visible=\(visible ? 1 : 0)&protocol=\(roomProtocol)"
    if let since { query += "&since=\(since)" }
    if let around { query += "&around=\(URIComponent.encode(around))" }
    if apart { query += "&apart=1" }
    return query
  }

  /** The room socket's path, with its query. */
  public func path(_ room: RoomID) -> String { "/api/rooms/\(URIComponent.encode(room))/socket\(query)" }
}

/** `workspaceSocketQuery`: whether the app shows, which an absent query says it doesn't. */
public func workspaceSocketPath(visible: Bool) -> String { "/api/socket?visible=\(visible ? 1 : 0)" }

/** A frame the app sends on a room socket (`ClientFrame`). */
public enum ClientFrame: Sendable, Equatable, SocketFrame {
  case messageCreate(clientMessageId: String, body: String, parentId: String? = nil, alsoSend: Bool = false)
  case messageUpdate(messageId: String, body: String)
  /** Adds a link's preview to a message this socket sent, within `EmberLimits.latePreviewMilliseconds`. */
  case messagePreview(clientMessageId: String, preview: LinkPreview)
  case messageDelete(messageId: String)
  case boostCreate(messageId: String, content: String)
  case boostDelete(boostId: String)
  case typingStart
  case typingStop
  case historyBefore(before: String, limit: Int? = nil)
  case historyAfter(after: String, limit: Int? = nil)
  /** Without a message, the newest page. */
  case historyAround(messageId: String?)
  case messageCheck(clientMessageIds: [String])
  case threadOpen(parentId: String)
  case threadClose(parentId: String)
  case threadBefore(parentId: String, before: String, limit: Int? = nil)
  case presenceVisible(Bool)
  case cardClick(clickId: String, messageId: String, actionId: String, blockId: String? = nil, value: String? = nil)
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
    case let .messagePreview(clientMessageId, preview): return ["type": "message.preview", "clientMessageId": clientMessageId, "preview": preview.json]
    case let .messageDelete(messageId): return ["type": "message.delete", "messageId": messageId]
    case let .boostCreate(messageId, content): return ["type": "boost.create", "messageId": messageId, "content": content]
    case let .boostDelete(boostId): return ["type": "boost.delete", "boostId": boostId]
    case .typingStart: return ["type": "typing.start"]
    case .typingStop: return ["type": "typing.stop"]
    case let .historyBefore(before, limit): return withLimit(["type": "history.before", "before": before], limit)
    case let .historyAfter(after, limit): return withLimit(["type": "history.after", "after": after], limit)
    case let .historyAround(messageId):
      var frame: [String: Any] = ["type": "history.around"]
      if let messageId { frame["messageId"] = messageId }
      return frame
    case let .messageCheck(ids): return ["type": "message.check", "clientMessageIds": ids]
    case let .threadOpen(parentId): return ["type": "thread.open", "parentId": parentId]
    case let .threadClose(parentId): return ["type": "thread.close", "parentId": parentId]
    case let .threadBefore(parentId, before, limit): return withLimit(["type": "thread.before", "parentId": parentId, "before": before], limit)
    case let .presenceVisible(visible): return ["type": "presence.visible", "visible": visible]
    case let .cardClick(clickId, messageId, actionId, blockId, value):
      var frame: [String: Any] = ["type": "card.click", "clickId": clickId, "messageId": messageId, "actionId": actionId]
      if let blockId { frame["blockId"] = blockId }
      if let value { frame["value"] = value }
      return frame
    case .ping: return ["type": "ping"]
    }
  }

  private func withLimit(_ frame: [String: Any], _ limit: Int?) -> [String: Any] {
    guard let limit else { return frame }
    var frame = frame
    frame["limit"] = limit
    return frame
  }
}

/** A frame the app sends on the workspace socket (`WorkspaceClientFrame`). */
public enum WorkspaceClientFrame: Sendable, Equatable, SocketFrame {
  case ping
  /** Whether the app's in use: input within the last 10 minutes (`AWAY_AFTER_MS`). */
  case presenceActive(Bool)
  /** Whether the app shows. */
  case presenceVisible(Bool)

  public var json: [String: Any] {
    switch self {
    case .ping: ["type": "ping"]
    case let .presenceActive(active): ["type": "presence.active", "active": active]
    case let .presenceVisible(visible): ["type": "presence.visible", "visible": visible]
    }
  }
}

/** A page of messages that takes the timeline's place (`TimelinePage`). */
public struct TimelinePage: Sendable, Equatable {
  public var messages: [Message]
  public var hasMore: Bool
  public var hasNewer: Bool
  /** The message it's around, for a permalink, else nil for the newest. */
  public var around: String?
}

/** What a room's `error` frame says (`ServerFrame` `error`). The web shows `message` verbatim. */
public struct RoomError: Sendable, Equatable {
  public var message: String
  public var clientMessageId: String?
  /** The messages a `message.check` couldn't check. */
  public var clientMessageIds: [String]?
  public var clickId: String?
  /** The `type` of the client frame that failed. */
  public var failed: String?
  /** Refused for what it says, as blocked words are: keep the draft to change it. */
  public var rewrite: Bool

  public init(message: String, clientMessageId: String? = nil, clientMessageIds: [String]? = nil, clickId: String? = nil, failed: String? = nil, rewrite: Bool = false) {
    self.message = message
    self.clientMessageId = clientMessageId
    self.clientMessageIds = clientMessageIds
    self.clickId = clickId
    self.failed = failed
    self.rewrite = rewrite
  }

  /** The messages it says weren't sent. */
  public var notSent: [String] {
    if let clientMessageIds { return clientMessageIds }
    if let clientMessageId { return [clientMessageId] }
    return []
  }

  /** Whether the room's timeline shows it: not one about a thread, or a link's preview the app sent itself. */
  public var showsInRoom: Bool { !["thread.open", "thread.before", "message.preview"].contains(failed) }
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
  /** `doing` follows the name in the typing line, as an agent's "is searching this room". */
  case typing(user: User, typing: Bool, threadId: String?, doing: String?)
  case history(before: String, messages: [Message], hasMore: Bool)
  case historyAfter(after: String, messages: [Message], hasNewer: Bool)
  case historyAround(TimelinePage)
  case messageChecked(stored: [String], missing: [String])
  case threadOpened(parentId: String, parent: Message?, messages: [Message], hasMore: Bool)
  case threadHistory(parentId: String, before: String, messages: [Message], hasMore: Bool)
  case cardClicked(clickId: String)
  case error(RoomError)
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
      case boost, boostId, user, userId, typing, threadId, doing, before, after, stored, missing, parentId, parent
      case clientMessageId, clientMessageIds, clickId, failed, rewrite
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: Keys.self)
      let type = try c.decode(String.self, forKey: .type)
      func page() throws -> TimelinePage {
        TimelinePage(
          messages: try c.decode([Message].self, forKey: .messages),
          hasMore: try c.decode(Bool.self, forKey: .hasMore),
          hasNewer: try c.decode(Bool.self, forKey: .hasNewer),
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
        frame = .typing(
          user: try c.decode(User.self, forKey: .user), typing: try c.decode(Bool.self, forKey: .typing),
          threadId: try c.decodeIfPresent(String.self, forKey: .threadId), doing: try c.decodeIfPresent(String.self, forKey: .doing))
      case "history":
        frame = .history(before: try c.decode(String.self, forKey: .before), messages: try c.decode([Message].self, forKey: .messages), hasMore: try c.decode(Bool.self, forKey: .hasMore))
      case "history.after":
        frame = .historyAfter(after: try c.decode(String.self, forKey: .after), messages: try c.decode([Message].self, forKey: .messages), hasNewer: try c.decode(Bool.self, forKey: .hasNewer))
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
      case "card.clicked": frame = .cardClicked(clickId: try c.decode(String.self, forKey: .clickId))
      case "error":
        frame = .error(RoomError(
          message: try c.decode(String.self, forKey: .message), clientMessageId: try c.decodeIfPresent(String.self, forKey: .clientMessageId),
          clientMessageIds: try c.decodeIfPresent([String].self, forKey: .clientMessageIds), clickId: try c.decodeIfPresent(String.self, forKey: .clickId),
          failed: try c.decodeIfPresent(String.self, forKey: .failed), rewrite: try c.decodeIfPresent(Bool.self, forKey: .rewrite) == true))
      case "pong": frame = .pong
      default: frame = .unknown(type)
      }
    }
  }
}

/** A frame the Workspace sends on the workspace socket (`WorkspaceServerFrame`). */
public enum WorkspaceFrame: Sendable, Equatable {
  case welcome(you: Me, account: Account)
  /** `at` is when the first unread message came; `count`, in a DM, how many have. */
  case roomUnread(RoomID, at: String, count: Int?)
  case roomRead(RoomID)
  case userUpdated(DirectoryUser)
  /** Someone deleted their account: they leave every list. */
  case userGone(UserID)
  case roomSaved(Room)
  case roomGone(RoomID)
  case roomActive(RoomID, at: String)
  case roomHuddle(RoomID, LiveHuddle?)
  case huddleInvited(RoomID, by: UserID)
  case huddleAnswered(RoomID)
  case huddleSounds(HuddleSounds)
  case huddlesChanged
  case favoritesChanged(Favorites)
  case blocksChanged(Blocks)
  /** For administrators: how many reports are open. */
  case reportsChanged(open: Int)
  case roomInvolvement(RoomID, Involvement)
  case invitationDismissed
  case roomsReordered
  case accountUpdated(Account)
  /** The first after `presence.active` lists everyone active; later ones say who changed. */
  case presence(active: [UserID], away: [UserID])
  case error(String)
  case pong
  case unknown(String)

  public static func decode(_ text: String) throws -> WorkspaceFrame {
    try JSONDecoder().decode(Envelope.self, from: Data(text.utf8)).frame
  }

  private struct Envelope: Decodable {
    let frame: WorkspaceFrame

    enum Keys: String, CodingKey {
      case type, you, account, roomId, user, userId, room, at, count, huddle, by, sounds, favorites, blocks, open, involvement, active, away, message
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: Keys.self)
      let type = try c.decode(String.self, forKey: .type)
      func roomId() throws -> RoomID { try c.decode(String.self, forKey: .roomId) }
      switch type {
      case "welcome": frame = .welcome(you: try c.decode(Me.self, forKey: .you), account: try c.decode(Account.self, forKey: .account))
      case "room.unread": frame = .roomUnread(try roomId(), at: try c.decode(String.self, forKey: .at), count: try c.decodeIfPresent(Int.self, forKey: .count))
      case "room.read": frame = .roomRead(try roomId())
      case "user.updated": frame = .userUpdated(try c.decode(DirectoryUser.self, forKey: .user))
      case "user.gone": frame = .userGone(try c.decode(String.self, forKey: .userId))
      case "room.saved": frame = .roomSaved(try c.decode(Room.self, forKey: .room))
      case "room.gone": frame = .roomGone(try roomId())
      case "room.active": frame = .roomActive(try roomId(), at: try c.decode(String.self, forKey: .at))
      case "room.huddle": frame = .roomHuddle(try roomId(), try c.decodeIfPresent(LiveHuddle.self, forKey: .huddle))
      case "huddle.invited": frame = .huddleInvited(try roomId(), by: try c.decode(String.self, forKey: .by))
      case "huddle.answered": frame = .huddleAnswered(try roomId())
      case "huddle.sounds": frame = .huddleSounds(try c.decode(HuddleSounds.self, forKey: .sounds))
      case "huddles.changed": frame = .huddlesChanged
      case "favorites.changed": frame = .favoritesChanged(try c.decode(Favorites.self, forKey: .favorites))
      case "blocks.changed": frame = .blocksChanged(try c.decode(Blocks.self, forKey: .blocks))
      case "reports.changed": frame = .reportsChanged(open: try c.decode(Int.self, forKey: .open))
      case "room.involvement": frame = .roomInvolvement(try roomId(), try c.decode(Involvement.self, forKey: .involvement))
      case "invitation.dismissed": frame = .invitationDismissed
      case "rooms.reordered": frame = .roomsReordered
      case "account.updated": frame = .accountUpdated(try c.decode(Account.self, forKey: .account))
      case "presence": frame = .presence(active: try c.decode([String].self, forKey: .active), away: try c.decode([String].self, forKey: .away))
      case "error": frame = .error(try c.decode(String.self, forKey: .message))
      case "pong": frame = .pong
      default: frame = .unknown(type)
      }
    }
  }
}

/** Who's active, as the workspace socket's `presence` frames tell it (`activeAfter`). */
public struct ActivePeople: Sendable, Equatable {
  public private(set) var active: Set<UserID> = []
  /** Whether a `presence` frame has come since the socket connected, after which frames say who changed. */
  public private(set) var heard = false

  public init() {}

  public mutating func hear(active: [UserID], away: [UserID]) {
    if !heard { self.active = [] }
    heard = true
    self.active.subtract(away)
    self.active.formUnion(active)
  }

  /** The socket connected again: its first frame lists everyone afresh. */
  public mutating func reconnected() { heard = false }
}
