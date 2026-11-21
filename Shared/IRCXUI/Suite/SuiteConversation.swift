import AppCoreUI
import EmberKit
import SwiftUI

/** A room under the Suite theme: its header, its messages as Slack shows them, who's typing and the composer. */
struct SuiteConversation: View {
  let app: AppModel
  let session: InstanceSession
  @Bindable var room: RoomModel
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var showingPeople = false

  var body: some View {
    VStack(spacing: 0) {
      #if os(macOS)
      header
      #else
      // The header's words a phone's toolbar has no room for: the Agent badge, connecting, the bell's note.
      phoneHeader
      #endif
      SuiteMessageList(
        session: session, room: room, lines: room.timeline.lines, hasMore: room.timeline.hasMore, onOlder: room.loadOlder,
        openThread: room.openThread)
        .dropDestination(for: URL.self) { urls, _ in
          room.composer().pick(urls: urls)
          return true
        }
      SuiteRoomNotice(room: room)
      if room.ended {
        SuiteRoomDeleted()
      } else {
        SuiteComposer(app: app, session: session, room: room, placeholder: "Message \(displayName)")
      }
    }
    .roomRequests(room, composer: room.composer(), active: threadIsBeside)
    .reportsLoadingActivity(room.socketState != .open && room.timeline.seq == nil)
    #if os(iOS)
    .navigationTitle(displayName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) { headerButtons }
    }
    .sheet(isPresented: Binding(get: { room.thread != nil }, set: { if !$0 { room.closeThread() } })) {
      NavigationStack {
        SuiteThreadPane(app: app, session: session, room: room)
      }
      .presentationDetents([.medium, .large])
    }
    #endif
  }

  private var displayName: String {
    room.room.isDirect ? room.title : "#\(room.title)"
  }

  /** Whether the conversation shows what its thread asks for: on a phone the thread is a sheet over it, which does. */
  private var threadIsBeside: Bool {
    #if os(iOS)
    room.thread == nil
    #else
    true
    #endif
  }

  private var header: some View {
    PaneHeaderBar {
      HStack(spacing: Spacing.sm) {
        if room.room.isDirect {
          Image(systemName: "bubble.left").foregroundStyle(.secondary).accessibilityHidden(true)
        } else {
          RoomIconView(api: session.api, room: room.room, size: PaneGrid.iconColumn).foregroundStyle(.secondary)
        }
        Text(session.title(of: room.room)).font(DesignFont.cardTitle).lineLimit(1)
          .accessibilityLabel(room.room.isDirect ? "Direct message with \(session.title(of: room.room))" : session.title(of: room.room))
        if session.isWithAgent(room.room) { AgentBadge() }
        if !room.room.isDirect {
          starButton
        }
        if room.socketState != .open, !room.ended {
          StatusCapsule(text: room.socketState == .connecting ? "Connecting..." : "Reconnecting...", help: "Messages send once it's connected", isBusy: true)
        }
        if let note = session.involvementNotes[room.id] {
          Text(note).font(DesignFont.detail).foregroundStyle(.secondary).lineLimit(1)
        }
      }
    } trailing: {
      headerButtons
    }
  }

  @ViewBuilder
  private var phoneHeader: some View {
    let connecting = room.socketState != .open && !room.ended
    let note = session.involvementNotes[room.id]
    if session.isWithAgent(room.room) || connecting || note != nil {
      HStack(spacing: Spacing.sm) {
        if session.isWithAgent(room.room) { AgentBadge() }
        if connecting {
          StatusCapsule(text: room.socketState == .connecting ? "Connecting..." : "Reconnecting...", help: "Messages send once it's connected", isBusy: true)
        }
        if let note { Text(note).font(DesignFont.detail).foregroundStyle(.secondary).lineLimit(1) }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, PaneGrid.leadingEdge)
      .padding(.vertical, Spacing.xs)
    }
  }

  /** The header's star (web `FavoriteButton`): what Ember answers, dimmed while it's saving. */
  private var starButton: some View {
    let starred = session.isStarred(room.id)
    return PaneIconButton(systemImage: starred ? "star.fill" : "star", help: starred ? "Remove from favorites" : "Add to favorites") {
      session.toggleFavorite(room.id)
    }
    .disabled(session.starring.contains(room.id))
    .opacity(session.starring.contains(room.id) ? 0.5 : 1)
    .accessibilityLabel("Favorite room")
  }

  @ViewBuilder
  private var headerButtons: some View {
    if session.hasHuddles(room.room) { SuiteHuddleButton(app: app, session: session, room: room.room) }
    #if os(iOS)
    if !room.room.isDirect { starButton }
    #endif
    // Who has the room open: up to four faces and how many more (web `HereNow`).
    Button {
      showingPeople.toggle()
    } label: {
      SuiteHereFaces(session: session, present: room.timeline.present)
    }
    .buttonStyle(.plain)
    .help(hereHelp)
    .accessibilityLabel("\(room.timeline.present.count) here now")
    .popover(isPresented: $showingPeople) {
      SuitePeopleList(session: session, room: room)
    }
    PaneIconButton(systemImage: "magnifyingglass", help: "Search messages") { session.openSearchBox(in: room.id) }
    if let item = session.rooms.first(where: { $0.id == room.id }) {
      Menu {
        InvolvementMenu(session: session, item: item)
        PushMenuItems(session: session, room: room)
      } label: {
        Image(systemName: item.involvement.symbol)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help(item.involvement.sentence)
    }
    PaneIconButton(systemImage: "gearshape", help: "Conversation settings") { session.show(.settings(room.id)) }
  }

  /** Who has the room open, by name (web `HereNow`). */
  private var hereHelp: String {
    let present = room.timeline.present
    guard !present.isEmpty else { return "Nobody here now" }
    return "\(present.count) here now: " + present.map { session.people[$0.id]?.name ?? $0.name }.joined(separator: ", ")
  }
}

