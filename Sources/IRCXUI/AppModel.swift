import EmberKit
import Foundation
import Observation
import SwiftUI
#if canImport(AppKit)
import AppKit
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
    }
  }

  public var showingAddInstance = false
  public var showingSwitcher = false

  @ObservationIgnored private let tokens: TokenStore

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
  }

  public var selected: InstanceSession? { sessions.first { $0.id == selectedID } }

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
      return existing
    }
    let session = add(Instance(baseURL: baseURL), select: true)
    save()
    Task { await session.start() }
    return session
  }

  public func remove(_ session: InstanceSession) async {
    await session.signOut()
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
    sessions.flatMap { session in session.rooms.filter { $0.involvement != .invisible }.map { (session, $0) } }
  }

  public func open(_ room: RoomID, in session: InstanceSession) {
    selectedID = session.id
    session.selectedRoomID = room
  }

  @discardableResult
  private func add(_ instance: Instance, select: Bool) -> InstanceSession {
    let session = InstanceSession(instance: instance, tokens: tokens)
    session.onChange = { [weak self] _ in self?.save() }
    sessions.append(session)
    if select { selectedID = session.id }
    return session
  }

  private func save() {
    InstanceList(instances: sessions.map(\.instance)).save()
  }

  /** Keeps the Dock's badge at the number of unread rooms across every instance. */
  private func watchUnread() {
    #if os(macOS)
    withObservationTracking {
      let count = sessions.reduce(0) { $0 + $1.unreadCount }
      NSApplication.shared.dockTile.badgeLabel = count > 0 ? String(count) : nil
    } onChange: {
      Task { @MainActor [weak self] in self?.watchUnread() }
    }
    #endif
  }
}
