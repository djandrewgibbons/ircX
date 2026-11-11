import EmberKit
import SwiftUI

/** A room's buffer: its topic bar, its lines, a thread or the nick list beside them, the status bar and the input line. */
struct BufferView: View {
  let app: AppModel
  let session: InstanceSession
  @Bindable var room: RoomModel
  @Environment(\.theme) private var theme
  @Environment(\.horizontalSizeClass) private var sizeClass
  @AppStorage("showNickList") private var showNickList = true

  var body: some View {
    VStack(spacing: 0) {
      TopicBar(session: session, room: room, showNickList: $showNickList)
      HStack(spacing: 0) {
        MessageList(session: session, room: room, lines: room.timeline.lines, hasMore: room.timeline.hasMore, onOlder: room.loadOlder, openThread: room.openThread)
        if sizeClass != .compact {
          if room.thread != nil {
            Divider().overlay(theme.faint)
            ThreadPane(session: session, room: room).frame(width: 360)
          } else if showNickList {
            Divider().overlay(theme.faint)
            NickList(session: session, room: room).frame(width: 170)
          }
        }
      }
      StatusBar(session: session, room: room)
      InputLine(app: app, session: session, room: room)
    }
    .background(theme.buffer)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .navigationBar)
    .sheet(isPresented: Binding(get: { sizeClass == .compact && room.thread != nil }, set: { if !$0 { room.closeThread() } })) {
      ThreadPane(session: session, room: room).presentationDetents([.large])
    }
    #endif
  }
}

struct TopicBar: View {
  let session: InstanceSession
  let room: RoomModel
  @Binding var showNickList: Bool
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    HStack(spacing: 10) {
      Text(name).font(Theme.font(14, weight: .bold))
      Text(topic).font(Theme.font(12)).foregroundStyle(theme.dim).lineLimit(1)
      Spacer()
      Button {
        session.toggleFavorite(room.id)
      } label: {
        Image(systemName: session.favorites.contains(room.id) ? "star.fill" : "star")
      }
      .buttonStyle(.plain)
      .foregroundStyle(session.favorites.contains(room.id) ? theme.ember : theme.dim)
      .help("Star")
      Button {
        showNickList.toggle()
      } label: {
        Image(systemName: "person.2")
      }
      .buttonStyle(.plain)
      .foregroundStyle(showNickList ? theme.text : theme.dim)
      .help("Nick list")
    }
    .padding(.horizontal, 14)
    .frame(height: 40)
    .background(theme.buffer)
    .overlay(alignment: .bottom) { Rectangle().fill(theme.faint).frame(height: 1) }
  }

  private var name: String {
    switch room.room.kind {
    case .open: "#\(room.title)"
    case .closed: "&\(room.title)"
    case .direct: room.title
    }
  }

  private var topic: String {
    let here = room.timeline.present.count
    let kind = room.room.kind == .closed ? "private" : room.room.isDirect ? "query" : "channel"
    return "[\(kind)] \(here) here · \(session.name)"
  }
}

/** The buffer's lines, newest at the bottom, with a day line wherever the day changes. */
struct MessageList: View {
  let session: InstanceSession
  let room: RoomModel
  let lines: [BufferLine]
  let hasMore: Bool
  let onOlder: () -> Void
  let openThread: (String) -> Void
  var inThread = false
  @Environment(\.theme) private var theme

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 1) {
        if hasMore {
          Text("-- scroll for older --")
            .font(Theme.font(11))
            .foregroundStyle(theme.dim)
            .frame(maxWidth: .infinity)
            .padding(6)
            .onAppear(perform: onOlder)
        }
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
          if index == 0 || !Calendar.current.isDate(lines[index - 1].date, inSameDayAs: line.date) {
            DayLine(date: line.date)
          }
          MessageLine(session: session, room: room, line: line, openThread: openThread, inThread: inThread)
        }
      }
      .padding(.vertical, 8)
    }
    .defaultScrollAnchor(.bottom)
    .background(theme.buffer)
  }
}

struct DayLine: View {
  let date: Date
  @Environment(\.theme) private var theme

  var body: some View {
    Text("--- Day changed \(Clock.day(date))")
      .font(Theme.font(11))
      .foregroundStyle(theme.dim)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
  }
}

/**
 * The irssi-meets-BitchX status bar: the time, your nick, the window, its activity elsewhere and who's
 * typing, on the bar's own color.
 */
struct StatusBar: View {
  let session: InstanceSession
  let room: RoomModel
  @Environment(\.theme) private var theme

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      HStack(spacing: 6) {
        segment(Clock.time(context.date, seconds: false))
        segment((session.me?.administrator == true ? "@" : "") + (session.me?.name ?? "?"))
        segment("\(session.name)/\(room.room.isDirect ? room.title : "#" + room.title)")
        if !activity.isEmpty {
          segment("Act: " + activity.joined(separator: ","), color: theme.ember)
        }
        if room.socketState != .open {
          segment(stateText, color: .yellow)
        }
        Spacer(minLength: 0)
        if !room.typingNames.isEmpty {
          Text("\(room.typingNames.joined(separator: ", ")) typing…").foregroundStyle(theme.dim)
        }
      }
      .font(Theme.font(11))
      .lineLimit(1)
      .padding(.horizontal, 10)
      .frame(height: 22)
      .background(theme.statusBar)
    }
  }

  private func segment(_ text: String, color: Color? = nil) -> some View {
    HStack(spacing: 0) {
      Text("[").foregroundStyle(theme.statusBracket)
      Text(text).foregroundStyle(color ?? theme.text)
      Text("]").foregroundStyle(theme.statusBracket)
    }
  }

  /** The other windows with something unread, by their place in the sidebar, as irssi's Act: lists them. */
  private var activity: [String] {
    let windows = session.starred + session.channels + session.directs
    return windows.enumerated().compactMap { index, item in
      item.unread && item.id != room.id && item.involvement != .nothing ? String(index + 1) : nil
    }
  }

  private var stateText: String {
    switch room.socketState {
    case .connecting: "connecting"
    case let .waiting(retryIn): "lag: reconnecting in \(Int(retryIn.rounded()))s"
    case .closed: "disconnected"
    default: "idle"
    }
  }
}
