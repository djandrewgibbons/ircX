import EmberKit
import SwiftUI

/** Who's in the room, as IRC's nick list shows them: operators (administrators) first, then voiced bots, then everyone else. */
struct NickList: View {
  let session: InstanceSession
  let room: RoomModel
  @Environment(\.theme) private var theme

  var body: some View {
    let present = room.timeline.present.sorted(by: order)
    VStack(alignment: .leading, spacing: 0) {
      Text("\(present.count) nicks")
        .font(Theme.font(11))
        .foregroundStyle(theme.dim)
        .padding(.horizontal, 10)
        .frame(height: 28)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(present) { user in
            HStack(spacing: 0) {
              Text(mode(user)).foregroundStyle(theme.join)
              Text(session.people[user.id]?.name ?? user.name).foregroundStyle(theme.nick(user.id))
            }
            .font(Theme.font(12))
            .lineLimit(1)
            .padding(.horizontal, 10)
            // Away people dim, as an IRC client greys out /away nicks.
            .opacity(session.presence(of: user.id) == false && session.presenceShown(of: user.id) ? 0.5 : 1)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
              session.attempt("Opening a DM") { _ = try await session.query(user.name) }
            }
            .contextMenu {
              Button("Whois") { session.show(.person(user.id)) }
              if user.id != session.me?.id {
                Button("Query") { session.attempt("Opening a DM") { try await session.startDirect(with: [user.id]) } }
              }
            }
            .help("Double-click to /query; right-click for /whois")
          }
        }
      }
    }
    .background(theme.sidebar)
  }

  private func mode(_ user: User) -> String {
    switch session.people[user.id]?.role {
    case .administrator: "@"
    case .bot: "+"
    default: " "
    }
  }

  private func rank(_ user: User) -> Int {
    switch session.people[user.id]?.role {
    case .administrator: 0
    case .bot: 1
    default: 2
    }
  }

  private func order(_ a: User, _ b: User) -> Bool {
    rank(a) != rank(b) ? rank(a) < rank(b) : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
  }
}

/**
 * A thread beside its room, as Slack opens one: the message, its replies and a reply line, which is the
 * room's input line writing to the thread. On a phone it's a sheet over the room, which shows what its
 * messages ask for (`presented`).
 */
struct ThreadPane: View {
  let app: AppModel
  let session: InstanceSession
  @Bindable var room: RoomModel
  var presented = false
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Thread").font(Theme.font(13, weight: .bold))
        Text(room.room.isDirect ? room.title : "#\(room.title)").font(Theme.font(12)).foregroundStyle(theme.dim)
        Spacer()
        Button {
          room.closeThread()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.dim)
        .keyboardShortcut(.cancelAction)
      }
      .padding(.horizontal, 12)
      .frame(height: 40)
      .overlay(alignment: .bottom) { Rectangle().fill(theme.faint).frame(height: 1) }

      if let thread = room.thread {
        let parentLines = thread.parent.map { [BufferLine.message($0, pending: false)] } ?? []
        MessageList(
          session: session, room: room, lines: parentLines + thread.lines, hasMore: thread.hasMore, onOlder: room.loadOlderReplies,
          openThread: { _ in }, inThread: true)
        if !thread.loaded {
          ProgressView().controlSize(.small).padding(6)
        }
        ThreadStatusBar(room: room)
        if room.ended {
          IRCRoomDeleted()
        } else if thread.parent != nil {
          // The reply line shows once the thread's first message has (web `ThreadPanel`).
          InputLine(app: app, session: session, room: room, parentId: thread.parentId)
        }
      }
    }
    .background(theme.buffer)
    .dropDestination(for: URL.self) { urls, _ in
      room.composer(thread: room.thread?.parentId).pick(urls: urls)
      return true
    }
    .modifier(SheetRequests(room: room, presented: presented))
  }
}

/** A thread's requests, where it's a sheet over its room, which can't show them. */
private struct SheetRequests: ViewModifier {
  let room: RoomModel
  let presented: Bool

  func body(content: Content) -> some View {
    if presented {
      content.roomRequests(room, composer: room.composer(thread: room.thread?.parentId), printsShortcuts: true)
    } else {
      content
    }
  }
}

/** In place of the input line once the room is gone (web `RoomDeleted`). */
struct IRCRoomDeleted: View {
  @Environment(\.theme) private var theme

  var body: some View {
    Text("-!- This room was deleted.")
      .font(Theme.font(13))
      .foregroundStyle(theme.part)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .overlay(Rectangle().strokeBorder(theme.part))
      .padding(10)
      .background(theme.input)
  }
}


/**
 * The thread's status bar: its notice and the room's, which the thread covers on a phone, each until
 * it's dismissed with a click, and who's typing in the thread (web `ThreadReplies`).
 */
struct ThreadStatusBar: View {
  let room: RoomModel
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: 6) {
      if let notice = room.thread?.notice {
        Button(action: room.dismissThreadNotice) { segment("! " + notice) }
          .buttonStyle(.plain)
          .help("Dismiss")
      }
      if let notice = room.notice {
        Button(action: room.dismissNotice) { segment("! " + notice) }
          .buttonStyle(.plain)
          .help("Dismiss")
      }
      Spacer(minLength: 0)
      if let typing = room.threadTypingText {
        Text("\(typing)\u{2026}").foregroundStyle(theme.dim)
      }
    }
    .font(Theme.font(11))
    .lineLimit(1)
    .padding(.horizontal, 10)
    .frame(height: 22)
    .background(theme.statusBar)
  }

  private func segment(_ text: String) -> some View {
    HStack(spacing: 0) {
      Text("[").foregroundStyle(theme.statusBracket)
      Text(text).foregroundStyle(theme.part)
      Text("]").foregroundStyle(theme.statusBracket)
    }
  }
}
