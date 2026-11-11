import EmberKit
import Foundation
import Observation

/**
 * One room's buffer: its socket, its timeline, who's here and typing, and the thread open beside it.
 * The socket is connected while the room is on screen; leaving keeps the timeline and its `seq`, so
 * coming back asks only for what changed (`resumed`).
 */
@MainActor
@Observable
public final class RoomModel: Identifiable {
  public let id: RoomID
  public var room: Room
  public private(set) var timeline = Timeline()
  public private(set) var thread: ThreadTimeline?
  public private(set) var typing: [UserID: (user: User, until: Date)] = [:]
  public private(set) var socketState: EmberSocket.State = .idle
  public private(set) var loadingOlder = false
  /** Set once the room is gone for this person (taken out, or deleted), which stops the socket. */
  public private(set) var ended = false

  @ObservationIgnored private let api: EmberAPI
  @ObservationIgnored private var socket: EmberSocket?
  @ObservationIgnored private var lastTypingSent = Date.distantPast
  @ObservationIgnored private var typingSweep: Task<Void, Never>?
  @ObservationIgnored weak var instance: InstanceSession?

  init(room: Room, api: EmberAPI, instance: InstanceSession) {
    id = room.id
    self.room = room
    self.api = api
    self.instance = instance
  }

  public var me: UserID? { instance?.me?.id }
  public var title: String { room.title(for: me) }
  public var isOpen: Bool { socketState == .open }

  public var typingNames: [String] {
    let now = Date()
    return typing.values.filter { $0.until > now && $0.user.id != me }.map(\.user.name).sorted()
  }

  // MARK: - Socket

