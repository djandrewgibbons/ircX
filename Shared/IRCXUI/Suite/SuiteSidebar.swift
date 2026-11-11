import AppCoreUI
import EmberKit
import SwiftUI

/** A server's channels and DMs, in the suite's list column: starred first, then channels, then DMs. */
struct SuiteSidebar: View {
  let app: AppModel
  @Bindable var session: InstanceSession
  @Environment(\.suiteTheme) private var theme
  @State private var joining = false
  @State private var querying = false
  @State private var prompt = ""
  #if os(iOS)
  @State private var showingSettings = false
  #endif

  var body: some View {
    VStack(spacing: 0) {
      #if os(macOS)
      PaneHeaderBar(title: session.name) {
        PaneIconButton(systemImage: "magnifyingglass", help: "Jump To") { app.showingSwitcher = true }
      }
      #endif
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if !session.starred.isEmpty {
            section("Starred", session.starred)
          }
          section("Channels", session.channels, add: ("Join Channel", { joining = true }))
          section("Direct Messages", session.directs, add: ("New Message", { querying = true }))
        }
        .padding(.bottom, Spacing.lg)
      }
      .scrollFade()
      #if os(macOS)
      PaneFooterBar {
        Image(systemName: "circle.fill")
          .font(DesignFont.detail)
          .foregroundStyle(session.socketState == .open ? SemanticColor.positive : SemanticColor.warning)
          .help(session.socketState == .open ? "Connected" : "Reconnecting")
        Text(session.me?.name ?? session.instance.host).font(DesignFont.detail).foregroundStyle(.secondary).lineLimit(1)
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
        Button("Jump To", systemImage: "magnifyingglass") { app.showingSwitcher = true }
        Button("Settings", systemImage: "gearshape") { showingSettings = true }
      }
    }
    .sheet(isPresented: $showingSettings) {
      NavigationStack { SettingsView().navigationTitle("Settings") }
    }
    #endif
    .alert("Join Channel", isPresented: $joining) {
      TextField("Channel", text: $prompt).autocorrectionDisabled()
      Button("Join") {
        let name = takePrompt()
        if !name.isEmpty { Task { try? await session.join(name.hasPrefix("#") ? String(name.dropFirst()) : name) } }
      }
      Button("Cancel", role: .cancel) { prompt = "" }
    }
    .alert("New Message", isPresented: $querying) {
      TextField("Name", text: $prompt).autocorrectionDisabled()
      Button("Open") {
        let nick = takePrompt()
        if !nick.isEmpty { Task { _ = try? await session.query(nick) } }
      }
      Button("Cancel", role: .cancel) { prompt = "" }
    }
  }

  private func takePrompt() -> String {
    defer { prompt = "" }
    return prompt.trimmingCharacters(in: .whitespaces)
  }

  @ViewBuilder
  private func section(_ title: String, _ rooms: [SidebarRoom], add: (String, () -> Void)? = nil) -> some View {
    HStack {
      ListSectionHeader(title)
      Spacer()
      if let add {
        PaneIconButton(systemImage: "plus", help: add.0, action: add.1)
          .padding(.trailing, PaneGrid.leadingEdge)
          .padding(.top, Spacing.lg)
      }
    }
    ForEach(rooms) { item in
      SelectableListRow(isSelected: session.selectedRoomID == item.id) {
        session.selectedRoomID = item.id
      } label: {
        ListRowLabel(title: session.title(of: item.room), systemImage: item.room.symbol, iconColor: item.unread ? theme.accent : .secondary)
          .opacity(item.involvement == .nothing ? 0.5 : 1)
      } trailing: {
        ReservedSlot(width: Spacing.md, height: Spacing.md) {
          Circle()
            .fill(theme.accent)
            .opacity(item.unread && item.involvement != .nothing ? 1 : 0)
        }
      }
      .contextMenu { roomMenu(item) }
    }
  }

  @ViewBuilder
  private func roomMenu(_ item: SidebarRoom) -> some View {
    let starred = session.favorites.contains(item.id)
    Button(starred ? "Unstar" : "Star", systemImage: starred ? "star.slash" : "star") { session.toggleFavorite(item.id) }
    Picker("Notify Me About", selection: Binding(get: { item.involvement }, set: { session.setInvolvement($0, for: item.id) })) {
      ForEach([Involvement.everything, .mentions, .nothing], id: \.self) { Text($0.title).tag($0) }
    }
    Button("Hide", systemImage: "eye.slash") { session.setInvolvement(.invisible, for: item.id) }
  }
}

extension Involvement {
  /** The level in Title Case, as the suite writes labels. */
  var title: String {
    switch self {
    case .everything: "Every Message"
    case .mentions: "Mentions Only"
    case .nothing: "Nothing"
    case .invisible: "Hidden"
    }
  }
}
