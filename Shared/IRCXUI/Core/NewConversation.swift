import AppCoreUI
import EmberKit
import SwiftUI

extension View {
  /** A form as each theme draws one: the suite's grouped form, or IRC Classic's on its own palette and face. */
  @ViewBuilder
  func themedForm(_ look: AppTheme, _ irc: Theme) -> some View {
    switch look {
    case .suite:
      formStyle(.grouped)
    case .irc:
      formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(irc.buffer)
        .font(Theme.font(13))
        .foregroundStyle(irc.text)
        .tint(irc.ember)
        .preferredColorScheme(.dark)
    }
  }
}

/** A person as pickers and lists show them: avatar, name, @username and an Agent badge (web `PersonRow`). */
struct PersonRow: View {
  let session: InstanceSession
  let person: DirectoryUser
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    HStack(spacing: Spacing.md) {
      if look == .suite {
        SuiteAvatar(session: session, user: person.user, size: 24)
      }
      Text(person.name)
        .foregroundStyle(look == .irc ? irc.nick(person.id) : Color.primary)
        .lineLimit(1)
      if let username = person.username {
        Text("@\(username)").foregroundStyle(.secondary).lineLimit(1)
      }
      if PeopleList.isAgent(person) {
        AgentBadge()
      }
      Spacer(minLength: 0)
    }
  }
}

/** "Agent", beside an AI agent's name (web `AgentBadge`). */
struct AgentBadge: View {
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    switch look {
    case .suite:
      StatusCapsule(text: "Agent", tint: SemanticColor.accent, help: "An AI agent")
    case .irc:
      Text("[agent]").foregroundStyle(irc.action)
    }
  }
}

/**
 * New direct message (web `NewDirectDialog`): find people by name or @name, pick one or more, and
 * start the conversation, or open the one the group has.
 */
struct NewDirectSheet: View {
  let session: InstanceSession
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var query = ""
  @State private var picked: [DirectoryUser] = []
  @State private var shown = PeopleList.page
  @State private var loaded = false
  @State private var starting = false
  @State private var failure: String?
  @State private var loadFailed = false
  /** The person arrow keys have moved to, whom Return picks. */
  @State private var highlighted = 0

  private var matches: [DirectoryUser] {
    guard let me = session.me else { return [] }
    let pickedIds = Set(picked.map(\.id))
    return PeopleList.matching(session.people.values, me: me, name: PeopleList.soughtName(query)).filter { !pickedIds.contains($0.id) }
  }

  /** What the line under the list says (web `statusOf`). */
  private var status: String {
    if let failure { return failure }
    if starting { return "Starting conversation..." }
    if loadFailed { return NavigationText.couldNotLoadPeople }
    if !loaded { return "Loading people..." }
    guard let me = session.me else { return "Loading people..." }
    let everyone = PeopleList.matching(session.people.values, me: me, name: "")
    if everyone.isEmpty { return "No other people are available to message yet." }
    if matches.isEmpty { return picked.isEmpty || !PeopleList.soughtName(query).isEmpty ? "No people found. Try another name." : "Everyone shown is selected." }
    return picked.isEmpty ? "Choose one or more people." : ""
  }

