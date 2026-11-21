import EmberKit
import Foundation
import Observation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if os(iOS)
import UserNotifications
#endif

/** Every instance the app knows, in the rail's order, and which one is on screen. */
@MainActor
@Observable
public final class AppModel {
  public private(set) var sessions: [InstanceSession] = []
  public var selectedID: UUID? {
    didSet {
      guard oldValue != selectedID else { return }
      for session in sessions { session.setForeground(session.id == selectedID) }
      UserDefaults.standard.set(selectedID?.uuidString, forKey: "ember.selectedInstance")
      if !replaying { selected?.recordAgain() }
    }
  }

  public var showingAddInstance = false
  public var showingSwitcher = false
  /** The keyboard shortcuts dialog (⌘/), over whichever room. */
  public var showingShortcuts = false
  /** The huddle the app is in, on any server, its preview, and the invitations that ring. */
  public let huddles = HuddleCenter()

  /** Every page visited, on any server, which Back and Forward step through (web `useRoute`'s entries). */
  public private(set) var history: [HistoryEntry] = []
  public private(set) var historyIndex = -1
  /** While Back or Forward shows an entry, which adds nothing to history. */
  @ObservationIgnored private var replaying = false

  @ObservationIgnored private let tokens: TokenStore
  @ObservationIgnored private let useWatcher = UseWatcher()
  /** Whether the app's window shows, from its scene's phase. */
  @ObservationIgnored private var visible = true
  /** Whether the scene is active: frontmost on iOS, on screen on the Mac. */
  @ObservationIgnored private var active = true
  /** Whether the app is frontmost, where a room on screen needs no notification. */
  var isActive: Bool { active }

  public init(tokens: TokenStore? = nil) {
    #if canImport(Security)
    self.tokens = tokens ?? KeychainTokenStore()
    #else
    self.tokens = tokens ?? MemoryTokenStore()
    #endif
    for instance in InstanceList.load().instances { add(instance, select: false) }
    let saved = UserDefaults.standard.string(forKey: "ember.selectedInstance").flatMap(UUID.init(uuidString:))
    selectedID = sessions.first { $0.id == saved }?.id ?? sessions.first?.id
    sessions.first { $0.id == selectedID }?.setForeground(true)
    watchUnread()
    huddles.app = self
    huddles.hearRinging()
    useWatcher.onChange = { [weak self] _ in self?.tellPresence() }
    useWatcher.start()
    PushCenter.shared.attach(self)
  }

  /** Follows the scene's phase: what shows is read, and the sockets tell Ember whether the app's in use. */
  public func setScenePhase(_ phase: ScenePhase) {
    // The window shows while it's active: on the Mac, frontmost; a window behind another app's isn't read.
    visible = phase == .active
    active = phase == .active
    if active {
      // Notifications may have been allowed or blocked in System Settings meanwhile: allowed, a server switched on registers.
      Task { await PushCenter.shared.refreshPermission(registering: false) }
      useWatcher.used()
      #if os(iOS)
      useWatcher.watchWindows()
      #endif
    }
    tellPresence()
    #if os(iOS)
    // iOS keeps no sockets in the background: close them, and connect again, with what changed, on coming back.
    switch phase {
    case .background: for session in sessions { session.suspend() }
    case .active: for session in sessions { session.resume() }
    default: break
    }
    #endif
  }

  private func tellPresence() {
    for session in sessions { session.setPresence(visible: visible, inUse: active && useWatcher.inUse) }
  }

  public var selected: InstanceSession? { sessions.first { $0.id == selectedID } }

  // MARK: - Back and Forward

  public var canGoBack: Bool { historyIndex > 0 }
  public var canGoForward: Bool { historyIndex < history.count - 1 }

  /** Adds a page shown to history: one shown already adds nothing, and one after Back drops the pages ahead. */
  private func recorded(_ entry: HistoryEntry) {
    guard !replaying else { return }
    if history.indices.contains(historyIndex), history[historyIndex] == entry { return }
    history = Array(history.prefix(historyIndex + 1)) + [entry]
    historyIndex = history.count - 1
  }

  public func goBack() { leaving { self.step(by: -1) } }
  public func goForward() { leaving { self.step(by: 1) } }

  /** Goes once the server shown lets go of its unsaved changes. */
  private func leaving(_ go: @escaping () -> Void) {
    guard let selected else { return go() }
    selected.leave(go)
  }

  /** Shows the entry `by` steps away, past any whose server or room has gone. */
  private func step(by: Int) {
    var index = historyIndex + by
    while history.indices.contains(index) {
      let entry = history[index]
      if let session = sessions.first(where: { $0.id == entry.instance }), session.phase == .ready {
        replaying = true
        selectedID = session.id
        let shown = session.go(to: entry.destination)
        replaying = false
        if shown {
          historyIndex = index
          return
        }
      }
      index += by
    }
  }

  /** Activity, on the server shown. */
  public func toggleActivity() {
    selected?.toggleActivity()
  }

  /**
   * Moves a server to the custom domain Ember has moved to (the moved notice's Switch): the same server,
   * at its new address, signing in again there if the session doesn't carry over.
   */
  public func move(_ session: InstanceSession, to domain: String) {
    guard let url = Instance.baseURL(from: domain), let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
    var instance = session.instance
    instance.baseURL = url
    session.end()
    let moved = InstanceSession(instance: instance, tokens: tokens)
    wire(moved)
    sessions[index] = moved
    save()
    if selectedID == moved.id { moved.setForeground(true) }
    Task { await moved.start() }
  }

  /** What the window's toolbar names: the selected server, and its open room. */
  public var windowTitle: String {
    guard let session = selected else { return "ircX" }
    guard let room = session.selectedRoom else { return session.name }
    return "\(session.name) · \(room.room.isDirect ? room.title : "#" + room.title)"
  }

