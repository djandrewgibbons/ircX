import AppCoreUI
import EmberKit
import SwiftUI

/**
 * The staged shared order (web `useSharedOrder`): moves stage it, Save sends it, Cancel drops it. Its draft
 * is nil while it's the order as saved.
 */
@MainActor
@Observable
final class RoomOrderModel {
  private(set) var draft = Draft<[RoomID]?>(nil)
  var status: String?
  var saving = false

  /** The order as moved, nil while it's as saved. */
  var staged: [RoomID]? {
    get { draft.value }
    set { draft.value = newValue }
  }

  /** Whether there's an order to save, which leaving asks about. */
  var changed: Bool { draft.isDirty }

  /** The rooms in order: staged, with rooms that came since at its end and gone ones out (`stillStaged`). */
  func rooms(_ session: InstanceSession) -> [SidebarRoom] {
    let shared = session.rooms.filter { !$0.room.isDirect && $0.involvement != .invisible }
    let saved = RoomList.inSidebarOrder(shared, favorites: [], sharedOrder: session.sharedOrder, id: \.id)
    guard let staged else { return saved }
    let byId = Dictionary(shared.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let kept = staged.compactMap { byId[$0] }
    let keptIds = Set(staged)
    return kept + saved.filter { !keptIds.contains($0.id) }
  }

  func move(_ id: RoomID, by: Int, session: InstanceSession) {
    staged = RoomList.moved(rooms(session).map(\.id), id, by: by)
    status = NavigationText.sharedOrderUnsaved
  }

  func move(fromOffsets: IndexSet, toOffset: Int, session: InstanceSession) {
    var ids = rooms(session).map(\.id)
    ids.move(fromOffsets: fromOffsets, toOffset: toOffset)
    staged = ids
    status = NavigationText.sharedOrderUnsaved
  }

  func cancel() {
    draft.revert()
    status = nil
  }

  /** Save order (`PUT /api/account/room_order`): everyone hears `rooms.reordered`, and this sidebar loads again now. */
  func save(session: InstanceSession, then done: @escaping () -> Void = {}) {
    guard let staged, !saving else { return done() }
    saving = true
    status = NavigationText.savingOrder
    Task {
      do {
        _ = try await session.api.setSharedOrder(staged)
        // Unless it was moved again meanwhile.
        if draft.value == staged { draft.revert() }
        status = NavigationText.sharedOrderSaved
        await session.refreshSidebar()
        done()
      } catch {
        logger.error("Saving the room order failed: \(error.localizedDescription, privacy: .public)")
        status = NavigationText.orderFailed
      }
      saving = false
    }
  }
}

/** Rooms and permissions (web `workspace-settings-page.tsx`): New room, who can make rooms, and the room order. */
struct RoomsAndPermissionsSection: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let order: RoomOrderModel
  let newRoom: () -> Void
  let leave: (@escaping () -> Void) -> Void

  var body: some View {
    Section {
      if session.canCreateRooms {
        Button("New Room", systemImage: "plus", action: newRoom)
      }
      if admin.isAdministrator {
        Toggle("Admins Create Rooms", isOn: Binding(get: { session.account?.restrictRoomCreation == true }, set: admin.restrict))
          .disabled(admin.restricting)
          .help(AccountSettings.names["restrictRoomCreation"] ?? "Must be admin to create new rooms")
        RoomOrderEditor(session: session, order: order, leave: leave)
      } else {
        Text(NavigationText.adminsManageOrder).foregroundStyle(.secondary)
      }
    } header: {
      Text("Room order and permissions").help("Drag a room to reorder your community sidebar. Click a room to set its permissions.")
    }
  }
}

/**
 * The room order editor (web `RoomOrder`): every shared room in the administrator's sidebar in the
 * saved order, each with Move Up and Move Down (and dragging), its settings, and who's in it.
 */