  var body: some View {
    Group {
      switch look {
      case .suite:
        SheetFrame(title: "New direct message", systemImage: "square.and.pencil") {
          content
        } footer: {
          EditorFooter(
            canSave: !picked.isEmpty && !starting, canCancel: !starting, saveHelp: "Start conversation",
            saveTitle: EditorActionTitle("Start conversation"), onCancel: { dismiss() }, onSave: start)
        }
      case .irc:
        VStack(alignment: .leading, spacing: 10) {
          Text("/query").font(Theme.font(18, weight: .bold)).foregroundStyle(irc.ember)
          content
          HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.disabled(starting)
            Button("Start conversation", action: start)
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
              .disabled(picked.isEmpty || starting)
          }
        }
        .font(Theme.font(13))
        .padding(24)
        .background(irc.buffer)
        .preferredColorScheme(.dark)
      }
    }
    .frame(minWidth: 440, minHeight: 420)
    // Loaded again on each opening, so someone who just joined is there.
    .task { await load() }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text(NavigationText.newDirectHint).foregroundStyle(.secondary)
      if !picked.isEmpty {
        FlowLayout {
          ForEach(picked) { person in
            Button {
              picked.removeAll { $0.id == person.id }
            } label: {
              Label(person.name, systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .help("Remove \(person.name)")
          }
        }
      }
      TextField("Search by name or @name", text: $query)
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
        .onChange(of: query) {
          shown = PeopleList.page
          highlighted = 0
        }
        .onSubmit {
          let list = Array(matches.prefix(shown))
          if list.indices.contains(highlighted) { pick(list[highlighted]) }
        }
        .onKeyPress(.downArrow) {
          highlighted = min(highlighted + 1, max(min(matches.count, shown) - 1, 0))
          return .handled
        }
        .onKeyPress(.upArrow) {
          highlighted = max(highlighted - 1, 0)
          return .handled
        }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(matches.prefix(shown).enumerated()), id: \.element.id) { index, person in
            Button {
              pick(person)
            } label: {
              PersonRow(session: session, person: person)
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
                .background(index == highlighted ? (look == .irc ? irc.ember.opacity(0.22) : Color.accentColor.opacity(0.18)) : Color.clear)
            }
            .buttonStyle(.plain)
          }
          if matches.count > shown {
            Button("Show more people") { shown += PeopleList.page }.padding(.top, Spacing.sm)
          }
        }
      }
      .frame(minHeight: 200)
      if !status.isEmpty {
        Text(status).foregroundStyle(failure == nil && !loadFailed ? Color.secondary : SemanticColor.warning)
      }
      if loadFailed {
        Button("Try again", systemImage: "arrow.clockwise") { Task { await load() } }
      }
    }
  }

  private func load() async {
    loadFailed = false
    do {
      try await session.loadDirectory()
      loaded = true
    } catch {
      logger.error("Loading people failed: \(error.localizedDescription, privacy: .public)")
      loadFailed = true
    }
  }

  private func pick(_ person: DirectoryUser) {
    highlighted = 0
    picked.append(person)
    query = ""
    failure = nil
  }

  private func start() {
    guard !picked.isEmpty, !starting else { return }
    starting = true
    failure = nil
    Task {
      do {
        let started = try await session.startDirect(with: picked.map(\.id))
        if !started.without.isEmpty { session.notice = PeopleList.startedWithout(started.without) }
        dismiss()
      } catch let error as EmberError where error.problem != nil {
        failure = error.localizedDescription
      } catch {
        logger.error("Starting a DM failed: \(error.localizedDescription, privacy: .public)")
        failure = "Couldn't start the conversation. Please try again."
      }
      starting = false
    }
  }
}

/**
 * New room (web `NewRoomPage` and `RoomForm`): a name, an icon, and who's in it, everyone or the people
 * chosen. Ember lists it last and the app goes to it.
 */
struct NewRoomSheet: View {
  let session: InstanceSession
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var name = "New room"
  @State private var icon: String?
  @State private var everyone = true
  @State private var chosen: Set<UserID> = []
  @State private var people: [User] = []
  @State private var filter = ""
  @State private var saving = false
  @State private var failure: String?
  @State private var refused: String?
  @State private var confirmingLeave = false

  private var changed: Bool { name != "New room" || icon != nil || !everyone || !chosen.isEmpty }
  private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

