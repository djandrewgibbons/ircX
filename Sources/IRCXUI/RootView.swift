import EmberKit
import SwiftUI

/**
 * Slack's layout in IRC's clothes: a rail of instances, the selected one's channels and DMs, and the
 * open buffer, with a thread or the nick list beside it. On iPhone the rail sits atop the sidebar.
 */
public struct RootView: View {
  @Bindable var app: AppModel
  @Environment(\.theme) private var theme
  @Environment(\.horizontalSizeClass) private var sizeClass

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
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
    .sheet(isPresented: $app.showingAddInstance) {
      AddInstanceView(app: app)
    }
    .sheet(isPresented: $app.showingSwitcher) {
      QuickSwitcher(app: app)
    }
    .task { await app.start() }
  }

  @ViewBuilder
  private var workspace: some View {
    if let session = app.selected {
      InstanceView(app: app, session: session)
        .id(session.id)
    } else {
      EmptyState(title: "No servers", detail: "Add an Ember instance, such as irc.dxnd.ai, with /server or the + button.") {
        app.showingAddInstance = true
      }
    }
  }
}

/** One instance: signing in, or its sidebar and buffer. */
struct InstanceView: View {
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
      SignInView(app: app, session: session)
    case let .unreachable(reason):
      EmptyState(title: "Can't reach \(session.instance.host)", detail: reason, action: "Try again") {
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
          EmptyState(title: session.name, detail: "Pick a channel, or /join #room.")
        }
      }
      .navigationSplitViewStyle(.balanced)
    }
  }
}

struct EmptyState: View {
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