  func activate() {
    guard !ended else { return }
    if socket == nil {
      let socket = EmberSocket { [weak self] in
        guard let self else { return URLRequest(url: URL(string: "about:blank")!) }
        var query = "?visible=1&protocol=\(roomProtocol)"
        if let seq = self.timeline.seq { query += "&since=\(seq)" }
        return self.api.socketRequest("/api/rooms/\(self.id)/socket\(query)")
      }
      socket.onText = { [weak self] text in self?.receive(text) }
      socket.onState = { [weak self] state in self?.socketState = state }
      socket.onOpen = { [weak self] in self?.reopened() }
      socket.onEnded = { [weak self] code in self?.end(code) }
      socket.onDropped = { [weak self] in self?.checkAccess() }
      self.socket = socket
    }
    socket?.connect()
    socket?.send(.presenceVisible(true))
    typingSweep?.cancel()
    typingSweep = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        self?.sweepTyping()
      }
    }
  }

  func deactivate() {
    socket?.disconnect()
    typingSweep?.cancel()
    typing = [:]
  }

  private func reopened() {
    // Messages sent while the socket was down never got their confirmation: ask which the room has.
    let unconfirmed = Array(timeline.pending.keys.prefix(50))
    if !unconfirmed.isEmpty { socket?.send(.messageCheck(clientMessageIds: unconfirmed)) }
    if let thread { socket?.send(.threadOpen(parentId: thread.parentId)) }
  }

  private func checkAccess() {
    Task {
      // A room that's no longer in the sidebar is gone for this person; a 401 means signed out.
      guard let instance else { return }
      await instance.refreshSidebar()
      if instance.phase == .ready, instance.rooms.contains(where: { $0.id == id }) == false {
        end(.notFound)
      }
    }
  }

  private func end(_ code: CloseCode) {
    switch code {
    case .reconnect:
      Task { await instance?.checkSession() }
    case .notFound, .revoked:
      ended = true
      socket?.disconnect()
      timeline.note(code == .notFound ? "You're no longer in this room." : "Your access to this workspace has ended.", kind: .error)
    }
  }

  private func receive(_ text: String) {
    guard let frame = try? ServerFrame.decode(text) else { return }
    switch frame {
    case .pong, .unknown: return
    case let .typing(user, isTyping, _):
      if isTyping { typing[user.id] = (user, Date().addingTimeInterval(5)) } else { typing.removeValue(forKey: user.id) }
      return
    case let .messageCreated(message, _):
      typing.removeValue(forKey: message.creator.id)
    case let .presenceLeft(userId):
      typing.removeValue(forKey: userId)
    default: break
    }
    timeline.printsPresence = UserDefaults.standard.object(forKey: Preferences.showJoinsParts) as? Bool ?? true
    timeline.apply(frame)
    if var thread {
      if thread.apply(frame) { self.thread = thread }
    }
  }

  private func sweepTyping() {
    let now = Date()
    if typing.values.contains(where: { $0.until <= now }) {
      typing = typing.filter { $0.value.until > now }
    }
  }

  // MARK: - Actions

  /** Sends what the input line holds, as a message or an action, to the room or, with `parentId`, to a thread. */
  public func send(_ text: String, action: Bool = false, parentId: String? = nil, alsoSend: Bool = false) {
    guard let me = instance?.me else { return }
    let people = instance?.mentionable ?? []
    let body = action ? MessageBody.actionMarkup(for: text, by: me.name, mentioning: people) : MessageBody.markup(for: text, mentioning: people)
    let clientMessageId = UUID().uuidString.lowercased()
    let now = ISO8601DateFormatter.ember.string(from: Date())
    let plain = action ? "\(me.name) \(text)" : text
    let pending = Message(
      id: clientMessageId, clientMessageId: clientMessageId, roomId: id, creator: me.user, body: body, plainText: plain,
      mentions: [], createdAt: now, updatedAt: now, editedAt: nil, boosts: [], attachment: nil, parentId: parentId,
      alsoSent: alsoSend, parentText: nil, thread: nil, deleted: nil)
    if parentId == nil || alsoSend { timeline.send(pending) }
    if parentId != nil, var thread { thread.send(pending); self.thread = thread }
    socket?.send(.messageCreate(clientMessageId: clientMessageId, body: body, parentId: parentId, alsoSend: alsoSend))
    socket?.send(.typingStop)
    lastTypingSent = .distantPast
  }

  /** Tells the room this person is typing, at most once a second, as the web app does. */
  public func typed() {
    guard Date().timeIntervalSince(lastTypingSent) > 1 else { return }
    lastTypingSent = Date()
    socket?.send(.typingStart)
  }

  public func loadOlder() {
    guard timeline.hasMore, !loadingOlder, let oldest = timeline.oldestId else { return }
    loadingOlder = true
    socket?.send(.historyBefore(before: oldest, limit: 60))
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      self?.loadingOlder = false
    }
  }

  public func react(_ content: String, to message: Message) {
    if let mine = message.boosts.first(where: { $0.booster.id == me && $0.content == content }) {
      socket?.send(.boostDelete(boostId: mine.id))
    } else {
      socket?.send(.boostCreate(messageId: message.id, content: content))
    }
  }

  public func delete(_ message: Message) {
    socket?.send(.messageDelete(messageId: message.id))
  }

  public func edit(_ message: Message, to text: String) {
    socket?.send(.messageUpdate(messageId: message.id, body: MessageBody.markup(for: text, mentioning: instance?.mentionable ?? [])))
  }

  public func openThread(_ parentId: String) {
    if let thread, thread.parentId != parentId { socket?.send(.threadClose(parentId: thread.parentId)) }
    var opened = ThreadTimeline(parentId: parentId)
    if let parent = timeline.message(parentId) { _ = opened.apply(.messageUpdated(parent, seq: 0)) }
    thread = opened
    socket?.send(.threadOpen(parentId: parentId))
  }

  public func closeThread() {
    if let thread { socket?.send(.threadClose(parentId: thread.parentId)) }
    thread = nil
  }

  public func loadOlderReplies() {
    guard let thread, thread.hasMore, let oldest = thread.replies.first?.id else { return }
    socket?.send(.threadBefore(parentId: thread.parentId, before: oldest, limit: 60))
  }

  public func note(_ text: String, kind: BufferLine.EventKind = .info) {
    timeline.note(text, kind: kind)
  }
}

extension ISO8601DateFormatter {
  nonisolated(unsafe) static let ember: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
}

public enum Preferences {
  public static let showJoinsParts = "showJoinsParts"
  public static let fontSize = "fontSize"
  public static let showSeconds = "showSeconds"
  public static let theme = "theme"
}
