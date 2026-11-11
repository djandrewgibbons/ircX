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
    .windowToolbarStyle(.unified(showsTitle: false))
    #endif
    .commands {
      CommandGroup(after: .newItem) {
        Button("Add Server") { app.showingAddInstance = true }
          .keyboardShortcut("n", modifiers: [.command, .shift])
      }
      CommandMenu("Go") {
        Button("Jump To") { app.showingSwitcher = true }
          .keyboardShortcut("k")
        Divider()
        ForEach(Array(app.sessions.prefix(9).enumerated()), id: \.element.id) { index, session in
          Button(session.name) { app.select(index: index) }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
        Divider()
        Button("Next Room") { step(1) }.keyboardShortcut(.downArrow, modifiers: [.option])
        Button("Previous Room") { step(-1) }.keyboardShortcut(.upArrow, modifiers: [.option])
      }
    }

    #if os(macOS)
    Settings {
      SettingsView()
    }
    #endif
  }

  @MainActor
  private func step(_ by: Int) {
    if let session = app.selected { Commander.step(by, in: session) }
  }
}

/** Settings: the theme, and how the IRC Classic theme prints. */
struct SettingsView: View {
  @AppStorage(Preferences.theme) private var theme: AppTheme = .suite
  @AppStorage(Preferences.fontSize) private var fontSize = 13.0
  @AppStorage(Preferences.showJoinsParts) private var showJoinsParts = true
  @AppStorage(Preferences.showSeconds) private var showSeconds = false

  var body: some View {
    Form {
      Picker("Theme", selection: $theme) {
        ForEach(AppTheme.allCases) { Text($0.name).tag($0) }
      }
      .pickerStyle(.inline)
      Toggle("Show Joins and Parts", isOn: $showJoinsParts)
      Section("IRC Classic") {
        Slider(value: $fontSize, in: 10...20, step: 1) { Text("Font Size") }
        Toggle("Show Seconds", isOn: $showSeconds)
      }
    }
    .formStyle(.grouped)
    #if os(macOS)
    .frame(width: 420)
    #endif
  }
}
