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
  /** Messages sent from here the room hasn't confirmed, by clientMessageId, failed ones included. */
  public private(set) var pending: [String: Message] = [:]
  /** The pending messages that weren't sent, which show as not sent rather than sending. */
  public private(set) var failed: Set<String> = []
  /**
   * Why the room wouldn't take a failed message for what it says (a word Blocked words keeps out), by
   * clientMessageId, while it waits to go back to the composer for its writer to change.
   */
  public private(set) var rewrites: [String: String] = [:]
  /** Joins, parts and notices, which only this client sees. */
  public private(set) var events: [BufferLine] = []
  /** The latest change seen, which a socket that connects again names as `since`. */
  public private(set) var seq: Int?
  public private(set) var hasMore = false
  /** Whether newer messages than the timeline's are in the room, after opening it around an older one. */
  public private(set) var hasNewer = false
  /** The message the timeline was opened around, for a permalink. */
  public private(set) var around: String?
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
  /** The newest message the timeline holds, which `history.after` pages on from. */
  public var newestId: String? { messages.last?.id }

  /** Applies a frame from the room, and says whether it changed what the buffer shows. */
  @discardableResult
  public mutating func apply(_ frame: ServerFrame, now: Date = Date()) -> Bool {
    switch frame {
    case let .welcome(you, present, seq, page):
      me = you
      self.present = present
      self.seq = seq
      show(page)
      confirm(page.messages)
    case let .resumed(you, changed, deletedIds, present, seq):
      me = you
      self.present = present
      self.seq = seq
      let deleted = Set(deletedIds)
      messages.removeAll { deleted.contains($0.id) }
      for message in changed { upsert(message) }
      confirm(changed)
    case let .messageCreated(message, seq):
      self.seq = seq
      // A timeline that doesn't hold the newest messages shows this one once it pages forward to it.
      if !hasNewer || messages.contains(where: { $0.id == message.id }) { upsert(message) }
      confirm([message])
    case let .messageUpdated(message, seq):
      self.seq = seq
      // As the web's `replace`: an update changes a message the timeline holds.
      update(message.id) { $0 = message }
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
      show(page)
      confirm(page.messages)
    case let .historyAfter(after, newer, more):
      // An answer for a timeline that's since moved, or caught up, changes nothing.
      guard hasNewer, after == newestId else { return false }
      let known = Set(messages.map(\.id))
      messages.append(contentsOf: newer.filter { $0.isInRoom && !known.contains($0.id) })
      hasNewer = more
      confirm(newer)
    case let .messageChecked(stored, missing):
      // Stored before the oldest message of the page the reconnect brought: they're in older history,
      // where scrolling up finds them. Missing ones show as not sent.
      let sent = stored.filter { pending.removeValue(forKey: $0) != nil }.count
      for id in stored { forget(id) }
      for id in missing where pending[id] != nil { failed.insert(id) }
      if sent > 0 { note(sent == 1 ? EmberText.messageSentScrollUp : EmberText.messagesSentScrollUp, now: now) }
    case let .error(error):
      // A thread's errors are the thread's to show, and a link preview's, which the app sent itself, aren't shown.
      guard error.showsInRoom else { return false }
      let notSent = error.notSent
      // An error about messages this timeline isn't sending, as a thread's replies, is the thread's.
      if !notSent.isEmpty, !notSent.contains(where: { pending[$0] != nil }) { return false }
      for id in notSent where pending[id] != nil {
        failed.insert(id)
        if error.rewrite { rewrites[id] = error.message }
      }
      note(error.message, kind: .error, now: now)
    default:
      return false
    }
    return true
  }

  /** Adds a message sent from here, shown until the room confirms it. */
  public mutating func send(_ message: Message) {
    pending[message.clientMessageId] = message
  }

  /** Whether a pending message wasn't sent. */
  public func isFailed(_ clientMessageId: String) -> Bool { failed.contains(clientMessageId) }

  /** The pending messages still sending, not failed ones, which a socket that connects again asks the room about. */
  public var sending: [String] { pending.keys.filter { !failed.contains($0) && !queued.contains($0) } }

  /** Messages written while the socket wasn't open, in written order, which go once it opens (web `queued`). */
  public private(set) var queued: [String] = []

  /** Holds a pending message to send once the socket opens. */
  public mutating func queue(_ clientMessageId: String) {
    if pending[clientMessageId] != nil, !queued.contains(clientMessageId) { queued.append(clientMessageId) }
  }

  /** The queued messages, in written order, to send now the socket's open; they're sending from here. */
  public mutating func takeQueued() -> [Message] {
    defer { queued = [] }
    return queued.compactMap { pending[$0] }
  }

  /**
   * After the room's been away too long (`OFFLINE_AFTER_MS`), the queued messages show as not sent, and
   * the room says so (web `offline`). Says whether any did.
   */
  @discardableResult
  public mutating func giveUpQueued(now: Date = Date()) -> Bool {
    guard !queued.isEmpty else { return false }
    for id in queued { failed.insert(id) }
    queued = []
    note(EmberText.notConnectedNotSent, kind: .error, now: now)
    return true
  }

  /** A pending message that didn't go, such as a failed upload, shown as not sent. */
  public mutating func fail(_ clientMessageId: String) {
    if pending[clientMessageId] != nil { failed.insert(clientMessageId) }
  }

  /** A file's message, as its upload's last part answers it, in place of its card, unless the room's said so first. */
  public mutating func uploaded(_ message: Message) {
    pending.removeValue(forKey: message.clientMessageId)
    forget(message.clientMessageId)
    if !messages.contains(where: { $0.id == message.id }) { upsert(message) }
  }

  /**
   * Gives a message the room refused for what it says back to the composer: taken, it leaves the
   * timeline; not taken (the composer has something else in it), it stays as not sent.
   */
  public mutating func giveBack(_ clientMessageId: String, taken: Bool) {
    rewrites.removeValue(forKey: clientMessageId)
    if taken {
      pending.removeValue(forKey: clientMessageId)
      failed.remove(clientMessageId)
    }
  }

  public mutating func note(_ text: String, kind: BufferLine.EventKind = .info, now: Date = Date()) {
    events.append(.event(id: "note:\(events.count):\(now.timeIntervalSince1970)", date: now, text: text, kind: kind))
  }

  /** A message by id, from the timeline. */
  public func message(_ id: String) -> Message? {
    messages.first { $0.id == id }
  }

  private mutating func show(_ page: TimelinePage) {
    messages = page.messages.filter(\.isInRoom)
    hasMore = page.hasMore
    hasNewer = page.hasNewer
    around = page.around
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
    for message in stored {
      pending.removeValue(forKey: message.clientMessageId)
      forget(message.clientMessageId)
    }
  }

  private mutating func forget(_ clientMessageId: String) {
    failed.remove(clientMessageId)
    rewrites.removeValue(forKey: clientMessageId)
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
  /** Replies that weren't sent, which show as not sent. */
  public private(set) var failed: Set<String> = []
  /** Why the thread wouldn't take a failed reply for what it says, by clientMessageId, until it's given back. */
  public private(set) var rewrites: [String: String] = [:]
  /** What the thread has to say over its replies, as why a reply didn't go, until it's dismissed (web thread `RoomNotice`). */
  public private(set) var notice: String?
  /** The thread's own `-!-` lines, for its errors. */
  public private(set) var events: [BufferLine] = []

  public init(parentId: String) {
    self.parentId = parentId
  }

  public var lines: [BufferLine] {
    let confirmed = replies.map { BufferLine.message($0, pending: false) }
    let sending = pending.values.sorted { $0.createdAt < $1.createdAt }.map { BufferLine.message($0, pending: true) }
    guard !events.isEmpty else { return confirmed + sending }
    return (confirmed + events).sorted { $0.date < $1.date } + sending
  }

  public mutating func dismissNotice() { notice = nil }

  public mutating func send(_ message: Message) {
    pending[message.clientMessageId] = message
  }

  /** A reply that didn't go, such as a failed upload, shown as not sent. */
  public mutating func fail(_ clientMessageId: String) {
    if pending[clientMessageId] != nil { failed.insert(clientMessageId) }
  }

  /** A file's reply, as its upload's last part answers it. */
  public mutating func uploaded(_ message: Message) {
    pending.removeValue(forKey: message.clientMessageId)
    failed.remove(message.clientMessageId)
    guard message.parentId == parentId, !replies.contains(where: { $0.id == message.id }) else { return }
    replies.append(message)
  }

  public func isFailed(_ clientMessageId: String) -> Bool { failed.contains(clientMessageId) }

  /**
   * As `Timeline.giveBack`; the notice that said why goes with a reply the composer took, and one it
   * couldn't take says why it isn't sent (web `given-back`).
   */
  public mutating func giveBack(_ clientMessageId: String, taken: Bool) {
    let why = rewrites.removeValue(forKey: clientMessageId)
    if taken {
      pending.removeValue(forKey: clientMessageId)
      failed.remove(clientMessageId)
      if notice == why { notice = nil }
    } else if notice == nil {
      notice = why
    }
  }

  private mutating func note(_ text: String, now: Date) {
    notice = text
    events.append(.event(id: "thread-note:\(events.count):\(now.timeIntervalSince1970)", date: now, text: text, kind: .error))
  }

  @discardableResult
  public mutating func apply(_ frame: ServerFrame, now: Date = Date()) -> Bool {
    switch frame {
    case let .threadOpened(id, parent, messages, more) where id == parentId:
      self.parent = parent
      replies = messages
      hasMore = more
      loaded = true
      for m in messages { pending.removeValue(forKey: m.clientMessageId); failed.remove(m.clientMessageId) }
    case let .threadHistory(id, _, older, more) where id == parentId:
      let known = Set(replies.map(\.id))
      replies.insert(contentsOf: older.filter { !known.contains($0.id) }, at: 0)
      hasMore = more
    case let .messageCreated(message, _), let .messageUpdated(message, _):
      if message.id == parentId {
        parent = message
      } else if message.parentId == parentId {
        pending.removeValue(forKey: message.clientMessageId)
        failed.remove(message.clientMessageId)
        if let index = replies.firstIndex(where: { $0.id == message.id }) { replies[index] = message } else { replies.append(message) }
      } else {
        return false
      }
    case let .messageChecked(stored, missing):
      // The thread's own replies a reconnect asked about: stored ones are confirmed, missing ones weren't sent.
      guard stored.contains(where: { pending[$0] != nil }) || missing.contains(where: { pending[$0] != nil }) else { return false }
      for id in stored where pending[id] != nil {
        pending.removeValue(forKey: id)
        failed.remove(id)
      }
      for id in missing where pending[id] != nil { failed.insert(id) }
    case let .messageDeleted(id, _):
      if id == parentId { parent?.deleted = true }
      replies.removeAll { $0.id == id }
    case let .boostCreated(boost, _):
      if boost.messageId == parentId { parent?.boosts.append(boost) }
      if let index = replies.firstIndex(where: { $0.id == boost.messageId }) { replies[index].boosts.append(boost) }
    case let .boostDeleted(boostId, messageId, _):
      if messageId == parentId { parent?.boosts.removeAll { $0.id == boostId } }
      if let index = replies.firstIndex(where: { $0.id == messageId }) { replies[index].boosts.removeAll { $0.id == boostId } }
    case let .error(error):
      // The thread's own: it couldn't open, a page of replies failed, or a reply didn't go (web `threadReducer`).
      if error.failed == "thread.open" || error.failed == "thread.before" {
        note(error.message, now: now)
        return true
      }
      let notSent = error.notSent.filter { pending[$0] != nil }
      for id in notSent {
        failed.insert(id)
        if error.rewrite { rewrites[id] = error.message }
      }
      guard !notSent.isEmpty else { return false }
      note(error.message, now: now)
    default:
      return false
    }
    return true
  }
}