struct RoomOrderEditor: View {
  let session: InstanceSession
  let order: RoomOrderModel
  /** Leaves the settings for a room's, asking first about a staged order. */
  let leave: (@escaping () -> Void) -> Void
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    let rooms = order.rooms(session)
    if rooms.isEmpty {
      Text(NavigationText.noRoomsToArrange).foregroundStyle(.secondary)
    }
    ForEach(rooms) { item in
      HStack(spacing: Spacing.md) {
        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
        RoomIconView(api: session.api, room: item.room, size: 16)
        Button(session.title(of: item.room)) {
          leave { session.show(.settings(item.id)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings for \(session.title(of: item.room))")
        Spacer()
        Text(item.room.kind == .open ? "Everyone" : "Selected people").foregroundStyle(.secondary)
        Button("Move Up", systemImage: "chevron.up") { order.move(item.id, by: -1, session: session) }
          .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(item.id == rooms.first?.id)
        Button("Move Down", systemImage: "chevron.down") { order.move(item.id, by: 1, session: session) }
          .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(item.id == rooms.last?.id)
      }
      .font(look == .irc ? Theme.font(12) : DesignFont.body)
    }
    .onMove { order.move(fromOffsets: $0, toOffset: $1, session: session) }
    if let status = order.status {
      Text(status).foregroundStyle(status == NavigationText.orderFailed ? (look == .irc ? irc.part : SemanticColor.warning) : Color.secondary)
    }
    if order.changed {
      HStack {
        Button("Cancel", role: .cancel) { order.cancel() }
        Button(order.saving ? "Saving…" : "Save order") { order.save(session: session) }
          .buttonStyle(.borderedProminent)
          .disabled(order.saving)
      }
    }
  }
}

/**
 * The people list (web `PeopleList`): everyone but bots by name, Admins then Members; administrators also
 * see banned and suspended people, and change roles or remove people.
 */
struct PeopleListSection: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  @Environment(\.appTheme) private var look

  private var listed: [DirectoryUser] {
    let administrator = admin.isAdministrator
    return PeopleList.byName(session.people.values.filter { person in
      person.role != .bot && person.agent != true
        && (person.status == .active || (administrator && (person.status == .banned || person.status == .suspended)))
    })
  }

  var body: some View {
    let admins = listed.filter { $0.role == .administrator }
    let members = listed.filter { $0.role != .administrator }
    if !admins.isEmpty { group("Admins", admins) }
    if !members.isEmpty { group("Members", members) }
  }

  private func group(_ title: String, _ people: [DirectoryUser]) -> some View {
    Section(title) {
      ForEach(people) { person in
        HStack {
          Button {
            show(person)
          } label: {
            PersonRow(session: session, person: person)
          }
          .buttonStyle(.plain)
          .opacity(person.status == .active ? 1 : 0.5)
          if person.status == .banned { Image(systemName: "nosign").help("Banned") }
          if person.status == .suspended { Text("Membership lapsed").foregroundStyle(.secondary) }
          Spacer()
          if person.id == session.me?.id {
            // Your own crown shows your role, and can't be taken off, so there's always an administrator.
            if admin.isAdministrator, person.status == .active { crown(person).disabled(true) }
            Button("My Settings", systemImage: "pencil") {
              session.showingWorkspaceSettings = false
              session.show(.profile)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("My settings")
          } else if admin.isAdministrator {
            if person.status == .active { crown(person).disabled(admin.changingPeople.contains(person.id)) }
            if person.status != .banned {
              Button("Delete", systemImage: "minus.circle", role: .destructive) { admin.confirming = .remove(person) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(admin.changingPeople.contains(person.id))
                .help("Delete \(person.name)")
            }
          }
        }
      }
    }
  }

  /** The crown (web `RoleButton`): administrator or member. */
  private func crown(_ person: DirectoryUser) -> some View {
    Button(person.role == .administrator ? "Make Member" : "Make Admin", systemImage: person.role == .administrator ? "crown.fill" : "crown") {
      admin.setRole(person, administrator: person.role != .administrator)
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
    .help("Role: \(person.role == .administrator ? "Administrator" : "Member")")
  }

  /** Their page, in the server's window. */
  private func show(_ person: DirectoryUser) {
    session.showingWorkspaceSettings = false
    session.show(.person(person.id))
  }
}
