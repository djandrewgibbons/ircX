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
      // One window holds every server, so File's new items are a conversation, a room and a server.
      CommandGroup(replacing: .newItem) {
        command(.newMessage)
        command(.newRoom)
        Button("Add Server") { app.showingAddInstance = true }
          .keyboardShortcut("n", modifiers: [.command, .shift])
      }
      // The menus with keys come from the keyboard shortcuts dialog's catalog, so the two can't drift.
      CommandMenu("Go") {
        ForEach(ShortcutCatalog.goCommands) { command($0) }
        Divider()
        ForEach(Array(app.sessions.prefix(9).enumerated()), id: \.element.id) { index, session in
          Button(session.name) { app.select(index: index) }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
      }
      // The huddle of the room shown, and its microphone (web `togglesHuddle`, `mutesHuddle`).
      CommandMenu("Huddle") {
        command(.toggleHuddle)
        command(.muteHuddle).disabled(app.huddles.call == nil)
      }
      // The selected server's own settings, beside the app's.
      CommandGroup(after: .appSettings) {
        Button("Server Settings") { app.selected?.openWorkspaceSettings() }
          .keyboardShortcut(",", modifiers: [.command, .option])
          .disabled(app.selected?.phase != .ready)
      }
      CommandGroup(replacing: .help) {
        command(.showShortcuts)
      }
    }

    #if os(macOS)
    Settings {
      SettingsView()
    }
    // Each server's Server Settings (web community settings), which its sidebar's menu and /admin open.
    WindowGroup("Server Settings", id: ServerSettingsWindow.id, for: UUID.self) { $id in
      ServerSettingsWindow(app: app, id: id)
    }
    .windowToolbarStyle(.unified(showsTitle: true))
    #endif
  }

  @MainActor
  private func command(_ command: ShortcutCommand) -> some View {
    Button(command.title) { perform(command) }
      .keyboardShortcut(command.keyEquivalent, modifiers: command.modifiers)
  }

  @MainActor
  private func perform(_ command: ShortcutCommand) {
    switch command {
    case .jumpTo: app.showingSwitcher = true
    case .previousRoom: step(-1)
    case .nextRoom: step(1)
    case .back: app.goBack()
    case .forward: app.goForward()
    case .home: app.selected?.goHome()
    case .search: search()
    case .activity: app.toggleActivity()
    case .newMessage: app.selected?.showingNewDirect = true
    case .newRoom: if let session = app.selected, session.canCreateRooms { session.showingNewRoom = true }
    case .moveStarUp: moveStar(.up)
    case .moveStarDown: moveStar(.down)
    case .roomSettings: if let session = app.selected, let id = session.selectedRoomID { session.show(.settings(id)) }
    case .showShortcuts: app.showingShortcuts = true
    case .toggleHuddle: if let session = app.selected { app.huddles.toggle(in: session) }
    case .muteHuddle: app.huddles.toggleMute()
    }
  }

  /**
   * ⌘F: the search box, scoped to the open room; IRC Classic writes `/search in:#room ` in the input line
   * instead, as an IRC client would.
   */
  @MainActor
  private func search() {
    guard let session = app.selected else { return }
    let classic = UserDefaults.standard.string(forKey: Preferences.theme) == AppTheme.irc.rawValue
    if classic, session.page == nil, let room = session.selectedRoom {
      room.composer().line = room.room.isDirect ? "/search " : "/search in:#\(room.title) "
      return
    }
    session.openSearchBox(in: session.page == nil ? session.selectedRoomID : nil)
  }

  @MainActor
  private func moveStar(_ move: InputCommand.StarMove) {
    guard let session = app.selected, let id = session.selectedRoomID, session.isStarred(id) else { return }
    session.moveStar(id, move)
  }

  @MainActor
  private func step(_ by: Int) {
    if let session = app.selected { Commander.step(by, in: session) }
  }
}

extension ShortcutCommand {
  var keyEquivalent: KeyEquivalent {
    switch self {
    case .jumpTo: "k"
    case .previousRoom, .moveStarUp: .upArrow
    case .nextRoom, .moveStarDown: .downArrow
    case .back: "["
    case .forward: "]"
    case .home: "h"
    case .search: "f"
    case .activity: "a"
    case .newMessage, .newRoom: "n"
    case .roomSettings: "i"
    case .showShortcuts: "/"
    case .toggleHuddle: "h"
    case .muteHuddle: .space
    }
  }

  var modifiers: EventModifiers {
    switch self {
    case .jumpTo, .showShortcuts, .back, .forward, .search, .newMessage: .command
    case .previousRoom, .nextRoom: .option
    case .home, .activity, .roomSettings: [.command, .shift]
    case .newRoom, .moveStarUp, .moveStarDown: [.command, .option]
    case .toggleHuddle: [.command, .option, .shift]
    case .muteHuddle: [.command, .shift]
    }
  }
}

/** Settings: the theme, and how the IRC Classic theme prints. */
struct SettingsView: View {
  @AppStorage(Preferences.theme) private var theme: AppTheme = .suite
  @AppStorage(Preferences.appearance) private var appearance: Appearance = .system
  @AppStorage(Preferences.fontSize) private var fontSize = 13.0
  @AppStorage(Preferences.showJoinsParts) private var showJoinsParts = true
  @AppStorage(Preferences.showSeconds) private var showSeconds = false

  var body: some View {
    Form {
      Picker("Theme", selection: $theme) {
        ForEach(AppTheme.allCases) { Text($0.name).tag($0) }
      }
      .pickerStyle(.inline)
      Picker("Appearance", selection: $appearance) {
        ForEach(Appearance.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
      }
      .pickerStyle(.segmented)
      .help("Light, dark, or as the device is. IRC Classic keeps its own palette.")
      Toggle("Show Joins and Parts", isOn: $showJoinsParts)
      Section("IRC Classic") {
        Slider(value: $fontSize, in: 10...20, step: 1) { Text("Font Size") }
        Toggle("Show Seconds", isOn: $showSeconds)
      }
      #if os(iOS)
      // The keyboard shortcuts dialog, which a Mac opens from its Help menu.
      Section {
        NavigationLink("Keyboard Shortcuts") { ShortcutsSheet() }
      }
      #endif
    }
    .formStyle(.grouped)
    #if os(macOS)
    .frame(width: 420)
    #endif
  }
}
