import EmberKit
import Foundation
import Observation

/**
 * One Ember instance the app is signed in to, as Slack holds a workspace: its session, its workspace
 * socket, which keeps the sidebar's rooms, unread marks and people current, and a buffer per room.
 */
@MainActor
@Observable
public final class InstanceSession: Identifiable {
  public enum Phase: Equatable {
    case checking
    case signedOut
    case ready
    case unreachable(String)
  }

  public private(set) var instance: Instance
  public private(set) var phase: Phase = .checking
  public private(set) var bootstrap: Bootstrap?
  public private(set) var me: Me?
  public private(set) var account: Account?
  public private(set) var rooms: [SidebarRoom] = []
  public private(set) var favorites: [RoomID] = []
  public private(set) var sharedOrder: [RoomID] = []
  public private(set) var people: [UserID: DirectoryUser] = [:]
  public private(set) var socketState: EmberSocket.State = .idle
  public var selectedRoomID: RoomID? {
    didSet { if oldValue != selectedRoomID { switchBuffer(from: oldValue) } }
  }

  @ObservationIgnored public let api: EmberAPI
  @ObservationIgnored private var buffers: [RoomID: RoomModel] = [:]
  @ObservationIgnored private var socket: EmberSocket?
  @ObservationIgnored var onChange: ((Instance) -> Void)?
  /** Whether this instance is the one on screen, whose open room has its socket connected. */
  @ObservationIgnored var isForeground = false

  /** The instance's id, which never changes, kept apart from `instance` so `Identifiable` needs no main actor. */
  public nonisolated let id: UUID

  init(instance: Instance, tokens: TokenStore) {
    id = instance.id
    self.instance = instance
    api = EmberAPI(instance: instance, tokens: tokens)
  }

  public var name: String { account?.name ?? instance.name }
  public var hasUnread: Bool { rooms.contains { $0.unread && $0.involvement != .nothing && $0.involvement != .invisible } }
  public var unreadCount: Int { rooms.filter { $0.unread && $0.involvement != .invisible && $0.involvement != .nothing }.count }

  /** Everyone a message can mention: the people directory's active people. */
  public var mentionable: [User] {
    people.values.filter { $0.status == .active }.map { User(id: $0.id, name: $0.name) }
  }

  public var selectedRoom: RoomModel? { selectedRoomID.flatMap(buffer) }

  // MARK: - Sidebar sections, as Slack lists them

  private var visibleRooms: [SidebarRoom] { rooms.filter { $0.involvement != .invisible } }

  public var starred: [SidebarRoom] {
    favorites.compactMap { id in visibleRooms.first { $0.id == id } }
  }

  public var channels: [SidebarRoom] {
    let shared = visibleRooms.filter { !$0.room.isDirect && !favorites.contains($0.id) }
    let ranked = sharedOrder.compactMap { id in shared.first { $0.id == id } }
    let rest = shared.filter { !sharedOrder.contains($0.id) }.sorted { ($0.room.name ?? "").localizedCaseInsensitiveCompare($1.room.name ?? "") == .orderedAscending }
    return ranked + rest
  }

  public var directs: [SidebarRoom] {
    visibleRooms.filter { $0.room.isDirect && !favorites.contains($0.id) }.sorted { ($0.room.activeAt ?? "") > ($1.room.activeAt ?? "") }
  }

  public func title(of room: Room) -> String { room.title(for: me?.id) }

  // MARK: - Session

  public func start() async {
    phase = .checking
    do {
      let bootstrap = try await api.bootstrap()
      self.bootstrap = bootstrap
      account = bootstrap.account
      rename(bootstrap.account.name, nick: bootstrap.user?.name)
      guard bootstrap.setup == .complete else {
        phase = .unreachable("\(instance.host) isn't set up yet. Set it up in a browser first.")
        return
      }
      if let user = bootstrap.user, api.isSignedIn {
        me = user
        await signedIn()
      } else {
        api.tokens.setToken(nil, for: instance.id)
        phase = .signedOut
      }
    } catch EmberError.signedOut {
      phase = .signedOut
    } catch {
      phase = .unreachable(error.localizedDescription)
    }
  }

  public func signIn(emailAddress: String, password: String) async throws {
    me = try await api.signIn(emailAddress: emailAddress, password: password)
    await signedIn()
  }

  public func signIn(name: String) async throws {
    me = try await api.signIn(name: name)
    await signedIn()
  }

  public func signIn(transferLink: String) async throws {
    me = try await api.signIn(transferLink: transferLink)
    await signedIn()
  }

  public func signOut() async {
    tearDown()
    await api.signOut()
    me = nil
    rooms = []
    phase = .signedOut
  }

  /** Asks Ember whether this session still signs in, after a socket said to check. */
  func checkSession() async {
    guard let bootstrap = try? await api.bootstrap() else { return }
    if bootstrap.user == nil {
      tearDown()
      api.tokens.setToken(nil, for: instance.id)
      phase = .signedOut
    }
  }

  private func signedIn() async {
    rename(account?.name ?? instance.name, nick: me?.name)
    phase = .ready
    async let sidebar: Void = refreshSidebar()
    async let directory: Void = refreshDirectory()
    _ = await (sidebar, directory)
    connectWorkspace()
    if selectedRoomID == nil {
      selectedRoomID = (starred.first ?? channels.first ?? directs.first)?.id
    } else {
      switchBuffer(from: nil)
    }
  }

  func refreshSidebar() async {
    do {
      let sidebar = try await api.sidebar()
      rooms = sidebar.rooms
      favorites = sidebar.favorites.rooms
      sharedOrder = sidebar.sharedOrder
      for room in sidebar.rooms { buffers[room.id]?.room = room.room }
    } catch EmberError.signedOut {
      tearDown()
      phase = .signedOut
    } catch {}
  }

