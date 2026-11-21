import Foundation

// How a huddle's tiles are laid out (apps/web/src/lib/huddle-tiles.ts), the reactions that rise in it
// (huddle-reactions.ts), the invitations that ring (huddle-invitations.ts) and who's speaking
// (huddle-speaking.ts), as pure values the app's views and its huddle drive.

/** How `count` tiles show largest in a space (`TilesLayout`). */
public struct HuddleTiles: Equatable, Sendable {
  /** How many go in a row. */
  public var columns: Int
  /** How wide each is, in whole points. */
  public var width: Double
  /** Whether each is square, rather than 4 by 3. */
  public var square: Bool

  public var height: Double { square ? width : width * 3 / 4 }
}

/** How a shared screen shows large with the tiles (`StageLayout`). */
public struct HuddleStage: Equatable, Sendable {
  /** Whether the tiles are beside the screen, rather than under it. */
  public var beside: Bool
  /** How wide the screen shows. */
  public var screen: Double
  public var tiles: HuddleTiles
}

public enum HuddleLayout {
  static let narrowest = 132.0
  static let widest = 420.0
  /** `TILE_GAP` */
  public static let gap = 12.0
  static let uprightPhone = 560.0
  /** `SCREEN_CAPTION` */
  public static let screenCaption = 28.0
  /** `SCREEN_SHAPE` */
  public static let screenShape = 16.0 / 9.0
  static let stripShare = 0.22
  static let stripWidest = 220.0
  static let screenShare = 0.6
  static let smallPicture = 180.0

  /** `tilesLayout` */
  public static func tiles(_ count: Int, width: Double, height: Double) -> HuddleTiles {
    let square = width < uprightPhone
    let (columns, tile) = largest(count, width: width, height: height, shape: square ? 1 : 4.0 / 3.0, widest: widest, tied: Int(Double(count).squareRoot().rounded(.up)))
    return HuddleTiles(columns: columns, width: tile, square: square)
  }

  /** `showsCamerasSmall`: tiles no taller than a camera's smaller size. */
  public static func showsCamerasSmall(_ tiles: HuddleTiles) -> Bool { tiles.height <= smallPicture }

  static func largest(_ count: Int, width: Double, height: Double, shape: Double, widest: Double, tied: Int) -> (Int, Double) {
    func across(_ columns: Int) -> Double { (width - gap * Double(columns - 1)) / Double(columns) }
    func down(_ columns: Int) -> Double {
      let rows = Double((count + columns - 1) / columns)
      return ((height - gap * (rows - 1)) / rows) * shape
    }
    var best = (columns: 1, width: 0.0)
    func consider(_ columns: Int) {
      let fits = min(across(columns), down(columns), widest)
      if fits > best.width { best = (columns, fits) }
    }
    for columns in stride(from: tied, through: count, by: 1) where columns >= 1 { consider(columns) }
    for columns in stride(from: tied - 1, through: 1, by: -1) { consider(columns) }
    if best.width >= narrowest { return (best.columns, best.width.rounded(.down)) }
    let fit = max(1, Int(((width + gap) / (narrowest + gap)).rounded(.down)))
    if count <= fit { return (max(1, count), narrowest) }
    return (fit, max(narrowest, across(fit).rounded(.down)))
  }

  /** `stageLayout` */
  public static func stage(_ count: Int, shape: Double, width: Double, height: Double) -> HuddleStage {
    let beside = min(width - stripTile(count, width: width, height: height) - gap, (height - screenCaption) * shape)
    let over = min(width, (height * screenShare - screenCaption) * shape)
    let screen = max(0, max(beside, over).rounded(.down))
    if beside >= over {
      let (columns, tile) = largest(count, width: width - screen - gap, height: height, shape: 4.0 / 3.0, widest: stripWidest, tied: 1)
      return HuddleStage(beside: true, screen: screen, tiles: HuddleTiles(columns: columns, width: tile, square: false))
    }
    return HuddleStage(beside: false, screen: screen, tiles: tiles(count, width: width, height: height - screenCaption - screen / shape - gap))
  }