  public func start() async {
    await withTaskGroup(of: Void.self) { group in
      for session in sessions { group.addTask { await session.start() } }
    }
  }

  /** Adds an instance by address, or selects it if the app already has it. */
  @discardableResult
  public func addInstance(at baseURL: URL) -> InstanceSession {
    if let existing = sessions.first(where: { $0.instance.origin == Instance(baseURL: baseURL).origin }) {
      selectedID = existing.id
      // Adding a server the app already has, but couldn't reach, tries it again.
      if case .unreachable = existing.phase { Task { await existing.start() } }
      return existing
    }
    let session = add(Instance(baseURL: baseURL), select: true)
    save()
    Task { await session.start() }
    return session
  }

  /**
   * Follows a pasted link to an Ember: the server it's on, added if the app hasn't it, then where it leads,
   * such as a join link, an invitation, a sign-in link or a room.
   */
  public func follow(_ link: EmberLink) {
    addInstance(at: link.baseURL).follow(link.route)
  }

  public func remove(_ session: InstanceSession) async {
    if huddles.call?.session === session { huddles.leave() }
    await session.forgetSession()
    PushCenter.shared.removed(session)
    sessions.removeAll { $0.id == session.id }
    if selectedID == session.id { selectedID = sessions.first?.id }
    save()
  }

  public func move(fromOffsets: IndexSet, toOffset: Int) {
    sessions.move(fromOffsets: fromOffsets, toOffset: toOffset)
    save()
  }

  public func select(index: Int) {
    if sessions.indices.contains(index) { selectedID = sessions[index].id }
  }

  /** Every room of every instance signed in, for the quick switcher. */
  public var allRooms: [(session: InstanceSession, room: SidebarRoom)] {
    sessions.flatMap { session in session.windows.map { (session, $0) } }
  }

  public func open(_ room: RoomID, in session: InstanceSession) {
    selectedID = session.id
    session.open(room: room)
  }

  /**
   * Opens what a notification is about (its `path`) on the server it came from (its `origin`), bringing
   * the app forward; a server still connecting opens it once it's signed in.
   */
  func openNotification(_ data: DevicePushData) {
    guard let session = sessions.first(where: { $0.instance.origin.lowercased() == data.origin }) else {
      logger.error("A notification from \(data.origin, privacy: .public), which the app doesn't have, was opened")
      selected?.notice = "ircX isn't signed in to \(data.origin)"
      return
    }
    selectedID = session.id
    // A room's message opens at the message; a thread reply's path names it already.
    let path = if let roomId = data.roomId, let messageId = data.messageId, data.parentId == nil { Pages.messagePath(roomId, messageId) } else { data.path }
    session.follow(.page(session.instance.origin + path))
    #if os(macOS)
    NSApplication.shared.activate()
    #endif
  }

  /**
   * Opens a link to one of the servers' pages, such as a pasted permalink, or an `ircx://` link, which
   * names the page the same way (`ircx://irc.dxnd.ai/rooms/<id>/@<message>`); false for any other.
   */
  @discardableResult
  public func openLink(_ link: String) -> Bool {
    guard var components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), components.host != nil else { return false }
    if components.scheme?.lowercased() == "ircx" { components.scheme = "https" }
    guard let url = components.url else { return false }
    for session in sessions where session.phase == .ready && Pages.page(ofLink: url.absoluteString, origin: session.instance.origin) != nil {
      selectedID = session.id
      return session.open(link: url)
    }
    // The ways in (join links, invitations, sign-in links, an AI app's request) on a server the app has.
    guard let link = EmberLink.parse(url.absoluteString), sessions.contains(where: { $0.instance.origin == Instance(baseURL: link.baseURL).origin }) else {
      return false
    }
    switch link.route {
    case .instance, .page: return false
    default:
      follow(link)
      return true
    }
  }

  @discardableResult
  private func add(_ instance: Instance, select: Bool) -> InstanceSession {
    let session = InstanceSession(instance: instance, tokens: tokens)
    wire(session)
    sessions.append(session)
    if select { selectedID = session.id }
    return session
  }

  private func wire(_ session: InstanceSession) {
    session.huddleCenter = huddles
    session.onChange = { [weak self] _ in self?.save() }
    session.onSignedIn = { [weak session] in
      if let session { PushCenter.shared.save(session) }
    }
    session.onNavigate = { [weak self, weak session] destination in
      guard let self, let session, session.id == self.selectedID else { return }
      self.recorded(HistoryEntry(instance: session.id, destination: destination))
    }
    session.setPresence(visible: visible, inUse: active && useWatcher.inUse)
  }

  private func save() {
    InstanceList(instances: sessions.map(\.instance)).save()
  }

  /**
   * Keeps the app's badge at the number of conversations marked unread across every server, as each
   * server's Activity counts them (web `useAppBadge`).
   */
  private func watchUnread() {
    withObservationTracking {
      // Set only from lists that have loaded (web `useAppBadge(answered ? …)`).
      let count = sessions.filter(\.sidebarLoaded).reduce(0) { $0 + $1.activityCount }
      #if os(macOS)
      NSApplication.shared.dockTile.badgeLabel = count > 0 ? String(count) : nil
      #else
      Task {
        do {
          try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
          logger.error("Setting the badge failed: \(error.localizedDescription, privacy: .public)")
        }
      }
      #endif
    } onChange: { [weak self] in
      Task { @MainActor in self?.watchUnread() }
    }
  }
}

/** A page visited on a server, which Back and Forward return to. */
public struct HistoryEntry: Equatable, Sendable {
  public var instance: UUID
  public var destination: Destination
}
