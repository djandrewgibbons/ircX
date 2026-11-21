import AppCoreUI
import EmberKit
import SwiftUI

/** The page an instance shows in place of its room, in either theme. */
struct SessionPageView: View {
  let session: InstanceSession
  let page: SessionPage

  var body: some View {
    switch page {
    case .search:
      SearchResultsPage(session: session)
    case let .person(id):
      PersonPage(session: session, userID: id).id(id)
    case .profile:
      ProfilePage(session: session)
    case let .settings(id):
      RoomSettingsPage(session: session, roomID: id).id(id)
    case .huddles:
      HuddlesPage(session: session)
    case .pushSubscriptions:
      PushSubscriptionsPage(session: session)
    case let .unavailable(reason, id, messageId, threadId):
      UnavailablePage(session: session, reason: reason) { session.show(id, messageId: messageId, threadId: threadId) }
    }
  }
}

/** What shows in place of the room until the rooms have loaded: loading, or why they didn't, with Try again. */
struct SidebarLoadingState: View {
  let session: InstanceSession
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    if let failure = session.sidebarFailure {
      switch look {
      case .suite:
        ContentUnavailableView {
          Label("Couldn't Load Rooms", systemImage: "exclamationmark.triangle")
        } description: {
          Text(failure)
        } actions: {
          Button("Try Again", systemImage: "arrow.clockwise", action: session.retryLoading)
        }
      case .irc:
        IRCEmptyState(title: "Couldn't load rooms", detail: failure, action: "Try again", perform: session.retryLoading)
      }
    } else {
      switch look {
      case .suite:
        LoadingOcean().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .irc:
        VStack(spacing: 12) {
          ProgressView().controlSize(.small)
          Text("Loading rooms…").font(Theme.font(12)).foregroundStyle(irc.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(irc.buffer)
      }
    }
  }
}

/** A room the app couldn't look for: why, and Try again (web message page with its `reason`). */
struct UnavailablePage: View {
  let session: InstanceSession
  let reason: String
  let retry: () -> Void
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: "Room", back: session.closePage)
      switch look {
      case .suite:
        ContentUnavailableView {
          Label(reason, systemImage: "exclamationmark.triangle")
        } actions: {
          Button("Try Again", systemImage: "arrow.clockwise", action: retry)
        }
      case .irc:
        IRCEmptyState(title: reason, detail: "", action: "Try again", perform: retry)
      }
    }
  }
}

/**
 * Huddles (web `HuddlesPage`): the huddles going on in this person's rooms, latest first, each with who's
 * in it, when it started, their faces and Join, and the recent ones that are over, each with when it
 * started, how long it went on, its replies and the faces of who was in it, opening its thread. The list
 * loads once the rooms have, and again as a huddle ends or as rooms are listed or hidden.
 */
struct HuddlesPage: View {
  let session: InstanceSession
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var past: [PastHuddle]?
  @State private var failure: String?

  /** The huddles going on, while huddles are on here. */
  private var live: [RoomID: LiveHuddle] { session.account?.huddles == true ? session.huddles : [:] }

