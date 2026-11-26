import AppCoreUI
import EmberKit
import SwiftUI

/**
 * The Suite theme: the dxnd suite's window, built on AppCoreUI. On the Mac, the icon rail holds the
 * servers and the canvas holds panel cards for the channel list, the conversation and its thread.
 * On iPhone and iPad it's a stock split view, with the servers in a menu.
 */
struct SuiteRootView: View {
  @Bindable var app: AppModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    #if os(macOS)
    HStack(spacing: 0) {
      SuiteServerRail(app: app)
      workspace
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding([.top, .bottom, .trailing], panelCardGutter)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(panelCanvasColor)
    .toolbar {
      ToolbarItemGroup(placement: .navigation) {
        Button("Back", systemImage: "chevron.backward", action: app.goBack)
          .disabled(!app.canGoBack)
          .help("Back (⌘[)")
        Button("Forward", systemImage: "chevron.forward", action: app.goForward)
          .disabled(!app.canGoForward)
          .help("Forward (⌘])")
      }
      ToolbarItem(placement: .principal) {
        Text(app.windowTitle)
          .font(DesignFont.body.weight(.medium))
          .foregroundStyle(.secondary)
      }
      .sharedBackgroundVisibility(.hidden)
    }
    .toolbarBackground(SuiteTheme.ircX.accent.opacity(colorScheme == .dark ? 0.35 : 0.12), for: .windowToolbar)
    .loadingActivityBar(color: SuiteTheme.ircX.accent)
    .tracksWindowVisibility()
    .suiteTheme(.ircX)
    #else
    workspace
      .loadingActivityBar(color: SuiteTheme.ircX.accent)
      .suiteTheme(.ircX)
    #endif
  }

  @ViewBuilder
  private var workspace: some View {
    if let session = app.selected {
      SuiteInstanceView(app: app, session: session)
        .id(session.id)
        // Going to any other page minimizes the huddle to its bar (web workspace.tsx).
        .onChange(of: session.destination) { app.huddles.call?.setOpen(false) }
        .safeAreaInset(edge: .bottom, spacing: panelCardGutter) {
          if let call = app.huddles.call, !call.isOpen || call.session !== session { SuiteHuddleBar(call: call) }
        }
        .overlay(alignment: .topTrailing) { SuiteHuddleInvitations(center: app.huddles, ringing: app.huddles.ringing) }
    } else {
      ContentUnavailableView {
        Label("No Servers", systemImage: "server.rack")
      } actions: {
        Button("Add Server", systemImage: "plus") { app.showingAddInstance = true }
          .buttonStyle(.glassProminent)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      #if os(macOS)
      .panelCard()
      #endif
    }
  }
}

#if os(macOS)
/** The servers, one rail tile each, lettered by name, with add at the bottom. */
struct SuiteServerRail: View {
  @Bindable var app: AppModel
  @Environment(\.suiteTheme) private var theme

  var body: some View {
    IconRail {
      ForEach(app.sessions) { session in
        IconSidebarButton(
          symbol: session.railSymbol, tooltip: session.name, isActive: session.id == app.selectedID, tintColor: theme.accent
        ) {
          app.selectedID = session.id
        }
        .overlay(alignment: .topTrailing) {
          Circle()
            .fill(theme.accent)
            .frame(width: Spacing.md, height: Spacing.md)
            .opacity(session.hasUnread && session.id != app.selectedID ? 1 : 0)
        }
        .contextMenu { SuiteServerMenu(app: app, session: session) }
      }
    } bottom: {
      IconSidebarButton(symbol: "plus", tooltip: "Add Server", isActive: false) {
        app.showingAddInstance = true
      }
    }
  }
}
#endif

/** What a server's context menu offers, in the rail and in the iOS server menu. */
struct SuiteServerMenu: View {
  let app: AppModel
  let session: InstanceSession

