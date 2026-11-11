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
      #endif
      SuiteMessageList(
        session: session, room: room, lines: room.timeline.lines, hasMore: room.timeline.hasMore, onOlder: room.loadOlder,
        openThread: room.openThread)
      SuiteComposer(app: app, session: session, room: room, placeholder: "Message \(displayName)")
    }
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

  private var header: some View {
    PaneHeaderBar(systemImage: room.room.symbol) {
      Text(room.title).font(DesignFont.cardTitle).lineLimit(1)
    } trailing: {
      headerButtons
    }
  }

  @ViewBuilder
  private var headerButtons: some View {
    let starred = session.favorites.contains(room.id)
    PaneIconButton(systemImage: starred ? "star.fill" : "star", help: starred ? "Unstar" : "Star") {
      session.toggleFavorite(room.id)
    }
    PaneIconButton(systemImage: "person.2", help: "\(room.timeline.present.count) Here") {
      showingPeople.toggle()
    }
    .popover(isPresented: $showingPeople) {
      SuitePeopleList(session: session, room: room)
    }
  }
}

/** Who has the room open now. */
struct SuitePeopleList: View {
  let session: InstanceSession
  let room: RoomModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ListSectionHeader("Here Now", inset: .panel)
        .padding(.top, Spacing.lg)
      ForEach(room.timeline.present.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { user in
        SelectableListRow(isSelected: false) {
          Task { _ = try? await session.query(user.name) }
        } label: {
          ListRowLabel(title: session.people[user.id]?.name ?? user.name, systemImage: session.people[user.id]?.role == .administrator ? "person.badge.shield.checkmark" : "person")
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

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if hasMore {
          Color.clear.frame(height: Spacing.xxl).onAppear(perform: onOlder)
        }
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
          let previous = index > 0 ? lines[index - 1] : nil
          if previous == nil || !Calendar.current.isDate(previous!.date, inSameDayAs: line.date) {
            SuiteDayDivider(date: line.date)
          }
          SuiteMessageRow(
            session: session, room: room, line: line, continues: continues(line, after: previous), openThread: openThread, inThread: inThread)
        }
      }
      .padding(.vertical, Spacing.md)
    }
    .defaultScrollAnchor(.bottom)
    .scrollFade()
  }

  /** Whether `line` follows a message by the same author within five minutes, so it leaves out the name and avatar. */
  private func continues(_ line: BufferLine, after previous: BufferLine?) -> Bool {
    guard case let .message(message, _) = line, case let .message(before, _)? = previous else { return false }
    return before.creator.id == message.creator.id && message.createdDate.timeIntervalSince(before.createdDate) < 300
      && Calendar.current.isDate(before.createdDate, inSameDayAs: message.createdDate) && !message.isAction && !before.isAction
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

/** Typing, then the message field and its send button on glass. Slash commands work here too. */
struct SuiteComposer: View {
  let app: AppModel
  let session: InstanceSession
  let room: RoomModel
  let placeholder: String
  var parentId: String?
  @State private var draft = ""
  @State private var alsoSend = false
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      // Always laid out, so the composer doesn't move as people start and stop typing.
      Text(typingText)
        .font(DesignFont.detail)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.leading, Spacing.lg)
      HStack(alignment: .bottom, spacing: Spacing.md) {
        TextField(placeholder, text: $draft, axis: .vertical)
          .textFieldStyle(.plain)
          .font(DesignFont.body)
          .lineLimit(1...8)
          .focused($focused)
          .onSubmit(send)
          .onChange(of: draft) { _, new in if !new.isEmpty, !new.hasPrefix("/") { room.typed() } }
        Button("Send", systemImage: "paperplane.fill", action: send)
          .labelStyle(.iconOnly)
          .buttonStyle(.glassProminent)
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut(.return, modifiers: .command)
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.md)
      .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
      if parentId != nil {
        Toggle(room.room.isDirect ? "Also Send to the Conversation" : "Also Send to #\(room.title)", isOn: $alsoSend)
          .font(DesignFont.detail)
          .padding(.leading, Spacing.lg)
          #if os(macOS)
          .toggleStyle(.checkbox)
          #endif
      }
    }
    .padding(Spacing.lg)
    .onAppear { focused = true }
  }

  private var typingText: String {
    let names = room.typingNames
    switch names.count {
    case 0: return " "
    case 1: return "\(names[0]) is typing"
    case 2: return "\(names[0]) and \(names[1]) are typing"
    default: return "Several people are typing"
    }
  }

  private func send() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    draft = ""
    focused = true
    if let parentId {
      room.send(text, parentId: parentId, alsoSend: alsoSend)
    } else if let command = InputCommand.parse(text) {
      Commander.run(command, app: app, session: session, room: room)
    }
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
        SuiteComposer(app: app, session: session, room: room, placeholder: "Reply", parentId: thread.parentId)
      }
    }
    #if os(iOS)
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
