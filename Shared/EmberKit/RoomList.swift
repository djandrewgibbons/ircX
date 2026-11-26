import Foundation

// apps/web/src/lib/room-list.ts, directs.ts, involvement.ts and people.ts: how the sidebar orders and
// names rooms and people. Pure functions, so both themes list them alike and tests can check them.

public enum RoomList {
  /**
   * `rooms`, given in the order someone was put in them, in the sidebar's order (`inSidebarOrder`): the
   * starred first, in `favorites`' order, then the ones `sharedOrder` ranks, then the rest as given.
   */
  public static func inSidebarOrder<T>(_ rooms: [T], favorites: [RoomID], sharedOrder: [RoomID], id: (T) -> RoomID) -> [T] {
    let stars = Dictionary(favorites.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    let shared = Dictionary(sharedOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    return rooms.enumerated()
      .map { (room: $1, star: stars[id($1)] ?? Int.max, shared: shared[id($1)] ?? Int.max, given: $0) }
      .sorted { a, b in
        if a.star != b.star { return a.star < b.star }
        if a.shared != b.shared { return a.shared < b.shared }
        return a.given < b.given
      }
      .map(\.room)
  }

  /** DMs latest active first, and of two active at once, the one made (given) later (`inDirectOrder`). */
  public static func inDirectOrder<T>(_ directs: [T], activeAt: (T) -> String) -> [T] {
    directs.enumerated()
      .sorted { a, b in
        let x = activeAt(a.element), y = activeAt(b.element)
        return x != y ? x > y : a.offset > b.offset
      }
      .map(\.element)
  }

  /** A DM started as `me` joined, with someone already here, that nobody has written in yet (`isQuietWelcome`). */
  public static func isQuietWelcome(_ room: Room, me: UserID?) -> Bool {
    guard room.isDirect, let joined = room.joined, let me, joined.userId == me else { return false }
    return room.activeAt == joined.at
  }

  /** `order` with `roomId` moved to just before `beforeId`, or last when that's nil (`movedBefore`). */
  public static func movedBefore(_ order: [RoomID], _ roomId: RoomID, _ beforeId: RoomID?) -> [RoomID] {
    var others = order.filter { $0 != roomId }
    guard let beforeId, let place = others.firstIndex(of: beforeId) else { return others + [roomId] }
    others.insert(roomId, at: place)
    return others
  }

  /** `order` with `roomId` one place up (`by` -1) or down (1) among `order`, unchanged at either end. */
  public static func moved(_ order: [RoomID], _ roomId: RoomID, by: Int) -> [RoomID] {
    guard let from = order.firstIndex(of: roomId) else { return order }
    let to = from + by
    guard order.indices.contains(to) else { return order }
    var moved = order
    moved.swapAt(from, to)
    return moved
  }

  /** Names in a sentence, as Rails' `to_sentence` joins them: "Ada", "Ada and Grace", "Ada, Grace, and Alan". */
  public static func toSentence(_ names: [String]) -> String {
    guard names.count > 2, let last = names.last else { return names.joined(separator: " and ") }
    return names.dropLast().joined(separator: ", ") + ", and " + last
  }

  /** Who a DM shows `me`: the others in it, or just them in their DM with themselves (`membersShown`). */
  public static func membersShown(_ room: Room, me: UserID?) -> [User] {
    let members = room.members ?? []
    let others = members.filter { $0.id != me }
    return others.isEmpty ? members : others
  }
}

/** Ember's people rules (`lib/people.ts`, `lib/agents.ts`, `lib/directs.ts`). */
public enum PeopleList {
  /** How many people New direct message lists at a time (`PEOPLE_PAGE`). */
  public static let page = 20

  /** `text` in lower case as SQLite's LOWER() has it: A to Z, nothing else (`foldedCase`). */
  public static func folded(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.map { ("A"..."Z").contains($0) ? Unicode.Scalar($0.value + 32)! : $0 }))
  }

  /** What New direct message looks for in what's typed: the name without any @s before it (`soughtName`). */
  public static func soughtName(_ typed: String) -> String {
    var name = Substring(typed.trimmingCharacters(in: .whitespaces))
    while name.first == "@" { name = name.dropFirst() }
    return name.trimmingCharacters(in: .whitespaces)
  }

  /** Whether `person` is an AI agent (`isAgent`): marked so, or @ember. */
  public static func isAgent(_ person: DirectoryUser) -> Bool { person.agent == true || person.id == assistantId }

  /** @ember's id (`ASSISTANT_ID`). */
  public static let assistantId = "ember"

  /** Whether `me` can ask `person` (`canAsk`): administrators anyone, others anyone but admins-only agents. */
  public static func canAsk(_ person: DirectoryUser, me: Me) -> Bool { me.administrator || person.adminsOnly != true }