  static func stripTile(_ count: Int, width: Double, height: Double) -> Double {
    let rows = Double(max(1, count))
    let showsAll = ((height - gap * (rows - 1)) / rows) * (4.0 / 3.0)
    return max(narrowest, min(showsAll, width * stripShare, stripWidest).rounded(.down))
  }
}

// MARK: - Reactions

/** A reaction that rises (`RisingReaction`). */
public struct RisingReaction: Equatable, Sendable, Identifiable {
  public var nth: Int
  public var userId: UserID
  public var emoji: String
  public var id: Int { nth }

  /** `placeOf`: which of five places along the base it rises from. */
  public var place: Int { HuddleReactions.places[(nth - 1) % HuddleReactions.places.count] }
}

/** An emoji that rises, as its pill tells (`ReactionRun`). */
public struct ReactionRun: Equatable, Sendable, Identifiable {
  public var emoji: String
  public var first: UserID
  public var more: Int
  public var id: String { emoji }
}

/**
 * The reactions a huddle shows (`reactionsShown`): each rises for `showsFor` from when the room tells of
 * it; an emoji that rises has a pill. `expire` is called by whoever owns the timers.
 */
public struct HuddleReactions: Equatable, Sendable {
  /** `REACTION_SHOWS_MS` */
  public static let showsFor = 4.0
  /** `MOST_RISING` */
  public static let mostRising = 24
  /** `MOST_PILLS` */
  public static let mostPills = 3
  /** `PLACES` */
  public static let places = [2, 0, 4, 1, 3]

  public private(set) var rising: [RisingReaction] = []
  private var allRuns: [ReactionRun] = []
  private var count = 0

  public init() {}

  /** The emoji that have a pill, the latest to start. */
  public var runs: [ReactionRun] { Array(allRuns.suffix(Self.mostPills)) }

  /** Shows `whose` reaction from now; answers its number, to expire it by. */
  @discardableResult
  public mutating func show(_ whose: UserID, emoji: String) -> Int {
    count += 1
    let reaction = RisingReaction(nth: count, userId: whose, emoji: emoji)
    rising.append(reaction)
    if let index = allRuns.firstIndex(where: { $0.emoji == emoji }) {
      allRuns[index].more += 1
    } else {
      allRuns.append(ReactionRun(emoji: emoji, first: whose, more: 0))
    }
    if rising.count > Self.mostRising { drop(Set(rising.prefix(rising.count - Self.mostRising).map(\.nth))) }
    return reaction.nth
  }

  /** The reaction numbered `nth` has risen. */
  public mutating func expire(_ nth: Int) { drop([nth]) }

  /** Shows nothing more of `whose`, who left: an emoji they were first to send is the next sender's from then. */
  public mutating func forget(_ whose: UserID) {
    let theirs = Set(rising.filter { $0.userId == whose }.map(\.nth))
    guard !theirs.isEmpty || allRuns.contains(where: { $0.first == whose }) else { return }
    drop(theirs)
    allRuns = allRuns.map { run in
      guard run.first == whose, let next = rising.first(where: { $0.emoji == run.emoji }) else { return run }
      var passed = run
      passed.first = next.userId
      return passed
    }
  }

  public mutating func stop() { drop(Set(rising.map(\.nth))) }

  private mutating func drop(_ gone: Set<Int>) {
    rising.removeAll { gone.contains($0.nth) }
    allRuns.removeAll { run in !rising.contains { $0.emoji == run.emoji } }
  }
}

// MARK: - Invitations

/** An invitation into a room's huddle that rings (`HuddleInvitation`). */
public struct HuddleInvitation: Equatable, Sendable, Identifiable {
  public var roomId: RoomID
  public var by: UserID
  public var at: Date
  /** Whether its room has been seen among this person's since it came. */
  public var listed = false
  /** Whether its huddle has been seen going on since it came. */
  public var live = false
  public var id: String { "\(roomId) \(at.timeIntervalSince1970)" }

