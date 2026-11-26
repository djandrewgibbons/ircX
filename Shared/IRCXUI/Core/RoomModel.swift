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
  public private(set) var loadingNewer = false
  /** What each typer is doing besides typing, as an agent's "is searching this room". */
  public private(set) var doing: [UserID: String] = [:]
  /** Who's typing in the open thread, as @ember and agents do as they answer there, and what they're doing. */
  public private(set) var threadTyping: [UserID: (user: User, until: Date, doing: String?)] = [:]
  /** Set once the room is gone for this person (taken out, or deleted), which stops the socket. */
  public private(set) var ended = false
  /** Whether the room's been away more than 5 s (`OFFLINE_AFTER_MS`): its composers don't send, and what was queued shows as not sent. */
  public private(set) var offline = false
  /** Files on their way to becoming messages, by their messages' clientMessageId (web `PendingUpload`). */
  public private(set) var uploads: [String: UploadState] = [:]
  /** The messages open in their editors, by id (web `useMessageEditors`); closing one lets go of what it held. */
  public var editing: Set<String> = [] {
    didSet { editors = editors.filter { editing.contains($0.key) } }
  }
  /** Something a command asked the room's view to show: a picker, a dialog, a confirmation. */
  public var request: ComposerRequest?
  /** Messages that arrived while the reader was away from the newest (web `arrivals`), for Jump to newest. */
  public private(set) var arrivals = 0
  /** Goes up as Jump to newest or `/end` asks the room's messages to scroll to the newest. */
  public private(set) var toNewest = 0

  @ObservationIgnored private let api: EmberAPI
  @ObservationIgnored private var socket: EmberSocket?
  @ObservationIgnored private var lastTypingSent = Date.distantPast
  @ObservationIgnored private var typingSweep: Task<Void, Never>?
  /** Clicks on cards' buttons waiting for the room to say the bot answered, by clickId. */
  @ObservationIgnored private var clicks: [String: CheckedContinuation<Bool, Never>] = [:]
  @ObservationIgnored weak var instance: InstanceSession?
  /** The message a permalink opens the room at, as its socket next connects. */
  @ObservationIgnored private var around: String?
  /** Frames written while the socket wasn't open, in order, by their messages' clientMessageId, or nil for a jump (web outbox). */
  @ObservationIgnored private var queuedFrames: [(id: String?, frame: ClientFrame)] = []
  /** What each open editor holds, by its message's id, kept while the reader moves around the room (web `useMessageEditors`). */
  @ObservationIgnored private var editors: [String: ComposerModel] = [:]
  @ObservationIgnored private var offlineTimer: Task<Void, Never>?
  /** Left while messages were still going: the socket stays open until they've gone, as the web's outbox does. */
  @ObservationIgnored private var leaving = false
  @ObservationIgnored private var composers: [String: ComposerModel] = [:]
  /** Files waiting their turn to upload, one at a time. */
  @ObservationIgnored private var uploading: Task<Void, Never>?

  /** Whether it's a room's thread shown apart from the room, as beside a huddle: not counted, reads nothing. */
  public let apart: Bool

  init(room: Room, api: EmberAPI, instance: InstanceSession, apart: Bool = false) {
    id = room.id
    self.room = room
    self.api = api
    self.instance = instance
    self.apart = apart
  }

  public var me: UserID? { instance?.me?.id }

  /** Whether a message sent from here, in the room or its thread, wasn't sent. */
  public func isFailed(_ message: Message) -> Bool {
    timeline.isFailed(message.clientMessageId) || thread?.isFailed(message.clientMessageId) == true
  }

  /** Whether `message` collapses: its author is someone this person blocked, and it isn't a huddle's. */
  public func isCollapsed(_ message: Message) -> Bool {
    message.creator.id != me && message.huddle == nil && instance?.isBlocked(message.creator.id) == true
  }
  public var title: String { room.title(for: me) }
  public var isOpen: Bool { socketState == .open }

  public var typingNames: [String] {
    let now = Date()
    return typing.values.filter { $0.until > now && $0.user.id != me }.map(\.user.name).sorted()
  }

  /**
   * Who's typing, as the web's indicator says it: their names as the directory has them, each followed by
   * what it's doing meanwhile where an answerer said ("Ember is using Digg: digg_get_feed"), sorted and
   * comma-separated. Nil while nobody is.
   */
  public var typingText: String? {
    Self.typingText(typing.values.map { ($0.user, $0.until, doing[$0.user.id]) }, me: me, people: instance?.people ?? [:])
  }

  /** Who's typing in the open thread, said as `typingText` says the room's (web thread panel's composer). */
  public var threadTypingText: String? {
    Self.typingText(Array(threadTyping.values), me: me, people: instance?.people ?? [:])
  }

  private static func typingText(_ typists: [(user: User, until: Date, doing: String?)], me: UserID?, people: [UserID: DirectoryUser]) -> String? {
    let now = Date()
    let names = typists.filter { $0.until > now && $0.user.id != me }.map { typist -> String in
      let name = people[typist.user.id]?.name ?? typist.user.name
      guard let doing = typist.doing else { return name }
      return "\(name) \(doing)"
    }
    return names.isEmpty ? nil : names.sorted().joined(separator: ", ")
  }

  /** What the room has to say over its messages, such as why something didn't go, until it's dismissed (web `RoomNotice`). */
  public private(set) var notice: String?
  /** When the first unread message came, as the room was opened, which the "New" line goes above (web `newSince`). */
  public var newSince: String?

  /**
   * The line the "New" line goes over: the first message since `newSince` written by someone else, while
   * the timeline reaches back far enough to know it's the first.
   */
  public var firstNewLineID: String? {
    guard let newSince else { return nil }
    var first: BufferLine?
    for line in timeline.lines {
      guard case let .message(message, _) = line else { continue }
      if message.createdAt >= newSince, message.creator.id != me {
        first = line
        break
      }
    }
    guard let first else { return nil }
    if timeline.hasMore, timeline.lines.first?.id == first.id { return nil }
    return first.id
  }

  public func dismissNotice() { notice = nil }

  /** Says something over the room's messages, as the web's `warn`. */
  public func warn(_ text: String) { notice = text }

  // MARK: - Socket

  func activate() {
    guard !ended else { return }
    leaving = false
    if socket == nil {
      let socket = EmberSocket { [weak self, api, id] in
        guard let self else { return api.socketRequest(RoomSocketParams(visible: false).path(id)) }
        // A permalink's message opens a fresh page around it, rather than what changed since.
        let around = self.around
        let params = RoomSocketParams(
          visible: !self.apart && self.instance?.roomVisible != false, since: around == nil ? self.timeline.seq : nil, around: around, apart: self.apart)
        return api.socketRequest(params.path(id))
      }
      socket.onText = { [weak self] text in self?.receive(text) }
      socket.onState = { [weak self] state in self?.changed(to: state) }
      socket.onOpen = { [weak self] in self?.reopened() }
      socket.onEnded = { [weak self] code in self?.end(code) }
      socket.onDropped = { [weak self] in self?.checkAccess() }
      self.socket = socket
    }
    socket?.connect()
    typingSweep?.cancel()
    typingSweep = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        self?.sweepTyping()
      }
    }
  }

  func deactivate() {
    // Messages still going keep the socket until they've gone or can't (web `Outbox`).
    if hasUnsettled {
      leaving = true
      setVisible(false)
    } else {
      socket?.disconnect()
    }
    typingSweep?.cancel()
    typing = [:]
    threadTyping = [:]
  }

  /** Tells the room whether it shows: shown reads it, and a hidden room's mentions push. */
  func setVisible(_ visible: Bool) {
    socket?.send(ClientFrame.presenceVisible(visible))
  }

  /** Whether messages written here haven't gone or been confirmed yet. */
  private var hasUnsettled: Bool {
    !queuedFrames.isEmpty || !timeline.sending.isEmpty || thread.map { !$0.pending.isEmpty } == true || uploads.values.contains { $0.error == nil }
  }

  /** Closes the socket a room kept open for its outbox, once nothing's left to go. */
  private func settleIfLeaving() {
    guard leaving, !hasUnsettled else { return }
    leaving = false
    socket?.disconnect()
  }

  private func changed(to state: EmberSocket.State) {
    socketState = state
    if state == .open {
      offlineTimer?.cancel()
      offline = false
      return
    }
    guard offlineTimer == nil || offlineTimer?.isCancelled == true else { return }
    offlineTimer = Task { [weak self] in
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled, let self, self.socketState != .open else { return }
      self.goOffline()
    }
  }

  /** After 5 s away, queued messages show as not sent and the composers stop sending (web `offline`). */
  private func goOffline() {
    offline = true
    offlineTimer = nil
    guard !queuedFrames.isEmpty else { return }
    let ids = queuedFrames.compactMap(\.id)
    queuedFrames = []
    timeline.giveUpQueued()
    if var thread {
      for id in ids { thread.fail(id) }
      self.thread = thread
    }
    notice = EmberText.notConnectedNotSent
    settleIfLeaving()
  }

  private func reopened() {
    // What was written while the socket was down goes now, in written order.
    let queued = queuedFrames
    queuedFrames = []
    _ = timeline.takeQueued()
    for (_, frame) in queued { socket?.send(frame) }
    // Messages sent while the socket was down never got their confirmation: ask which the room has.
    // Files still uploading aren't asked about; they become messages as they finish (web `useRoom`).
    check(timeline.sending.filter { !isUploading($0) })
    // The thread asks about its replies once it has opened again (`threadOpened`).
    if let thread { socket?.send(.threadOpen(parentId: thread.parentId)) }
  }

  /** Whether a file is still on its way to becoming the message `clientMessageId`; a failed one isn't. */
  private func isUploading(_ clientMessageId: String) -> Bool {
    guard let upload = uploads[clientMessageId] else { return false }
    return upload.error == nil
  }

  /** Asks the room which of these messages it has (`message.check`), as many at a time as it takes. */
  private func check(_ clientMessageIds: [String]) {
    for start in stride(from: 0, to: clientMessageIds.count, by: EmberLimits.maxCheckedMessages) {
      let chunk = Array(clientMessageIds[start..<min(start + EmberLimits.maxCheckedMessages, clientMessageIds.count)])
      socket?.send(ClientFrame.messageCheck(clientMessageIds: chunk))
    }
  }

  /**
   * As the thread opens again, asks about its replies the room hasn't confirmed (web `useThread`): not
   * those not sent, queued or still uploading, nor those also sent to the room, which the room asks about.
   */
  private func checkReplies() {
    guard let thread else { return }
    let queued = Set(queuedFrames.compactMap(\.id))
    let unconfirmed = thread.pending.keys.filter {
      !thread.isFailed($0) && !queued.contains($0) && !isUploading($0) && timeline.pending[$0] == nil
    }
    check(unconfirmed.sorted())
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

  func end(_ code: CloseCode) {
    switch code {
    case .reconnect:
      Task { await instance?.checkSession() }
    case .notFound, .revoked:
      ended = true
      socket?.disconnect()
      note(code == .notFound ? "You're no longer in this room." : "Your access to this workspace has ended.", kind: .error)
    }
  }

  func receive(_ text: String) {
    let frame: ServerFrame
    do {
      frame = try ServerFrame.decode(text)
    } catch {
      logger.error("A frame from \(self.id, privacy: .public) didn't decode: \(error.localizedDescription, privacy: .public)")
      timeline.note("Ember sent something ircX couldn't read: \(error.localizedDescription)", kind: .error)
      return
    }
    switch frame {
    case .pong, .unknown: return
    case let .typing(user, isTyping, threadId, doing):
      // Typing in a thread shows in the thread, while it's open (web `threadReducer`).
      if let threadId {
        guard threadId == thread?.parentId else { return }
        if isTyping {
          threadTyping[user.id] = (user, Date().addingTimeInterval(5), doing)
        } else {
          threadTyping.removeValue(forKey: user.id)
        }
        return
      }
      if isTyping {
        typing[user.id] = (user, Date().addingTimeInterval(5))
        self.doing[user.id] = doing
      } else {
        typing.removeValue(forKey: user.id)
        self.doing.removeValue(forKey: user.id)
      }
      return
    case .historyAfter:
      loadingNewer = false
    case let .error(error) where error.failed == "history.after":
      loadingNewer = false
    case let .error(error) where error.failed == "history.before":
      loadingOlder = false
    case .history:
      loadingOlder = false
    case let .messageCreated(message, _):
      if message.parentId == nil || message.alsoSent == true { typing.removeValue(forKey: message.creator.id) }
      if message.parentId != nil, message.parentId == thread?.parentId { threadTyping.removeValue(forKey: message.creator.id) }
    case .welcome:
      around = nil
    case let .presenceLeft(userId):
      typing.removeValue(forKey: userId)
      threadTyping.removeValue(forKey: userId)
    default: break
    }
    timeline.printsPresence = UserDefaults.standard.object(forKey: Preferences.showJoinsParts) as? Bool ?? true
    if case let .messageCreated(message, _) = frame, timeline.hasNewer || message.creator.id != me { arrivals += 1 }
    apply(frame)
    settleIfLeaving()
  }

  /** The reader's back at the newest messages: Jump to newest has nothing to show. */
  public func readNewest() { arrivals = 0 }

  /** Applies a frame the room sent: to the timeline, the thread open beside it, and the clicks waiting on answers. */
  func apply(_ frame: ServerFrame) {
    let heard = timeline.events.count
    timeline.apply(frame)
    noticeNew(since: heard)
    if var thread {
      if thread.apply(frame) { self.thread = thread }
    }
    if case let .threadOpened(parentId, _, _, _) = frame, parentId == thread?.parentId { checkReplies() }
    switch frame {
    case let .cardClicked(clickId):
      clicks.removeValue(forKey: clickId)?.resume(returning: true)
    case let .error(error):
      if let clickId = error.clickId { clicks.removeValue(forKey: clickId)?.resume(returning: false) }
      // A thread's errors are its own notice (`ThreadTimeline.notice`); the room's come from its timeline's lines.
    case .welcome, .resumed:
      // The answers to clicks sent before the socket dropped are lost: their buttons work again.
      for click in clicks.values { click.resume(returning: false) }
      clicks = [:]
    default: break
    }
  }

  /** The room's latest error since `count` events, as its notice. */
  private func noticeNew(since count: Int) {
    for case let .event(_, _, text, kind) in timeline.events.dropFirst(count) where kind == .error || kind == .info { notice = text }
  }

  private func sweepTyping() {
    let now = Date()
    if typing.values.contains(where: { $0.until <= now }) {
      typing = typing.filter { $0.value.until > now }
    }
    if threadTyping.values.contains(where: { $0.until <= now }) {
      threadTyping = threadTyping.filter { $0.value.until > now }
    }
  }

  // MARK: - Actions

  /**
   * Sends what the input line holds, as a message or an action, to the room or, with `parentId`, to a
   * thread: IRC Classic's Markdown-style input, made the markup the web editor writes.
   */
  public func send(_ text: String, action: Bool = false, parentId: String? = nil, alsoSend: Bool = false, previews: SentPreviews = SentPreviews()) {
    guard let me = instance?.me else { return }
    // A typed `@Name` or `Name:` mentions only whom the room's @ prompt offered (`/api/autocompletable/users`).
    let people = composer(thread: parentId).mentionable
    if action {
      let body = MessageBody.actionMarkup(for: text, by: me.name, mentioning: people)
      post(body: body, plainText: "\(me.name) \(text)", parentId: parentId, alsoSend: alsoSend, previews: previews)
      return
    }
    send(ComposerDocument(markdown: text, mentioning: people), parentId: parentId, alsoSend: alsoSend, previews: previews)
  }

  /**
   * Sends a written message (web `postMessage`): too long, it doesn't go, and the room says why, so what's
   * written stays; it says whether it went, or is queued to go once the socket opens.
   */
  @discardableResult
  public func send(_ document: ComposerDocument, quoting: String? = nil, parentId: String? = nil, alsoSend: Bool = false, previews: SentPreviews = SentPreviews()) -> Bool {
    var document = document.trimmed()
    guard !document.isBlank || quoting != nil else { return false }
    if let shown = previews.shown {
      // The pasted link's preview goes below the first line that has the link, or at the end (web `useLinkPreviews.pasted`).
      let below = document.lines.firstIndex { $0.text.contains(shown.link) } ?? document.lines.count - 1
      document.lines.insert(ComposerLine(.attachment(html: Previews.attachment(shown.preview), label: shown.preview.title)), at: below + 1)
    }
    var body = document.isBlank ? String() : document.html
    if let quoting { body = quoting + body }
    guard !document.isTooLong, body.utf16.count <= EmberLimits.maxMessageHTMLLength else {
      warn(EmberText.messageTooLong)
      return false
    }
    post(body: body, plainText: document.plainText, parentId: parentId, alsoSend: alsoSend, previews: previews)
    return true
  }

  private func post(body: String, plainText: String, parentId: String?, alsoSend: Bool, previews: SentPreviews) {
    guard let me = instance?.me else { return }
    // A message sent while reading older history lands at the newest, so the timeline goes there first (web `toNewest`).
    if parentId == nil, timeline.hasNewer { jump(to: nil) }
    let clientMessageId = UUID().uuidString.lowercased()
    let now = ISO8601DateFormatter.ember.string(from: Date())
    let pending = Message(
      id: clientMessageId, clientMessageId: clientMessageId, roomId: id, creator: me.user, body: body, plainText: plainText,
      mentions: [], createdAt: now, updatedAt: now, editedAt: nil, boosts: [], attachment: nil, parentId: parentId,
      alsoSent: alsoSend, parentText: nil, thread: nil, deleted: nil)
    if parentId == nil || alsoSend { timeline.send(pending) }
    if parentId != nil, var thread { thread.send(pending); self.thread = thread }
    let frame = ClientFrame.messageCreate(clientMessageId: clientMessageId, body: body, parentId: parentId, alsoSend: alsoSend)
    if !(socket?.send(frame) == true) {
      queuedFrames.append((clientMessageId, frame))
      timeline.queue(clientMessageId)
      if offline { goOffline() }
    }
    socket?.send(.typingStop)
    lastTypingSent = .distantPast
    addLatePreview(to: clientMessageId, text: plainText, previews: previews)
  }

  // MARK: - Composers

  /** The composer of the room, or of a thread, which keeps what's written per person and room. */
  public func composer(thread parentId: String? = nil) -> ComposerModel {
    let slot = parentId.map { "thread:" + $0 } ?? "room"
    if let composer = composers[slot] { return composer }
    let user = instance?.me?.id ?? "nobody"
    let host = instance?.instance.host ?? "ember"
    var key = "composer-draft-\(host)-\(user)-\(id)"
    if let parentId { key += "/threads/\(parentId)" }
    let composer = ComposerModel(key: key, name: nameOf)
    composers[slot] = composer
    return composer
  }

  /** A mention's name as the people directory has it now, for markup read back into a composer. */
  private var nameOf: (UserID) -> String {
    { [weak instance] id in instance?.people[id]?.name ?? Display.missingAttachable }
  }

  /** What the editor open on `message` holds, seeded with its body as it opens; kept until the editor closes. */
  public func editor(for message: Message) -> ComposerModel {
    if let editor = editors[message.id] { return editor }
    let editor = ComposerModel(key: nil, name: nameOf)
    editor.replace(with: editable(message))
    editors[message.id] = editor
    return editor
  }

  /** Sends what a composer holds: its files first, each its own message, then what's written (web `submit`). */
  @discardableResult
  public func submit(_ composer: ComposerModel, parentId: String? = nil, previews: SentPreviews = SentPreviews()) -> Bool {
    guard !offline else { return false }
    let files = composer.takeFiles()
    let alsoSend = composer.alsoSend
    if !files.isEmpty {
      send(files: files, parentId: parentId, alsoSend: alsoSend)
      composer.alsoSend = false
    }
    guard !composer.document.isBlank else { return !files.isEmpty }
    guard send(composer.document, parentId: parentId, alsoSend: alsoSend, previews: previews) else { return false }
    composer.clear()
    composer.alsoSend = false
    return true
  }

  // MARK: - Uploads

  /** Uploads files one at a time, in order, each its own message, its card in the timeline as it goes. */
  public func send(files: [PickedFile], parentId: String? = nil, alsoSend: Bool = false) {
    guard let me = instance?.me else { return }
    var waiting: [(PickedFile, String)] = []
    for file in files {
      let clientMessageId = UUID().uuidString.lowercased()
      let now = ISO8601DateFormatter.ember.string(from: Date())
      let pending = Message(
        id: clientMessageId, clientMessageId: clientMessageId, roomId: id, creator: me.user, body: "", plainText: file.name,
        mentions: [], createdAt: now, updatedAt: now, editedAt: nil, boosts: [], attachment: nil, parentId: parentId,
        alsoSent: alsoSend, parentText: nil, thread: nil, deleted: nil)
      if parentId == nil || alsoSend { timeline.send(pending) }
      if parentId != nil, var thread { thread.send(pending); self.thread = thread }
      uploads[clientMessageId] = UploadState(name: file.name, size: file.size)
      waiting.append((file, clientMessageId))
    }
    let before = uploading
    uploading = Task { [weak self, api, id] in
      await before?.value
      for (file, clientMessageId) in waiting {
        do {
          let message = try await Uploader.upload(file, api: api, room: id, clientMessageId: clientMessageId, parentId: parentId, alsoSend: alsoSend) { percent in
            self?.uploads[clientMessageId]?.percent = percent
          }
          guard let self else { return }
          self.uploads.removeValue(forKey: clientMessageId)
          if message.isInRoom { self.timeline.uploaded(message) }
          if var thread = self.thread, message.parentId == thread.parentId {
            thread.uploaded(message)
            self.thread = thread
          }
        } catch {
          guard let self else { return }
          self.uploads[clientMessageId]?.error = error.localizedDescription
          logger.error("An upload failed: \(error.localizedDescription, privacy: .public)")
          // The file may have gone with its answer lost: ask (web `upload-failed`).
          self.socket?.send(ClientFrame.messageCheck(clientMessageIds: [clientMessageId]))
        }
      }
      self?.settleIfLeaving()
    }
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
    socket?.send(ClientFrame.historyBefore(before: oldest, limit: EmberLimits.historyPageSize))
  }

  /** Pages forward, for a timeline opened around an older message. */
  public func loadNewer() {
    guard timeline.hasNewer, !loadingNewer, let newest = timeline.newestId else { return }
    loadingNewer = true
    socket?.send(ClientFrame.historyAfter(after: newest, limit: EmberLimits.historyPageSize))
  }

  /** Opens the timeline at a message, as a permalink does; nil for the newest. */
  public func jump(to messageId: String?) {
    let frame = ClientFrame.historyAround(messageId: messageId)
    // Written while the socket's down, it goes once it opens, ahead of what's written after it (web outbox).
    if !(socket?.send(frame) == true) { queuedFrames.append((nil, frame)) }
  }

  /** Back to the newest messages (web `jump(null)`): a fresh page of them only where the timeline doesn't hold them. */
  public func jumpToNewest() {
    if timeline.hasNewer { jump(to: nil) }
    readNewest()
    toNewest += 1
  }

  /** Boosts a message (`boost.create`): one of `Reactions.all`, or a word of up to 16 characters; a person adds each once. */
  public func react(_ content: String, to message: Message) {
    let content = content.trimmingCharacters(in: .whitespaces)
    guard !content.isEmpty else { return }
    guard content.count <= EmberLimits.maxBoostLength else { return warn(EmberText.boostTooLong) }
    guard !message.boosts.contains(where: { $0.booster.id == me && $0.content == content }) else { return }
    guard isOpen else { return warn(EmberText.notConnected) }
    socket?.send(.boostCreate(messageId: message.id, content: content))
  }

  /** Takes back your own boost (`boost.delete`). */
  public func unboost(_ boost: Boost) {
    guard boost.booster.id == me else { return }
    guard isOpen else { return warn(EmberText.notConnected) }
    socket?.send(.boostDelete(boostId: boost.id))
  }

  public func delete(_ message: Message) {
    guard isOpen else { return warn(EmberText.notConnected) }
    editing.remove(message.id)
    socket?.send(.messageDelete(messageId: message.id))
  }

  /**
   * Saves an edit (web `messageActionsOf.edit`): blank or unchanged closes the editor; too long, or not
   * connected, says why and keeps it open; otherwise it goes and the editor closes. Says whether it closes.
   */
  @discardableResult
  public func edit(_ message: Message, to document: ComposerDocument) -> Bool {
    let document = document.trimmed()
    let body = document.html
    guard !document.isBlank, body != message.body else {
      editing.remove(message.id)
      return true
    }
    guard !document.isTooLong else {
      warn(EmberText.messageTooLong)
      return false
    }
    guard isOpen else {
      warn(EmberText.notConnected)
      return false
    }
    socket?.send(.messageUpdate(messageId: message.id, body: body))
    editing.remove(message.id)
    return true
  }

  /** As `edit(_:to:)`, from IRC Classic's Markdown-style text. */
  @discardableResult
  public func edit(_ message: Message, to text: String) -> Bool {
    edit(message, to: ComposerDocument(markdown: text, mentioning: mentioned(in: message) + composer(thread: message.parentId).mentionable))
  }

  /** Whom `message` mentions, named as the directory has them now. */
  private func mentioned(in message: Message) -> [User] {
    message.mentions.map { User(id: $0.id, name: instance?.people[$0.id]?.name ?? $0.name) }
  }

  /**
   * IRC Classic's `/edit`: the message's body as the Markdown-style text its input line takes, which
   * saves back to the same markup; nil where it can't be written that way (an underline, a named link, a
   * preview), which only the Suite editor can edit without losing it.
   */
  public func editableLine(_ message: Message) -> String? {
    editable(message).markdown()
  }

  /** A message's body as a document to edit, mentions named as the directory has them now (`editableBody`). */
  public func editable(_ message: Message) -> ComposerDocument {
    do {
      return try ComposerDocument(html: message.body, name: { [instance] id in
        if let person = instance?.people[id] { return person.name }
        if let mentioned = message.mentions.first(where: { $0.id == id }) { return mentioned.name }
        return Display.missingAttachable
      })
    } catch {
      logger.error("A message to edit didn't read: \(error.localizedDescription, privacy: .public)")
      return ComposerDocument(plain: message.plainText)
    }
  }

  /** Your newest message, which Up Arrow in an empty composer edits (web `newestWrittenBy`); not while reading older history. */
  public func newestOwn(inThread: Bool) -> Message? {
    guard let me else { return nil }
    if inThread, let thread { return MessageAction.newest(([thread.parent].compactMap { $0 }) + thread.replies, writtenBy: me) }
    guard !timeline.hasNewer else { return nil }
    return MessageAction.newest(timeline.messages, writtenBy: me)
  }

  /** The nth-newest message (1 the newest), or your nth-newest with `mine`, for IRC Classic's commands. */
  public func message(numbered n: Int?, mine: Bool = false) -> Message? {
    let candidates = timeline.messages.filter { $0.deleted != true && (!mine || $0.creator.id == me) }
    let index = candidates.count - (n ?? 1)
    return candidates.indices.contains(index) ? candidates[index] : nil
  }

  /** A message's absolute permalink, as Copy link writes it (web `permalinkOf`). */
  public func permalink(_ message: Message) -> String {
    guard let origin = instance?.instance.origin else { return Pages.messagePath(id, message.id) }
    if let parentId = message.parentId { return origin + Pages.threadPath(id, parentId, replyId: message.id) }
    return origin + Pages.messagePath(id, message.id)
  }

  /** What Quote writes in the composer for `message` (web `replyQuote`). */
  public func quote(_ message: Message) -> String {
    guard let host = instance?.instance.host else {
      logger.error("A message was quoted after its instance went")
      return String()
    }
    let people = instance?.people ?? [:]
    let nameOf = { (user: UserID) in people[user]?.name ?? message.mentions.first { $0.id == user }?.name ?? Display.missingAttachable }
    let author = people[message.creator.id]?.name ?? message.creator.name
    let nodes: [DisplayNode]
    if message.body.isEmpty, message.cards?.isEmpty == false {
      nodes = Quote.cards(message.plainText)
    } else {
      do {
        nodes = try Display.body(message.body, plainText: message.plainText, host: host)
      } catch {
        logger.error("A message to quote didn't read: \(error.localizedDescription, privacy: .public)")
        nodes = Quote.cards(message.plainText)
      }
    }
    return Quote.markup(nodes, author: author, link: permalink(message), nameOf: nameOf)
  }

  /** Quote: the composer's content replaced with a quote of `message`, to write under (web `Composer.replace`). */
  public func quote(_ message: Message, into composer: ComposerModel) {
    let html = quote(message)
    do {
      composer.replace(with: try ComposerDocument(html: html, name: nameOf))
    } catch {
      logger.error("A quote didn't read: \(error.localizedDescription, privacy: .public)")
    }
    composer.quoting = html
  }

  /** Blocks or unblocks a message's author (web More actions' Block). */
  public func setBlocked(_ blocked: Bool, _ user: UserID) {
    instance?.attempt(blocked ? "Blocking" : "Unblocking") { [instance] in try await instance?.setBlocked(blocked, user) }
  }

  /** Reports a message to the administrators; throws Ember's reason, or that the message is gone (404). */
  public func report(_ message: Message, reason: ReportReason, note: String) async throws {
    do {
      try await api.report(message: message.id, in: id, NewReport(reason: reason, note: note))
    } catch let error as EmberError where error.problem?.status == 404 {
      throw EmberError.refused(404, "That message has been deleted.")
    }
  }

  /** Shows a message a permalink names, and the thread it names open beside it (web `useVisit`). */
  public func show(messageId: String?, threadId: String?) {
    if let messageId {
      if isOpen { jump(to: messageId) } else { around = messageId }
    }
    if let threadId { openThread(threadId) }
  }

  public func openThread(_ parentId: String) {
    threadTyping = [:]
    if let thread, thread.parentId != parentId { socket?.send(.threadClose(parentId: thread.parentId)) }
    var opened = ThreadTimeline(parentId: parentId)
    if let parent = timeline.message(parentId) { _ = opened.apply(.messageUpdated(parent, seq: 0)) }
    thread = opened
    socket?.send(.threadOpen(parentId: parentId))
  }

  public func closeThread() {
    if let thread { socket?.send(.threadClose(parentId: thread.parentId)) }
    thread = nil
    threadTyping = [:]
  }

  public func dismissThreadNotice() {
    thread?.dismissNotice()
  }

  public func loadOlderReplies() {
    guard let thread, thread.hasMore, let oldest = thread.replies.first?.id else { return }
    socket?.send(ClientFrame.threadBefore(parentId: thread.parentId, before: oldest, limit: EmberLimits.historyPageSize))
  }

  /**
   * Gives the composer back the first message the room refused for what it says (a word Blocked words
   * keeps out), for its writer to change, if the composer is empty; it leaves the timeline as it does.
   * Any other, or one the composer can't take, stays as not sent (web `useGivingBack`).
   */
  public func takeBack(composerEmpty: Bool) -> GivenBack? {
    let refused = timeline.rewrites.keys.compactMap { timeline.pending[$0] }.sorted { $0.createdAt < $1.createdAt }
    var given: GivenBack?
    for (index, message) in refused.enumerated() {
      let taken = index == 0 && composerEmpty
      let why = timeline.rewrites[message.clientMessageId]
      if taken, let why { given = GivenBack(text: Self.composerText(of: message), why: why, html: message.isAction ? nil : message.body) }
      timeline.giveBack(message.clientMessageId, taken: taken)
      // The composer says why over what it took back; one it couldn't take says why it isn't sent (web `given-back`).
      if taken, notice == why { notice = nil } else if !taken, notice == nil { notice = why }
    }
    return given
  }

  /** As `takeBack(composerEmpty:)`, for the thread's composer. */
  public func takeBackReply(composerEmpty: Bool) -> GivenBack? {
    guard var thread else { return nil }
    let refused = thread.rewrites.keys.compactMap { thread.pending[$0] }.sorted { $0.createdAt < $1.createdAt }
    var given: GivenBack?
    for (index, message) in refused.enumerated() {
      let taken = index == 0 && composerEmpty
      if taken, let why = thread.rewrites[message.clientMessageId] {
        given = GivenBack(text: Self.composerText(of: message), why: why, alsoSend: message.alsoSent == true, html: message.isAction ? nil : message.body)
      }
      thread.giveBack(message.clientMessageId, taken: taken)
      // A reply also sent to the room is in the room's timeline too.
      timeline.giveBack(message.clientMessageId, taken: taken)
    }
    self.thread = thread
    return given
  }

  /** What the input line held for a message: `/me` and the action, for an action. */
  private static func composerText(of message: Message) -> String {
    message.isAction ? "/me " + MessageBody.actionText(plainText: message.plainText, author: message.creator.name) : message.plainText
  }

  /** Prints lines in the buffer without making them the room's notice, as `/help` does. */
  public func print(_ lines: [String]) {
    for line in lines { timeline.note(line) }
  }

  public func note(_ text: String, kind: BufferLine.EventKind = .info) {
    timeline.note(text, kind: kind)
    if kind == .error || kind == .info { notice = text }
  }

  // MARK: - Cards

  /**
   * Clicks a card's button that acts (web `messageActionsOf.click`): the room reports it to the card's
   * bot, and this answers true once the bot has taken it, false where the room said why it hasn't
   * (which shows as the room's notice) or the answer was lost as the socket dropped.
   */
  public func click(_ action: CardAction, on message: Message) async -> Bool {
    guard isOpen else {
      notice = Self.notConnected
      return false
    }
    let clickId = UUID().uuidString.lowercased()
    return await withCheckedContinuation { continuation in
      clicks[clickId] = continuation
      socket?.send(.cardClick(clickId: clickId, messageId: message.id, actionId: action.id, blockId: action.blockId, value: action.value))
    }
  }

  /** What an action says when the socket isn't open (web `messageActionsOf`). */
  static let notConnected = EmberText.notConnected

  // MARK: - Link previews

  /**
   * After a message goes, its first web address is unfurled and the preview added to it (web
   * `typedLinkPreview`): the room adds it, unmarked as an edit, within `EmberLimits.latePreviewMilliseconds`.
   */
  private func addLatePreview(to clientMessageId: String, text: String, previews: SentPreviews) {
    // Not where the composer added a preview, or one was taken out of what was written (web `useLinkPreviews.sent`).
    guard !previews.added else { return }
    let links = Autolink.linkedUrls(text)
    let pasted = previews.asking.flatMap { links.contains($0.url) ? $0.preview : nil }
    let typed = links.first { ($0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://")) && !previews.asked.contains($0) }
    guard pasted != nil || typed != nil else { return }
    let sent = Date()
    Task { [weak self, api] in
      do {
        var found = await pasted?.value
        if found == nil, let typed { found = try await api.linkPreview(typed) }
        guard let preview = found else { return }
        guard !preview.title.trimmingCharacters(in: .whitespaces).isEmpty, !preview.url.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard Date().timeIntervalSince(sent) * 1000 < Double(EmberLimits.latePreviewMilliseconds) else { return }
        self?.socket?.send(ClientFrame.messagePreview(clientMessageId: clientMessageId, preview: preview))
      } catch let error as EmberError where error.problem?.status == 429 {
        self?.notice = error.localizedDescription
      } catch {
        logger.error("Couldn't preview a link: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}

/** What a command asks a room's view to show, which each theme shows its way. */
public enum ComposerRequest: Equatable {
  case upload
  case snippet(String)
  case report(Message)
  case delete(Message)
  case shortcuts
  /** iOS: the photo library, for photos and videos to attach. */
  case photos
  /** New boost: a word or an emoji of up to 16 characters for the message (IRC Classic's React menu). */
  case boost(Message)
  /** IRC Classic's `/edit` without text: the message's text in the input line to change, the thread's where it was asked there. */
  case editLine(Message, inThread: Bool)
}

/** A message the room refused for what it says, back in the composer (web `giveBack`): its text, why, and whether it went to the room too. */
public struct GivenBack: Equatable, Sendable {
  public var text: String
  public var why: String
  public var alsoSend = false
  /** Its markup, for the Suite editor; nil for an action, which only IRC Classic's line writes. */
  public var html: String?
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
  public static let appearance = "appearance"
}
