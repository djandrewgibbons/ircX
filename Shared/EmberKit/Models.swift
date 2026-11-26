import Foundation

// Swift mirrors of the people, room, sidebar, account and message types in packages/protocol/src/index.ts.
// TypeScript's required fields are non-optional here, its optional ones (`field?:`) and nullable ones
// (`T | null`) optional. The other areas live beside this: Admin.swift, Profile.swift, Huddles.swift,
// Cards.swift, Files.swift, Search.swift, Reports.swift, Push.swift, Elsewhere.swift, Bots.swift,
// Agents.swift, Apps.swift, Assistant.swift and Outside.swift.

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

/** Who's signed in: someone, and whether they're one of the workspace's administrators. */
public struct Me: Codable, Hashable, Sendable {
  public var id: UserID
  public var name: String
  public var administrator: Bool

  public init(id: UserID, name: String, administrator: Bool) {
    self.id = id
    self.name = name
    self.administrator = administrator
  }

  public var user: User { User(id: id, name: name) }
}

/** What someone is in the workspace (`Role`). */
public enum Role: String, Codable, Sendable, CaseIterable {
  case member, administrator, bot
}

/** A role an administrator can give someone (`PersonRole`): any but a bot's. */
public enum PersonRole: String, Codable, Sendable, CaseIterable {
  case member, administrator
}

/** Whether someone can still sign in (`UserStatus`). */
public enum UserStatus: String, Codable, Sendable, CaseIterable {
  case active, deactivated, banned, suspended
}

/** Someone as the people directory lists them (`DirectoryUser`). */
public struct DirectoryUser: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  /** The username they picked, which typing @ finds them by too. Left out while they have none. */
  public var username: String?
  public var bio: String?
  public var role: Role
  public var status: UserStatus
  /** `/users/<token>/avatar?v=<version>`, which needs the session cookie. */
  public var avatarUrl: String
  /** True for an AI agent, @ember or one an administrator made; left out for anyone else. */
  public var agent: Bool?
  /** True for an AI agent only administrators can ask; left out for anyone else. */
  public var adminsOnly: Bool?

  public init(
    id: UserID, name: String, username: String? = nil, bio: String? = nil, role: Role, status: UserStatus, avatarUrl: String,
    agent: Bool? = nil, adminsOnly: Bool? = nil
  ) {
    self.id = id
    self.name = name
    self.username = username
    self.bio = bio
    self.role = role
    self.status = status
    self.avatarUrl = avatarUrl
    self.agent = agent
    self.adminsOnly = adminsOnly
  }

  public var user: User { User(id: id, name: name) }
  public var isAgent: Bool { agent == true }
  public var isAdminsOnly: Bool { adminsOnly == true }
}

/** What `GET /api/users` answers (`Directory`). */
public struct Directory: Codable, Sendable {
  public var users: [DirectoryUser]
}

public enum RoomKind: String, Codable, Sendable, CaseIterable {
  case open, closed, direct

  /** The path segment pages name the kind by (`KIND_SEGMENTS`). */
  public var segment: String {
    switch self {
    case .open: "opens"
    case .closed: "closeds"
    case .direct: "directs"
    }
  }
}

/** How much someone hears of a room they're in (`INVOLVEMENTS`, in order). */
public enum Involvement: String, Codable, Sendable, CaseIterable {
  case mentions, everything, nothing, invisible

  /** The level someone starts at (`startingInvolvement`): all messages in a DM, @mentions elsewhere. */
  public static func starting(in room: Room) -> Involvement { room.isDirect ? .everything : .mentions }
}

/** Someone who joined the workspace, and when (`Joined`). */
public struct Joined: Codable, Hashable, Sendable {
  public var userId: UserID
  public var at: String
}

/**
 * A room as the sidebar and `room.saved` frames carry it (`Room = SharedRoom | DirectRoom`), flattened
 * into one type: a shared room has `name` and `icon`, a DM `members`, `activeAt` and maybe `joined`.
 */
public struct Room: Codable, Hashable, Sendable, Identifiable {
  public var id: RoomID
  public var kind: RoomKind
  /** Shared rooms only. */
  public var name: String?
  /** Shared rooms only: a `RoomIcons` name, or nil for the default `#`. */
  public var icon: String?
  /** Shared rooms only: false while the room's settings don't allow huddles in it, else left out. */
  public var huddles: Bool?
  /** DMs only: everyone in it, the reader included. */
  public var members: [User]?
  /** DMs only, as an ISO time: when its latest message came, or when it started. */
  public var activeAt: String?
  /** DMs only: who joined the workspace, for a DM started as they joined. */
  public var joined: Joined?

