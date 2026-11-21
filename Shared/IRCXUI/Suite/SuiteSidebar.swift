import AppCoreUI
import EmberKit
import SwiftUI

/**
 * A server's rooms and DMs, in the suite's list column, as the web's sidebar lists them: its name and
 * tagline, the rail's entries (New Message, Search, Activity and a menu), the rooms with the starred first,
 * then the DMs.
 */
struct SuiteSidebar: View {
  let app: AppModel
  @Bindable var session: InstanceSession
  @Environment(\.suiteTheme) private var theme
  #if os(iOS)
  @State private var showingSettings = false
  #endif

  var body: some View {
    VStack(spacing: 0) {
      #if os(macOS)
      PaneHeaderBar {
        VStack(alignment: .leading, spacing: 0) {
          Text(session.name).font(DesignFont.cardTitle).lineLimit(1)
          if let tagline = session.account?.tagline, !tagline.isEmpty {
            Text(tagline).font(DesignFont.detail).foregroundStyle(.secondary).lineLimit(1)
          }
        }
      } trailing: {
        PaneIconButton(systemImage: "square.and.pencil", help: "New direct message") { session.showingNewDirect = true }
        PaneIconButton(systemImage: "magnifyingglass", help: "Search") { session.openSearchBox(in: nil) }
        activityButton
        SuiteWorkspaceMenu(app: app, session: session)
      }
      #endif
      if let failure = session.sidebarFailure {
        // A failed load keeps the last list, saying why, with Try again.
        Notice(failure, systemImage: "exclamationmark.triangle.fill", tint: SemanticColor.destructive, actionTitle: "Try Again", action: session.retryLoading)
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.sm)
      } else if let notice = session.notice {
        Notice(notice, systemImage: "exclamationmark.triangle.fill", tint: SemanticColor.destructive, onDismiss: { session.clearNotice() })
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.sm)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if session.account?.huddles == true, !session.showingActivity {
            huddlesRow
          }
          header("Rooms", systemImage: "number", add: session.canCreateRooms ? ("New room", { session.showingNewRoom = true }) : nil)
            .help(NavigationText.starHint)
          // The starred rooms drag among themselves; the rest follow the workspace order.
          if #available(macOS 27, iOS 27, *) {
            ForEach(starredRooms) { row($0) }
              .reorderable()
          } else {
            ForEach(starredRooms) { row($0) }
          }
          ForEach(otherRooms) { row($0) }
          header("DMs", systemImage: "bubble.left.and.bubble.right", add: ("New direct message", { session.showingNewDirect = true }))
          ForEach(session.listedDirects) { row($0) }
          if session.listedRooms.isEmpty, session.listedDirects.isEmpty {
            if session.sidebarLoaded {
              Text(session.showingActivity ? NavigationText.caughtUp : NavigationText.noConversations)
                .font(DesignFont.detail)
                .foregroundStyle(.secondary)
                .padding(.horizontal, PaneGrid.leadingEdge)
                .padding(.top, Spacing.md)
            } else if session.sidebarFailure == nil {
              ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, Spacing.md)
            }
          }
          if agentsToAsk > 0, !session.showingActivity {
            agentsRow
          }
        }
        .padding(.bottom, Spacing.lg)
        .modifier(StarReordering(session: session))
      }
      .scrollFade()
      #if os(iOS)
      .modifier(SwipeActionsContainer())
      #endif
      if let status = session.orderStatus {
        Notice(
          status, systemImage: status == NavigationText.orderFailed ? "exclamationmark.triangle.fill" : "checkmark.circle",
          tint: status == NavigationText.orderFailed ? SemanticColor.warning : SemanticColor.positive, onDismiss: { session.clearOrderStatus() })
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.sm)
      }
      #if os(macOS)
      PaneFooterBar {
        Image(systemName: "circle.fill")
          .font(DesignFont.detail)
          .foregroundStyle(session.socketState == .open ? SemanticColor.positive : SemanticColor.warning)
          .help(session.socketState == .open ? "Connected" : "Reconnecting")
        Button {
          session.show(.profile)
        } label: {
          Text(session.me?.name ?? session.instance.host).font(DesignFont.detail).foregroundStyle(.secondary).lineLimit(1)
        }
        .buttonStyle(.plain)
        .help("Your profile")
      }
      #endif
    }
    #if os(iOS)
    .navigationTitle(session.name)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Menu {
          ForEach(app.sessions) { other in
            Button(other.name, systemImage: other.id == session.id ? "checkmark" : other.railSymbol) { app.selectedID = other.id }
          }
          Divider()
          Button("Add Server", systemImage: "plus") { app.showingAddInstance = true }
          SuiteServerMenu(app: app, session: session)
        } label: {
          Label("Servers", systemImage: "server.rack")
        }
      }
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Search", systemImage: "magnifyingglass") { session.openSearchBox(in: nil) }
        activityButton
        Menu {
          SuiteWorkspaceItems(app: app, session: session)
          Divider()
          Button("Settings", systemImage: "gearshape") { showingSettings = true }
        } label: {
          Label("More", systemImage: "ellipsis.circle")
        }
      }
      ToolbarItem(placement: .bottomBar) {
        Button("New direct message", systemImage: "square.and.pencil") { session.showingNewDirect = true }
      }
    }
    .sheet(isPresented: $showingSettings) {
      NavigationStack { SettingsView().navigationTitle("Settings") }
    }
    #endif
  }

  /** Activity (web rail): pressed while only unread conversations show, with how many there are in an ink pill, hidden at none. */
  private var activityButton: some View {
    let count = session.activityCount
    return PaneIconButton(systemImage: session.showingActivity ? "bell.fill" : "bell", help: "Show unread conversations") {
      session.toggleActivity()
    }
    .overlay(alignment: .topTrailing) {
      if count > 0 {
        CountPill(count: count, tint: Color.primary)
          .offset(x: Spacing.sm, y: -Spacing.xs)
          .allowsHitTesting(false)
      }
    }
    .accessibilityLabel("Activity")
    .accessibilityValue(count > 0 ? "\(count) unread" : "")
    .accessibilityAddTraits(session.showingActivity ? .isSelected : [])
  }

  /** The starred rooms the list shows, which come first, and the rest. */
  private var starredRooms: [SidebarRoom] { session.listedRooms.filter { session.isStarred($0.id) } }
  private var otherRooms: [SidebarRoom] { session.listedRooms.filter { !session.isStarred($0.id) } }

  /** How many AI agents this person can ask, once the people directory has loaded (`agentsToAsk`). */
  private var agentsToAsk: Int {
    guard session.peopleLoaded, let me = session.me else { return 0 }
    return PeopleList.agentsToAsk(session.people.values, me: me).count
  }

  private func header(_ title: String, systemImage: String, add: (String, () -> Void)?) -> some View {
    HStack {
      ListSectionHeader(title, systemImage: systemImage)
      Spacer()
      if let add {
        PaneIconButton(systemImage: "plus", help: add.0, action: add.1)
          .padding(.trailing, PaneGrid.leadingEdge)
          .padding(.top, Spacing.lg)
      }
    }
  }

  private func row(_ item: SidebarRoom) -> some View {
    SelectableListRow(isSelected: session.selectedRoomID == item.id && session.page == nil) {
      session.open(room: item.id)
      // Following a link in the sidebar turns Activity off once it's gone there (web `showAllForLink`).
      session.showingActivity = false
    } label: {
      SuiteRoomRowLabel(session: session, item: item)
    } trailing: {
      SuiteRoomRowTrailing(session: session, item: item)
    }
    .contextMenu { SuiteRoomMenu(session: session, item: item) }
    #if os(iOS)
    .swipeActions(edge: .trailing) { SuiteRoomSwipeActions(session: session, item: item) }
    #endif
  }

  /** Huddles (web `HuddlesRow`): the page of huddles, with how many are going on, on green. */
  private var huddlesRow: some View {
    let going = HuddleList.goingOn(session.rooms, live: session.huddles).count
    return SelectableListRow(isSelected: session.page == .huddles) {
      session.show(.huddles)
    } label: {
      ListRowLabel(title: NavigationText.huddles, systemImage: "headphones")
    } trailing: {
      if going > 0 {
        CountPill(count: going, tint: SemanticColor.positive)
      }
    }
    .accessibilityLabel(going > 0 ? NavigationText.huddlesHappening(going) : NavigationText.huddles)
    .padding(.top, Spacing.sm)
  }

  /** Available Agents (web `AgentsRow`): opens the agents this person can ask, with how many. */
  private var agentsRow: some View {
    SelectableListRow(isSelected: session.showingAgents) {
      session.showingAgents = true
    } label: {
      HStack(spacing: Spacing.sm) {
        Text(NavigationText.availableAgents).font(DesignFont.detail).foregroundStyle(.secondary)
        CountPill(count: agentsToAsk, tint: SemanticColor.secondaryFill, ink: Color.secondary)
      }
    } trailing: {
      Image(systemName: "chevron.right").font(DesignFont.detail).foregroundStyle(.secondary)
    }
    .accessibilityLabel(NavigationText.agentsToAsk(agentsToAsk))
    .padding(.top, Spacing.md)
  }
}

