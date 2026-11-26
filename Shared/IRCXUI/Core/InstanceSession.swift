import EmberKit
import Foundation
import Observation
import OSLog

let logger = Logger(subsystem: "ai.dxnd.ircX", category: "instance")

/**
 * One Ember instance the app is signed in to, as Slack holds a workspace: its session, its workspace
 * socket, which keeps the sidebar's rooms, unread marks, blocks, presence and people current, and a
 * buffer per room.
 */
@MainActor
@Observable
public final class InstanceSession: Identifiable {
  public enum Phase: Equatable {
    case checking
    case signedOut
    case ready
    case unreachable(String)
    /** A new Ember, waiting for whoever deployed it to set it up (`Bootstrap.setup` pending). */
    case notSetUp
  }

  public private(set) var instance: Instance
  public private(set) var phase: Phase = .checking
  public private(set) var bootstrap: Bootstrap?
  public private(set) var me: Me?
  public private(set) var account: Account?
  public private(set) var rooms: [SidebarRoom] = []
  public private(set) var favorites: [RoomID] = []
  @ObservationIgnored private var favoritesVersion = -1
  public private(set) var sharedOrder: [RoomID] = []
  public private(set) var people: [UserID: DirectoryUser] = [:]
  /** Whom this person has blocked: their messages collapse, and a DM with one of them alone leaves the sidebar. */
  public private(set) var blocks = Blocks.none
  /** The welcome card's invitation, for an administrator who hasn't dismissed it. */
  public private(set) var invitation: Invitation?
  /** For administrators: how many reports are open. */
  public private(set) var openReports: Int?
  /** The huddle going on in each room that has one. */
  public private(set) var huddles: [RoomID: LiveHuddle] = [:]
  /** Which huddle sounds this person hears; nil while they hear them all. */
  public private(set) var huddleSounds: HuddleSounds?
  /** The invitations into huddles that ring, in the order they came, one a room at most (web `invitationsReducer`). */
  public private(set) var ringing: [HuddleInvitation] = []
  /** The app's huddles, which a huddle's link and the ring go through. */
  @ObservationIgnored weak var huddleCenter: HuddleCenter?
  @ObservationIgnored private var ringTimers: [String: Task<Void, Never>] = [:]
  /** The rooms whose huddles' threads show beside the huddle, on sockets of their own that read nothing (`apart`). */
  @ObservationIgnored private var apartBuffers: [RoomID: RoomModel] = [:]
  /** Counts `huddles.changed` frames, so the Huddles list knows to load again. */
  public private(set) var huddlesChanged = 0
  /** Who's active, as the workspace socket says. */
  public private(set) var activePeople = ActivePeople()
  /** The latest failure to show, until it's dismissed or something works again. */
  public internal(set) var notice: String?
  public private(set) var socketState: EmberSocket.State = .idle
  public var selectedRoomID: RoomID? {
    didSet {
      if oldValue != selectedRoomID {
        switchBuffer(from: oldValue)
        rememberLastRoom()
      }
      // A room shown takes the place of any page, as following a link in the sidebar does.
      if selectedRoomID != nil, page != nil { page = nil }
      if selectedRoomID != nil { pageBack = [] }
      record()
    }
  }
  /** A page shown in place of the open room: search, someone's page, a room's settings. */
  public private(set) var page: SessionPage?
  /** The pages a page was opened from, which Go Back returns to before the room (web `useBackPath`). */
  @ObservationIgnored private var pageBack: [SessionPage] = []
  /** Whether the first sidebar load has answered, before which nothing says there are no rooms (web `answered`). */
  public private(set) var sidebarLoaded = false
  /** Why the latest sidebar load failed, which shows with Try again until one works. */
  public private(set) var sidebarFailure: String?
  /** Whether the people directory has loaded, which Available Agents counts from. */
  public private(set) var peopleLoaded = false
  /** For administrators: the newer release of Ember there is, which the Admin entry marks (web `newRelease`). */
  public private(set) var newRelease: String?
  /** For administrators: what the Worker last said of Ember's releases, merged across its isolates (web `useReleaseCheck`). */
  public private(set) var releaseCheck: ReleaseCheck?
  /** Counts `reports.changed` frames, so the reports list knows to load again (web `heard`). */
  public private(set) var reportsHeard = 0
  /** The Server Settings section to show as it opens, which `/admin <section>` asks for. */
  public var adminSection: AdminSection = .general
  /** Server Settings' state, which its window, its sheet and the input line's commands share. */
  @ObservationIgnored public private(set) lazy var admin = WorkspaceAdmin(session: self)
  /** Whether the page shown holds changes that leaving it would lose (web `guardLeaving`). */
  public var holdsChanges = false
  /** Where the app was going when unsaved changes held it, asked about until it's discarded or kept. */
  public var leaving: (() -> Void)?
  /** Available Agents, open over the page. */
  public var showingAgents = false
  /** The welcome page, for someone new who joined with Memberful or single sign-on (web `/welcome`). */
  public var showingWelcome = false
  /** An AI app's request to connect as this person, whose consent sheet shows (web `/oauth/authorize`). */
  public var outsideAsk: OutsideAsk?
  /** What the profile does as it opens, which an input line command asked for. */
  public var profileIntent: ProfileIntent?
  /** The setup token a pasted first-run link carried, which setting up sends. */
  public var setupToken: String?
  /** Where a pasted link leads once the session knows whether it's signed in. */
  @ObservationIgnored private var pendingRoute: EmberRoute?
  /** Signing in, and the ways in it links to, which both themes' sign-in screens show. */
  @ObservationIgnored public private(set) lazy var signInForm = SignInModel(session: self)
  /** Someone `/report nick` is reporting, whose report sheet shows. */
  public var reportingPerson: Person?
  /** Activity: the sidebar lists only the conversations marked unread (web rail's Activity). */
  public var showingActivity = false
  /** The rooms whose star is being saved, whose star ignores presses meanwhile. */
  public private(set) var starring: Set<RoomID> = []
  /** The rooms whose notification level is being saved. */
  public private(set) var involving: Set<RoomID> = []
  /** What the bell last said of a room's level, for a moment (web `InvolvementButton`'s tooltip). */
  public private(set) var involvementNotes: [RoomID: String] = [:]
  /** What saving the starred rooms' order says: saving, saved, or why it wasn't. */
  public private(set) var orderStatus: String?
  /** Whether a starred room is being dragged, until it's dropped or the drag ends. */
  @ObservationIgnored private var movingStar = false
  /** The starred rooms' order while it's being saved, which the sidebar shows meanwhile. */
  @ObservationIgnored private var savingStarOrder: [RoomID]?
  /** Whether Ember was updated since the app connected (web `UpdatedNotice`). */
  public private(set) var updated = false
  /** The custom domain whose moved notice was closed, until the domain changes. */
  public private(set) var movedNoticeClosed: String?
  /** Messages found, and the recent searches. */
  public let search = SearchModel()
  /** Sheets the sidebar, the menus and the input line open. */
  public var showingNewDirect = false
  public var showingNewRoom = false
  public var showingWorkspaceSettings = false
  /** The search box, open over the page, and the room it was opened in, which In this room scopes it to. */
  public var showingSearchBox = false
  public private(set) var searchBoxRoom: RoomID?
  /** What's being asked about before it's done: leaving, deleting, banning, clearing searches. */
  public var confirmation: Confirmation?
  /** Each room's count of workspace frames heard about it, which a write's answer checks it against (web `askForRoom`). */
  @ObservationIgnored private var heardOf: [RoomID: Int] = [:]
  /** The destination last told to `onNavigate`, so showing it again adds nothing to history. */
  @ObservationIgnored private var recorded: Destination?
  /** Hears each page this instance shows, for Back and Forward. */
  @ObservationIgnored var onNavigate: ((Destination) -> Void)?

