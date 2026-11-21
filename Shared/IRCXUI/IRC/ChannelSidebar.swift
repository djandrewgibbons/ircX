import EmberKit
import SwiftUI

/** The instance's channels and DMs, as Slack's sidebar lists them, written as an IRC client's window list. */
struct ChannelSidebar: View {
  let app: AppModel
  @Bindable var session: InstanceSession
  @Environment(\.theme) private var theme
  @State private var showingSettings = false

  var body: some View {
    VStack(spacing: 0) {
      #if os(iOS)
      InstanceRail(app: app, horizontal: true)
      #endif
      header
      if let failure = session.sidebarFailure {
        // A failed load keeps the last list, saying why; a click tries again.
        line("-!- \(failure) [try again]", color: theme.part, clear: session.retryLoading)
      } else if let notice = session.notice {
        line("*** \(notice)", color: theme.part) { session.clearNotice() }
      }
      List(selection: Binding(get: { session.selectedRoomID }, set: { id in
        guard let id else { return }
        session.open(room: id)
        // Following a link in the sidebar turns Activity off (web `showAllForLink`).
        session.showingActivity = false
      })) {
        if session.account?.huddles == true, !session.showingActivity {
          huddlesRow
        }
        Section {
          // The starred windows drag among themselves; the rest follow the workspace order.
          ForEach(starredRooms) { row($0) }
            .onMove { from, to in
              let starred = starredRooms
              session.dropStars(from.map { starred[$0].id }, before: to < starred.count ? starred[to].id : nil)
            }
          ForEach(otherRooms) { row($0) }
        } header: {
          sectionHeader("Rooms", add: session.canCreateRooms ? { session.showingNewRoom = true } : nil)
        }
        Section {
          ForEach(session.listedDirects) { row($0) }
        } header: {
          sectionHeader("DMs", add: { session.showingNewDirect = true })
        }
        if session.listedRooms.isEmpty, session.listedDirects.isEmpty {
          Group {
            if session.sidebarLoaded {
              Text(session.showingActivity ? NavigationText.caughtUp : NavigationText.noConversations)
            } else if session.sidebarFailure == nil {
              Text("Loading rooms…")
            }
          }
          .font(Theme.font(11))
          .foregroundStyle(theme.dim)
          .listRowBackground(Color.clear)
        }
        if agentsToAsk > 0, !session.showingActivity {
          Button {
            session.showingAgents = true
          } label: {
            HStack {
              Text("\(NavigationText.availableAgents) (\(agentsToAsk))")
              Spacer()
              Text(">")
            }
            .font(Theme.font(11))
            .foregroundStyle(theme.dim)
          }
          .buttonStyle(.plain)
          .listRowBackground(Color.clear)
          .accessibilityLabel(NavigationText.agentsToAsk(agentsToAsk))
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      if let status = session.orderStatus {
        line("-!- \(status)", color: status == NavigationText.orderFailed ? theme.part : theme.join) { session.clearOrderStatus() }
      }
    }
    .background(theme.sidebar)
    .sheet(isPresented: $showingSettings) {
      NavigationStack { SettingsView().navigationTitle("Settings") }
    }
  }

  /** A line of the server's to say, as an IRC client prints one: click to clear it. */
  private func line(_ text: String, color: Color, clear: @escaping () -> Void) -> some View {
    Button(action: clear) {
      Text(text)
        .font(Theme.font(11))
        .foregroundStyle(color)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 14)
    .padding(.vertical, 6)
    .help(text)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(session.name).font(Theme.font(15, weight: .bold)).lineLimit(1)
        if let tagline = session.account?.tagline, !tagline.isEmpty {
          Text(tagline).font(Theme.font(11)).foregroundStyle(theme.dim).lineLimit(1)
        }
        HStack(spacing: 6) {
          Circle().fill(session.socketState == .open ? theme.join : Color.yellow).frame(width: 7, height: 7)
          if let me = session.me { Text(me.name).font(Theme.font(11)).foregroundStyle(theme.dim).lineLimit(1).layoutPriority(1) }
          Text(session.instance.host).font(Theme.font(11)).foregroundStyle(theme.dim.opacity(0.7)).lineLimit(1)
        }
      }
      Spacer()
      headerButton("square.and.pencil", help: "New direct message (/query)") { session.showingNewDirect = true }
      headerButton("magnifyingglass", help: "Search (/search)") { session.openSearchBox(in: nil) }
      Button {
        session.toggleActivity()
      } label: {
        Text(session.activityCount > 0 ? "[\(session.activityCount)]" : "[act]")
          .font(Theme.font(11, weight: session.showingActivity ? .bold : .regular))
      }
      .buttonStyle(.plain)
      .foregroundStyle(session.showingActivity || session.activityCount > 0 ? theme.ember : theme.dim)
      .help(session.showingActivity ? "Show every conversation (/activity)" : "Activity: only unread conversations (/activity)")
      Menu {
        SuiteWorkspaceItems(app: app, session: session)
        #if os(iOS)
        Button("Settings", systemImage: "gearshape") { showingSettings = true }
        #endif
      } label: {
        Text(session.workspaceNotice == nil ? "[...]" : "[*..]")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .foregroundStyle(session.workspaceNotice == nil ? theme.dim : theme.ember)
      .help(session.workspaceNotice ?? "Workspace, /admin")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .overlay(alignment: .bottom) { Rectangle().fill(theme.faint).frame(height: 1) }
  }

  private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol) }
      .buttonStyle(.plain)
      .foregroundStyle(theme.dim)
      .help(help)
  }

  private var starredRooms: [SidebarRoom] { session.listedRooms.filter { session.isStarred($0.id) } }
  private var otherRooms: [SidebarRoom] { session.listedRooms.filter { !session.isStarred($0.id) } }

  /** How many AI agents this person can ask, once the people directory has loaded (`agentsToAsk`). */
  private var agentsToAsk: Int {
    guard session.peopleLoaded, let me = session.me else { return 0 }
    return PeopleList.agentsToAsk(session.people.values, me: me).count
  }

  private func row(_ item: SidebarRoom) -> some View {
    RoomRow(session: session, item: item)
      .tag(item.id)
      .listRowBackground(session.selectedRoomID == item.id && session.page == nil ? theme.ember.opacity(0.22) : Color.clear)
      .contextMenu { SuiteRoomMenu(session: session, item: item) }
      #if os(iOS)
      .swipeActions(edge: .trailing) { SuiteRoomSwipeActions(session: session, item: item) }
      #endif
  }

  /** Huddles: the page of huddles, with how many are going on, in green (web `HuddlesRow`). */
  private var huddlesRow: some View {
    let going = HuddleList.goingOn(session.rooms, live: session.huddles).count
    return Button {
      session.show(.huddles)
    } label: {
      HStack(spacing: 6) {
        Text("~").frame(width: 14).foregroundStyle(theme.dim)
        Text(NavigationText.huddles).foregroundStyle(session.page == .huddles ? theme.text : theme.text.opacity(0.75))
        Spacer(minLength: 0)
        if going > 0 { Text("[\(going > 99 ? "99+" : String(going))]").foregroundStyle(theme.join) }
      }
      .font(Theme.font(13, weight: session.page == .huddles ? .bold : .regular))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(session.page == .huddles ? theme.ember.opacity(0.22) : Color.clear)
    .accessibilityLabel(going > 0 ? NavigationText.huddlesHappening(going) : NavigationText.huddles)
  }

  private func sectionHeader(_ title: String, add: (() -> Void)?) -> some View {
    HStack {
      Text(title.uppercased()).font(Theme.font(10, weight: .semibold)).foregroundStyle(theme.dim)
      Spacer()
      if let add {
        Button(action: add) { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(theme.dim)
          .help(title == "Rooms" ? "New room (/newroom)" : "New direct message (/query)")
      }
    }
    .help(title == "Rooms" ? NavigationText.starHint : "")
  }
}

struct RoomRow: View {
  let session: InstanceSession
  let item: SidebarRoom
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: 6) {
      Group {
        if !item.room.isDirect, item.room.icon != nil {
          RoomIconView(api: session.api, room: item.room, size: 12).foregroundStyle(theme.dim)
        } else {
          Text(prefix)
            .font(Theme.font(13))
            .foregroundStyle(item.room.isDirect ? presenceColor : theme.dim)
            .help(presenceHelp)
        }
      }
      .frame(width: 14, alignment: .center)
      Text(name)
        .font(Theme.font(13, weight: marked ? .bold : .regular))
        .foregroundStyle(marked ? theme.text : theme.text.opacity(0.75))
        .lineLimit(1)
      if session.isWithAgent(item.room) {
        Text("[agent]").font(Theme.font(10)).foregroundStyle(theme.action)
      }
      Spacer(minLength: 0)
      if let huddle = session.huddles[item.id] {
        Text("[H\(huddle.userIds.count)]").font(Theme.font(11)).foregroundStyle(theme.join)
          .help(huddle.userIds.compactMap { session.people[$0]?.name }.joined(separator: ", "))
      }
      if marked, item.room.isDirect, let count = item.unreadCount {
        Text("(\(count > 99 ? "99+" : String(count)))").font(Theme.font(11)).foregroundStyle(theme.ember)
      } else if marked {
        Circle().fill(theme.ember).frame(width: 7, height: 7)
      }
      if item.involvement == .nothing {
        Text("(m)").font(Theme.font(10)).foregroundStyle(theme.dim).help(Involvement.nothing.sentence)
      }
      if session.isStarred(item.id) {
        Text("*").font(Theme.font(12, weight: .bold)).foregroundStyle(theme.ember).help("Favorite")
      }
    }
    .padding(.vertical, 1)
  }

  private var marked: Bool { session.isMarkedUnread(item) }

  /** A DM's others' names with ", ", and "(you)" in your DM with yourself. */
  private var name: String {
    guard item.room.isDirect else { return session.title(of: item.room) }
    let shown = RoomList.membersShown(item.room, me: session.me?.id)
    let names = shown.map { session.people[$0.id]?.name ?? $0.name }.joined(separator: ", ")
    return shown.count == 1 && shown.first?.id == session.me?.id ? "\(names) (you)" : names
  }

  /** Active, away, or not yet known, for a DM with one other human. */
  private var presence: Bool? { session.presenceShown(in: item.room).flatMap(session.presence(of:)) }

  private var presenceHelp: String {
    guard let presence else { return item.room.isDirect ? "DM" : "" }
    return presence ? "Active" : "Away"
  }

  /** `#` open, `&` private, `@` a DM: `+` while its one other person is active, `-` while they're away. */
  private var prefix: String {
    switch item.room.kind {
    case .open: "#"
    case .closed: "&"
    case .direct:
      switch presence {
      case true?: "+"
      case false?: "-"
      case nil: "@"
      }
    }
  }

  /** A DM's mark is green while the other person is active, dim while they're away or unknown. */
  private var presenceColor: Color { presence == true ? theme.join : theme.dim }
}

extension Involvement {
  var label: String {
    switch self {
    case .everything: "Every message"
    case .mentions: "Mentions only"
    case .nothing: "Nothing"
    case .invisible: "Hidden"
    }
  }
}