/**
 * Dragging a starred room among the starred (web `useStarOrder`): announced as it starts, saved as it's
 * dropped, and "canceled" if it isn't.
 */
private struct StarReordering: ViewModifier {
  let session: InstanceSession

  func body(content: Content) -> some View {
    if #available(macOS 27, iOS 27, *) {
      content
        .reorderContainer(for: SidebarRoom.self) { difference in
          let before: RoomID?
          switch difference.destination.position {
          case let .before(id): before = id
          case .end: before = nil
          }
          session.dropStars(difference.sources, before: before)
        }
        .dragContainer(for: String.self, itemID: \.self) { ids in
          session.startedMovingStar(ids)
          return ids
        }
        .onDragSessionUpdated { drag in
          if case .ended = drag.phase { session.endedMovingStar() }
        }
    } else {
      content
    }
  }
}

#if os(iOS)
/** Rows' swipe actions in a scroll view, which iOS 27 coordinates. */
private struct SwipeActionsContainer: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 27, *) {
      content.swipeActionsContainer()
    } else {
      content
    }
  }
}
#endif

/** A count in a pill, 99+ at most, as the web counts unread DMs, huddles going on and agents. */
struct CountPill: View {
  let count: Int
  var tint: Color = SemanticColor.accent
  var ink: Color = SemanticColor.background