  var body: some View {
    NavigationStack {
      Form {
        if let refused {
          Section { Text(refused).foregroundStyle(SemanticColor.warning) }
        } else {
          Section {
            Text(NavigationText.newRoomHint).foregroundStyle(.secondary)
            TextField("Room name", text: $name, prompt: Text("Name the room"))
              .onChange(of: name) { _, new in if new.count > EmberLimits.maxRoomNameLength { name = String(new.prefix(EmberLimits.maxRoomNameLength)) } }
            LabeledContent("Icon") { IconPicker(api: session.api, icon: $icon) }
          }
          RoomPeopleSection(session: session, people: people, everyone: $everyone, chosen: $chosen, filter: $filter, editable: true)
          if let failure {
            Section { Text(failure).foregroundStyle(SemanticColor.warning) }
          }
        }
      }
      .themedForm(look, irc)
      .navigationTitle("New room")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { if changed { confirmingLeave = true } else { dismiss() } }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(saving ? "Saving…" : "Save", action: save)
            .disabled(trimmed.isEmpty || saving || refused != nil)
        }
      }
      .confirmationDialog("Discard this room?", isPresented: $confirmingLeave) {
        Button("Discard", role: .destructive) { dismiss() }
        Button("Keep Editing", role: .cancel) {}
      }
    }
    .frame(minWidth: 460, minHeight: 520)
    // A swipe down can't drop what's filled in: Cancel asks first.
    .interactiveDismissDisabled(changed)
    .task { await load() }
  }

  private func load() async {
    do {
      people = try await session.api.people().people
    } catch let error as EmberError where error.problem?.status == 403 {
      refused = error.localizedDescription
    } catch {
      logger.error("Loading the new room form failed: \(error.localizedDescription, privacy: .public)")
      failure = error.localizedDescription
    }
  }

  private func save() {
    guard !trimmed.isEmpty, !saving else { return }
    saving = true
    failure = nil
    Task {
      do {
        try await session.createRoom(name: trimmed, icon: icon, closed: !everyone, memberIds: Array(chosen))
        dismiss()
      } catch {
        logger.error("Making a room failed: \(error.localizedDescription, privacy: .public)")
        failure = error.localizedDescription
      }
      saving = false
    }
  }
}

/**
 * Who's in a room, as the room form lists them (web `RoomForm`'s people box): an Everyone switch, then
 * each person, checked in an open room, or with an access switch in a private one; you're always in it.
 * A filter shows above 20 people.
 */
struct RoomPeopleSection: View {
  let session: InstanceSession
  let people: [User]
  @Binding var everyone: Bool
  @Binding var chosen: Set<UserID>
  @Binding var filter: String
  let editable: Bool
  /** Whether you're always in it, as a new room's maker is; a room's settings can take you out. */
  var includesMe = true
  /** A private room's members as it was saved, who list first, over a divider, then everyone else (web `RoomForm`). */
  var members: Set<UserID>?

  private var shown: [User] {
    let sought = PeopleList.folded(filter.trimmingCharacters(in: .whitespaces))
    let named = people.map { session.people[$0.id].map(\.user) ?? $0 }
    let filtered = sought.isEmpty ? named : named.filter { PeopleList.folded($0.name).contains(sought) }
    return filtered.sorted { PeopleList.folded($0.name) < PeopleList.folded($1.name) }
  }

  var body: some View {
    Section("People") {
      Toggle("Everyone", isOn: $everyone).disabled(!editable)
      if people.count > 20 {
        TextField("Filter...", text: $filter)
      }
      if !everyone, let members {
        ForEach(shown.filter { members.contains($0.id) }) { row($0) }
        Divider()
        ForEach(shown.filter { !members.contains($0.id) }) { row($0) }
      } else {
        ForEach(shown) { row($0) }
      }
    }
  }

  @ViewBuilder
  private func row(_ person: User) -> some View {
    if everyone || (includesMe && person.id == session.me?.id) {
      Label(person.name, systemImage: "checkmark")
    } else {
      Toggle(person.name, isOn: Binding(
        get: { chosen.contains(person.id) },
        set: { on in if on { chosen.insert(person.id) } else { chosen.remove(person.id) } }))
        .disabled(!editable)
        .help("Give \(person.name) access to this room")
    }
  }
}