  var body: some View {
    Text(session.instance.host)
    if session.phase == .ready {
      Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") { session.attempt("Signing out") { try await session.signOut() } }
    }
    Button("Remove Server", systemImage: "trash", role: .destructive) { Task { await app.remove(session) } }
  }
}

extension InstanceSession {
  /** The rail's glyph for a server: the letter its name starts with, in a rounded square. */
  var railSymbol: String {
    guard let first = name.lowercased().first(where: { $0.isLetter || $0.isNumber }), first.isASCII else { return "server.rack" }
    return "\(first).square"
  }
}

/** One server: connecting, signing in, or its panels. */
struct SuiteInstanceView: View {
  let app: AppModel
  @Bindable var session: InstanceSession
  @AppStorage("suite.sidebarWidth") private var sidebarWidth = 260.0
  @AppStorage("suite.threadWidth") private var threadWidth = 380.0

  var body: some View {
    switch session.phase {
    case .checking:
      LoadingOcean()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .panelCard()
        #endif
    case .signedOut:
      SuiteSignInView(app: app, session: session)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .panelCard()
        #endif
    case let .unreachable(reason):
      ContentUnavailableView {
        Label("Can't Reach \(session.instance.host)", systemImage: "wifi.exclamationmark")
      } description: {
        Text(reason)
      } actions: {
        Button("Try Again", systemImage: "arrow.clockwise") { Task { await session.start() } }
          .buttonStyle(.glass)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      #if os(macOS)
      .panelCard()
      #endif
    case .notSetUp:
      SetupView(session: session)
        #if os(macOS)
        .panelCard()
        #endif
    case .ready:
      ready
    }
  }

  /** The huddle opened, while it's this server's: it covers the room and its thread. */
  private var openHuddle: HuddleCall? {
    guard let call = app.huddles.call, call.session === session, call.isOpen else { return nil }
    return call
  }

  #if os(macOS)
  private var ready: some View {
    HStack(spacing: 0) {
      SuiteSidebar(app: app, session: session)
        .frame(width: sidebarWidth)
        .panelCard()
      PanelCardGutter(width: widthBinding($sidebarWidth), edge: .trailing, minWidth: 200, maxWidth: 420)
      if let call = openHuddle {
        SuiteHuddleView(app: app, call: call)
          .panelCard()
          .instanceSheets(session, app: app)
      } else {
        conversation
          .panelCard()
      }
      if openHuddle == nil, let room = session.selectedRoom, room.thread != nil {
        PanelCardGutter(width: widthBinding($threadWidth), edge: .leading, minWidth: 280, maxWidth: 560)
        SuiteThreadPane(app: app, session: session, room: room)
          .frame(width: threadWidth)
          .panelCard()
      }
    }
  }
  #else
  private var ready: some View {
    NavigationSplitView {
      SuiteSidebar(app: app, session: session)
    } detail: {
      conversation
    }
    .fullScreenCover(isPresented: Binding(get: { openHuddle != nil }, set: { if !$0 { app.huddles.call?.setOpen(false) } })) {
      if let call = app.huddles.call { SuiteHuddleView(app: app, call: call) }
    }
  }
  #endif

  @ViewBuilder
  private var conversation: some View {
    VStack(spacing: 0) {
      InstanceNotices(app: app, session: session)
      if let page = session.page {
        SessionPageView(session: session, page: page)
      } else if let room = session.selectedRoom {
        SuiteConversation(app: app, session: session, room: room)
          .id(room.id)
      } else if !session.sidebarLoaded {
        // Nothing says there are no rooms until the first load has answered.
        SidebarLoadingState(session: session)
      } else {
        ContentUnavailableView(NavigationText.noRoomsYet, systemImage: "bubble.left.and.bubble.right")
          .accessibilityLabel(session.me?.name ?? session.name)
      }
    }
    .instanceSheets(session, app: app)
  }

  private func widthBinding(_ stored: Binding<Double>) -> Binding<CGFloat> {
    Binding(get: { CGFloat(stored.wrappedValue) }, set: { stored.wrappedValue = Double($0) })
  }
}