  /** The agents `me` can ask (`agentsToAsk`): active agents, admins-only ones for administrators. */
  public static func agentsToAsk(_ people: some Sequence<DirectoryUser>, me: Me) -> [DirectoryUser] {
    byName(people.filter { isAgent($0) && $0.status == .active && canAsk($0, me: me) })
  }

  /** People by name as SQLite compares `LOWER(name)`, then by id (`byName`). */
  public static func byName(_ people: some Sequence<DirectoryUser>) -> [DirectoryUser] {
    people.map { (person: $0, key: folded($0.name)) }
      .sorted { $0.key != $1.key ? $0.key < $1.key : $0.person.id < $1.person.id }
      .map(\.person)
  }

  /**
   * The people New direct message lists `me` for `name` (`peopleMatching`): everyone active but them,
   * bots included, whose name has `name` in it or whose username starts with it, by name.
   */
  public static func matching(_ people: some Sequence<DirectoryUser>, me: Me, name: String) -> [DirectoryUser] {
    let sought = folded(name)
    return byName(people.filter { person in
      person.status == .active && person.id != me.id && canAsk(person, me: me)
        && (sought.isEmpty || folded(person.name).contains(sought) || person.username?.hasPrefix(sought) == true)
    })
  }

  /**
   * What New direct message says when Ember started the DM without some of the people picked
   * (`startedWithout`): admins-only agents an administrator picked together with someone who isn't one.
   */
  public static func startedWithout(_ names: [String]) -> String {
    let one = names.count == 1
    return "\(RoomList.toSentence(names)) \(one ? "is" : "are") only for DMs between administrators, so this DM is without \(one ? "it" : "them")."
  }
}

extension Involvement {
  /** What each level's button says it does (`INVOLVEMENT_LABELS`). */
  public var sentence: String {
    switch self {
    case .mentions: "Notifying about @ mentions"
    case .everything: "Notifying about all messages"
    case .nothing: "Notifications are off"
    case .invisible: "Notifications are off and room invisible in sidebar"
    }
  }

  /** The levels a room offers: all four in a shared room, all messages and off in a DM. */
  public static func levels(in room: Room) -> [Involvement] { room.isDirect ? [.everything, .nothing] : [.mentions, .everything, .nothing, .invisible] }

  /**
   * The levels a menu offers for a room whose level is `current`: the room's levels, and `current` too
   * when it isn't one of them (a DM hidden by blocking its person is `invisible`), so it shows as chosen.
   */
  public static func choices(in room: Room, current: Involvement) -> [Involvement] {
    let levels = levels(in: room)
    return levels.contains(current) ? levels : levels + [current]
  }

  /** The level after this one as the bell goes round them (`nextInvolvement`). */
  public func next(in room: Room) -> Involvement {
    let levels = Involvement.levels(in: room)
    return levels[((levels.firstIndex(of: self) ?? -1) + 1) % levels.count]
  }
}

extension Room {
  /** A room's name as `me` reads it (`roomName`): a shared room's own, a DM's others' names in a sentence. */
  public func name(for me: UserID?, nameOf: (User) -> String) -> String {
    guard isDirect else { return name ?? id }
    return RoomList.toSentence(RoomList.membersShown(self, me: me).map(nameOf))
  }
}

/** Ember's own words for navigation, as the web shows them. */
public enum NavigationText {
  public static let roomNotFound = "Room not found or inaccessible"
  public static let favoriteFailed = "Couldn't save your favorite. Please try again."
  public static let involvementFailed = "Couldn't update notifications. Try again."
  public static let savingOrder = "Saving room order…"
  public static let starOrderSaved = "Starred room order saved."
  public static let orderFailed = "Couldn't save room order. Please try again."
  public static let sharedOrderUnsaved = "Unsaved room order. Save to apply it to everyone."
  public static let sharedOrderSaved = "Room order saved for everyone."
  public static let sharedOrderLeaving = "You've changed the room order. Save it before you leave, or discard it to keep things as they were."
  public static let noRoomsToArrange = "No rooms to arrange yet."
  public static let adminsManageOrder = "Community admins manage room order and permissions."
  public static let caughtUp = "You're all caught up. No unread conversations."
  public static let noConversations = "No conversations found."
  public static let noRoomsYet = "No rooms yet"
  public static let leaveRoomConfirm = "Are you sure you want to leave this room? Only someone in it who can change it can add you back."
  public static let deleteRoomConfirm = "Are you sure you want to delete this room and all messages in it? This can't be undone."
  public static let deletePingConfirm = "Are you sure you want to delete this ping and all messages in it? This can't be undone."
  public static let banConfirm = "Are you sure you want to ban this user? This will log them out, delete their messages, and block their IP addresses."
  public static let unbanConfirm = "Are you sure you want to remove the ban on this user?"
  public static let removePersonConfirm = "Are you sure you want to permanently remove this person from the account? This can't be undone."
  public static let clearSearchesConfirm = "Are you sure you want to clear your recent searches?"
  public static let welcomeTitle = "Welcome to Ember"
  public static let welcomeText = "To invite people to chat, share the join link below."
  public static let joinShareText = "Hit this link to join me in Ember and start chatting."
  public static let updated = "Ember has been updated."
  public static let newDirectHint = "Find people by full name. You can also type @name."
  public static let couldNotReach = "Couldn't reach Ember. Check your connection and try again."
  public static let signInLinkHint = "Share to get them back into their account"
  public static let newRoomHint = "Create a place for a team, topic, or project."
  public static let canStartHuddles = "Members can start and join huddles in this room."
  public static let cannotStartHuddles = "Members can't start or join huddles in this room."
  public static let savingEndsHuddle = "Saving ends the huddle that's going on."
  public static let starHint =
    "Hold a starred room to drag it, or press Alt and the up or down arrow to reorder your favorites. Other rooms follow the workspace order."
  public static let searchHint = "Search for words, or narrow a search with in:, from:, has:link, has:file, is:thread or with:me."