  @ObservationIgnored public let api: EmberAPI
  @ObservationIgnored private var buffers: [RoomID: RoomModel] = [:]
  @ObservationIgnored private var socket: EmberSocket?
  @ObservationIgnored var onChange: ((Instance) -> Void)?
  /** Hears each sign-in, which saves this device for notifications again. */
  @ObservationIgnored var onSignedIn: (() -> Void)?
  /** Whether this instance is the one on screen, whose open room has its socket connected. */
  var isForeground = false
  /** Whether the app shows, which the sockets tell Ember: a hidden app's rooms aren't read, and it's pushed to. */
  @ObservationIgnored private(set) var isVisible = true
  /**
   * Whether the open room counts as shown: the app's visibility once it has held for 5 seconds, so a
   * moment in another app neither reads rooms nor stops reading them (web `settledVisibility`).
   */
  @ObservationIgnored private(set) var roomVisible = true
  @ObservationIgnored private var settling: Task<Void, Never>?
  /** Whether the app's in use: shown, with input in the last 10 minutes. */
  @ObservationIgnored private(set) var inUse = true
  /** What the workspace socket last told Ember of visibility, which it tells again only when that changes. */
  @ObservationIgnored private var toldVisible: Bool?
  @ObservationIgnored private var reloadingRooms: Task<Void, Never>?
  /** The sidebar load under way, and the one asked for while it was, which starts once it's done (web `oneAtATime`). */
  @ObservationIgnored private var sidebarLoad: Task<Void, Never>?
  @ObservationIgnored private var nextSidebarLoad: Task<Void, Never>?
  /**
   * While a sidebar load is on its way, the workspace frames that changed the list since it was asked
   * for, which it may not show, replayed over it once it arrives (web `roomListReducer`'s `pending`).
   */
  @ObservationIgnored private var heardWhileLoading: [WorkspaceFrame]?
  /** When the app was last hidden, which, after `EmberLimits.reloadAfterHidden`, loads everything again once it shows. */
  @ObservationIgnored private var hiddenAt: Date?
  /** Whether the sockets are closed while the iOS app is in the background, to connect again when it comes back. */
  @ObservationIgnored private var suspended = false

  /** The instance's id, which never changes, kept apart from `instance` so `Identifiable` needs no main actor. */
  public nonisolated let id: UUID

  init(instance: Instance, tokens: TokenStore) {
    id = instance.id
    self.instance = instance
    api = EmberAPI(instance: instance, tokens: tokens)
    loadClosedNotice()
  }

  /** Sets what a signed-in session would have heard, for render tests, which draw screens without a server. */
  func showForRendering(
    me: Me, people: [DirectoryUser], huddles: [RoomID: LiveHuddle] = [:], rooms: [SidebarRoom] = [], favorites: [RoomID] = [],
    invitation: Invitation? = nil, account: Account? = nil, active: [UserID] = []
  ) {
    self.me = me
    self.people = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
    self.huddles = huddles
    self.rooms = rooms
    self.favorites = favorites
    self.invitation = invitation
    self.account = account
    if !active.isEmpty { activePeople.hear(active: active, away: []) }
    sidebarLoaded = true
    peopleLoaded = true
    phase = .ready
  }

  /** Sets whom this person blocks, for render tests. */
  func changeBlocksForRendering(_ blocks: Blocks) { self.blocks = blocks }

  /** Sets how many reports are open, as `reports.changed` says, for render tests. */
  func countReportsForRendering(_ open: Int) { openReports = open }

  /** Sets what a server that isn't signed in, or isn't set up, says of itself, for render tests. */
  func showSignedOutForRendering(_ bootstrap: Bootstrap) {
    self.bootstrap = bootstrap
    account = bootstrap.account
    phase = bootstrap.setup == .complete ? .signedOut : .notSetUp
  }

  public var name: String { account?.name ?? instance.name }
  /** Rooms marked unread: every unread room but a hidden one, whatever its level, as the web marks them. */
  public var hasUnread: Bool { activityCount > 0 }
  /** How many conversations the sidebar marks unread, as Activity's pill and the app's badge count them. */
  public var activityCount: Int { (orderedRooms + orderedDirects).filter(isMarkedUnread).count }
  public var unreadCount: Int { activityCount }

  /**
   * Whether the sidebar marks `room` unread (web `markedUnread`): never the room on screen, which counts
   * as read while it's open, though its mark is kept for when it isn't.
   */
  public func isMarkedUnread(_ room: SidebarRoom) -> Bool {
    room.isMarkedUnread && !(isForeground && room.id == selectedRoomID)
  }

  /** Everyone a message can mention: the people directory's active people. */
  public var mentionable: [User] {
    people.values.filter { $0.status == .active }.map { User(id: $0.id, name: $0.name) }
  }

  public var selectedRoom: RoomModel? { selectedRoomID.flatMap(buffer) }

  public func isBlocked(_ user: UserID) -> Bool { blocks.userIds.contains(user) }
  public func isActive(_ user: UserID) -> Bool { activePeople.active.contains(user) }

  // MARK: - The sidebar's lists, as the web's sidebar orders them

  /** The stars, in the order being saved while it is. */
  public var shownFavorites: [RoomID] { savingStarOrder ?? favorites }

  /** Every room the sidebar lists, starred first, then the workspace's order, then as Ember gave them; none hidden. */
  public var orderedRooms: [SidebarRoom] {
    let shared = rooms.filter { !$0.room.isDirect && $0.involvement != .invisible }
    return RoomList.inSidebarOrder(shared, favorites: shownFavorites, sharedOrder: sharedOrder, id: \.id)
  }

  /**
   * Every DM the sidebar lists, latest active first: none hidden, and no quiet welcome DM unless it's
   * open or has a huddle going on (web `sidebar.tsx`).
   */
  public var orderedDirects: [SidebarRoom] {
    let directs = rooms.filter { item in
      item.room.isDirect && item.involvement != .invisible
        && (!RoomList.isQuietWelcome(item.room, me: me?.id) || item.id == selectedRoomID || huddles[item.id] != nil)
    }
    return RoomList.inDirectOrder(directs) { item in
      guard let activeAt = item.room.activeAt else { return item.id }
      return activeAt
    }
  }

  /** The rooms the sidebar shows: under Activity only those marked unread. */
  public var listedRooms: [SidebarRoom] { showingActivity ? orderedRooms.filter(isMarkedUnread) : orderedRooms }
  public var listedDirects: [SidebarRoom] { showingActivity ? orderedDirects.filter(isMarkedUnread) : orderedDirects }

  /** Every window in the sidebar's order, which ⌥↑ ⌥↓ step through and IRC Classic's Act: numbers. */
  public var windows: [SidebarRoom] { orderedRooms + orderedDirects }

  public func isStarred(_ id: RoomID) -> Bool { shownFavorites.contains(id) }

  /** Whether this person can make rooms (`restrictRoomCreation`): administrators always. */
  public var canCreateRooms: Bool { me?.administrator == true || account?.restrictRoomCreation == false }

  /** A room's name as this person reads it: a DM's others' names, as the directory has them now. */
  public func title(of room: Room) -> String {
    room.name(for: me?.id) { self.people[$0.id]?.name ?? $0.name }
  }

  /** A DM's single other person, who's human, which presence shows on. */
  public func presenceShown(in room: Room) -> UserID? {
    guard room.isDirect else { return nil }
    let others = (room.members ?? []).filter { $0.id != me?.id }
    guard others.count == 1, let other = others.first, let person = people[other.id], person.role != .bot, !PeopleList.isAgent(person) else { return nil }
    return other.id
  }

  /** Whether someone has presence to show: a human, not a bot or an AI agent (`usePresenceOf`). */
  public func presenceShown(of user: UserID) -> Bool {
    guard let person = people[user] else { return false }
    return person.role != .bot && !PeopleList.isAgent(person)
  }

  /** Whether someone's active, away, or not yet known (nil) until the first `presence` frame. */
  public func presence(of user: UserID) -> Bool? { activePeople.heard ? activePeople.active.contains(user) : nil }

