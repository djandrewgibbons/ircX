import AppCoreUI
import EmberKit
import SwiftUI

/** Something that can't be undone, asked about first with the web's words, from a page or the input line. */
public enum Confirmation: Identifiable, Equatable, Sendable {
  case leave(RoomID)
  case delete(RoomID)
  case ban(UserID, Bool)
  case clearSearches
  /** Something Server Settings asks about, which the input line's workspace commands ask about too. */
  case admin(AdminConfirmation)

  public var id: String {
    switch self {
    case let .leave(id): "leave-\(id)"
    case let .delete(id): "delete-\(id)"
    case let .ban(id, banned): "ban-\(id)-\(banned)"
    case .clearSearches: "clear-searches"
    case let .admin(confirmation): "admin-\(confirmation.id)"
    }
  }
}

extension InstanceSession {
  func title(of confirmation: Confirmation) -> String {
    switch confirmation {
    case let .leave(id):
      guard let item = rooms.first(where: { $0.id == id }) else { return "Leave" }
      return "Leave \(title(of: item.room))"
    case let .delete(id):
      guard let item = rooms.first(where: { $0.id == id }) else { return "Delete" }
      return item.room.isDirect ? "Delete Ping" : "Delete \(title(of: item.room))"
    case let .ban(id, banned):
      guard banned else { return "Remove ban" }
      guard let person = people[id] else { return "Ban" }
      return "Ban \(person.name)"
    case .clearSearches: return "Clear"
    case let .admin(confirmation): return confirmation.title
    }
  }

  func message(of confirmation: Confirmation) -> String {
    switch confirmation {
    case .leave: NavigationText.leaveRoomConfirm
    case let .delete(id): rooms.first { $0.id == id }?.room.isDirect == true ? NavigationText.deletePingConfirm : NavigationText.deleteRoomConfirm
    case let .ban(_, banned): banned ? NavigationText.banConfirm : NavigationText.unbanConfirm
    case .clearSearches: NavigationText.clearSearchesConfirm
    case let .admin(confirmation): confirmation.message
    }
  }

  /** Does what was confirmed, showing why if it fails. */
  func confirm(_ confirmation: Confirmation) {
    switch confirmation {
    case let .leave(id): attempt("Leaving the room") { try await self.leaveRoom(id) }
    case let .delete(id): attempt("Deleting the room") { try await self.deleteRoom(id) }
    case let .ban(id, banned): attempt(banned ? "Banning" : "Removing the ban") { try await self.setBanned(banned, id) }
    case .clearSearches: attempt("Clearing recent searches") { try await self.clearRecentSearches() }
    case let .admin(confirmation): admin.confirm(confirmation)
    }
  }
}

extension View {
  /** Asks about the instance's pending confirmation, in either theme. */
  func sessionConfirmations(_ session: InstanceSession) -> some View {
    modifier(SessionConfirmations(session: session))
  }
}

private struct SessionConfirmations: ViewModifier {
  @Bindable var session: InstanceSession

  func body(content: Content) -> some View {
    content.confirmationDialog(
      title, isPresented: Binding(get: { session.confirmation != nil }, set: { if !$0 { session.confirmation = nil } }),
      titleVisibility: .visible, presenting: session.confirmation
    ) { confirmation in
      Button(session.title(of: confirmation), role: .destructive) { session.confirm(confirmation) }
      Button("Cancel", role: .cancel) {}
    } message: { confirmation in
      Text(session.message(of: confirmation))
    }
  }

  private var title: String {
    guard let confirmation = session.confirmation else { return "Are you sure?" }
    return session.title(of: confirmation)
  }
}

extension View {
  /** The instance's sheets (New direct message, New room, Server Settings, the search box) and its confirmations. */
  func instanceSheets(_ session: InstanceSession, app: AppModel) -> some View {
    modifier(InstanceSheets(session: session, app: app))
  }
}

private struct InstanceSheets: ViewModifier {
  @Bindable var session: InstanceSession
  let app: AppModel
  @Environment(\.appTheme) private var look
  #if os(macOS)
  @Environment(\.openWindow) private var openWindow
  #endif

  func body(content: Content) -> some View {
    content
      .sheet(isPresented: $session.showingNewDirect) { NewDirectSheet(session: session).environment(\.appTheme, look) }
      .sheet(isPresented: $session.showingNewRoom) { NewRoomSheet(session: session).environment(\.appTheme, look) }
      #if os(macOS)
      // Server Settings is a window of its own on the Mac, one for each server.
      .onChange(of: session.showingWorkspaceSettings, initial: true) { _, showing in
        guard showing else { return }
        session.showingWorkspaceSettings = false
        openWindow(id: ServerSettingsWindow.id, value: session.id)
      }
      #else
      .sheet(isPresented: $session.showingWorkspaceSettings) { ServerSettingsView(app: app, session: session).environment(\.appTheme, look) }
      #endif
      .sheet(isPresented: $session.showingSearchBox) { SearchBoxSheet(session: session).environment(\.appTheme, look) }
      .sheet(isPresented: $session.showingAgents) { AvailableAgentsSheet(session: session).environment(\.appTheme, look) }
      .sheet(isPresented: $session.showingWelcome) { WelcomeSheet(session: session).environment(\.appTheme, look) }
      .sheet(item: Binding(get: { session.outsideAsk.map(OutsideAskItem.init) }, set: { if $0 == nil { session.outsideAsk = nil } })) { item in
        OutsideConnectSheet(session: session, ask: item.ask).environment(\.appTheme, look)
      }
      .sheet(isPresented: Binding(get: { session.reportingPerson != nil }, set: { if !$0 { session.reportingPerson = nil } })) {
        if let person = session.reportingPerson { ReportSheet(session: session, person: person).environment(\.appTheme, look) }
      }
      // Leaving a page with unsaved changes asks first (web `UnsavedChanges`).
      .confirmationDialog(
        "Discard your changes?", isPresented: Binding(get: { session.leaving != nil }, set: { if !$0 { session.leaving = nil } }),
        titleVisibility: .visible
      ) {
        Button("Discard", role: .destructive) { session.discardAndLeave() }
        Button("Keep Editing", role: .cancel) { session.leaving = nil }
      } message: {
        Text("You have unsaved changes. Discard them to leave, or keep editing.")
      }
      .sessionConfirmations(session)
      // Password reset opens over a signed-in session too (web `/passwords/new`).
      .signInSheets(session.signInForm)
  }
}
