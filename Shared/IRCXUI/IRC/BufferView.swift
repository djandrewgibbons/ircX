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
            ThreadPane(app: app, session: session, room: room).frame(width: 360)
          } else if showNickList {
            Divider().overlay(theme.faint)
            VStack(spacing: 0) {
              if let call = app.huddles.call, call.session === session, call.roomId == room.id { IRCHuddleRoster(call: call) }
              NickList(session: session, room: room)
            }
            .frame(width: 170)
          }
        }
      }
      StatusBar(session: session, room: room)
      if room.ended {
        IRCRoomDeleted()
      } else {
        InputLine(app: app, session: session, room: room)
      }
    }
    .background(theme.buffer)
    .dropDestination(for: URL.self) { urls, _ in
      room.composer().pick(urls: urls)
      return true
    }
    // On a phone the thread is a sheet over the buffer, which shows what the thread asks for itself.
    .roomRequests(room, composer: room.composer(), printsShortcuts: true, active: !threadIsSheet)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .navigationBar)
    .sheet(isPresented: Binding(get: { threadIsSheet }, set: { if !$0 { room.closeThread() } })) {
      ThreadPane(app: app, session: session, room: room, presented: true).presentationDetents([.large])
    }
    #endif
  }
}

extension BufferView {
  private var threadIsSheet: Bool { sizeClass == .compact && room.thread != nil }
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
      if let note = session.involvementNotes[room.id] {
        Text(note).font(Theme.font(11)).foregroundStyle(theme.ember).lineLimit(1)
      }
      Spacer()
      IRCHuddleTopicButton(session: session, room: room.room).font(Theme.font(12))
      if !room.room.isDirect {
        Button {
          session.toggleFavorite(room.id)
        } label: {
          Text(session.isStarred(room.id) ? "[*]" : "[ ]")
        }
        .buttonStyle(.plain)
        .disabled(session.starring.contains(room.id))
        .foregroundStyle(session.isStarred(room.id) ? theme.ember : theme.dim)
        .help(session.isStarred(room.id) ? "Remove from favorites (/unstar)" : "Add to favorites (/star)")
      }
      if let item = session.rooms.first(where: { $0.id == room.id }) {
        Menu {
          InvolvementMenu(session: session, item: item)
          PushMenuItems(session: session, room: room)
        } label: {
          Text("(\(item.involvement.short))")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme.dim)
        .help("\(item.involvement.sentence) (/notify)")
      }
      Button {
        session.openSearchBox(in: room.id)
      } label: {
        Image(systemName: "magnifyingglass")
      }
      .buttonStyle(.plain)
      .foregroundStyle(theme.dim)
      .help("Search messages (/search in:#room)")
      Button {
        session.show(.settings(room.id))
      } label: {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.plain)
      .foregroundStyle(theme.dim)
      .help("Conversation settings (/room)")
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
    case .direct: session.title(of: room.room) + (session.isWithAgent(room.room) ? " [agent]" : "")
    }
  }

  private var topic: String {
    let here = room.timeline.present.count
    let kind = room.room.kind == .closed ? "private" : room.room.isDirect ? "query" : "channel"
    let state = room.socketState == .open || room.ended ? "" : room.socketState == .connecting ? " · connecting..." : " · reconnecting..."
    return "[\(kind)] \(here) here · \(session.name)\(state)"
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
  @State private var position = ScrollPosition(edge: .bottom)
  @State private var atBottom = true
  @State private var outlined: String?

  /** The message a permalink opened, scrolled to and lit for a moment. */
  private func outline(_ around: String?) {
    guard !inThread, let around, let line = lines.first(where: { if case let .message(message, _) = $0 { message.id == around } else { false } }) else { return }
    position.scrollTo(id: line.id, anchor: .center)
    outlined = line.id
    Task {
      try? await Task.sleep(for: .milliseconds(1500))
      if outlined == line.id { outlined = nil }
    }
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 1) {
        if !inThread {
          WelcomeCard(session: session, room: room)
        }
        if hasMore {
          Text(room.loadingOlder && !inThread ? "-- loading older --" : "-- scroll for older --")
            .font(Theme.font(11))
            .foregroundStyle(theme.dim)
            .frame(maxWidth: .infinity)
            .padding(6)
            .onAppear(perform: onOlder)
        }
        if !inThread, !hasMore, let joined = room.room.joined, let date = EmberDate.parse(joined.at) {
          // A welcome DM starts with who joined (web `JoinedItem`).
          DayLine(date: date)
          let name = session.people[joined.userId]?.name ?? joined.userId
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Clock.time(date, seconds: false)).foregroundStyle(theme.dim)
            Text("-->").foregroundStyle(theme.join)
            Button(name) { session.show(.person(joined.userId)) }.buttonStyle(.plain).foregroundStyle(theme.nick(joined.userId)).bold()
            Text(NavigationText.joined(session.name)).foregroundStyle(theme.dim)
          }
          .font(Theme.font(13))
          .padding(.horizontal, 12)
        }
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
          let before = index > 0 ? lines[index - 1].date : (inThread || hasMore ? nil : room.room.joined.flatMap { EmberDate.parse($0.at) })
          if before.map({ !Calendar.current.isDate($0, inSameDayAs: line.date) }) != false {
            DayLine(date: line.date)
          }
          if !inThread, line.id == room.firstNewLineID {
            Text("--- New").font(Theme.font(11, weight: .bold)).foregroundStyle(theme.part).padding(.horizontal, 12).padding(.vertical, 2)
          }
          MessageLine(session: session, room: room, line: line, openThread: openThread, inThread: inThread)
            .background(outlined == line.id ? theme.highlight : Color.clear)
            .id(line.id)
        }
        if !inThread, room.timeline.hasNewer {
          Text(room.loadingNewer ? "-- loading newer --" : "-- scroll for newer --")
            .font(Theme.font(11))
            .foregroundStyle(theme.dim)
            .frame(maxWidth: .infinity)
            .padding(6)
            .onAppear(perform: room.loadNewer)
        }
      }
      .padding(.vertical, 8)
    }
    .scrollPosition($position)
    .defaultScrollAnchor(.bottom)
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
    } action: { _, bottom in
      atBottom = bottom
      if bottom, !room.timeline.hasNewer { room.readNewest() }
    }
    .overlay(alignment: .bottom) {
      if !inThread, room.timeline.hasNewer || (room.arrivals > 0 && !atBottom) {
        Button(room.arrivals > 0 ? "-- \(room.arrivals) new below: /end --" : "-- /end for the newest --") {
          room.jumpToNewest()
        }
        .buttonStyle(.plain)
        .font(Theme.font(11))
        .foregroundStyle(theme.ember)
        .padding(4)
        .background(theme.statusBar)
        .help("Jump to newest message")
      }
    }
    .onChange(of: room.timeline.around) { _, around in outline(around) }
    .onChange(of: room.arrivals) { old, new in if new < old, !inThread { position.scrollTo(edge: .bottom) } }
    .onChange(of: room.toNewest) { _, _ in if !inThread { position.scrollTo(edge: .bottom) } }
    .background(theme.buffer)
    .environment(\.openURL, MessageLinks.opener(session))
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
        // Notifications from this server, while they aren't on (`/push`).
        if let notify {
          Button { session.show(.pushSubscriptions) } label: { segment("Notify: " + notify, color: theme.ember) }
            .buttonStyle(.plain)
            .help("\(PushText.detail(PushCenter.shared.state(of: session))) (/push)")
        }
        // For administrators, open reports and a newer Ember, which /reports and /version tell of.
        if session.me?.administrator == true {
          if let open = session.openReports, open > 0 {
            Button { session.openWorkspaceSettings(.membership) } label: { segment("Rpt: \(open)", color: theme.ember) }
              .buttonStyle(.plain)
              .help(NavigationText.openReports(open))
          }
          if let release = session.newRelease {
            Button { session.openWorkspaceSettings(.general) } label: { segment("Upd: \(release)", color: theme.ember) }
              .buttonStyle(.plain)
              .help(NavigationText.releaseAvailable(release))
          }
        }
        if room.socketState != .open {
          segment(room.offline ? "offline" : stateText, color: theme.ember)
        }
        if !room.timeline.queued.isEmpty {
          segment("sending \(room.timeline.queued.count)", color: theme.ember)
        }
        ForEach(room.uploads.sorted { $0.key < $1.key }, id: \.key) { _, upload in
          segment("Upload \(upload.name) \(upload.error == nil ? "\(upload.percent)%" : "failed")", color: upload.error == nil ? theme.text : theme.part)
        }
        if let notice = room.notice {
          // The room's notice, until it's dismissed with a click (web `RoomNotice`).
          Button {
            room.dismissNotice()
          } label: {
            segment("! " + notice, color: theme.part)
          }
          .buttonStyle(.plain)
          .help("Dismiss")
        }
        Spacer(minLength: 0)
        if let typing = room.typingText {
          Text("\(typing)…").foregroundStyle(theme.dim)
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

  /** Where this server's notifications are, while they aren't on. */
  private var notify: String? {
    switch PushCenter.shared.state(of: session) {
    case .on, .turningOn: nil
    case .off, .unconfigured: "off"
    case .blocked: "denied"
    case .failed: "failed"
    }
  }

  /** The other windows with something unread, by their place in the sidebar, as irssi's Act: lists them, a DM's count after it. */
  private var activity: [String] {
    session.windows.enumerated().compactMap { index, item in
      guard session.isMarkedUnread(item), item.id != room.id else { return nil }
      if item.room.isDirect, let count = item.unreadCount { return "\(index + 1)(\(count))" }
      return String(index + 1)
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

extension Involvement {
  /** The level as IRC Classic's topic bar shows it, as `/notify` names it. */
  var short: String {
    switch self {
    case .mentions: "mentions"
    case .everything: "everything"
    case .nothing: "off"
    case .invisible: "hidden"
    }
  }
}