  /** The huddles that are over in rooms still listed and not hidden, but one still going on (`recentHuddles`). */
  private var recent: [(room: SidebarRoom, huddle: PastHuddle)]? {
    guard let past else { return nil }
    let listed = Dictionary(session.rooms.filter { $0.involvement != .invisible }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return past.compactMap { huddle in
      guard let room = listed[huddle.roomId], live[huddle.roomId]?.startedAt != huddle.startedAt else { return nil }
      return (room, huddle)
    }
  }

  /** What the list loads again on: a huddle's end, as the sidebar hears, and the rooms it's for, once they've come. */
  private var reload: String? {
    guard session.sidebarLoaded else { return nil }
    let shown = session.rooms.filter { $0.involvement != .invisible }.map(\.id).sorted().joined(separator: " ")
    return "\(session.huddlesChanged) \(shown)"
  }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: NavigationText.huddles, back: session.closePage)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: look == .irc ? 2 : Spacing.md) {
          let going = HuddleList.goingOn(session.rooms, live: live)
          if !going.isEmpty {
            heading(NavigationText.happeningNow)
            ForEach(going, id: \.room.id) { item in
              goingOn(item.room, item.huddle)
            }
          }
          if let recent {
            heading(NavigationText.recentHuddles)
            if recent.isEmpty {
              Text(NavigationText.noHuddlesYet).foregroundStyle(.secondary)
            }
            ForEach(recent, id: \.huddle.messageId) { item in
              over(item.room, item.huddle)
            }
          } else if let failure {
            Text(failure).foregroundStyle(look == .irc ? irc.part : SemanticColor.warning)
          }
        }
        .padding(look == .irc ? 12 : PaneGrid.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .loadingActivity(past == nil && failure == nil)
    }
    .font(look == .irc ? Theme.font(12) : DesignFont.body)
    .background(look == .irc ? irc.buffer : Color.clear)
    .task(id: reload) {
      guard reload != nil else { return }
      await load()
    }
  }

  private func heading(_ text: String) -> some View {
    Text(text).font(look == .irc ? Theme.font(12, weight: .bold) : DesignFont.sectionHeader).padding(.top, Spacing.sm)
  }

  private func name(_ room: SidebarRoom) -> String {
    look == .irc && !room.room.isDirect ? "#" + session.title(of: room.room) : session.title(of: room.room)
  }

  private func names(_ ids: [UserID]) -> [String] { ids.compactMap { session.people[$0]?.name } }

  /** A huddle going on: its room, LIVE, who's in it and when it started, their faces, and Join unless the app is in it. */
  private func goingOn(_ room: SidebarRoom, _ huddle: LiveHuddle) -> some View {
    let me = session.me?.id
    let others = huddle.userIds.filter { $0 != me }
    let who = MessageWords.inItsHuddle(names(others), count: others.count, you: others.count < huddle.userIds.count)
    let started = EmberDate.parse(huddle.startedAt)
    let here = session.huddleCenter?.call.map { $0.session === session && $0.roomId == room.id } == true
    return HStack(spacing: Spacing.md) {
      Button {
        session.open(room: room.id)
      } label: {
        HStack(spacing: Spacing.md) {
          if look == .suite { Image(systemName: "headphones").foregroundStyle(SemanticColor.positive) }
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.sm) {
              Text(name(room)).font(look == .irc ? Theme.font(12, weight: .bold) : DesignFont.bodyEmphasized)
              if look == .suite { SuiteLiveBadge() } else { Text("[LIVE]").foregroundStyle(irc.join) }
            }
            Text("\(who) · started \(started.map { $0.formatted(date: .omitted, time: .shortened) } ?? huddle.startedAt)")
              .foregroundStyle(.secondary).lineLimit(1)
              .help(started.map(MessageWords.dateTime) ?? huddle.startedAt)
          }
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      HuddleFaces(session: session, ids: huddle.userIds)
      if !here {
        let place = HuddleRules.place(room.room, name: session.title(of: room.room))
        Button {
          session.huddleCenter?.preview(room.id, in: session)
        } label: {
          if look == .suite {
            SuiteJoinLabel()
          } else {
            HStack(spacing: 0) {
              Text("[").foregroundStyle(irc.statusBracket)
              Text("join").foregroundStyle(irc.join)
              Text("]").foregroundStyle(irc.statusBracket)
            }
          }
        }
        .buttonStyle(.plain)
        .help("Join the huddle \(place)")
        .accessibilityLabel("Join the huddle \(place)")
      }
    }
    .padding(look == .suite ? Spacing.md : 0)
    .background {
      if look == .suite {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(SemanticColor.positive.opacity(0.08))
      }
    }
  }

  /** A huddle that's over: its room, when it started, how long it went on, its replies, and the faces of who was in it. */
  private func over(_ room: SidebarRoom, _ huddle: PastHuddle) -> some View {
    let me = session.me?.id
    let others = huddle.userIds.filter { $0 != me }
    let who = HuddleWords.wereInItsHuddle(names(others), count: others.count, you: others.count < huddle.userIds.count)
    let start = EmberDate.parse(huddle.startedAt)
    var detail = [start.map { MessageWords.huddleStarted($0) } ?? huddle.startedAt]
    if let start, let end = EmberDate.parse(huddle.endedAt) { detail.append(MessageWords.huddleLasted(from: start, to: end)) }
    if huddle.replies > 0 { detail.append(MessageWords.replies(huddle.replies)) }
    return Button {
      session.show(room.room.id, messageId: nil, threadId: huddle.messageId)
    } label: {
      HStack(spacing: Spacing.md) {
        if look == .suite { Image(systemName: "headphones").foregroundStyle(Color.secondary) }
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(name(room)).font(look == .irc ? Theme.font(12, weight: .bold) : DesignFont.bodyEmphasized)
          Text(detail.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
        HuddleFaces(session: session, ids: huddle.userIds).help(who)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityValue(who)
  }

  private func load() async {
    do {
      past = try await session.api.pastHuddles()
      failure = nil
    } catch {
      logger.error("Loading huddles failed: \(error.localizedDescription, privacy: .public)")
      // Once the list has come, one that can't come again leaves the page as it was.
      if past == nil { failure = error.localizedDescription }
    }
  }
}

/** The faces of the first four people in a huddle, overlapping, in either theme (web `Faces`). */
struct HuddleFaces: View {
  let session: InstanceSession
  let ids: [UserID]
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    let face = look == .suite ? HuddleLook.suite(session) : HuddleLook.irc(irc)
    HStack(spacing: look == .suite ? -Spacing.xs : 2) {
      ForEach(ids.prefix(4).compactMap { session.people[$0]?.user }) { user in
        face.face(user, look == .suite ? 24 : 18)
          .clipShape(RoundedRectangle(cornerRadius: look == .suite ? Radius.section : 2, style: .continuous))
      }
    }
    .accessibilityHidden(true)
  }
}

/**
 * Available Agents (web `AvailableAgentsDialog`): the AI agents this person can ask, @ember first, and the
 * one picked, with its @name, what it does, where it works, and Message.
 */
struct AvailableAgentsSheet: View {
  let session: InstanceSession
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var loaded: [AvailableAgent]?
  @State private var pickedId: UserID?
  @State private var starting = false
  @State private var failure: String?
  /** The page an administrator asked for (New agent, Edit), opened over Server Settings once this closes. */
  @State private var editing: AIEditor?

  private var administrator: Bool { session.me?.administrator == true }

  /** The agents as the directory has them now: gone ones and ones now kept for administrators left out (`listedNow`). */
  private var agents: [AvailableAgent] {
    guard let me = session.me else { return [] }
    return (loaded ?? []).compactMap { agent in
      guard let listed = session.people[agent.id], listed.status == .active, PeopleList.canAsk(listed, me: me) else { return nil }
      var shown = agent
      shown.name = listed.name
      return shown
    }
  }

  var body: some View {
    let picked = agents.first { $0.id == pickedId } ?? agents.first
    NavigationStack {
      Form {
        Section {
          Text(NavigationText.howToAsk).foregroundStyle(.secondary)
          ForEach(agents) { agent in
            Button {
              pickedId = agent.id
            } label: {
              HStack(spacing: Spacing.md) {
                if look == .suite { SuiteAvatar(session: session, user: User(id: agent.id, name: agent.name), size: 24) }
                Text(agent.name).fontWeight(agent.id == picked?.id ? .semibold : .regular)
                Spacer(minLength: 0)
                if let kept = NavigationText.keptFor(agent.access) { Text(kept).foregroundStyle(.secondary) }
                if agent.id == picked?.id { Image(systemName: "checkmark").foregroundStyle(.secondary) }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        } header: {
          Text("\(NavigationText.availableAgents) (\(agents.count))")
        }
        if administrator, loaded != nil, agents.filter({ $0.id != Assistant.id }).count < AgentRules.maxAgents {
          Section {
            Button(look == .irc ? "[new agent]" : "New Agent", systemImage: "plus") { edit(.agent(nil)) }
          }
        }
        if let picked {
          Section(picked.name) {
            if look == .suite {
              SuiteAvatar(session: session, user: User(id: picked.id, name: picked.name), size: 64)
            }
            Button("@\(picked.name)", systemImage: "doc.on.doc") { Pasteboard.copy("@\(picked.name)") }
              .help("Copy @\(picked.name)")
            Text(picked.description)
            Text(picked.rooms?.isEmpty == true ? NavigationText.directOnly(picked.access) : "Type @\(picked.name) in a room it's in, or message it directly.")
              .foregroundStyle(.secondary)
            whereItWorks(picked)
            Button(starting ? "Starting…" : "Message \(picked.name)", systemImage: "bubble.left.and.text.bubble.right") { message(picked) }
              .disabled(starting)
            if administrator {
              Button(look == .irc ? "[edit]" : "Edit", systemImage: "pencil") { edit(picked.id == Assistant.id ? .ember : .agent(picked.id)) }
                .help("Edit \(picked.name)")
            }
          }
        } else if loaded != nil {
          Text(NavigationText.noAgents).foregroundStyle(.secondary)
        }
        if let failure {
          Section { Text(failure).foregroundStyle(SemanticColor.warning) }
        }
      }
      .themedForm(look, irc)
      .loadingActivity(loaded == nil && failure == nil)
      .navigationTitle(NavigationText.availableAgents)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
      }
    }
    .frame(minWidth: 460, minHeight: 440)
    .task { await load() }
    .onDisappear {
      guard let editing else { return }
      // Server Settings opens once this sheet has gone, at Ember AI, with the page asked for over it.
      session.openWorkspaceSettings(.assistant)
      session.admin.ai.editor = editing
    }
  }

  private func edit(_ editor: AIEditor) {
    editing = editor
    dismiss()
  }

  /**
   * Where an agent works (web `Where`): every room, DMs alone, or a chip for each room it shares with this
   * person, named as the sidebar names it, which opens the room.
   */
  @ViewBuilder
  private func whereItWorks(_ agent: AvailableAgent) -> some View {
    if let rooms = agent.rooms, !rooms.isEmpty {
      LabeledContent("Available in") {
        FlowLayout {
          ForEach(rooms, id: \.id) { room in
            let listed = session.rooms.first { $0.id == room.id }
            let name = listed.map { session.title(of: $0.room) } ?? room.name
            Button(look == .irc ? "[\(name)]" : name) {
              session.open(room: room.id)
              dismiss()
            }
            .buttonStyle(.bordered)
            .help("Open \(name)")
          }
        }
      }
    } else {
      LabeledContent("Available in") { Text(agent.rooms == nil ? NavigationText.everyRoom : NavigationText.directsOnly) }
    }
  }

  private func load() async {
    do {
      loaded = try await session.api.availableAgents()
    } catch {
      logger.error("Loading the agents failed: \(error.localizedDescription, privacy: .public)")
      failure = error.localizedDescription
    }
  }

  private func message(_ agent: AvailableAgent) {
    guard !starting else { return }
    starting = true
    Task {
      do {
        try await session.startDirect(with: [agent.id])
        dismiss()
      } catch {
        logger.error("Starting a DM with an agent failed: \(error.localizedDescription, privacy: .public)")
        failure = error.localizedDescription
      }
      starting = false
    }
  }
}