  public static func moved(to domain: String) -> String { "Ember has moved to \(domain)." }
  public static func noLongerHere(_ name: String) -> String { "\(name) is no longer on this account" }
  public static func lapsed(_ name: String) -> String { "\(name)'s Memberful membership has lapsed, so they can't sign in until it's renewed." }
  public static func onlyAdministratorsAsk(_ name: String) -> String { "Only administrators can ask \(name)." }

  public static let roomMoveCanceled = "Room move canceled."
  public static func moving(_ name: String) -> String { "Moving \(name). Release to save, or press Escape to cancel." }
  public static let couldNotLoadPeople = "Couldn't load people. Please try again."
  public static let huddles = "Huddles"
  public static let happeningNow = "Happening now"
  public static let recentHuddles = "Recent huddles"
  public static let noHuddlesYet = "No huddles yet. A huddle shows here once it\u{2019}s over, if someone else joined it or its thread has a reply."
  public static func huddlesHappening(_ count: Int) -> String { "Huddles, \(count) happening now" }
  public static let availableAgents = "Available Agents"
  public static func agentsToAsk(_ count: Int) -> String { "Available Agents, \(count) to ask" }
  public static let howToAsk = "Type @ and an agent's name in a room it's in, or message it directly."
  public static let noAgents = "There are no agents to ask right now."
  public static let everyRoom = "Every room"
  public static let directsOnly = "Direct messages only"
  public static func directOnly(_ access: AgentAccess) -> String {
    access == .adminDms ? "Message it directly. It isn't in any room, and only administrators can see it." : "Message it directly. It isn't in any of your rooms."
  }
  public static func keptFor(_ access: AgentAccess) -> String? {
    switch access {
    case .everyone: nil
    case .admins: "Admins only"
    case .adminDms: "Admin DMs only"
    }
  }
  public static func openReports(_ open: Int) -> String { "\(open) open \(open == 1 ? "report" : "reports")" }
  public static func releaseAvailable(_ release: String) -> String { "Ember \(release) is available" }
  public static func joined(_ workspace: String) -> String { "joined \(workspace)" }

  /** `countLabel`: "1 result", "12 results", "100+ results" while there are more. */
  public static func resultCount(_ count: Int, more: Bool) -> String {
    more ? "\(count)+ results" : count == 1 ? "1 result" : "\(count) results"
  }
}

/** apps/web/src/lib/huddle-list.ts */
public enum HuddleList {
  /**
   * The huddles going on in someone's rooms and DMs (`huddlesGoingOn`), as the Huddles page lists them and
   * the sidebar's Huddles row counts them: the latest started first, ties in the rooms' order, hidden rooms left out.
   */
  public static func goingOn(_ rooms: [SidebarRoom], live: [RoomID: LiveHuddle]) -> [(room: SidebarRoom, huddle: LiveHuddle)] {
    rooms.enumerated()
      .compactMap { index, room -> (Int, SidebarRoom, LiveHuddle)? in
        guard let huddle = live[room.id], room.involvement != .invisible else { return nil }
        return (index, room, huddle)
      }
      .sorted { a, b in a.2.startedAt != b.2.startedAt ? a.2.startedAt > b.2.startedAt : a.0 < b.0 }
      .map { (room: $0.1, huddle: $0.2) }
  }
}

extension ReleaseCheck {
  /** The release to update to (`updateOf`): a newer release, or for a beta the newer beta, or nil. */
  public var update: Release? {
    if let newest, newest.newer { return newest }
    if beta, let newestBeta, newestBeta.newer { return newestBeta }
    return nil
  }
}
