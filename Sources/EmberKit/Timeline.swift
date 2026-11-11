import Foundation

/** A line in a buffer: a message, or something the client says itself, as IRC clients print joins and errors. */
public enum BufferLine: Identifiable, Hashable, Sendable {
  case message(Message, pending: Bool)
  case event(id: String, date: Date, text: String, kind: EventKind)

  public enum EventKind: String, Sendable {
    case join, part, info, error
  }

  public var id: String {
    switch self {
    case let .message(message, _): message.clientMessageId.isEmpty ? message.id : "m:" + message.clientMessageId
    case let .event(id, _, _, _): id
    }
  }

  public var date: Date {
    switch self {
    case let .message(message, _): message.createdDate
    case let .event(_, date, _, _): date
    }
  }
}

/**
 * A room's messages as the app holds them, applying the room's frames in order: the page its welcome
 * brings, changes since, and the messages this client is still sending, which the room confirms by
 * their `clientMessageId`. It's a value, so it's tested without a socket.
 */
public struct Timeline: Sendable, Equatable {
  /** The room's messages in its timeline, oldest first: none sent only to a thread. */
  public private(set) var messages: [Message] = []
  /** Messages sent from here the room hasn't confirmed, by clientMessageId. */
  public private(set) var pending: [String: Message] = [:]
  /** Joins, parts and notices, which only this client sees. */
  public private(set) var events: [BufferLine] = []
  /** The latest change seen, which a socket that connects again names as `since`. */
  public private(set) var seq: Int?
  public private(set) var hasMore = false
  public private(set) var present: [User] = []
  public private(set) var me: User?
  /** Whether joins and parts print a line, as most IRC clients let people turn off. */
  public var printsPresence = true

  public init() {}

  /** Every line in time order: messages, pending ones last, and events between. */
  public var lines: [BufferLine] {
    let confirmed = messages.map { BufferLine.message($0, pending: false) }
    let sending = pending.values.sorted { $0.createdAt < $1.createdAt }.map { BufferLine.message($0, pending: true) }
    guard !events.isEmpty else { return confirmed + sending }
    return (confirmed + events).sorted { $0.date < $1.date } + sending
  }

  public var oldestId: String? { messages.first?.id }

  /** Applies a frame from the room, and says whether it changed what the buffer shows. */
  @discardableResult
  public mutating func apply(_ frame: ServerFrame, now: Date = Date()) -> Bool {
    switch frame {
    case let .welcome(you, present, seq, page):
      me = you
      self.present = present
      self.seq = seq
      messages = page.messages.filter(\.isInRoom)
      hasMore = page.hasMore
      confirm(page.messages)
    case let .resumed(you, changed, deletedIds, present, seq):
      me = you
      self.present = present
      self.seq = seq
      let deleted = Set(deletedIds)
      messages.removeAll { deleted.contains($0.id) }
      for message in changed { upsert(message) }
      confirm(changed)
    case let .messageCreated(message, seq), let .messageUpdated(message, seq):
      self.seq = seq
      upsert(message)
      confirm([message])
    case let .messageDeleted(id, seq):
      self.seq = seq
      messages.removeAll { $0.id == id }
    case let .boostCreated(boost, seq):
      self.seq = seq
      update(boost.messageId) { if !$0.boosts.contains(where: { $0.id == boost.id }) { $0.boosts.append(boost) } }
    case let .boostDeleted(boostId, messageId, seq):
      self.seq = seq
      update(messageId) { $0.boosts.removeAll { $0.id == boostId } }
    case let .presenceJoined(user):
      guard !present.contains(where: { $0.id == user.id }) else { return false }
      present.append(user)
      guard printsPresence else { return true }
      events.append(.event(id: "join:\(user.id):\(now.timeIntervalSince1970)", date: now, text: "\(user.name) has joined", kind: .join))
    case let .presenceLeft(userId):
      guard let user = present.first(where: { $0.id == userId }) else { return false }
      present.removeAll { $0.id == userId }
      guard printsPresence else { return true }
      events.append(.event(id: "part:\(userId):\(now.timeIntervalSince1970)", date: now, text: "\(user.name) has left", kind: .part))
    case let .history(_, older, more):
      let known = Set(messages.map(\.id))
      messages.insert(contentsOf: older.filter { $0.isInRoom && !known.contains($0.id) }, at: 0)
      hasMore = more
    case let .historyAround(page):
      messages = page.messages.filter(\.isInRoom)
      hasMore = page.hasMore
    case let .messageChecked(_, missing):
      // Never received: say so, and let the person send them again.
      for id in missing {
        if let lost = pending.removeValue(forKey: id) {
          note("Not sent: \(lost.plainText)", kind: .error, now: now)
        }
      }
    case let .error(message, clientMessageId, _):
      if let clientMessageId { pending.removeValue(forKey: clientMessageId) }
      note(message, kind: .error, now: now)
    default:
      return false
    }
    return true
  }