  var body: some View {
    Text(count > 99 ? "99+" : "\(count)")
      .font(DesignFont.detail.weight(.semibold).monospacedDigit())
      .foregroundStyle(ink)
      .padding(.horizontal, Spacing.xs)
      .frame(minWidth: Spacing.lg)
      .background(tint, in: Capsule())
      .accessibilityHidden(true)
  }
}

/** A row's swipe actions on iOS: star or unstar, and hide (web header controls). */
struct SuiteRoomSwipeActions: View {
  let session: InstanceSession
  let item: SidebarRoom

  var body: some View {
    if !item.room.isDirect {
      Button("Hide", systemImage: "eye.slash") { session.setInvolvement(.invisible, for: item.id) }
        .tint(Color.secondary)
      let starred = session.isStarred(item.id)
      Button(starred ? "Unstar" : "Star", systemImage: starred ? "star.slash" : "star") { session.toggleFavorite(item.id) }
        .tint(Color.orange)
    }
  }
}

/** A row's leading content: a room's icon and name, or a DM's faces, presence and names. */
struct SuiteRoomRowLabel: View {
  let session: InstanceSession
  let item: SidebarRoom
  @Environment(\.suiteTheme) private var theme

  var body: some View {
    let marked = session.isMarkedUnread(item)
    HStack(spacing: PaneGrid.iconGap) {
      if item.room.isDirect {
        SuiteDirectFaces(session: session, room: item.room)
      } else {
        RoomIconView(api: session.api, room: item.room, size: PaneGrid.iconColumn)
          .foregroundStyle(marked ? theme.accent : Color.secondary)
      }
      Text(name)
        .font(marked ? DesignFont.bodyEmphasized : DesignFont.body)
        .lineLimit(1)
      if session.isWithAgent(item.room) { AgentBadge() }
    }
    .frame(height: 20)
  }