  func refreshDirectory() async {
    guard let directory = try? await api.directory() else { return }
    people = Dictionary(directory.users.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
  }

  private func rename(_ name: String, nick: String?) {
    guard name != instance.name || nick != instance.nick else { return }
    instance.name = name
    instance.nick = nick
    onChange?(instance)
  }

  private func tearDown() {
    socket?.disconnect()
    socket = nil
    for buffer in buffers.values { buffer.deactivate() }
    buffers = [:]
    socketState = .idle
  }

  // MARK: - Workspace socket

  private func connectWorkspace() {
    if socket == nil {
      let socket = EmberSocket { [api] in api.socketRequest("/api/socket") }
      socket.onText = { [weak self] text in self?.receive(text) }
      socket.onState = { [weak self] state in self?.socketState = state }
      // Whatever changed while it was down, the sidebar says now.
      socket.onOpen = { [weak self] in Task { await self?.refreshSidebar() } }
      socket.onDropped = { [weak self] in Task { await self?.checkSession() } }
      self.socket = socket
    }
    socket?.connect()
  }

  private func receive(_ text: String) {
    guard let frame = try? WorkspaceFrame.decode(text) else { return }
    switch frame {
    case let .welcome(you, account):
      me = you
      self.account = account
      rename(account.name, nick: you.name)
    case let .roomUnread(id):
      // The room on screen is read as it's shown; anything else is marked.
      if !(isForeground && id == selectedRoomID) { setUnread(id, true) }
    case let .roomRead(id): setUnread(id, false)
    case let .userUpdated(user): people[user.id] = user
    case let .roomSaved(room):
      if let index = rooms.firstIndex(where: { $0.id == room.id }) {
        rooms[index].room = room
      } else {
        rooms.append(SidebarRoom(room: room, unread: false, involvement: room.isDirect ? .everything : .mentions))
      }
      buffers[room.id]?.room = room
    case let .roomGone(id):
      rooms.removeAll { $0.id == id }
      buffers.removeValue(forKey: id)?.deactivate()
      if selectedRoomID == id { selectedRoomID = channels.first?.id }
    case let .roomActive(id, at):
      if let index = rooms.firstIndex(where: { $0.id == id }), (rooms[index].room.activeAt ?? "") < at { rooms[index].room.activeAt = at }
    case let .favoritesChanged(favorites): self.favorites = favorites.rooms
    case let .roomInvolvement(id, involvement):
      if let index = rooms.firstIndex(where: { $0.id == id }) { rooms[index].involvement = involvement }
    case .roomsReordered: Task { await refreshSidebar() }
    case let .accountUpdated(account):
      self.account = account
      rename(account.name, nick: me?.name)
    case .roomHuddle, .error, .pong, .unknown: break
    }
  }

  private func setUnread(_ id: RoomID, _ unread: Bool) {
    if let index = rooms.firstIndex(where: { $0.id == id }), rooms[index].unread != unread { rooms[index].unread = unread }
  }

  // MARK: - Buffers

  public func buffer(_ id: RoomID) -> RoomModel? {
    if let buffer = buffers[id] { return buffer }
    guard let room = rooms.first(where: { $0.id == id })?.room else { return nil }
    let buffer = RoomModel(room: room, api: api, instance: self)
    buffers[id] = buffer
    return buffer
  }

  private func switchBuffer(from old: RoomID?) {
    if let old, old != selectedRoomID { buffers[old]?.deactivate() }
    guard isForeground, phase == .ready, let id = selectedRoomID else { return }
    setUnread(id, false)
    buffer(id)?.activate()
  }

  /** Brings this instance on screen, or takes it off, connecting or closing its open room's socket. */
  func setForeground(_ foreground: Bool) {
    isForeground = foreground
    if foreground { switchBuffer(from: nil) } else { selectedRoom?.deactivate() }
  }

  // MARK: - Commands

  /** `/join #name`: opens the room with that name, or makes it. */
  public func join(_ name: String) async throws {
    if let room = rooms.first(where: { $0.room.name?.caseInsensitiveCompare(name) == .orderedSame }) {
      selectedRoomID = room.id
      return
    }
    let room = try await api.createRoom(name: name)
    if !rooms.contains(where: { $0.id == room.id }) {
      rooms.append(SidebarRoom(room: room, unread: false, involvement: .mentions))
    }
    selectedRoomID = room.id
  }

  /** `/msg nick`: opens the DM with the person of that name, starting it if there's none. */
  public func query(_ nick: String) async throws -> RoomModel? {
    guard let person = people.values.first(where: { $0.name.caseInsensitiveCompare(nick) == .orderedSame && $0.status == .active })
      ?? people.values.first(where: { $0.name.lowercased().hasPrefix(nick.lowercased()) && $0.status == .active })
    else {
      throw EmberError.problem(status: 404, message: "No such nick: \(nick)")
    }
    let others = person.id == me?.id ? [] : [person.id]
    let room = try await api.startDirect(with: others)
    if !rooms.contains(where: { $0.id == room.id }) {
      rooms.append(SidebarRoom(room: room, unread: false, involvement: .everything))
    }
    selectedRoomID = room.id
    return buffer(room.id)
  }

  public func toggleFavorite(_ id: RoomID) {
    let starred = favorites.contains(id)
    favorites = starred ? favorites.filter { $0 != id } : favorites + [id]
    Task { try? await api.setFavorite(!starred, room: id) }
  }

  public func setInvolvement(_ involvement: Involvement, for id: RoomID) {
    if let index = rooms.firstIndex(where: { $0.id == id }) { rooms[index].involvement = involvement }
    Task { try? await api.setInvolvement(involvement, in: id) }
  }
}