/** Who has the room open, as stacked faces: up to four, then +N (web `HereNow`'s `Faces`). */
struct SuiteHereFaces: View {
  let session: InstanceSession
  let present: [User]

  var body: some View {
    HStack(spacing: Spacing.xs) {
      if present.isEmpty {
        Image(systemName: "person.2").foregroundStyle(.secondary)
      } else {
        HStack(spacing: -Spacing.sm) {
          ForEach(present.prefix(4)) { user in
            SuiteAvatar(session: session, user: session.people[user.id]?.user ?? user, size: 22)
              .overlay(Circle().strokeBorder(SemanticColor.background, lineWidth: 1.5))
          }
        }
        if present.count > 4 {
          Text("+\(present.count - 4)").font(DesignFont.detail).foregroundStyle(.secondary)
        }
      }
    }
  }
}

/** In place of the composer once the room is gone (web `RoomDeleted`). */
struct SuiteRoomDeleted: View {
  var body: some View {
    Text("This room was deleted.")
      .font(DesignFont.body)
      .foregroundStyle(SemanticColor.destructive)
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.sm)
      .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(SemanticColor.destructive))
      .padding(Spacing.lg)
      .accessibilityAddTraits(.isStaticText)
  }
}

/** What the room has to say, such as why something didn't go, until it's dismissed (web `RoomNotice`). */
struct SuiteRoomNotice: View {
  let room: RoomModel

  var body: some View {
    SuiteNotice(text: room.notice, dismiss: room.dismissNotice)
  }
}

/** What the open thread has to say, such as why a reply didn't go, over its replies (web thread panel's `RoomNotice`). */
struct SuiteThreadNotice: View {
  let room: RoomModel

  var body: some View {
    SuiteNotice(text: room.thread?.notice, dismiss: room.dismissThreadNotice)
  }
}

struct SuiteNotice: View {
  let text: String?
  let dismiss: () -> Void

  var body: some View {
    if let text {
      Notice(text, systemImage: "exclamationmark.bubble", tint: SemanticColor.warning, onDismiss: dismiss)
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
    }
  }
}

/** Who has the room open now. */
struct SuitePeopleList: View {
  let session: InstanceSession
  let room: RoomModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ListSectionHeader("Here Now", systemImage: "person.2", inset: .panel)
        .padding(.top, Spacing.lg)
      ForEach(room.timeline.present.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { user in
        SelectableListRow(isSelected: false) {
          session.show(.person(user.id))
        } label: {
          ListRowLabel(title: session.people[user.id]?.name ?? user.name, systemImage: session.people[user.id]?.role == .administrator ? "person.badge.shield.checkmark" : "person")
        } trailing: {
          if user.id != session.me?.id {
            PaneIconButton(systemImage: "bubble.left", help: "Message \(session.people[user.id]?.name ?? user.name)") {
              session.attempt("Opening a DM") { try await session.startDirect(with: [user.id]) }
            }
          }
        }
      }
    }
    .padding(.bottom, Spacing.md)
    .frame(minWidth: 240)
  }
}

