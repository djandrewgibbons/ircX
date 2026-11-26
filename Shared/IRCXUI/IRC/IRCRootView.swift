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
      .toolbar {
        ToolbarItemGroup(placement: .navigation) {
          Button("Back", systemImage: "chevron.backward", action: app.goBack).disabled(!app.canGoBack).help("Back (⌘[, /back)")
          Button("Forward", systemImage: "chevron.forward", action: app.goForward).disabled(!app.canGoForward).help("Forward (⌘], /forward)")
        }
        ToolbarItem(placement: .principal) {
          Text("[\(app.windowTitle)]").font(Theme.font(12, weight: .semibold)).foregroundStyle(theme.text)
        }
        .sharedBackgroundVisibility(.hidden)
      }
      .toolbarBackground(theme.statusBar, for: .windowToolbar)
      #else
      workspace
      #endif
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // Going to any other page minimizes the huddle to its bar (web workspace.tsx).
        .onChange(of: session.destination) { app.huddles.call?.setOpen(false) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if let call = app.huddles.call, !call.isOpen || call.session !== session { IRCHuddleBar(call: call) }
        }
        .overlay(alignment: .topTrailing) { IRCHuddleInvitations(center: app.huddles, ringing: app.huddles.ringing) }
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
    case .notSetUp:
      SetupView(session: session)
    case let .unreachable(reason):
      IRCEmptyState(title: "Can't reach \(session.instance.host)", detail: reason, action: "Try again") {
        Task { await session.start() }
      }
    case .ready:
      NavigationSplitView(columnVisibility: $columns) {
        ChannelSidebar(app: app, session: session)
          .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
      } detail: {
        VStack(spacing: 0) {
          InstanceNotices(app: app, session: session)
          if let call = app.huddles.call, call.session === session, call.isOpen {
            IRCHuddleView(app: app, call: call)
          } else if let page = session.page {
            SessionPageView(session: session, page: page)
          } else if let room = session.selectedRoom {
            BufferView(app: app, session: session, room: room)
              .id(room.id)
          } else if !session.sidebarLoaded {
            SidebarLoadingState(session: session)
          } else {
            IRCEmptyState(title: NavigationText.noRoomsYet, detail: "/join #room, or /newroom #name.")
          }
        }
        .instanceSheets(session, app: app)
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
