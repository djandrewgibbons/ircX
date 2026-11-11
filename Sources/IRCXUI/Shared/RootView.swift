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

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
    Group {
      switch theme {
      case .suite: SuiteRootView(app: app)
      case .irc: IRCRootView(app: app)
      }
    }
    .environment(\.appTheme, theme)
    .sheet(isPresented: $app.showingAddInstance) {
      AddInstanceView(app: app).environment(\.appTheme, theme)
    }
    .sheet(isPresented: $app.showingSwitcher) {
      QuickSwitcher(app: app).environment(\.appTheme, theme)
    }
    .task { await app.start() }
  }
}