/** Messages, newest at the bottom, grouped by author as Slack groups them, with day dividers. */
struct SuiteMessageList: View {
  let session: InstanceSession
  let room: RoomModel
  let lines: [BufferLine]
  let hasMore: Bool
  let onOlder: () -> Void
  let openThread: (String) -> Void
  var inThread = false

  @State private var position = ScrollPosition(edge: .bottom)
  @State private var atBottom = true
  @State private var outlined: String?

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if !inThread {
          WelcomeCard(session: session, room: room)
        }
        if hasMore {
          Text(room.loadingOlder && !inThread ? "Loading earlier messages\u{2026}" : " ")
            .font(DesignFont.detail)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.xxl)
            .onAppear(perform: onOlder)
        }
        if let joined = joinedShown {
          SuiteDayDivider(date: joined.date)
          SuiteJoinedRow(session: session, joined: joined.joined, date: joined.date)
        }
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
          let previous = index > 0 ? lines[index - 1] : nil
          let before = previous?.date ?? joinedShown?.date
          if before.map({ !Calendar.current.isDate($0, inSameDayAs: line.date) }) != false {
            SuiteDayDivider(date: line.date)
          }
          if !inThread, line.id == room.firstNewLineID {
            SuiteNewDivider()
          }
          SuiteMessageRow(
            session: session, room: room, line: line, continues: Self.continues(line, after: previous), openThread: openThread, inThread: inThread)
            .overlay {
              if outlined == line.id {
                RoundedRectangle(cornerRadius: Radius.control).strokeBorder(SemanticColor.accent, lineWidth: 2).allowsHitTesting(false)
              }
            }
            .id(line.id)
        }
        if !inThread, room.timeline.hasNewer {
          Text(room.loadingNewer ? "Loading newer messages\u{2026}" : " ")
            .font(DesignFont.detail)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.xxl)
            .onAppear(perform: room.loadNewer)
        }
      }
      .padding(.vertical, Spacing.md)
    }
    .scrollPosition($position)
    .defaultScrollAnchor(.bottom)
    .scrollFade()
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
    } action: { _, bottom in
      atBottom = bottom
      if bottom, !room.timeline.hasNewer { room.readNewest() }
    }
    .overlay(alignment: .bottomTrailing) {
      if !inThread, room.timeline.hasNewer || (room.arrivals > 0 && !atBottom) {
        PaneIconButton(systemImage: "arrow.down", help: "Jump to newest message", action: jumpToNewest)
          .padding(Spacing.xs)
          .glassEffect(.regular, in: Circle())
          .padding(Spacing.lg)
      }
    }
    .onChange(of: room.timeline.around) { _, around in outline(around) }
    .onChange(of: room.toNewest) { _, _ in if !inThread { position.scrollTo(edge: .bottom) } }
    .onAppear { outline(room.timeline.around) }
    .environment(\.openURL, MessageLinks.opener(session))
  }

  /** A welcome DM's joined line, once the timeline reaches back to its start, never in a thread (web `JoinedItem`). */
  private var joinedShown: (joined: Joined, date: Date)? {
    guard !inThread, !hasMore, let joined = room.room.joined, let date = EmberDate.parse(joined.at) else { return nil }
    return (joined, date)
  }

  /** Back to the newest messages, paging there first if the timeline doesn't hold them (web `jump`). */
  private func jumpToNewest() {
    room.jumpToNewest()
  }

  /** The message a permalink opened, scrolled to the middle and outlined for a moment (web `OUTLINE_MS`). */
  private func outline(_ around: String?) {
    guard !inThread, let around, let line = lines.first(where: { if case let .message(message, _) = $0 { message.id == around } else { false } }) else { return }
    position.scrollTo(id: line.id, anchor: .center)
    outlined = line.id
    Task {
      try? await Task.sleep(for: .milliseconds(1500))
      if outlined == line.id { outlined = nil }
    }
  }

  /**
   * Whether `line` follows a message by the same author within five minutes, across midnight too, so it
   * leaves out the name and avatar; never a huddle's or a deleted stand-in, nor one after them (web `timeline`).
   */
  static func continues(_ line: BufferLine, after previous: BufferLine?) -> Bool {
    guard case let .message(message, _) = line, case let .message(before, _)? = previous else { return false }
    let interval = message.createdDate.timeIntervalSince(before.createdDate)
    return before.creator.id == message.creator.id && interval >= 0 && interval < 300 && !message.isAction && !before.isAction
      && message.deleted != true && before.deleted != true && message.huddle == nil && before.huddle == nil
  }
}

