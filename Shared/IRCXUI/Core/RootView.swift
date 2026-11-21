import AppCoreUI
import EmberKit
import SwiftUI

/** The looks ircX comes in, which Settings switches between. Both lay out the same app. */
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
  /** The dxnd suite's style, built on AppCoreUI: panel cards, the icon rail and Slack-like messages. */
  case suite
  /** The fixed-width throwback: a terminal palette, aligned nicks, a BitchX status bar. */
  case irc

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .suite: "Suite"
    case .irc: "IRC Classic"
    }
  }
}

extension EnvironmentValues {
  @Entry var appTheme: AppTheme = .suite
}

/** ircX's accent and brand under the Suite theme: Ember's orange. */
extension SuiteTheme {
  static let ircX = SuiteTheme(id: "ircx", name: "ircX", accent: .orange, brand: .orange)
}

/** The window's content, in whichever theme Settings picked. */
public struct RootView: View {
  @Bindable var app: AppModel
  @AppStorage(Preferences.theme) private var theme: AppTheme = .suite
  @AppStorage(Preferences.appearance) private var appearance: Appearance = .system
  @Environment(\.scenePhase) private var scenePhase

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
    Group {
      switch theme {
      case .suite: SuiteRootView(app: app).preferredColorScheme(appearance.colorScheme)
      case .irc: IRCRootView(app: app)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.appTheme, theme)
    .sheet(isPresented: $app.showingAddInstance) {
      AddInstanceView(app: app).environment(\.appTheme, theme)
    }
    .sheet(isPresented: $app.showingSwitcher) {
      QuickSwitcher(app: app).environment(\.appTheme, theme)
    }
    .sheet(isPresented: $app.showingShortcuts) {
      ShortcutsSheet().environment(\.appTheme, theme)
    }
    // Every start and join of a huddle goes by its preview; Invite people is over the opened huddle.
    .sheet(item: Binding(get: { app.huddles.preview }, set: { app.huddles.preview = $0 })) { request in
      HuddlePreviewSheet(request: request, center: app.huddles).environment(\.appTheme, theme)
    }
    .sheet(isPresented: Binding(get: { app.huddles.inviting && app.huddles.call != nil }, set: { app.huddles.inviting = $0 })) {
      if let call = app.huddles.call { HuddleInviteSheet(call: call).environment(\.appTheme, theme) }
    }
    .task { await app.start() }
    // ircx:// links name a server's page as its own address does.
    .onOpenURL { url in
      guard !app.openLink(url.absoluteString) else { return }
      logger.error("No server opens \(url.absoluteString, privacy: .public)")
      app.selected?.notice = "No server here opens \(url.absoluteString)"
    }
    .onChange(of: scenePhase, initial: true) { _, phase in app.setScenePhase(phase) }
  }
}

/** Light, Dark or System (web `AppearanceMenu`), per device, which the Suite theme follows; IRC Classic keeps its palette. */
public enum Appearance: String, CaseIterable, Identifiable, Sendable {
  case light, dark, system

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .light: "Light"
    case .dark: "Dark"
    case .system: "System"
    }
  }

  var symbol: String {
    switch self {
    case .light: "sun.max"
    case .dark: "moon"
    case .system: "circle.lefthalf.filled"
    }
  }

  /** The scheme it forces, or nil to follow the device. */
  var colorScheme: ColorScheme? {
    switch self {
    case .light: .light
    case .dark: .dark
    case .system: nil
    }
  }
}