  /** A row's name: a room's own, or a DM's others' names with ", ", and "(you)" in your DM with yourself (web `DirectRow`). */
  private var name: String {
    guard item.room.isDirect else { return session.title(of: item.room) }
    let shown = RoomList.membersShown(item.room, me: session.me?.id)
    let names = shown.map { session.people[$0.id]?.name ?? $0.name }.joined(separator: ", ")
    return shown.count == 1 && shown.first?.id == session.me?.id ? "\(names) (you)" : names
  }
}

/** A DM's faces: the other person with their presence, or up to four in a grid for a group (`MAX_FACES`). */
struct SuiteDirectFaces: View {
  let session: InstanceSession
  let room: Room

  var body: some View {
    let shown = RoomList.membersShown(room, me: session.me?.id)
    Group {
      if shown.count == 1, let other = shown.first {
        SuiteAvatar(session: session, user: other, size: PaneGrid.iconColumn)
          .overlay(alignment: .bottomTrailing) {
            if let id = session.presenceShown(in: room), let active = session.presence(of: id) {
              Circle()
                .fill(active ? SemanticColor.positive : SemanticColor.background)
                .strokeBorder(active ? SemanticColor.background : Color.secondary, lineWidth: 1)
                .frame(width: Spacing.md, height: Spacing.md)
                .offset(x: Spacing.xxs, y: Spacing.xxs)
                .help(active ? "Active" : "Away")
                .accessibilityLabel(active ? "Active" : "Away")
            }
          }
      } else {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
          let faces = Array(shown.prefix(4))
          GridRow {
            ForEach(faces.prefix(2)) { SuiteAvatar(session: session, user: $0, size: PaneGrid.iconColumn / 2 - 0.5) }
          }
          if faces.count > 2 {
            GridRow {
              ForEach(faces.dropFirst(2)) { SuiteAvatar(session: session, user: $0, size: PaneGrid.iconColumn / 2 - 0.5) }
            }
          }
        }
      }
    }
    .frame(width: PaneGrid.iconColumn, height: PaneGrid.iconColumn)
  }
}

/** A row's end, in order: the huddle mark, the unread dot or a DM's count, and the star (web `RoomRow`). */
struct SuiteRoomRowTrailing: View {
  let session: InstanceSession
  let item: SidebarRoom
  @Environment(\.suiteTheme) private var theme

  var body: some View {
    let marked = session.isMarkedUnread(item)
    HStack(spacing: Spacing.xs) {
      if let huddle = session.huddles[item.id] {
        // The first two faces, the headphones and how many, in green (web `HuddleMark`).
        HStack(spacing: -Spacing.xs) {
          ForEach(huddle.userIds.prefix(2), id: \.self) { id in
            SuiteAvatar(session: session, user: session.people[id]?.user ?? User(id: id, name: id), size: Spacing.lg)
          }
        }
        .accessibilityHidden(true)
        Label("\(huddle.userIds.count)", systemImage: "headphones")
          .labelStyle(.titleAndIcon)
          .font(DesignFont.detail)
          .foregroundStyle(SemanticColor.positive)
          .help(huddle.userIds.compactMap { session.people[$0]?.name }.joined(separator: ", "))
      }
      if marked, item.room.isDirect, let count = item.unreadCount {
        Text(count > 99 ? "99+" : "\(count)")
          .font(DesignFont.detail.weight(.semibold))
          .foregroundStyle(SemanticColor.background)
          .padding(.horizontal, Spacing.xs)
          .background(theme.accent, in: Capsule())
          .help(count == 1 ? "1 unread message" : "\(count) unread messages")
      } else {
        ReservedSlot(width: Spacing.md, height: Spacing.md) {
          Circle()
            .fill(theme.accent)
            .opacity(marked ? 1 : 0)
        }
      }
      if session.isStarred(item.id) {
        Image(systemName: "star.fill")
          .font(DesignFont.detail)
          .foregroundStyle(.secondary)
          .help("Favorite")
      }
    }
  }
}

