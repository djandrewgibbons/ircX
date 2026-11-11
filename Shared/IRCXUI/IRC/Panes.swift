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
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
              Task { _ = try? await session.query(user.name) }
            }
            .help("Double-click to /query")
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

/** A thread beside its room, as Slack opens one: the message, its replies and a reply line. */
struct ThreadPane: View {
  let session: InstanceSession
  @Bindable var room: RoomModel
  @Environment(\.theme) private var theme
  @State private var draft = ""
  @State private var alsoSend = false

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
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Text("reply ▸").font(Theme.font(13)).foregroundStyle(theme.ember)
            TextField("", text: $draft, axis: .vertical)
              .textFieldStyle(.plain)
              .font(Theme.font(13))
              .lineLimit(1...6)
              .onSubmit { send(thread.parentId) }
          }
          Toggle(room.room.isDirect ? "Also send to the conversation" : "Also send to #\(room.title)", isOn: $alsoSend)
            .font(Theme.font(11))
            .foregroundStyle(theme.dim)
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
        }
        .padding(10)
        .background(theme.input)
      }
    }
    .background(theme.buffer)
  }

  private func send(_ parentId: String) {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    room.send(text, parentId: parentId, alsoSend: alsoSend)
    draft = ""
  }
}