  /** Whether a DM is with one AI agent alone (`useIsWithAgent`). */
  public func isWithAgent(_ room: Room) -> Bool {
    guard room.isDirect else { return false }
    let others = (room.members ?? []).filter { $0.id != me?.id }
    return others.count == 1 && others.first.flatMap { people[$0.id] }.map(PeopleList.isAgent) == true
  }

  // MARK: - Session

  public func start() async {
    phase = .checking
    do {
      let bootstrap = try await api.bootstrap()
      self.bootstrap = bootstrap
      account = bootstrap.account
      rename(bootstrap.account.name, nick: bootstrap.user?.name)
      guard bootstrap.setup == .complete else {
        phase = .notSetUp
        return
      }
      if let user = bootstrap.user, api.isSignedIn {
        me = user
        await signedIn()
      } else {
        api.tokens.setToken(nil, for: instance.id)
        phase = .signedOut
      }
      followPending()
    } catch EmberError.signedOut {
      phase = .signedOut
    } catch {
      logger.error("\(self.instance.host, privacy: .public) unreachable: \(error.localizedDescription, privacy: .public)")
      phase = .unreachable(error.localizedDescription)
    }
  }

  /** Signs in with a password, or answers where to connect an account, when the workspace now signs people in elsewhere. */
  public func signIn(emailAddress: String, password: String) async throws -> ElsewhereStart? {
    switch try await api.signIn(emailAddress: emailAddress, password: password) {
    case let .signedIn(user):
      me = user
      await signedIn()
      return nil
    case let .elsewhere(start):
      return start
    }
  }

  public func signIn(name: String) async throws {
    me = try await api.signIn(name: name)
    await signedIn()
  }

  /** Signs in with a sign-in link, which replaces any session this instance has (web `TransferPage`). */
  public func signIn(transferLink: String) async throws {
    let user = try await api.signIn(transferLink: transferLink)
    if phase == .ready { tearDown() }
    me = user
    await signedIn()
  }

  /** Signs in as whoever a password reset signed in, in place of anyone signed in here. */
  func signedIn(afterReset user: Me) async {
    if phase == .ready { tearDown() }
    me = user
    await signedIn()
  }

  /** Keeps the session a web view's flow ended with, and starts again with it, showing the welcome page to someone new. */
  func adoptSession(_ token: String, welcome: Bool) {
    tearDown()
    api.tokens.setToken(token, for: instance.id)
    Task {
      await start()
      if welcome, phase == .ready { showingWelcome = true }
    }
  }

  /**
   * Log out (web profile's Log out): ends the session at Ember, then here. While Ember can't be reached
   * the person stays signed in, and it throws why.
   */
  public func signOut() async throws {
    try await api.signOut()
    signedOutHere()
  }