/** A row's context menu, the web's header controls on the row: star and its order, notifications, hide, settings. */
struct SuiteRoomMenu: View {
  let session: InstanceSession
  let item: SidebarRoom

  var body: some View {
    if !item.room.isDirect {
      let starred = session.isStarred(item.id)
      Button(starred ? "Remove from favorites" : "Add to favorites", systemImage: starred ? "star.slash" : "star") { session.toggleFavorite(item.id) }
      if starred {
        Button("Move Up", systemImage: "arrow.up") { session.moveStar(item.id, .up) }
        Button("Move Down", systemImage: "arrow.down") { session.moveStar(item.id, .down) }
      }
    }
    InvolvementMenu(session: session, item: item)
    Button(item.room.isDirect ? "Conversation settings" : "Room settings", systemImage: "gearshape") {
      session.selectedRoomID = item.id
      session.show(.settings(item.id))
    }
  }
}

/** The notification levels a room offers, with the web's sentences, the current one checked (web `InvolvementButton`). */
struct InvolvementMenu: View {
  let session: InstanceSession
  let item: SidebarRoom

  var body: some View {
    Picker("Notifications", selection: Binding(get: { item.involvement }, set: { session.setInvolvement($0, for: item.id) })) {
      ForEach(Involvement.choices(in: item.room, current: item.involvement), id: \.self) { level in
        Label(level.sentence, systemImage: level.symbol).tag(level)
      }
    }
    .disabled(session.involving.contains(item.id))
  }
}

extension Involvement {
  /** The bell's icon for each level (web `NotificationBell`). */
  var symbol: String {
    switch self {
    case .mentions: "at"
    case .everything: "bell.fill"
    case .nothing: "bell.slash"
    case .invisible: "eye.slash"
    }
  }
}

/** The workspace menu (the web rail's Home, Admin and profile), in the sidebar's header. */
struct SuiteWorkspaceMenu: View {
  let app: AppModel
  let session: InstanceSession

  var body: some View {
    Menu {
      SuiteWorkspaceItems(app: app, session: session)
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    // A dot while a newer Ember is out or reports are open, which Admin then says (web rail's Admin).
    .overlay(alignment: .topTrailing) {
      if session.workspaceNotice != nil {
        Circle().fill(Color.primary).frame(width: Spacing.sm, height: Spacing.sm).allowsHitTesting(false)
      }
    }
    .help(session.workspaceNotice.map { "More: \($0)" } ?? "More")
  }
}

struct SuiteWorkspaceItems: View {
  let app: AppModel
  let session: InstanceSession

  var body: some View {
    Button("Home", systemImage: "house") { session.goHome() }
    Button("Jump To", systemImage: "arrow.right.circle") { app.showingSwitcher = true }
    if session.canCreateRooms {
      Button("New room", systemImage: "plus.bubble") { session.showingNewRoom = true }
    }
    Divider()
    Button(action: { session.openWorkspaceSettings() }) {
      Label(session.me?.administrator == true ? "Admin" : "Workspace", systemImage: session.workspaceNotice == nil ? "building.2" : "building.2.fill")
      if let notice = session.workspaceNotice { Text(notice) }
    }
    if session.me != nil {
      Button("Your Profile", systemImage: "person.crop.circle") { session.show(.profile) }
      Button("Notifications", systemImage: "bell.badge") { session.show(.pushSubscriptions) }
    }
  }
}
