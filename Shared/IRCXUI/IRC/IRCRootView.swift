import EmberKit
import SwiftUI

/**
 * The IRC Classic theme: Slack's layout in IRC's clothes, a rail of instances, the selected one's
 * channels and DMs, and the open buffer, with a thread or the nick list beside it. On iPhone the
 * rail sits atop the sidebar.
 */
struct IRCRootView: View {
  @Bindable var app: AppModel
  @Environment(\.theme) private var theme

  var body: some View {
    Group {
      #if os(macOS)
      HStack(spacing: 0) {
        InstanceRail(app: app)
        Divider().overlay(theme.faint)
        workspace
      }
      #else
      workspace
      #endif
    }
    .background(theme.buffer)
    .foregroundStyle(theme.text)
    .preferredColorScheme(.dark)
    .tint(theme.ember)
  }

  @ViewBuilder
  private var workspace: some View {
    if let session = app.selected {
      IRCInstanceView(app: app, session: session)
        .id(session.id)
    } else {
      IRCEmptyState(title: "No servers", detail: "Add an Ember instance, such as irc.dxnd.ai, with /server or the + button.") {
        app.showingAddInstance = true
      }
    }
  }
}

/** One instance: signing in, or its sidebar and buffer. */
struct IRCInstanceView: View {
  let app: AppModel
  @Bindable var session: InstanceSession
  @Environment(\.theme) private var theme
  @State private var columns = NavigationSplitViewVisibility.all

  var body: some View {
    switch session.phase {
    case .checking:
      VStack(spacing: 12) {
        ProgressView().controlSize(.small)
        Text("Connecting to \(session.instance.host)…").font(Theme.font(12)).foregroundStyle(theme.dim)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.buffer)
    case .signedOut:
      IRCSignInView(app: app, session: session)
    case let .unreachable(reason):
      IRCEmptyState(title: "Can't reach \(session.instance.host)", detail: reason, action: "Try again") {
        Task { await session.start() }
      }
    case .ready:
      NavigationSplitView(columnVisibility: $columns) {
        ChannelSidebar(app: app, session: session)
          .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
      } detail: {
        if let room = session.selectedRoom {
          BufferView(app: app, session: session, room: room)
            .id(room.id)
        } else {
          IRCEmptyState(title: session.name, detail: "Pick a channel, or /join #room.")
        }
      }
      .navigationSplitViewStyle(.balanced)
    }
  }
}

struct IRCEmptyState: View {
  let title: String
  let detail: String
  var action: String = "Add server"
  var perform: (() -> Void)?
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(spacing: 10) {
      Text("-!- \(title)").font(Theme.font(14, weight: .semibold)).foregroundStyle(theme.ember)
      Text(detail).font(Theme.font(12)).foregroundStyle(theme.dim).multilineTextAlignment(.center)
      if let perform {
        Button(action, action: perform).buttonStyle(.bordered).font(Theme.font(12))
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.buffer)
  }
}