  /** Forgets the session whatever Ember answers, as removing the server does. */
  func forgetSession() async {
    do {
      try await api.signOut()
    } catch {
      // Ember ends the session when it next hears of it; here it's gone either way.
      logger.error("Signing out of \(self.instance.host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
      api.tokens.setToken(nil, for: instance.id)
    }
    signedOutHere()
  }

  /** Deletes this person's account (`DELETE /api/users/me`), then shows sign-in saying so (web `ACCOUNT_DELETED`). */
  public func deleteAccount(_ deletion: AccountDeletion) async throws {
    try await api.deleteAccount(deletion)
    signedOutHere()
    signInForm.notice = PeopleText.accountDeleted
  }

  private func signedOutHere() {
    PushCenter.shared.signedOut(self)
    tearDown()
    me = nil
    rooms = []
    page = nil
    pageBack = []
    phase = .signedOut
  }

  /**
   * Follows a pasted link to this instance: a page opens once signed in, a sign-in link signs in, an AI
   * app's request asks for consent, and the ways in open over sign-in. Before the session knows whether
   * it's signed in, it waits.
   */
  public func follow(_ route: EmberRoute) {
    switch (phase, route) {
    case (_, .instance):
      return
    case (.checking, _), (.unreachable, _):
      pendingRoute = route
    case let (_, .firstRun(token)):
      if let token { setupToken = token }
    case let (.ready, .page(address)):
      guard let url = URL(string: address), open(link: url) else {
        notice = "No page here opens \(address)"
        return
      }
    case let (.ready, .outsideConnect(ask)):
      outsideAsk = ask
    case let (.ready, .transfer(id)):
      attempt("Signing in with a sign-in link") { try await self.signIn(transferLink: id) }
    case let (.ready, .passwordReset(emailAddress)):
      // Ember serves password reset to people signed in too.
      signInForm.openReset(emailAddress: emailAddress ?? "")
    case (.ready, _):
      notice = EmberText.signedInAlready
    case (.signedOut, .page), (.signedOut, .outsideConnect):
      // Sign in first, then it opens, as the web remembers the page.
      pendingRoute = route
    case let (.signedOut, route):
      signInForm.follow(route)
    case (.notSetUp, _):
      pendingRoute = route
    }
  }

  private func followPending() {
    guard let route = pendingRoute, phase != .checking else { return }
    pendingRoute = nil
    follow(route)
  }

  /** Asks Ember whether this session still signs in, after a socket said to check. */
  func checkSession() async {
    do {
      let bootstrap = try await api.bootstrap()
      if bootstrap.user == nil {
        tearDown()
        api.tokens.setToken(nil, for: instance.id)
        phase = .signedOut
      }
    } catch EmberError.signedOut {
      tearDown()
      phase = .signedOut
    } catch {
      // Unreachable for now: the socket keeps trying, and says so.
      logger.error("Checking the session at \(self.instance.host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func signedIn() async {
    rename(account?.name ?? instance.name, nick: me?.name)
    phase = .ready
    async let sidebar: Void = refreshSidebar()
    async let directory: Void = refreshDirectory()
    _ = await (sidebar, directory)
    connectWorkspace()
    if selectedRoomID == nil, page == nil {
      goHome()
    } else {
      switchBuffer(from: nil)
    }
    onSignedIn?()
    followPending()
  }

  /**
   * Loads the sidebar again, one load at a time: called while one is on its way, it loads once more
   * after it, for every call made meanwhile, and returns once that has.
   */
  func refreshSidebar() async {
    if let next = nextSidebarLoad {
      await next.value
    } else if let running = sidebarLoad {
      let next = Task { [weak self] in
        await running.value
        guard let self else { return }
        self.nextSidebarLoad = nil
        await self.startSidebarLoad().value
      }
      nextSidebarLoad = next
      await next.value
    } else {
      await startSidebarLoad().value
    }
  }

  private func startSidebarLoad() -> Task<Void, Never> {
    let load = Task { [weak self] in
      await self?.loadSidebar()
      self?.sidebarLoad = nil
    }
    sidebarLoad = load
    return load
  }

  private func loadSidebar() async {
    heardWhileLoading = []
    do {
      let sidebar = try await api.sidebar()
      let heard = heardWhileLoading ?? []
      heardWhileLoading = nil
      rooms = sidebar.rooms
      favorites = sidebar.favorites.rooms
      favoritesVersion = sidebar.favorites.version
      sharedOrder = sidebar.sharedOrder
      blocks = sidebar.blocks
      invitation = sidebar.invitation
      openReports = sidebar.openReports
      huddles = sidebar.huddles
      huddleSounds = sidebar.huddleSounds
      // What changed while the list was on its way, which it may not show; stars and blocks by version.
      for frame in heard { changeList(frame) }
      for room in rooms { buffers[room.id]?.room = room.room }
      clearNotice()
      sidebarFailure = nil
      if !sidebarLoaded {
        sidebarLoaded = true
        checkRelease()
      }
      seeRinging()
      // Taken out of a room the list has and put back in meanwhile: the room may be in the wrong place.
      if putBackIn(listed: Set(sidebar.rooms.map(\.id)), heard) { Task { await refreshSidebar() } }
    } catch EmberError.signedOut {
      heardWhileLoading = nil
      tearDown()
      phase = .signedOut
    } catch {
      heardWhileLoading = nil
      sidebarFailure = error.localizedDescription
      fail("Loading rooms", error)
    }
  }

  private func putBackIn(listed: Set<RoomID>, _ heard: [WorkspaceFrame]) -> Bool {
    var takenOut: Set<RoomID> = []
    for frame in heard {
      switch frame {
      case let .roomGone(id) where listed.contains(id): takenOut.insert(id)
      case let .roomSaved(room) where takenOut.contains(room.id): return true
      default: break
      }
    }
    return false
  }

  /** Loads the people and rooms again, and the huddles list, as the web does on each welcome and after a while hidden. */
  private func reloadEverything() {
    Task {
      async let sidebar: Void = refreshSidebar()
      async let directory: Void = refreshDirectory()
      _ = await (sidebar, directory)
      huddlesChanged += 1
    }
  }

  func refreshDirectory() async {
    do {
      try await loadDirectory()
    } catch EmberError.signedOut {
      tearDown()
      phase = .signedOut
    } catch {
      fail("Loading people", error)
    }
  }

  /** Loads the people directory, throwing why it didn't. */
  func loadDirectory() async throws {
    let directory = try await api.directory()
    people = Dictionary(directory.users.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    peopleLoaded = true
  }

  /** Try again, after the sidebar failed to load: the rooms and people again. */
  public func retryLoading() {
    Task {
      async let sidebar: Void = refreshSidebar()
      async let directory: Void = refreshDirectory()
      _ = await (sidebar, directory)
    }
  }

  /**
   * For an administrator, whether a newer release of Ember is out (`GET /api/account/release`), which the
   * Admin entry marks, asked once the rooms have loaded and afresh each time Admin opens (web `useReleaseCheck`).
   */
  public func checkRelease() {
    guard me?.administrator == true else {
      newRelease = nil
      return
    }
    Task {
      do {
        adoptRelease(try await api.releaseCheck())
      } catch EmberError.signedOut {
        tearDown()
        phase = .signedOut
      } catch {
        logger.error("Checking for a newer Ember failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /** What the Admin entry's dot says is waiting: a newer Ember, open reports (web `Rail`'s `notices`). */
  public var workspaceNotice: String? {
    guard me?.administrator == true else { return nil }
    var notices: [String] = []
    if let newRelease { notices.append(NavigationText.releaseAvailable(newRelease)) }
    if let openReports, openReports > 0 { notices.append(NavigationText.openReports(openReports)) }
    return notices.isEmpty ? nil : notices.joined(separator: ". ")
  }

  /** Takes a release check, merged with the one before (web `together`), which the Admin entry marks. */
  func adoptRelease(_ check: ReleaseCheck) {
    let merged = ReleaseCheck.together(releaseCheck, check)
    releaseCheck = merged
    newRelease = merged.update?.release
  }

  /**
   * Opens workspace settings (Admin, or Workspace), at `section` if given, asking afresh about releases as
   * the web does each time Admin opens (`POST /api/account/release_checks`).
   */
  public func openWorkspaceSettings(_ section: AdminSection? = nil) {
    if let section { adminSection = section }
    showingWorkspaceSettings = true
    guard me?.administrator == true else { return }
    Task {
      do {
        adoptRelease(try await api.checkForReleaseAfresh())
      } catch EmberError.signedOut {
        tearDown()
        phase = .signedOut
      } catch {
        logger.error("Asking afresh for a newer Ember failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /** Takes the workspace an account change answered with, as every page shows it (web `answered`). */
  func adoptAccount(_ account: Account) {
    self.account = account
    rename(account.name, nick: me?.name)
  }

  /** Takes a new join code, which the welcome card shares too. */
  func adoptJoinCode(_ code: String) {
    invitation?.joinCode = code
  }

  /** Takes someone's directory entry, as a role change, removal or ban answers it. */
  func adoptPerson(_ person: DirectoryUser) {
    people[person.id] = person
  }

  /** Logs a failure and shows it. */
  func fail(_ doing: String, _ error: Error) {
    logger.error("\(doing, privacy: .public) on \(self.instance.host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    notice = error.localizedDescription
  }

  public func clearNotice() { notice = nil }

  /** Runs something the person asked for, showing why if it fails. */
  public func attempt(_ doing: String, _ work: @escaping @MainActor () async throws -> Void) {
    Task {
      do {
        try await work()
      } catch {
        fail(doing, error)
      }
    }
  }

  private func rename(_ name: String, nick: String?) {
    guard name != instance.name || nick != instance.nick else { return }
    instance.name = name
    instance.nick = nick
    onChange?(instance)
  }

  /** Closes this instance's sockets for good, as a server moved to a new address is replaced. */
  func end() { tearDown() }

  /** The session ended (a 401): its sockets close, and it goes to sign in. */
  func sessionEnded() {
    tearDown()
    phase = .signedOut
  }

  private func tearDown() {
    if let call = huddleCenter?.call, call.session === self { call.leave() }
    ringing = []
    for buffer in apartBuffers.values { buffer.deactivate() }
    apartBuffers = [:]
    socket?.disconnect()
    socket = nil
    suspended = false
    reloadingRooms?.cancel()
    for buffer in buffers.values { buffer.deactivate() }
    buffers = [:]
    socketState = .idle
    activePeople = ActivePeople()
    toldVisible = nil
  }

  // MARK: - Presence

  /** Says whether the app shows and is in use, which the sockets tell Ember as it changes. */
  func setPresence(visible: Bool, inUse: Bool) {
    let shown = visible != isVisible
    let used = inUse != self.inUse
    isVisible = visible
    self.inUse = inUse
    if used { socket?.send(WorkspaceClientFrame.presenceActive(inUse)) }
    if shown {
      tellVisibility()
      settleRoomVisibility()
      if !visible {
        hiddenAt = Date()
      } else {
        // Shown after more than a minute hidden: what changed meanwhile may not have reached the sockets.
        if let hiddenAt, Date().timeIntervalSince(hiddenAt) > EmberLimits.reloadAfterHidden, phase == .ready, !suspended { reloadEverything() }
        hiddenAt = nil
      }
    }
  }

  /** Tells the open room the app shows, or doesn't, once that has held for 5 seconds (`SETTLE_MS`). */
  private func settleRoomVisibility() {
    settling?.cancel()
    let visible = isVisible
    guard visible != roomVisible else { return }
    settling = Task { [weak self] in
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled, let self, self.isVisible == visible else { return }
      self.roomVisible = visible
      if self.isForeground {
        self.selectedRoom?.setVisible(visible)
        if visible, let id = self.selectedRoomID { self.markRead(id) }
      }
    }
  }

  /**
   * Closes the sockets while the iOS app is in the background, which keeps none open; `resume()`
   * connects them again, the welcome and `resumed` bringing what changed meanwhile.
   */
  func suspend() {
    guard phase == .ready, !suspended else { return }
    suspended = true
    socket?.disconnect()
    for buffer in buffers.values { buffer.deactivate() }
  }

  func resume() {
    guard suspended else { return }
    suspended = false
    guard phase == .ready else { return }
    connectWorkspace()
    switchBuffer(from: nil)
  }

  private func tellVisibility() {
    guard toldVisible != isVisible, socket?.send(WorkspaceClientFrame.presenceVisible(isVisible)) == true else { return }
    toldVisible = isVisible
  }

  // MARK: - Workspace socket

  private func connectWorkspace() {
    if socket == nil {
      let socket = EmberSocket { [weak self, api] in
        guard let self else { return api.socketRequest(workspaceSocketPath(visible: false)) }
        // The address tells Ember how the app shows until the welcome says otherwise.
        self.toldVisible = self.isVisible
        self.activePeople.reconnected()
        return api.socketRequest(workspaceSocketPath(visible: self.isVisible))
      }
      socket.onText = { [weak self] text in self?.receive(text) }
      socket.onState = { [weak self] state in self?.socketState = state }
      socket.onDropped = { [weak self] in Task { await self?.checkSession() } }
      socket.onEnded = { [weak self] code in Task { await self?.workspaceEnded(code) } }
      self.socket = socket
    }
    socket?.connect()
  }

  /**
   * The workspace closed the socket for good (Revoked, or NotFound): asks whether this session still
   * signs in, and as whom, as the web's `fetchMe` does, connecting again while it's still them.
   */
  private func workspaceEnded(_ code: CloseCode) async {
    logger.error("The workspace socket at \(self.instance.host, privacy: .public) was closed with \(code.rawValue)")
    do {
      let bootstrap = try await api.bootstrap()
      guard let user = bootstrap.user else {
        tearDown()
        api.tokens.setToken(nil, for: instance.id)
        phase = .signedOut
        return
      }
      if let me, me.id != user.id {
        tearDown()
        await start()
        return
      }
    } catch EmberError.signedOut {
      tearDown()
      phase = .signedOut
      return
    } catch {
      fail("Connecting to the workspace", error)
    }
    try? await Task.sleep(for: .seconds(2))
    guard phase == .ready, !suspended else { return }
    socket?.connect()
  }

  private func receive(_ text: String) {
    let frame: WorkspaceFrame
    do {
      frame = try WorkspaceFrame.decode(text)
    } catch {
      fail("Reading the workspace socket", error)
      return
    }
    if changeList(frame) {
      heardWhileLoading?.append(frame)
    }
    defer { seeRinging() }
    switch frame {
    case let .welcome(you, account):
      if let me, me.id != you.id {
        // Signed out and in as someone else elsewhere, and the session went with it: start again as them.
        tearDown()
        Task { await start() }
        return
      }
      socket?.send(WorkspaceClientFrame.presenceActive(inUse))
      toldVisible = nil
      tellVisibility()
      me = you
      self.account = account
      rename(account.name, nick: you.name)
      // Whatever changed while it was down, the sidebar and directory say now.
      reloadEverything()
      checkVersion()
    case .roomUnread, .roomRead, .roomActive, .roomHuddle, .roomInvolvement, .favoritesChanged, .blocksChanged, .reportsChanged,
      .invitationDismissed, .huddleSounds:
      break
    case let .userUpdated(user):
      people[user.id] = user
      if let me, me.id == user.id {
        let wasAdministrator = me.administrator
        self.me = Me(id: user.id, name: user.name, administrator: user.role == .administrator)
        rename(name, nick: user.name)
        // Only administrators get the welcome card and admins-only agents, so a new role loads both again.
        if wasAdministrator != (user.role == .administrator) {
          Task {
            await refreshSidebar()
            await refreshDirectory()
          }
        }
      }
    case let .userGone(id):
      people.removeValue(forKey: id)
    case let .roomSaved(room):
      buffers[room.id]?.room = room
    case let .roomGone(id):
      if selectedRoomID == id {
        // The room on screen stays, saying it's gone, until another page is shown (web `gone`).
        buffers[id]?.end(.notFound)
      } else {
        buffers.removeValue(forKey: id)?.deactivate()
      }
    case let .huddleInvited(id, by):
      let at = Date()
      ringing = HuddleRinging.invited(ringing, room: id, by: by, at: at)
      // It rings for half a minute, then gives up, unanswered (`INVITATION_RINGS_MS`).
      let key = HuddleInvitation(roomId: id, by: by, at: at).id
      ringTimers[key] = Task { [weak self] in
        try? await Task.sleep(for: .seconds(HuddleRinging.ringsFor))
        guard !Task.isCancelled, let self else { return }
        self.ringTimers[key] = nil
        if self.ringing.contains(where: { $0.id == key }) { self.ringing = HuddleRinging.over(self.ringing, room: id) }
      }
    case let .huddleAnswered(id):
      stopRinging(id)
    case .huddlesChanged:
      huddlesChanged += 1
    case .roomsReordered:
      // Every client hears this at once, so each waits a while before asking, as the web does.
      guard reloadingRooms == nil else { return }
      reloadingRooms = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(Int.random(in: 0..<5_000)))
        guard !Task.isCancelled else { return }
        self?.reloadingRooms = nil
        await self?.refreshSidebar()
      }
    case let .accountUpdated(account):
      self.account = account
      rename(account.name, nick: me?.name)
    case let .presence(active, away):
      activePeople.hear(active: active, away: away)
    case let .error(message):
      fail("The workspace socket", EmberError.refused(400, message))
    case .pong, .unknown:
      break
    }
  }

  /**
   * Applies a frame that changes the sidebar's list (rooms, marks, stars, blocks, huddles, reports, the
   * welcome card, huddle sounds), as the web's `changed` does, and says whether it was one.
   */
  @discardableResult
  private func changeList(_ frame: WorkspaceFrame) -> Bool {
    if let id = frame.roomId { heardOf[id, default: 0] += 1 }
    switch frame {
    case let .roomSaved(room):
      if let index = rooms.firstIndex(where: { $0.id == room.id }) {
        var saved = room
        // A later activity the list heard of first stays.
        if let kept = rooms[index].room.activeAt, let given = room.activeAt, kept > given { saved.activeAt = kept }
        rooms[index].room = saved
      } else {
        rooms.append(SidebarRoom(room: room, unread: false, involvement: Involvement.starting(in: room)))
      }
    case let .roomGone(id):
      rooms.removeAll { $0.id == id }
      favorites.removeAll { $0 == id }
      huddles.removeValue(forKey: id)
    case let .roomUnread(id, at, count):
      // The server tells of a mark only as it makes one, so a room marked already takes the new time.
      guard let index = rooms.firstIndex(where: { $0.id == id }) else { return true }
      rooms[index].unread = true
      rooms[index].unreadSince = at
      rooms[index].unreadCount = count
    case let .roomRead(id):
      markRead(id)
    case let .roomActive(id, at):
      if let index = rooms.firstIndex(where: { $0.id == id }), (rooms[index].room.activeAt ?? at) <= at { rooms[index].room.activeAt = at }
    case let .roomHuddle(id, huddle):
      huddles[id] = huddle
    case let .roomInvolvement(id, involvement):
      if let index = rooms.firstIndex(where: { $0.id == id }) { rooms[index].involvement = involvement }
    case let .favoritesChanged(favorites):
      adopt(favorites)
    case let .blocksChanged(blocks):
      adopt(blocks)
    case let .reportsChanged(open):
      openReports = open
      reportsHeard += 1
    case .invitationDismissed:
      invitation = nil
    case let .huddleSounds(sounds):
      huddleSounds = sounds.hearsAll ? nil : sounds
    default:
      return false
    }
    return true
  }

  private func markRead(_ id: RoomID) {
    PushCenter.shared.clearDelivered(room: id, origin: instance.origin)
    guard let index = rooms.firstIndex(where: { $0.id == id }), rooms[index].unread || rooms[index].unreadCount != nil else { return }
    rooms[index].unread = false
    rooms[index].unreadSince = nil
    rooms[index].unreadCount = nil
  }

  /** Takes the newer of two lists of stars, by version, whichever arrives last. */
  private func adopt(_ favorites: Favorites) {
    guard favorites.version > favoritesVersion else { return }
    favoritesVersion = favorites.version
    self.favorites = favorites.rooms
  }

  /** Saves which huddle sounds this person hears, taking what Ember answers (`PATCH /api/users/me/huddle-sounds`). */
  public func changeHuddleSounds(_ changes: HuddleSoundChanges) async throws {
    let sounds = try await api.changeHuddleSounds(changes)
    huddleSounds = sounds.hearsAll ? nil : sounds
  }

  /** Takes this person's name as a profile answer has it, before the workspace socket says so. */
  func adoptName(_ name: String) {
    guard let me, me.name != name else { return }
    self.me = Me(id: me.id, name: name, administrator: me.administrator)
    rename(self.name, nick: name)
  }

  /** Blocks or unblocks someone (`POST`/`DELETE /api/users/<id>/block`), taking the blocks it answers. */
  public func setBlocked(_ blocked: Bool, _ user: UserID) async throws {
    let changed = try await api.setBlocked(blocked, user)
    adopt(changed.blocks)
    // Blocking hides the DM with them alone, and unblocking shows it again, at the level Ember answers.
    if let direct = changed.direct, let index = rooms.firstIndex(where: { $0.id == direct.roomId }) {
      rooms[index].involvement = direct.involvement
    }
  }

  private func adopt(_ blocks: Blocks) {
    guard blocks.version > self.blocks.version else { return }
    self.blocks = blocks
  }

  // MARK: - Buffers

  /** Rings `invitations`, for render tests. */
  func ringForRendering(_ invitations: [HuddleInvitation]) { ringing = invitations }

  /** Stops an invitation ringing here, answered here or elsewhere. */
  func stopRinging(_ room: RoomID) {
    ringing = HuddleRinging.over(ringing, room: room)
  }

  /** Lets the ringing invitations go by what's seen now: rooms, huddles going on, and the one the app is in. */
  func seeRinging() {
    guard let me, !ringing.isEmpty else { return }
    let joined = huddleCenter?.call.flatMap { $0.session === self ? $0.roomId : nil }
    let seen = HuddlesSeen(
      on: account?.huddles == true, me: me.id, roomIds: sidebarLoaded ? Set(rooms.map(\.id)) : nil, live: huddles, joinedRoomId: joined)
    let next = HuddleRinging.seen(ringing, seen)
    if next != ringing { ringing = next }
  }

  /**
   * A room as the huddle's thread shows it beside the huddle: a socket of its own, `apart`, which the room
   * doesn't count as present nor marks read through (web `useRoomApart`).
   */
  public func apartBuffer(_ id: RoomID) -> RoomModel? {
    if let buffer = apartBuffers[id] { return buffer }
    guard let room = rooms.first(where: { $0.id == id })?.room else { return nil }
    let buffer = RoomModel(room: room, api: api, instance: self, apart: true)
    apartBuffers[id] = buffer
    return buffer
  }

  /** Lets go of the huddle's thread's socket, once the huddle closes it. */
  public func closeApartBuffer(_ id: RoomID) {
    apartBuffers.removeValue(forKey: id)?.deactivate()
  }

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
    // The "New" line goes where the room was read up to, which reading it now forgets.
    if old != id, let item = rooms.first(where: { $0.id == id }) { buffer(id)?.newSince = item.unread ? item.unreadSince : nil }
    if roomVisible { markRead(id) }
    buffer(id)?.activate()
  }

  /** Brings this instance on screen, or takes it off, connecting or closing its open room's socket. */
  func setForeground(_ foreground: Bool) {
    isForeground = foreground
    if foreground { switchBuffer(from: nil) } else { selectedRoom?.deactivate() }
  }

  /**
   * Opens a link to one of this instance's rooms, its messages or its threads in place, as the web's
   * `MessageLink` opens its own pages; false for any other link, which the system opens.
   */
  public func open(link url: URL) -> Bool {
    guard let page = Pages.page(ofLink: url.absoluteString, origin: instance.origin) else { return false }
    switch page {
    case let .room(id, messageId, threadId, _, huddle):
      if huddle {
        // A huddle's link opens its room with its preview over it, or says huddles are off (web workspace.tsx).
        show(id, messageId: nil, threadId: nil)
        huddleCenter?.preview(id, in: self)
      } else {
        show(id, messageId: messageId, threadId: threadId)
      }
    case let .message(id, messageId): show(id, messageId: messageId, threadId: nil)
    case let .roomOfKind(_, id): show(id, messageId: nil, threadId: nil)
    case .home: leave { self.goHome() }
    case .newestRoom: leave { self.goToNewestRoom() }
    case let .person(id): show(.person(id))
    case .profile: show(.profile)
    case .search:
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
      guard let query else {
        show(.search(Search(q: String()), .newest))
        return true
      }
      let (search, sort) = Searches.search(ofQuery: query)
      runSearch(search, sort: sort, record: false)
    case let .roomSettings(_, id), let .directSettings(id): showSettings(of: id)
    case .newDirect: showingNewDirect = true
    case .newRoom: if canCreateRooms { showingNewRoom = true } else { notice = "Only administrators can create rooms" }
    case .huddles: show(.huddles)
    case .pushSubscriptions: show(.pushSubscriptions)
    case .workspaceSettings:
      // Reports' link, which a report's notification opens: Membership, where they're listed (`REPORTS_PATH`).
      guard url.fragment() == "membership-settings" else { return false }
      openWorkspaceSettings(.membership)
    default: return false
    }
    return true
  }

  /** A room's settings, or a DM's, by address: not listed, it's not found (web `direct-settings`). */
  private func showSettings(of id: RoomID) {
    guard rooms.contains(where: { $0.id == id }) else {
      notice = NavigationText.roomNotFound
      return
    }
    show(.settings(id))
  }

  /**
   * Shows a room, at a message or in a thread. A room the list doesn't have is asked for again once,
   * then home it is, saying it's not found (web `ROOM_NOT_FOUND`); if asking fails, a page says why, with Try again.
   */
  func show(_ id: RoomID, messageId: String?, threadId: String?) {
    guard let room = buffer(id) else {
      Task {
        await refreshSidebar()
        if let room = buffer(id) {
          leave {
            self.selectedRoomID = id
            room.show(messageId: messageId, threadId: threadId)
          }
        } else if let failure = sidebarFailure {
          show(.unavailable(failure, id, messageId: messageId, threadId: threadId))
        } else {
          leave {
            self.goHome()
            self.notice = NavigationText.roomNotFound
          }
        }
      }
      return
    }
    leave {
      self.selectedRoomID = id
      room.show(messageId: messageId, threadId: threadId)
    }
  }

  // MARK: - Commands

  /** `/join #name`: opens the room with that name. A room that isn't listed is private, or not there. */
  public func join(_ name: String) async throws {
    guard let room = room(named: name) else {
      throw EmberError.refused(404, "#\(name): No such channel")
    }
    selectedRoomID = room.id
  }

  /** The shared room called `name`, hidden ones too, however it's cased. */
  public func room(named name: String) -> SidebarRoom? {
    rooms.first { !$0.room.isDirect && $0.room.name?.caseInsensitiveCompare(name) == .orderedSame }
  }

  /** The active person a typed nick names: a name in full, a username, then a name or username that starts with it. */
  public func person(named nick: String) -> DirectoryUser? {
    let sought = PeopleList.folded(PeopleList.soughtName(nick))
    let active = PeopleList.byName(people.values.filter { $0.status == .active })
    return active.first { PeopleList.folded($0.name) == sought || $0.username == sought }
      ?? active.first { PeopleList.folded($0.name).hasPrefix(sought) || $0.username?.hasPrefix(sought) == true }
  }

  /** `/msg nick`: opens the DM with the person of that name, starting it if there's none. */
  public func query(_ nick: String) async throws -> RoomModel? {
    try await query([nick])
  }

  /** `/query a b c`: opens the DM with those people, starting it if there's none. */
  public func query(_ nicks: [String]) async throws -> RoomModel? {
    var ids: [UserID] = []
    for nick in nicks {
      guard let person = person(named: nick) else { throw EmberError.refused(404, "No such nick: \(nick)") }
      if person.id != me?.id { ids.append(person.id) }
    }
    let started = try await startDirect(with: ids)
    if !started.without.isEmpty { notice = PeopleList.startedWithout(started.without) }
    return buffer(started.room.id)
  }

  /**
   * Starts or opens the DM with `userIds` (`POST /api/directs`), lists it and shows it. Says who Ember
   * left out: admins-only agents an administrator picked with someone who isn't one.
   */
  @discardableResult
  public func startDirect(with userIds: [UserID]) async throws -> (room: Room, without: [String]) {
    let room = try await api.startDirect(with: userIds).room
    changeList(.roomSaved(room))
    selectedRoomID = room.id
    let members = Set((room.members ?? []).map(\.id))
    let without = userIds.filter { !members.contains($0) }.map { people[$0]?.name ?? $0 }
    return (room, without)
  }

  /** Makes a room (`POST /api/rooms`), lists it last, and shows it. A private room always has its maker in it. */
  @discardableResult
  public func createRoom(name: String, icon: String?, closed: Bool, memberIds: [UserID]) async throws -> Room {
    let new: NewRoom
    if closed {
      var members = memberIds.filter { $0 != me?.id }
      if let me { members.insert(me.id, at: 0) }
      new = .closed(name: name, icon: icon, memberIds: members)
    } else {
      new = .open(name: name, icon: icon)
    }
    let room = try await api.createRoom(new)
    changeList(.roomSaved(room))
    selectedRoomID = room.id
    return room
  }

  /**
   * Saves a room's settings (`PATCH /api/rooms/<id>`). Saving yourself out of a private room takes it
   * out of the sidebar and goes home saying so; anything else shows the room.
   */
  public func changeRoom(_ id: RoomID, _ changes: RoomChanges) async throws {
    let room = try await api.changeRoom(id, changes)
    if changes.kind == .closed, let me, changes.memberIds?.contains(me.id) == false {
      removeRoom(id)
      goHome()
      notice = NavigationText.roomNotFound
      return
    }
    changeList(.roomSaved(room))
    buffers[id]?.room = room
    selectedRoomID = id
  }

  /** Deletes a room or DM (`DELETE /api/rooms/<id>`) and goes home. */
  public func deleteRoom(_ id: RoomID) async throws {
    try await api.deleteRoom(id)
    removeRoom(id)
    goHome()
  }

  /** Leaves a private room (`DELETE /api/rooms/<id>/membership`) and goes home. */
  public func leaveRoom(_ id: RoomID) async throws {
    try await api.leaveRoom(id)
    removeRoom(id)
    goHome()
  }

  private func removeRoom(_ id: RoomID) {
    changeList(.roomGone(id))
    buffers.removeValue(forKey: id)?.deactivate()
    if selectedRoomID == id { selectedRoomID = nil }
    if case let .settings(shown)? = page, shown == id { page = nil }
  }

  /** Stars or unstars a room (`PUT /api/rooms/<id>/favorite`), showing what Ember answers; failing, the room says so. */
  public func toggleFavorite(_ id: RoomID) {
    guard !starring.contains(id) else { return }
    let starred = favorites.contains(id)
    starring.insert(id)
    Task {
      defer { starring.remove(id) }
      do {
        adopt(try await api.setFavorite(!starred, room: id))
      } catch {
        logger.error("Starring failed: \(error.localizedDescription, privacy: .public)")
        buffers[id]?.warn(NavigationText.favoriteFailed)
        fail(starred ? "Unstarring" : "Starring", error)
      }
    }
  }

  /** Moves a starred room up or down among the starred rooms the sidebar shows, or to the top, and saves the order. */
  public func moveStar(_ id: RoomID, _ move: InputCommand.StarMove) {
    // Under Activity, only the starred rooms it lists move, past one another.
    let visible = listedRooms.map(\.id).filter(isStarred)
    guard visible.contains(id) else { return }
    let moved: [RoomID]
    switch move {
    case .up: moved = RoomList.moved(visible, id, by: -1)
    case .down: moved = RoomList.moved(visible, id, by: 1)
    case .top: moved = RoomList.movedBefore(visible, id, visible.first)
    }
    guard moved != visible else { return }
    // The stars the sidebar doesn't show keep their places.
    var next = moved.makeIterator()
    reorderStars(shownFavorites.map { visible.contains($0) ? (next.next() ?? $0) : $0 })
  }

  /** Saves the starred rooms' order (`PUT /api/sidebar/order`), showing it meanwhile and the stars Ember keeps if it fails. */
  public func reorderStars(_ order: [RoomID]) {
    savingStarOrder = order
    orderStatus = NavigationText.savingOrder
    Task {
      do {
        let saved = try await api.setFavoriteOrder(order)
        savingStarOrder = nil
        adopt(saved)
        orderStatus = NavigationText.starOrderSaved
      } catch {
        savingStarOrder = nil
        logger.error("Saving the star order failed: \(error.localizedDescription, privacy: .public)")
        orderStatus = NavigationText.orderFailed
      }
    }
  }

  public func clearOrderStatus() { orderStatus = nil }

  /**
   * A starred room dragged among the starred rooms the sidebar lists (`useStarOrder`): `sources` put
   * before `before`, or after the last, and the order saved; hidden stars keep their places.
   */
  public func dropStars(_ sources: [RoomID], before: RoomID?) {
    movingStar = false
    let visible = listedRooms.map(\.id).filter(isStarred)
    let moving = sources.filter(visible.contains)
    var moved = visible.filter { !moving.contains($0) }
    let place = before.flatMap { moved.firstIndex(of: $0) } ?? moved.endIndex
    moved.insert(contentsOf: moving, at: place)
    guard moved != visible else {
      orderStatus = NavigationText.roomMoveCanceled
      return
    }
    var next = moved.makeIterator()
    reorderStars(shownFavorites.map { visible.contains($0) ? (next.next() ?? $0) : $0 })
  }

  /** A drag of a starred room has started, which is announced (web `onDrag`). */
  public func startedMovingStar(_ ids: [RoomID]) {
    guard let id = ids.first, isStarred(id), let item = rooms.first(where: { $0.id == id }) else { return }
    movingStar = true
    orderStatus = NavigationText.moving(title(of: item.room))
  }

  /** A drag has ended: with no drop among the stars, it was canceled (web `onCancel`). */
  public func endedMovingStar() {
    guard movingStar else { return }
    Task {
      // The drop, if there was one, is heard a moment after the drag ends.
      try? await Task.sleep(for: .milliseconds(300))
      guard movingStar else { return }
      movingStar = false
      orderStatus = NavigationText.roomMoveCanceled
    }
  }

  /**
   * Sets a room's notification level (`PUT /api/rooms/<id>/involvement`), showing what Ember answers
   * unless a frame about the room came meanwhile; failing, the room says so.
   */
  public func setInvolvement(_ involvement: Involvement, for id: RoomID) {
    guard !involving.contains(id) else { return }
    involving.insert(id)
    let ticket = heardOf[id, default: 0]
    Task {
      defer { involving.remove(id) }
      do {
        let answered = try await api.setInvolvement(involvement, in: id)
        if heardOf[id, default: 0] == ticket, let index = rooms.firstIndex(where: { $0.id == id }) { rooms[index].involvement = answered }
        say(answered.sentence, about: id)
      } catch {
        logger.error("Changing the notification level failed: \(error.localizedDescription, privacy: .public)")
        say(NavigationText.involvementFailed, about: id)
        buffers[id]?.warn(NavigationText.involvementFailed)
      }
    }
  }

  /** Shows what the bell says for 3.2 seconds (web `NOTE_MS`). */
  private func say(_ note: String, about id: RoomID) {
    involvementNotes[id] = note
    Task {
      try? await Task.sleep(for: .milliseconds(3_200))
      if involvementNotes[id] == note { involvementNotes.removeValue(forKey: id) }
    }
  }

  /** Dismisses the welcome card on every device (`DELETE /api/sidebar/invitation`). */
  public func dismissInvitation() async throws {
    try await api.dismissInvitation()
    invitation = nil
  }

  /** The join link the welcome card shares, `https://<host>/join/<code>`. */
  public func joinLink(_ code: String) -> String { publicOrigin + Pages.joinLink(code) }

  /**
   * Where shared links lead and Memberful and the provider send people back to: `https://` and the custom
   * domain, or this server's address while it has none (the web builds them where its page is).
   */
  public var publicOrigin: String {
    guard let domain = account?.customDomain, !domain.isEmpty else { return instance.origin }
    return "https://\(domain)"
  }

  /** Bans or lifts a ban (`POST`/`DELETE /api/users/<id>/ban`), taking the person it answers. */
  public func setBanned(_ banned: Bool, _ user: UserID) async throws {
    let person = banned ? try await api.ban(user) : try await api.unban(user)
    people[person.id] = person
  }

  /** Opens the search box, scoped to `room` when it's opened from one (web Cmd+F, a room's Search). */
  public func openSearchBox(in room: RoomID?) {
    searchBoxRoom = room
    showingSearchBox = true
    loadRecentSearches()
  }

  // MARK: - Navigation

  /** What this instance shows: a page, or the open room. */
  public var destination: Destination? {
    if let page { return .page(page) }
    return selectedRoomID.map(Destination.room)
  }

  /** Shows a page in place of the room, once any unsaved changes are let go; Go Back returns to the page it was opened from. */
  public func show(_ page: SessionPage) {
    guard page != self.page else { return }
    leave {
      // A search shown in place of another replaces it, as the web's search page does its address.
      if let shown = self.page, !(shown.isSearch && page.isSearch) { self.pageBack.append(shown) }
      self.page = page
      self.record()
    }
  }

  /** Shows a room from the sidebar or a menu, once any unsaved changes are let go. */
  public func open(room id: RoomID) {
    leave {
      self.selectedRoomID = id
      // A room's own page replaces any page, even the room already open.
      if self.page != nil {
        self.page = nil
        self.pageBack = []
        self.record()
      }
    }
  }

  /** Leaves a page for the page it was opened from, or the room it was opened over, or home (web `useBackPath`). */
  public func closePage() {
    holdsChanges = false
    // Exit search goes back to the room (web `back`), not to the page the search was run from.
    if page?.isSearch == true { pageBack = [] }
    if let previous = pageBack.popLast() {
      page = previous
      if case let .search(search, sort) = previous { requery(search, sort) }
    } else {
      page = nil
      if selectedRoomID == nil { goHome() }
    }
    record()
  }

  /**
   * Goes where `go` goes once the page shown lets it: straight away, or after asking about its
   * unsaved changes (web `leave`).
   */
  public func leave(_ go: @escaping () -> Void) {
    guard holdsChanges else { return go() }
    leaving = go
  }

  /** Discard: lets the unsaved changes go, and goes where the app was going. */
  public func discardAndLeave() {
    holdsChanges = false
    let go = leaving
    leaving = nil
    go?()
  }

  /** Activity (the rail's): on a page, home first, then only unread conversations, or all again (web `toggleActivity`). */
  public func toggleActivity() {
    leave {
      if self.page != nil {
        self.page = nil
        self.pageBack = []
        self.goHome()
        self.record()
      }
      self.showingActivity.toggle()
    }
  }

  /** Shows a destination again, as Back and Forward do; false when it's gone. A search is asked again. */
  @discardableResult
  func go(to destination: Destination) -> Bool {
    switch destination {
    case let .room(id):
      guard rooms.contains(where: { $0.id == id }) else { return false }
      selectedRoomID = id
    case let .page(page):
      pageBack = []
      self.page = page
      if case let .search(search, sort) = page { requery(search, sort) }
      record()
    }
    return true
  }

  /** A search page shown again: its search asked again unless it's the one shown (web `fetchSearch` on each visit). */
  private func requery(_ search: Search, _ sort: SearchSort) {
    guard search.isSearchable, search != self.search.search || sort != self.search.sort || !self.search.ran else { return }
    Task { await self.search.run(search, sort: sort, record: false, api: api) }
  }

  /** Home (web `/`): the room last visited if it's still listed, else the room this person was put in first. */
  public func goHome() {
    let remembered = UserDefaults.standard.string(forKey: lastRoomKey)
    selectedRoomID = rooms.first { $0.id == remembered }?.id ?? rooms.first?.id
  }

  /** `/rooms`: the room made most recently, skipping quiet welcome DMs (web `newest-room`). */
  public func goToNewestRoom() {
    guard let newest = rooms.last(where: { !RoomList.isQuietWelcome($0.room, me: me?.id) }) else { return goHome() }
    selectedRoomID = newest.id
  }

  private var lastRoomKey: String { "ircX.lastRoom.\(id.uuidString)" }

  private func rememberLastRoom() {
    guard let selectedRoomID else { return }
    UserDefaults.standard.set(selectedRoomID, forKey: lastRoomKey)
  }

  private func record() {
    guard let destination, destination != recorded else { return }
    recorded = destination
    onNavigate?(destination)
  }

  /** Recorded again as the instance comes on screen, so switching servers is a step back can undo. */
  func recordAgain() {
    recorded = nil
    record()
  }

  // MARK: - Notices

  /** The custom domain Ember has moved to, while this instance is reached at another and the notice isn't closed. */
  public var movedTo: String? {
    guard let domain = account?.customDomain, !domain.isEmpty, domain.lowercased() != instance.host.lowercased(),
      movedNoticeClosed != domain
    else { return nil }
    return domain
  }

  public func closeMovedNotice() {
    movedNoticeClosed = account?.customDomain
    UserDefaults.standard.set(movedNoticeClosed, forKey: "ircX.movedClosed.\(id.uuidString)")
  }

  /** Whether Ember's version changed since the app connected, after a reconnect (web `useUpdated`). */
  private func checkVersion() {
    guard let known = bootstrap?.version else { return }
    Task {
      do {
        let fresh = try await api.bootstrap()
        if fresh.version != known { updated = true }
      } catch {
        logger.error("Checking Ember's version failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /** Closes the updated notice until Ember is updated again. */
  public func closeUpdatedNotice() { updated = false }

  /** Reload: the version Ember runs now, its rooms and people again, and the open room's socket afresh. */
  public func reloadAfterUpdate() {
    updated = false
    Task {
      do {
        bootstrap = try await api.bootstrap()
      } catch {
        fail("Reloading", error)
      }
      reloadEverything()
      selectedRoom?.deactivate()
      switchBuffer(from: nil)
    }
  }

  func loadClosedNotice() {
    movedNoticeClosed = UserDefaults.standard.string(forKey: "ircX.movedClosed.\(id.uuidString)")
  }
}

/** A page an instance shows in place of a room (web `WorkspacePage`s other than rooms). */
public enum SessionPage: Hashable, Sendable {
  /** A search's results, which its address holds, so Back and Forward ask it again. */
  case search(Search, SearchSort)
  case person(UserID)
  /** Your profile (web `/users/me/profile`). */
  case profile
  /** A shared room's settings, or a DM's. */
  case settings(RoomID)
  /** The huddles going on, and recent ones. */
  case huddles
  /** Notifications: this device's switch, and the devices and browsers notified (web `/users/me/push_subscriptions`). */
  case pushSubscriptions
  /** A room that couldn't be looked for, saying why, with Try again (web's message page with `reason`). */
  case unavailable(String, RoomID, messageId: String?, threadId: String?)
}

extension SessionPage {
  var isSearch: Bool {
    if case .search = self { return true }
    return false
  }
}

/** Where Back and Forward go within an instance. */
public enum Destination: Hashable, Sendable {
  case room(RoomID)
  case page(SessionPage)
}

extension WorkspaceFrame {
  /** The room a frame is about, for `askForRoom`'s tickets. */
  var roomId: RoomID? {
    switch self {
    case let .roomSaved(room): room.id
    case let .roomGone(id), let .roomUnread(id, _, _), let .roomRead(id), let .roomActive(id, _), let .roomHuddle(id, _),
      let .roomInvolvement(id, _):
      id
    default: nil
    }
  }
}