  public init(roomId: RoomID, by: UserID, at: Date) {
    self.roomId = roomId
    self.by = by
    self.at = at
  }
}

/** What the ringing invitations go by (`HuddlesSeen`). */
public struct HuddlesSeen: Sendable {
  public var on: Bool
  public var me: UserID
  /** This person's rooms, or nil until their list has come. */
  public var roomIds: Set<RoomID>?
  public var live: [RoomID: LiveHuddle]
  /** The room whose huddle the app is in. */
  public var joinedRoomId: RoomID?

  public init(on: Bool, me: UserID, roomIds: Set<RoomID>?, live: [RoomID: LiveHuddle], joinedRoomId: RoomID?) {
    self.on = on
    self.me = me
    self.roomIds = roomIds
    self.live = live
    self.joinedRoomId = joinedRoomId
  }
}

/** lib/huddle-invitations.ts */
public enum HuddleRinging {
  /** `INVITATION_RINGS_MS` */
  public static let ringsFor = 30.0

  /** A later invitation for a room rings in place of the one before. */
  public static func invited(_ invitations: [HuddleInvitation], room: RoomID, by: UserID, at: Date) -> [HuddleInvitation] {
    invitations.filter { $0.roomId != room } + [HuddleInvitation(roomId: room, by: by, at: at)]
  }

  public static func over(_ invitations: [HuddleInvitation], room: RoomID) -> [HuddleInvitation] {
    invitations.filter { $0.roomId != room }
  }

  /** The invitations that ring still, by what's seen, each marked with what it has seen (`stillRinging`). */
  public static func seen(_ invitations: [HuddleInvitation], _ seen: HuddlesSeen) -> [HuddleInvitation] {
    guard seen.on else { return [] }
    return invitations.filter { rings($0, seen) }.map { marked($0, seen) }
  }

  static func isListed(_ room: RoomID, _ seen: HuddlesSeen) -> Bool { seen.roomIds?.contains(room) == true }

  static func rings(_ invitation: HuddleInvitation, _ seen: HuddlesSeen) -> Bool {
    let huddle = seen.live[invitation.roomId]
    if invitation.listed, !isListed(invitation.roomId, seen) { return false }
    if seen.joinedRoomId == invitation.roomId || huddle?.userIds.contains(seen.me) == true { return false }
    return huddle != nil || !invitation.live
  }

  static func marked(_ invitation: HuddleInvitation, _ seen: HuddlesSeen) -> HuddleInvitation {
    var marked = invitation
    marked.listed = invitation.listed || isListed(invitation.roomId, seen)
    marked.live = invitation.live || seen.live[invitation.roomId] != nil
    return marked
  }
}

// MARK: - Speaking

/**
 * Who's speaking, by how loud each voice is (lib/huddle-speaking.ts): loud enough for speech, and for a
 * while after the last loud moment, so the gaps between words don't end it. A muted person never is.
 */
public struct HuddleSpeaking: Sendable {
  /** `SPEAKING_LEVEL` */
  public static let level = 0.01
  /** `MEASURED_EVERY_MS` */
  public static let measuredEvery = 0.1
  /** `QUIET_FOR_MS` */
  public static let quietFor = 0.6

  private var loudAt: [UserID: Date] = [:]

  public init() {}

  /** Takes in each voice's level at `now`, and answers who's speaking. */
  public mutating func hear(_ levels: [UserID: Double], muted: Set<UserID>, now: Date) -> Set<UserID> {
    for (who, level) in levels where level >= Self.level { loudAt[who] = now }
    loudAt = loudAt.filter { levels[$0.key] != nil }
    return Set(loudAt.filter { now.timeIntervalSince($0.value) < Self.quietFor && !muted.contains($0.key) }.map(\.key))
  }
}
