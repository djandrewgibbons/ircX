import AppCoreUI
import EmberKit
import SwiftUI

/** A page's top bar in either theme: Go Back and its title (web `PageHeader`). */
struct PageHeader<Trailing: View>: View {
  let title: String
  let back: () -> Void
  @ViewBuilder var trailing: () -> Trailing
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    switch look {
    case .suite:
      PaneHeaderBar(onBack: back) {
        Text(title).font(DesignFont.cardTitle).lineLimit(1)
      } trailing: {
        trailing()
      }
    case .irc:
      HStack(spacing: 10) {
        Button("<- back", action: back).buttonStyle(.plain).foregroundStyle(irc.ember).help("Go Back")
        Text(title).font(Theme.font(14, weight: .bold)).lineLimit(1)
        Spacer()
        trailing()
      }
      .font(Theme.font(12))
      .padding(.horizontal, 14)
      .frame(height: 40)
      .background(irc.buffer)
      .overlay(alignment: .bottom) { Rectangle().fill(irc.faint).frame(height: 1) }
    }
  }
}

extension PageHeader where Trailing == EmptyView {
  init(title: String, back: @escaping () -> Void) {
    self.init(title: title, back: back) { EmptyView() }
  }
}

/** A room's settings, or a DM's (web `RoomSettingsPage`, `DirectSettingsPage`), in place of the room. */
struct RoomSettingsPage: View {
  let session: InstanceSession
  let roomID: RoomID

  var body: some View {
    if let item = session.rooms.first(where: { $0.id == roomID }), item.room.isDirect {
      DirectSettingsPage(session: session, room: item.room)
    } else {
      SharedRoomSettingsPage(session: session, roomID: roomID)
    }
  }
}

/** A DM's settings: who's in it, and Delete Ping. Its people never change. */
struct DirectSettingsPage: View {
  let session: InstanceSession
  let room: Room
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: "Edit settings for \(session.title(of: room))", back: session.closePage)
      Form {
        Section("People") {
          ForEach(RoomList.membersShown(room, me: session.me?.id)) { member in
            if let person = session.people[member.id] {
              PersonRow(session: session, person: person)
            } else {
              Text(member.name)
            }
          }
        }
        Section {
          Button("Delete Ping", systemImage: "trash", role: .destructive) { session.confirmation = .delete(room.id) }
            .help(NavigationText.deletePingConfirm)
        }
      }
      .themedForm(look, irc)
    }
  }
}

/** A shared room's settings: its name, icon, people and huddles for who can change it, else a read-only page. */
struct SharedRoomSettingsPage: View {
  let session: InstanceSession
  let roomID: RoomID
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var settings: RoomSettings?
  @State private var name = ""
  @State private var icon: String?
  @State private var everyone = true
  @State private var chosen: Set<UserID> = []
  @State private var huddles = true
  @State private var filter = ""
  @State private var saving = false
  @State private var failure: String?