  /** Adds a message sent from here, shown until the room confirms it. */
  public mutating func send(_ message: Message) {
    pending[message.clientMessageId] = message
  }

  public mutating func note(_ text: String, kind: BufferLine.EventKind = .info, now: Date = Date()) {
    events.append(.event(id: "note:\(events.count):\(now.timeIntervalSince1970)", date: now, text: text, kind: kind))
  }

  /** A message by id, from the timeline. */
  public func message(_ id: String) -> Message? {
    messages.first { $0.id == id }
  }

  private mutating func upsert(_ message: Message) {
    // A reply sent only to its thread changes its parent's summary, which a `message.updated` of the parent carries.
    guard message.isInRoom else { return }
    if let index = messages.firstIndex(where: { $0.id == message.id }) {
      messages[index] = message
    } else if let last = messages.last, last.createdAt > message.createdAt {
      let index = messages.firstIndex { $0.createdAt > message.createdAt } ?? messages.endIndex
      messages.insert(message, at: index)
    } else {
      messages.append(message)
    }
  }

  private mutating func update(_ id: String, _ change: (inout Message) -> Void) {
    if let index = messages.firstIndex(where: { $0.id == id }) { change(&messages[index]) }
  }

  private mutating func confirm(_ stored: [Message]) {
    for message in stored { pending.removeValue(forKey: message.clientMessageId) }
  }
}

/** A thread as its pane shows it: the parent and its replies, oldest first. */
public struct ThreadTimeline: Sendable, Equatable {
  public let parentId: String
  public private(set) var parent: Message?
  public private(set) var replies: [Message] = []
  public private(set) var hasMore = false
  public private(set) var loaded = false
  public private(set) var pending: [String: Message] = [:]

  public init(parentId: String) {
    self.parentId = parentId
  }

  public var lines: [BufferLine] {
    replies.map { .message($0, pending: false) } + pending.values.sorted { $0.createdAt < $1.createdAt }.map { .message($0, pending: true) }
  }

  public mutating func send(_ message: Message) {
    pending[message.clientMessageId] = message
  }

  @discardableResult
  public mutating func apply(_ frame: ServerFrame) -> Bool {
    switch frame {
    case let .threadOpened(id, parent, messages, more) where id == parentId:
      self.parent = parent
      replies = messages
      hasMore = more
      loaded = true
      for m in messages { pending.removeValue(forKey: m.clientMessageId) }
    case let .threadHistory(id, _, older, more) where id == parentId:
      let known = Set(replies.map(\.id))
      replies.insert(contentsOf: older.filter { !known.contains($0.id) }, at: 0)
      hasMore = more
    case let .messageCreated(message, _), let .messageUpdated(message, _):
      if message.id == parentId {
        parent = message
      } else if message.parentId == parentId {
        pending.removeValue(forKey: message.clientMessageId)
        if let index = replies.firstIndex(where: { $0.id == message.id }) { replies[index] = message } else { replies.append(message) }
      } else {
        return false
      }
    case let .messageDeleted(id, _):
      if id == parentId { parent?.deleted = true }
      replies.removeAll { $0.id == id }
    case let .boostCreated(boost, _):
      if boost.messageId == parentId { parent?.boosts.append(boost) }
      if let index = replies.firstIndex(where: { $0.id == boost.messageId }) { replies[index].boosts.append(boost) }
    case let .boostDeleted(boostId, messageId, _):
      if messageId == parentId { parent?.boosts.removeAll { $0.id == boostId } }
      if let index = replies.firstIndex(where: { $0.id == messageId }) { replies[index].boosts.removeAll { $0.id == boostId } }
    case let .error(_, clientMessageId?, _):
      return pending.removeValue(forKey: clientMessageId) != nil
    default:
      return false
    }
    return true
  }
}