  public init(
    id: RoomID, kind: RoomKind, name: String? = nil, icon: String? = nil, huddles: Bool? = nil, members: [User]? = nil,
    activeAt: String? = nil, joined: Joined? = nil
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.icon = icon
    self.huddles = huddles
    self.members = members
    self.activeAt = activeAt
    self.joined = joined
  }

  public var isDirect: Bool { kind == .direct }
  /** Whether its settings allow huddles in it, as every room's do until someone turns them off. */
  public var allowsHuddles: Bool { huddles != false }

  /** What the sidebar and the buffer title call the room: `#name`, or the other people in a DM. */
  public func title(for me: UserID?) -> String {
    if let name, !isDirect { return name }
    guard let members else { return id }
    let others = members.filter { $0.id != me }
    if others.isEmpty { return members.first?.name ?? id }
    return others.map(\.name).sorted().joined(separator: ", ")
  }
}

/** The welcome card's invitation (`Invitation`): the first room, and the join link's code. */
public struct Invitation: Codable, Hashable, Sendable {
  public var roomId: RoomID
  public var joinCode: String
}

/** A room in someone's sidebar (`SidebarRoom = Room & { unread, unreadSince?, unreadCount?, involvement }`). */
public struct SidebarRoom: Codable, Hashable, Sendable, Identifiable {
  public var room: Room
  public var unread: Bool
  /** While it's marked unread, when the first of the messages since came. */
  public var unreadSince: String?
  /** In a DM, while it's marked unread, how many messages have come since. */
  public var unreadCount: Int?
  public var involvement: Involvement

  public var id: RoomID { room.id }

  public init(room: Room, unread: Bool, unreadSince: String? = nil, unreadCount: Int? = nil, involvement: Involvement) {
    self.room = room
    self.unread = unread
    self.unreadSince = unreadSince
    self.unreadCount = unreadCount
    self.involvement = involvement
  }

  /** Whether the sidebar shows it marked: unread, unless it's hidden (`markedUnread`). */
  public var isMarkedUnread: Bool { unread && involvement != .invisible }

  public init(from decoder: Decoder) throws {
    room = try Room(from: decoder)
    let c = try decoder.container(keyedBy: Keys.self)
    unread = try c.decode(Bool.self, forKey: .unread)
    unreadSince = try c.decodeIfPresent(String.self, forKey: .unreadSince)
    unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount)
    involvement = try c.decode(Involvement.self, forKey: .involvement)
  }

  public func encode(to encoder: Encoder) throws {
    try room.encode(to: encoder)
    var c = encoder.container(keyedBy: Keys.self)
    try c.encode(unread, forKey: .unread)
    try c.encodeIfPresent(unreadSince, forKey: .unreadSince)
    try c.encodeIfPresent(unreadCount, forKey: .unreadCount)
    try c.encode(involvement, forKey: .involvement)
  }

  private enum Keys: String, CodingKey { case unread, unreadSince, unreadCount, involvement }
}

/** The rooms someone has starred, in order (`Favorites`). Of two, the one with the larger version is newer. */
public struct Favorites: Codable, Hashable, Sendable {
  public var rooms: [RoomID]
  public var version: Int

  public init(rooms: [RoomID], version: Int) {
    self.rooms = rooms
    self.version = version
  }
}

/** The people someone has blocked, in order (`Blocks`). Of two, the one with the larger version is newer. */
public struct Blocks: Codable, Hashable, Sendable {
  public var userIds: [UserID]
  public var version: Int

  public init(userIds: [UserID], version: Int) {
    self.userIds = userIds
    self.version = version
  }

  public static let none = Blocks(userIds: [], version: 0)
}

/** What `GET /api/sidebar` answers (`Sidebar`). */
public struct Sidebar: Codable, Sendable {
  public var rooms: [SidebarRoom]
  public var favorites: Favorites
  public var sharedOrder: [RoomID]
  public var invitation: Invitation?
  public var huddles: [RoomID: LiveHuddle]
  public var blocks: Blocks
  /** For an administrator, how many open reports they see. Nobody else is given it. */
  public var openReports: Int?
  /** Which huddle sounds they hear, left out while they hear them all. */
  public var huddleSounds: HuddleSounds?
}

/** A room to create (`NewRoom`): an open room takes in everyone, a closed one only `memberIds`. */
public struct NewRoom: Encodable, Sendable {
  public var name: String
  /** A `RoomIcons` name, or "" for the default `#`. */
  public var icon: String?
  public var kind: RoomKind
  public var memberIds: [UserID]?

