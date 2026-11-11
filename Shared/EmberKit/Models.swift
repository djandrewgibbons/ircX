import Foundation

// Swift mirrors of the types in packages/protocol/src/index.ts that the app reads. Fields the app
// doesn't use are left out: JSONDecoder ignores keys a type doesn't name.

public typealias UserID = String
public typealias RoomID = String

public struct User: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String

  public init(id: UserID, name: String) {
    self.id = id
    self.name = name
  }
}

public struct Me: Codable, Hashable, Sendable {
  public var id: UserID
  public var name: String
  public var administrator: Bool

  public var user: User { User(id: id, name: name) }
}

public enum Role: String, Codable, Sendable {
  case member, administrator, bot
}

public enum UserStatus: String, Codable, Sendable {
  case active, deactivated, banned, suspended
}

public struct DirectoryUser: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  public var bio: String?
  public var role: Role
  public var status: UserStatus
  public var avatarUrl: String
  public var agent: Bool?
}

public struct Directory: Codable, Sendable {
  public var users: [DirectoryUser]
}

public enum RoomKind: String, Codable, Sendable {
  case open, closed, direct
}

public enum Involvement: String, Codable, Sendable, CaseIterable {
  case mentions, everything, nothing, invisible
}

/** A room as the sidebar and `room.saved` frames carry it: a shared room or a DM, flattened into one type. */
public struct Room: Codable, Hashable, Sendable, Identifiable {
  public var id: RoomID
  public var kind: RoomKind
  /** Shared rooms only. */
  public var name: String?
  public var icon: String?
  /** DMs only: everyone in it, the reader included. */
  public var members: [User]?
  /** DMs only, as an ISO time. */
  public var activeAt: String?

  public var isDirect: Bool { kind == .direct }

  /** What the sidebar and the buffer title call the room: `#name`, or the other people in a DM. */
  public func title(for me: UserID?) -> String {
    if let name, !isDirect { return name }
    let others = (members ?? []).filter { $0.id != me }
    if others.isEmpty { return members?.first?.name ?? "me" }
    return others.map(\.name).sorted().joined(separator: ", ")
  }
}

public struct SidebarRoom: Codable, Hashable, Sendable, Identifiable {
  public var room: Room
  public var unread: Bool
  public var involvement: Involvement

  public var id: RoomID { room.id }

  public init(room: Room, unread: Bool, involvement: Involvement) {
    self.room = room
    self.unread = unread
    self.involvement = involvement
  }

  // The protocol's SidebarRoom is `Room & { unread, involvement }`: one flat object.
  public init(from decoder: Decoder) throws {
    room = try Room(from: decoder)
    let c = try decoder.container(keyedBy: Keys.self)
    unread = try c.decode(Bool.self, forKey: .unread)
    involvement = try c.decodeIfPresent(Involvement.self, forKey: .involvement) ?? (room.isDirect ? .everything : .mentions)
  }

  public func encode(to encoder: Encoder) throws {
    try room.encode(to: encoder)
    var c = encoder.container(keyedBy: Keys.self)
    try c.encode(unread, forKey: .unread)
    try c.encode(involvement, forKey: .involvement)
  }

  private enum Keys: String, CodingKey { case unread, involvement }
}

public struct Favorites: Codable, Hashable, Sendable {
  public var rooms: [RoomID]
  public var version: Int
}

public struct LiveHuddle: Codable, Hashable, Sendable {
  public var startedAt: String
  public var userIds: [UserID]
}

public struct Sidebar: Codable, Sendable {
  public var rooms: [SidebarRoom]
  public var favorites: Favorites
  public var sharedOrder: [RoomID]
  public var suggestions: [User]
  public var huddles: [RoomID: LiveHuddle]
}

public struct Account: Codable, Hashable, Sendable {
  public var name: String
  public var tagline: String
  public var logo: String?
  public var customDomain: String?
}

public enum SetupState: String, Codable, Sendable {
  case pending, complete
}

public struct Bootstrap: Codable, Sendable {
  public var setup: SetupState
  public var guestSignIn: Bool
  public var signInWithMemberful: Bool
  public var account: Account
  public var version: String
  public var user: Me?
}

public struct Boost: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var messageId: String
  public var booster: User
  public var content: String
  public var createdAt: String
}

public struct StoredFile: Codable, Hashable, Sendable {
  public var id: String
  public var name: String
  public var contentType: String
  public var byteSize: Int
  public var width: Int?
  public var height: Int?
  public var url: String
  public var downloadUrl: String
  public var previewUrl: String?

  public var isImage: Bool { contentType.hasPrefix("image/") }
}

public struct ThreadSummary: Codable, Hashable, Sendable {
  public var count: Int
  public var latestAt: String
  public var people: [User]
}

public struct Message: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var clientMessageId: String
  public var roomId: RoomID
  public var creator: User
  public var body: String
  public var plainText: String
  public var mentions: [User]
  public var createdAt: String
  public var updatedAt: String
  public var editedAt: String?
  public var boosts: [Boost]
  public var attachment: StoredFile?
  public var parentId: String?
  public var alsoSent: Bool?
  public var parentText: String?
  public var thread: ThreadSummary?
  public var deleted: Bool?

  public init(
    id: String, clientMessageId: String, roomId: RoomID, creator: User, body: String, plainText: String, mentions: [User] = [],
    createdAt: String, updatedAt: String, editedAt: String? = nil, boosts: [Boost] = [], attachment: StoredFile? = nil,
    parentId: String? = nil, alsoSent: Bool? = nil, parentText: String? = nil, thread: ThreadSummary? = nil, deleted: Bool? = nil
  ) {
    self.id = id
    self.clientMessageId = clientMessageId
    self.roomId = roomId
    self.creator = creator
    self.body = body
    self.plainText = plainText
    self.mentions = mentions
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.editedAt = editedAt
    self.boosts = boosts
    self.attachment = attachment
    self.parentId = parentId
    self.alsoSent = alsoSent
    self.parentText = parentText
    self.thread = thread
    self.deleted = deleted
  }

  /** Whether the room's timeline shows it: every message but a reply sent only to its thread. */
  public var isInRoom: Bool { parentId == nil || alsoSent == true }

  public var createdDate: Date { EmberDate.parse(createdAt) ?? .distantPast }

  /** Whether it was written with /me: its whole body one `<em>` that starts with its author's name. */
  public var isAction: Bool { MessageBody.isAction(body: body, plainText: plainText, author: creator.name) }

  public func mentions(_ userID: UserID) -> Bool { mentions.contains { $0.id == userID } }
}

/** What `POST /api/directs` answers. */
public struct StartedDirect: Codable, Sendable {
  public var room: Room
}

public struct NewRoomForm: Codable, Sendable {
  public var people: [User]
}

public enum EmberDate {
  nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  nonisolated(unsafe) private static let whole: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  public static func parse(_ text: String) -> Date? {
    fractional.date(from: text) ?? whole.date(from: text)
  }
}
