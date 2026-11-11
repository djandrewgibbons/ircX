import EmberKit
import SwiftUI

/** The instance's channels and DMs, as Slack's sidebar lists them, written as an IRC client's window list. */
struct ChannelSidebar: View {
  let app: AppModel
  @Bindable var session: InstanceSession
  @Environment(\.theme) private var theme
  @State private var joining = false
  @State private var querying = false
  @State private var prompt = ""
  @State private var showingSettings = false

  var body: some View {
    VStack(spacing: 0) {
      #if os(iOS)
      InstanceRail(app: app, horizontal: true)
      #endif
      header
      List(selection: $session.selectedRoomID) {
        if !session.starred.isEmpty {
          section("Starred", session.starred)
        }
        section("Channels", session.channels, add: { joining = true })
        section("Direct messages", session.directs, add: { querying = true })
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
    .background(theme.sidebar)
    .sheet(isPresented: $showingSettings) {
      NavigationStack { SettingsView().navigationTitle("Settings") }
    }
    .alert("Join a channel", isPresented: $joining) {
      promptField("#channel")
      Button("Join") {
        let name = takePrompt()
        if !name.isEmpty { Task { try? await session.join(name.hasPrefix("#") ? String(name.dropFirst()) : name) } }
      }
      Button("Cancel", role: .cancel) { prompt = "" }
    }
    .alert("Message someone", isPresented: $querying) {
      promptField("nick")
      Button("Open") {
        let nick = takePrompt()
        if !nick.isEmpty { Task { _ = try? await session.query(nick) } }
      }
      Button("Cancel", role: .cancel) { prompt = "" }
    }
  }

  private func promptField(_ placeholder: String) -> some View {
    TextField(placeholder, text: $prompt)
      .autocorrectionDisabled()
      #if os(iOS)
      .textInputAutocapitalization(.never)
      #endif
  }

  private func takePrompt() -> String {
    defer { prompt = "" }
    return prompt.trimmingCharacters(in: .whitespaces)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(session.name).font(Theme.font(15, weight: .bold)).lineLimit(1)
        HStack(spacing: 6) {
          Circle().fill(session.socketState == .open ? theme.join : Color.yellow).frame(width: 7, height: 7)
          Text(session.me?.name ?? "").font(Theme.font(11)).foregroundStyle(theme.dim)
          Text(session.instance.host).font(Theme.font(11)).foregroundStyle(theme.dim.opacity(0.7)).lineLimit(1)
        }
      }
      Spacer()
      Button {
        app.showingSwitcher = true
      } label: {
        Image(systemName: "magnifyingglass")
      }
      .buttonStyle(.plain)
      .foregroundStyle(theme.dim)
      .help("Jump to… (⌘K)")
      #if os(iOS)
      Button {
        showingSettings = true
      } label: {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.plain)
      .foregroundStyle(theme.dim)
      #endif
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .overlay(alignment: .bottom) { Rectangle().fill(theme.faint).frame(height: 1) }
  }

  private func section(_ title: String, _ rooms: [SidebarRoom], add: (() -> Void)? = nil) -> some View {
    Section {
      ForEach(rooms) { item in
        RoomRow(session: session, item: item)
          .tag(item.id)
          .listRowBackground(session.selectedRoomID == item.id ? theme.ember.opacity(0.22) : Color.clear)
          .contextMenu { menu(for: item) }
      }
    } header: {
      HStack {
        Text(title.uppercased()).font(Theme.font(10, weight: .semibold)).foregroundStyle(theme.dim)
        Spacer()
        if let add {
          Button(action: add) { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(theme.dim)
        }
      }
    }
  }

  @ViewBuilder
  private func menu(for item: SidebarRoom) -> some View {
    Button(session.favorites.contains(item.id) ? "Unstar" : "Star") { session.toggleFavorite(item.id) }
    Menu("Notify me about") {
      ForEach([Involvement.everything, .mentions, .nothing], id: \.self) { level in
        Button {
          session.setInvolvement(level, for: item.id)
        } label: {
          if item.involvement == level { Label(level.label, systemImage: "checkmark") } else { Text(level.label) }
        }
      }
    }
    Button("Hide from sidebar") { session.setInvolvement(.invisible, for: item.id) }
  }
}

struct RoomRow: View {
  let session: InstanceSession
  let item: SidebarRoom
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: 6) {
      Text(prefix)
        .font(Theme.font(13))
        .foregroundStyle(item.room.isDirect ? presenceColor : theme.dim)
        .frame(width: 14, alignment: .center)
      Text(session.title(of: item.room))
        .font(Theme.font(13, weight: item.unread ? .bold : .regular))
        .foregroundStyle(item.unread ? theme.text : theme.text.opacity(muted ? 0.45 : 0.75))
        .lineLimit(1)
      Spacer(minLength: 0)
      if item.unread, item.involvement == .everything || item.room.isDirect {
        Circle().fill(theme.ember).frame(width: 7, height: 7)
      }
      if item.involvement == .nothing {
        Image(systemName: "bell.slash").font(.system(size: 10)).foregroundStyle(theme.dim)
      }
    }
    .padding(.vertical, 1)
  }

  private var muted: Bool { item.involvement == .nothing }

  private var prefix: String {
    switch item.room.kind {
    case .open: "#"
    case .closed: "&"
    case .direct: "@"
    }
  }

  private var presenceColor: Color { theme.nick(otherID ?? item.id) }

  private var otherID: UserID? {
    item.room.members?.first { $0.id != session.me?.id }?.id
  }
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