  public static func open(name: String, icon: String? = nil) -> NewRoom { NewRoom(name: name, icon: icon, kind: .open, memberIds: nil) }
  public static func closed(name: String, icon: String? = nil, memberIds: [UserID]) -> NewRoom {
    NewRoom(name: name, icon: icon, kind: .closed, memberIds: memberIds)
  }
}

/** Someone active, as a room's settings list them, with whether they're in the room (`RoomPerson`). */
public struct RoomPerson: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  public var member: Bool
}

/** What `GET /api/rooms/new` answers (`NewRoomForm`). */
public struct NewRoomForm: Codable, Sendable {
  public var people: [User]
}

/** What `POST /api/directs` answers (`StartedDirect`), 201 when it's new and 200 when the group had one. */
public struct StartedDirect: Codable, Sendable {
  public var room: Room
}

/** What blocking or unblocking someone answers (`ChangedBlocks`). */
public struct ChangedBlocks: Codable, Sendable {
  public struct Direct: Codable, Hashable, Sendable {
    public var roomId: RoomID
    public var involvement: Involvement
  }

  public var blocks: Blocks
  public var direct: Direct?
}

/** What `GET /api/rooms/<id>/settings` answers (`RoomSettings`). DMs have none. */
public struct RoomSettings: Codable, Sendable {
  public var room: Room
  public var canAdminister: Bool
  public var canChangeHuddles: Bool
  public var people: [RoomPerson]
}

/** What `PATCH /api/rooms/<id>` changes (`RoomChanges`). A closed room names its `memberIds`. */
public struct RoomChanges: Encodable, Sendable {
  public var name: String?
  /** A `RoomIcons` name, or "" for the default `#`. */
  public var icon: String?
  public var huddles: Bool?
  public var kind: RoomKind?
  public var memberIds: [UserID]?

  public init(name: String? = nil, icon: String? = nil, huddles: Bool? = nil, kind: RoomKind? = nil, memberIds: [UserID]? = nil) {
    self.name = name
    self.icon = icon
    self.huddles = huddles
    self.kind = kind
    self.memberIds = memberIds
  }
}

/** The rail's buttons and the appearance modes, whose icons an administrator can choose (`NAVIGATION_SLOTS`). */
public enum NavigationSlot: String, Codable, Sendable, CaseIterable {
  case home, dms, activity, search, admin, light, dark, system

  /** Its icon until an administrator chooses another (`DEFAULT_NAVIGATION_ICONS`). */
  public var defaultIcon: String {
    switch self {
    case .home: "iconoir:regular:home"
    case .dms: "iconoir:regular:multi-bubble"
    case .activity: "iconoir:regular:bell"
    case .search: "iconoir:regular:search"
    case .admin: "iconoir:regular:box"
    case .light: "iconoir:regular:sun-light"
    case .dark: "iconoir:regular:half-moon"
    case .system: "iconoir:regular:computer"
    }
  }
}

/** The workspace, as every page shows it (`Account`). */
public struct Account: Codable, Hashable, Sendable {
  public var name: String
  public var tagline: String
  public var hideTranslationButtons: Bool
  /** CSS for the web app's pages, which native chrome doesn't apply. */
  public var customStyles: String
  public var restrictRoomCreation: Bool
  public var logo: String?
  public var customDomain: String?
  public var joinLink: Bool
  public var openSignUp: Bool
  public var memberfulJoin: Bool
  public var memberfulSignIn: Bool
  public var ssoJoin: Bool
  public var ssoSignIn: Bool
  public var emailDomainSignUp: Bool
  public var emailDomains: [String]
  /** The icons an administrator chose, by `NavigationSlot` raw value. */
  public var navigationIcons: [String: String]
  public var huddles: Bool
  public var huddleCameras: Bool
  public var huddleScreens: Bool

  /** The icon a slot shows: an administrator's choice, or its default. */
  public func icon(for slot: NavigationSlot) -> String { navigationIcons[slot.rawValue] ?? slot.defaultIcon }

  /** Whether only Memberful's members or the SSO provider's sign in, and administrators (`signsInElsewhereOnly`). */
  public var signsInElsewhereOnly: Bool { memberfulSignIn || ssoSignIn }
  /** `joinsWithLink` */
  public var joinsWithLink: Bool { joinLink && !signsInElsewhereOnly }
  /** `signsUpOpenly` */
  public var signsUpOpenly: Bool { openSignUp && !signsInElsewhereOnly }
  /** `signsUpWithEmailDomain` */
  public var signsUpWithEmailDomain: Bool { emailDomainSignUp && !emailDomains.isEmpty && !signsInElsewhereOnly }
}