  private var changed: Bool {
    guard let room = settings?.room, let settings else { return false }
    let members = Set(settings.people.filter(\.member).map(\.id))
    return name != room.name || icon != room.icon || everyone != (room.kind == .open) || huddles != room.allowsHuddles
      || (!everyone && chosen != members)
  }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: "Edit settings for \(title)", back: { session.leave(session.closePage) })
      if let settings {
        Form {
          if settings.canAdminister {
            editable(settings)
          } else {
            readOnly(settings)
          }
        }
        .themedForm(look, irc)
      } else if let failure {
        Text(failure).foregroundStyle(SemanticColor.warning).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Color.clear.loadingActivity(true)
      }
    }
    .task(id: roomID) { await load() }
    // Leaving with changes, any way at all, asks first: Go Back, a sidebar row, Back and Forward, another page.
    .onChange(of: changed) { _, held in session.holdsChanges = held }
    .onDisappear { session.holdsChanges = false }
  }

  private var title: String {
    if let name = settings?.room.name { return name }
    guard let item = session.rooms.first(where: { $0.id == roomID }) else { return "room" }
    return session.title(of: item.room)
  }

  @ViewBuilder
  private func editable(_ settings: RoomSettings) -> some View {
    Section {
      TextField("Room name", text: $name, prompt: Text("Name the room"))
        .onChange(of: name) { _, new in if new.count > EmberLimits.maxRoomNameLength { name = String(new.prefix(EmberLimits.maxRoomNameLength)) } }
      LabeledContent("Icon") { IconPicker(api: session.api, icon: $icon) }
    }
    RoomPeopleSection(
      session: session, people: settings.people.map { User(id: $0.id, name: $0.name) }, everyone: $everyone, chosen: $chosen, filter: $filter,
      editable: true, includesMe: false, members: Set(settings.people.filter(\.member).map(\.id)))
    if session.account?.huddles == true {
      Section("Huddles") {
        if settings.canChangeHuddles {
          Toggle("Huddles", isOn: $huddles)
          Text(huddles ? NavigationText.canStartHuddles : NavigationText.cannotStartHuddles).foregroundStyle(.secondary)
          if session.huddles[roomID] != nil, huddles != settings.room.allowsHuddles {
            Text(NavigationText.savingEndsHuddle).foregroundStyle(SemanticColor.warning)
          }
        } else if !settings.room.allowsHuddles {
          Text(NavigationText.cannotStartHuddles).foregroundStyle(.secondary)
        }
      }
    }
    if let failure {
      Section { Text(failure).foregroundStyle(SemanticColor.warning) }
    }
    Section {
      Button(saving ? "Saving…" : "Save", action: save)
        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
        .keyboardShortcut(.defaultAction)
      Button("Delete \(title)", systemImage: "trash", role: .destructive) { session.confirmation = .delete(roomID) }
        .help(NavigationText.deleteRoomConfirm)
    }
  }

  @ViewBuilder
  private func readOnly(_ settings: RoomSettings) -> some View {
    Section {
      Text(title).font(look == .irc ? Theme.font(15, weight: .bold) : DesignFont.cardTitle)
    }
    RoomPeopleSection(
      session: session, people: settings.people.filter { settings.room.kind == .open || $0.member }.map { User(id: $0.id, name: $0.name) },
      everyone: .constant(settings.room.kind == .open), chosen: .constant(Set(settings.people.filter(\.member).map(\.id))), filter: $filter,
      editable: false, includesMe: false)
    if settings.room.kind == .closed {
      Section {
        Button("Leave \(title)", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { session.confirmation = .leave(roomID) }
          .help(NavigationText.leaveRoomConfirm)
      }
    }
  }

  private func load() async {
    do {
      let settings = try await session.api.roomSettings(roomID)
      self.settings = settings
      name = settings.room.name ?? title
      icon = settings.room.icon
      everyone = settings.room.kind == .open
      chosen = Set(settings.people.filter(\.member).map(\.id))
      huddles = settings.room.allowsHuddles
    } catch let error as EmberError where error.problem?.status == 404 {
      session.closePage()
      session.goHome()
      session.notice = NavigationText.roomNotFound
    } catch {
      logger.error("Loading a room's settings failed: \(error.localizedDescription, privacy: .public)")
      failure = error.localizedDescription
    }
  }

  private func save() {
    guard let settings else { return }
    saving = true
    failure = nil
    let chosenIcon: String
    if let icon { chosenIcon = icon } else { chosenIcon = String() }
    var changes = RoomChanges(name: name.trimmingCharacters(in: .whitespaces), icon: chosenIcon)
    if everyone {
      changes.kind = .open
    } else {
      changes.kind = .closed
      changes.memberIds = settings.people.map(\.id).filter(chosen.contains)
    }
    if session.account?.huddles == true, settings.canChangeHuddles { changes.huddles = huddles }
    Task {
      do {
        try await session.changeRoom(roomID, changes)
      } catch {
        logger.error("Saving a room's settings failed: \(error.localizedDescription, privacy: .public)")
        failure = error.localizedDescription
      }
      saving = false
    }
  }
}
