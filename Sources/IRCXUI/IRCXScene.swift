import EmberKit
import SwiftUI

/** The app's scenes, which the macOS and iOS targets share: one window, and on the Mac, Settings and the menu commands. */
public struct IRCXScene: Scene {
  @State private var app = AppModel()

  public init() {}

  public var body: some Scene {
    WindowGroup("ircX") {
      RootView(app: app)
        #if os(macOS)
        .frame(minWidth: 820, minHeight: 480)
        #endif
    }
    #if os(macOS)
    .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    #endif
    .commands {
      CommandGroup(after: .newItem) {
        Button("Add Server…") { app.showingAddInstance = true }
          .keyboardShortcut("n", modifiers: [.command, .shift])
      }
      CommandMenu("Go") {
        Button("Jump to…") { app.showingSwitcher = true }
          .keyboardShortcut("k")
        Divider()
        ForEach(Array(app.sessions.prefix(9).enumerated()), id: \.element.id) { index, session in
          Button(session.name) { app.select(index: index) }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
        Divider()
        Button("Next Window") { step(1) }.keyboardShortcut(.downArrow, modifiers: [.option])
        Button("Previous Window") { step(-1) }.keyboardShortcut(.upArrow, modifiers: [.option])
      }
    }

    #if os(macOS)
    Settings {
      SettingsView().preferredColorScheme(.dark)
    }
    #endif
  }

  /** ⌥↑ and ⌥↓ step through the selected instance's windows, as Slack's and irssi's do. */
  @MainActor
  private func step(_ by: Int) {
    guard let session = app.selected else { return }
    let windows = (session.starred + session.channels + session.directs).map(\.id)
    guard !windows.isEmpty else { return }
    let current = session.selectedRoomID.flatMap { windows.firstIndex(of: $0) } ?? -by
    session.selectedRoomID = windows[(current + by + windows.count) % windows.count]
  }
}

struct SettingsView: View {
  @AppStorage(Preferences.fontSize) private var fontSize = 13.0
  @AppStorage(Preferences.showJoinsParts) private var showJoinsParts = true
  @AppStorage(Preferences.showSeconds) private var showSeconds = false

  var body: some View {
    Form {
      Slider(value: $fontSize, in: 10...20, step: 1) { Text("Font size: \(Int(fontSize))") }
      Toggle("Show joins and parts", isOn: $showJoinsParts)
      Toggle("Show seconds in timestamps", isOn: $showSeconds)
    }
    .font(Theme.font(13))
    .padding(20)
    .frame(width: 380)
  }
}
