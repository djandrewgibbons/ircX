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

  var body: some View {
    #if os(macOS)
    HStack(spacing: 0) {
      SuiteServerRail(app: app)
      workspace
        .padding([.top, .bottom, .trailing], panelCardGutter)
    }
    .background(panelCanvasColor)
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
    } else {
      ContentUnavailableView {
        Label("No Servers", systemImage: "server.rack")
      } actions: {
        Button("Add Server", systemImage: "plus") { app.showingAddInstance = true }
          .buttonStyle(.glassProminent)
      }
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
      Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") { Task { await session.signOut() } }
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
        #if os(macOS)
        .panelCard()
        #endif
    case .signedOut:
      SuiteSignInView(app: app, session: session)
        #if os(macOS)
        .panelCard()
        #endif
    case let .unreachable(reason):
      ContentUnavailableView {
        Label("Can't Reach \(session.instance.host)", systemImage: "wifi.exclamationmark")
      } actions: {
        Button("Try Again", systemImage: "arrow.clockwise") { Task { await session.start() } }
          .buttonStyle(.glass)
      }
      .help(reason)
      #if os(macOS)
      .panelCard()
      #endif
    case .ready:
      ready
    }
  }

  #if os(macOS)
  private var ready: some View {
    HStack(spacing: 0) {
      SuiteSidebar(app: app, session: session)
        .frame(width: sidebarWidth)
        .panelCard()
      PanelCardGutter(width: widthBinding($sidebarWidth), edge: .trailing, minWidth: 200, maxWidth: 420)
      conversation
        .panelCard()
      if let room = session.selectedRoom, room.thread != nil {
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
  }
  #endif

  @ViewBuilder
  private var conversation: some View {
    if let room = session.selectedRoom {
      SuiteConversation(app: app, session: session, room: room)
        .id(room.id)
    } else {
      ContentUnavailableView(session.name, systemImage: "bubble.left.and.bubble.right")
    }
  }

  private func widthBinding(_ stored: Binding<Double>) -> Binding<CGFloat> {
    Binding(get: { CGFloat(stored.wrappedValue) }, set: { stored.wrappedValue = Double($0) })
  }
}