/** "joined <workspace>": the start of a welcome DM, with the newcomer's avatar, name and time (web `JoinedItem`). */
struct SuiteJoinedRow: View {
  let session: InstanceSession
  let joined: Joined
  let date: Date

  var body: some View {
    let name = session.people[joined.userId]?.name ?? joined.userId
    HStack(alignment: .top, spacing: Spacing.md) {
      Button { session.show(.person(joined.userId)) } label: {
        SuiteAvatar(session: session, user: User(id: joined.userId, name: name), size: 36)
      }
      .buttonStyle(.plain)
      VStack(alignment: .leading, spacing: Spacing.xs) {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
          Text(name).font(DesignFont.bodyEmphasized)
          Text(date.formatted(date: .omitted, time: .shortened)).font(DesignFont.detail).foregroundStyle(.secondary)
        }
        Text(NavigationText.joined(session.name)).font(DesignFont.body).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, PaneGrid.leadingEdge)
    .padding(.vertical, Spacing.xs)
  }
}

/** The red "New" line over the first message that came since the room was last read (web `NewSeparator`). */
struct SuiteNewDivider: View {
  var body: some View {
    HStack(spacing: Spacing.md) {
      VStack { Divider().overlay(SemanticColor.destructive) }
      Text("New").font(DesignFont.detail.weight(.semibold)).foregroundStyle(SemanticColor.destructive)
    }
    .padding(.horizontal, PaneGrid.leadingEdge)
    .padding(.vertical, Spacing.xs)
  }
}

struct SuiteDayDivider: View {
  let date: Date

  var body: some View {
    HStack(spacing: Spacing.md) {
      VStack { Divider() }
      Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .font(DesignFont.detail)
        .foregroundStyle(.secondary)
      VStack { Divider() }
    }
    .padding(.horizontal, PaneGrid.leadingEdge)
    .padding(.vertical, Spacing.md)
  }
}

/** A thread beside the conversation: its first message, the replies and a reply composer. */
struct SuiteThreadPane: View {
  let app: AppModel
  let session: InstanceSession
  @Bindable var room: RoomModel

  var body: some View {
    VStack(spacing: 0) {
      #if os(macOS)
      PaneHeaderBar(title: "Thread", systemImage: "bubble.left.and.bubble.right") {
        PaneIconButton(systemImage: "xmark", help: "Close Thread") { room.closeThread() }
          .keyboardShortcut(.cancelAction)
      }
      #endif
      if let thread = room.thread {
        let parent = thread.parent.map { [BufferLine.message($0, pending: false)] } ?? []
        SuiteMessageList(
          session: session, room: room, lines: parent + thread.lines, hasMore: thread.hasMore, onOlder: room.loadOlderReplies,
          openThread: { _ in }, inThread: true)
          .loadingActivity(!thread.loaded)
          .safeAreaInset(edge: .top, spacing: 0) {
            // The thread's own notice, and the room's, which the thread covers on iOS (web `ThreadReplies`).
            VStack(spacing: 0) {
              SuiteThreadNotice(room: room)
              SuiteRoomNotice(room: room)
            }
          }
        if room.ended {
          SuiteRoomDeleted()
        } else if thread.parent != nil {
          // The reply composer shows once the thread's first message has (web `ThreadPanel`).
          SuiteComposer(app: app, session: session, room: room, placeholder: "Reply\u{2026}", parentId: thread.parentId)
        }
      }
    }
    #if os(iOS)
    // A sheet over the conversation, which can't show anything more: the thread shows what its messages ask for.
    .roomRequests(room, composer: room.composer(thread: room.thread?.parentId))
    .navigationTitle("Thread")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close", systemImage: "xmark") { room.closeThread() }
      }
    }
    #endif
  }
}

/** Three dots that pulse in turn before who's typing, as the web's typing spinner. */
struct SuiteTypingDots: View {
  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.3)) { context in
      let step = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 3
      HStack(spacing: 2) {
        ForEach(0..<3) { index in
          Circle()
            .frame(width: 4, height: 4)
            .opacity(index == step ? 1 : 0.35)
        }
      }
    }
    .accessibilityHidden(true)
  }
}