public enum SetupState: String, Codable, Sendable {
  case pending, complete
}

/** How first run lets someone set Ember up (`SetupAccess`). */
public enum SetupAccess: String, Codable, Sendable {
  case password, link, open, closed
}

/** What the setup page's fields show as examples (`SetupPlaceholders`). */
public struct SetupPlaceholders: Codable, Hashable, Sendable {
  public var name: String
  public var emailAddress: String
}

/** What the Worker read of the caller's user agent (`Platform`). Native clients don't use it. */
public struct Platform: Codable, Hashable, Sendable {
  public var ios: Bool
  public var android: Bool
  public var desktop: Bool
  public var windows: Bool
  public var chrome: Bool
  public var firefox: Bool
  public var safari: Bool
  public var edge: Bool
  public var browser: String
  public var operatingSystem: String
}

/** What `GET /api/bootstrap` answers (`Bootstrap`). */
public struct Bootstrap: Codable, Sendable {
  public var setup: SetupState
  public var setupAccess: SetupAccess
  public var setupPlaceholders: SetupPlaceholders
  public var guestSignIn: Bool
  public var signInWithMemberful: Bool
  /** The SSO provider's name while single sign-on is offered. */
  public var signInWithSso: String?
  public var turnstileSiteKey: String?
  public var passwordResetCodes: Bool
  public var account: Account
  public var version: String
  public var vapidPublicKey: String?
  /** Whether this deployment can push to the ircX apps through APNs, or nil from a server that predates native push. */
  public var apnsPush: Bool?
  public var platform: Platform
  public var user: Me?

  /** The name a sign-in page calls single sign-on by (`workspace.signInWithSso ?? DEFAULT_SSO_NAME`). */
  public var ssoName: String { signInWithSso ?? SSO.defaultName }
}

public struct Boost: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var messageId: String
  public var booster: User
  public var content: String
  public var createdAt: String
}

public struct ThreadSummary: Codable, Hashable, Sendable {
  public var count: Int
  public var latestAt: String
  public var people: [User]
}

/** A link's preview (`LinkPreview`), which `POST /api/unfurl` answers and `message.preview` sends. */
public struct LinkPreview: Codable, Hashable, Sendable {
  public var title: String
  public var url: String
  public var image: String?
  public var description: String

  public init(title: String, url: String, image: String?, description: String) {
    self.title = title
    self.url = url
    self.image = image
    self.description = description
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(title, forKey: .title)
    try c.encode(url, forKey: .url)
    try c.encode(image, forKey: .image)
    try c.encode(description, forKey: .description)
  }

  var json: [String: Any] { ["title": title, "url": url, "image": image.map { $0 as Any } ?? NSNull(), "description": description] }
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
  /** What a bot or an agent showed under its text, which can't be edited. */
  public var cards: [Card]?
  public var parentId: String?
  public var alsoSent: Bool?
  public var parentText: String?
  public var thread: ThreadSummary?
  /** The huddle a room posts a message for, kept current by `message.updated`; not editable. */
  public var huddle: MessageHuddle?
  /** A message deleted while replies in its thread are left, which keeps its place for them. */
  public var deleted: Bool?

  public init(
    id: String, clientMessageId: String, roomId: RoomID, creator: User, body: String, plainText: String, mentions: [User] = [],
    createdAt: String, updatedAt: String, editedAt: String? = nil, boosts: [Boost] = [], attachment: StoredFile? = nil,
    parentId: String? = nil, alsoSent: Bool? = nil, parentText: String? = nil, thread: ThreadSummary? = nil, deleted: Bool? = nil,
    cards: [Card]? = nil, huddle: MessageHuddle? = nil
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
    self.cards = cards
    self.huddle = huddle
  }

  /** Whether the room's timeline shows it: every message but a reply sent only to its thread (`isInRoom`). */
  public var isInRoom: Bool { parentId == nil || alsoSent == true }

  /** Whether it can be edited: not one with cards (`HAS_CARDS`) nor a huddle's (`OF_A_HUDDLE`). */
  public var isEditable: Bool { (cards ?? []).isEmpty && huddle == nil && deleted != true }

  public var createdDate: Date { EmberDate.parse(createdAt) ?? .distantPast }

  /** Whether it was written with /me: its whole body one `<em>` that starts with its author's name. */
  public var isAction: Bool { MessageBody.isAction(body: body, plainText: plainText, author: creator.name) }

  public func mentions(_ userID: UserID) -> Bool { mentions.contains { $0.id == userID } }
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
