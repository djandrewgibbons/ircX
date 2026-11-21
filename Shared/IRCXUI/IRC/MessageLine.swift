import EmberKit
import SwiftUI

/**
 * One line, weechat-style: the time, the nick right-aligned in its column, a bar, and the text, which
 * wraps under itself. Below it, Slack's reactions and thread summary, drawn as text.
 */
struct MessageLine: View {
  let session: InstanceSession
  let room: RoomModel
  let line: BufferLine
  let openThread: (String) -> Void
  var inThread = false
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  @AppStorage(Preferences.fontSize) private var fontSize = 13.0
  @AppStorage(Preferences.showSeconds) private var showSeconds = false
  @State private var hovering = false
  /** A blocked person's message, shown anyway after a click. */
  @State private var shownAnyway = false
  /** Your boost whose delete button shows, after a click on it. */
  @State private var revealed: String?

  private static let nickWidth: CGFloat = 112

  var body: some View {
    lineContent
      // Shown anyway only while blocked: blocking again collapses it again (web `message-item.tsx`).
      .onChange(of: blocked) { _, nowBlocked in
        if shownAnyway && !nowBlocked { shownAnyway = false }
      }
  }

  /** Whether this line is a blocked person's message. */
  private var blocked: Bool {
    if case let .message(message, _) = line { return room.isCollapsed(message) }
    return false
  }

  @ViewBuilder private var lineContent: some View {
    switch line {
    case let .message(message, pending):
      if room.isCollapsed(message) && !shownAnyway {
        row(date: message.createdDate, nick: Text("*").foregroundStyle(theme.dim)) {
          Button(EmberText.blockedMessage) { shownAnyway = true }
            .buttonStyle(.plain)
            .foregroundStyle(theme.dim)
            .italic()
        }
      } else {
        messageRow(message, pending: pending)
      }
    case let .event(_, date, text, kind):
      row(date: date, nick: Text(eventMark(kind)).foregroundStyle(eventColor(kind))) {
        Text(text).foregroundStyle(kind == .error ? theme.part : theme.dim)
      }
    }
  }

  private func messageRow(_ message: Message, pending: Bool) -> some View {
    let mine = message.creator.id == session.me?.id
    // Any message that mentions you, yours too, as the web marks them.
    let highlighted = session.me.map { message.mentions($0.id) } == true
    let blocks = message.attachment != nil || message.huddle != nil ? [] : RichLayout.blocks(message.body, plainText: message.plainText, host: session.instance.host)
    return VStack(alignment: .leading, spacing: 2) {
      if message.deleted == true {
        // A deleted message keeps its place for its replies, saying so without its author or time (web `DeletedMessage`).
        row(date: nil, nick: Text("")) {
          Text(EmberText.messageDeleted).foregroundStyle(theme.dim).italic()
        }
      } else if let huddle = message.huddle {
        row(date: message.createdDate, nick: Text("*").foregroundStyle(theme.join)) {
          IRCHuddle(session: session, message: message, huddle: huddle)
        }
      } else if message.isAction {
        row(date: message.createdDate, nick: Text("*").foregroundStyle(theme.action)) {
          (Text(message.creator.name).foregroundStyle(theme.nick(message.creator.id)).bold()
            + Text(" " + MessageBody.actionText(plainText: message.plainText, author: message.creator.name)).foregroundStyle(theme.action))
            .italic()
        }
      } else if blocks == nil {
        // A body that can't be shown (web `UnrenderableMessage`).
        row(date: message.createdDate, nick: Text("-!-").foregroundStyle(theme.part)) {
          Text(Display.failedToLoad).foregroundStyle(theme.part)
        }
      } else {
        row(date: message.createdDate, nick: nick(message.creator, mine: mine), whois: message.creator.id) {
          VStack(alignment: .leading, spacing: 2) {
            if let parentId = message.parentId, !inThread {
              Button {
                openThread(parentId)
              } label: {
                Text("\u{21B3} replied to a thread: \(message.parentText.flatMap { $0.isEmpty ? nil : $0 } ?? EmberText.messageDeleted)")
                  .foregroundStyle(theme.dim)
                  .lineLimit(1)
              }
              .buttonStyle(.plain)
            } else if message.parentId != nil, inThread, message.alsoSent == true {
              Text("\u{21B3} also sent \(room.room.isDirect ? "as direct message" : "to #" + room.title)").foregroundStyle(theme.dim).lineLimit(1)
            }
            if let upload = room.uploads[message.clientMessageId], pending {
              // An upload's card, as a line that changes as it goes (web `UploadCard`).
              Text("-- \(upload.error == nil ? "Uploading" : "Upload failed:") \(upload.name) (\(UploadWords.size(upload.size)))\(upload.error.map { " \($0)" } ?? " \(upload.percent)%")")
                .foregroundStyle(upload.error == nil ? theme.dim : theme.part)
            } else if let file = message.attachment {
              IRCAttachment(session: session, file: file)
            } else if let blocks, !message.body.isEmpty || message.cards == nil {
              IRCMessageBody(session: session, blocks: blocks, mentions: message.mentions)
            }
            if let cards = message.cards, !cards.isEmpty {
              IRCBotCards(session: session, cards: cards, onAction: pending ? nil : { action in await room.click(action, on: message) })
            }
            if message.editedAt != nil {
              Text("(edited)").font(Theme.font(fontSize - 3)).foregroundStyle(theme.dim)
            }
            if pending && room.isFailed(message) {
              Text("(\(EmberText.notSent.lowercased()))").font(Theme.font(fontSize - 3)).foregroundStyle(theme.part)
            }
          }
        }
      }
      extras(message)
    }
    .opacity(pending ? 0.5 : 1)
    .background(highlighted ? theme.highlight : hovering ? theme.faint.opacity(0.35) : Color.clear)
    .overlay(alignment: .leading) {
      if highlighted { Rectangle().fill(theme.ember).frame(width: 2) }
    }
    .onHover { hovering = $0 }
    .contextMenu { if !pending, message.deleted != true { menu(message, mine: mine) } }
  }

  @ViewBuilder
  private func extras(_ message: Message) -> some View {
    if !message.boosts.isEmpty || (message.thread != nil && !inThread) {
      HStack(spacing: 6) {
        // A boost each, oldest first, as the web's pills; your own takes itself back after a second click.
        ForEach(message.boosts) { boost in
          let mine = boost.booster.id == session.me?.id
          let booster = session.people[boost.booster.id]?.name ?? boost.booster.name
          Button {
            if mine { revealed = revealed == boost.id ? nil : boost.id }
          } label: {
            Text("[\(boost.content) \(booster)]").foregroundStyle(mine ? theme.ember : theme.dim)
          }
          .buttonStyle(.plain)
          .disabled(!mine)
          .help("\(booster) boosted \(boost.content)")
          if revealed == boost.id {
            Button("[-]") {
              revealed = nil
              room.unboost(boost)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.part)
            .help("Delete this boost")
          }
        }
        if let thread = message.thread, !inThread {
          Button {
            openThread(message.id)
          } label: {
            Text("\u{2514}\u{2500} \(MessageWords.replies(thread.count)) \u{B7} \(thread.people.map { session.people[$0.id]?.name ?? $0.name }.joined(separator: ", "))\(lastReply(thread))")
              .foregroundStyle(theme.link)
          }
          .buttonStyle(.plain)
        }
      }
      .font(Theme.font(fontSize - 2))
      .padding(.leading, timeWidth + Self.nickWidth + 26)
      .padding(.bottom, 2)
    }
  }

  private func lastReply(_ thread: ThreadSummary) -> String {
    guard let latest = EmberDate.parse(thread.latestAt) else { return "" }
    return " \u{B7} last reply \(MessageWords.lastReply(latest))"
  }

  private var timeWidth: CGFloat { showSeconds ? 64 : 42 }

  private func row<Content: View>(date: Date?, nick: Text, whois: UserID? = nil, @ViewBuilder text: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(date.map { Clock.time($0, seconds: showSeconds) } ?? "")
        .foregroundStyle(theme.dim)
        .frame(width: timeWidth, alignment: .leading)
      // A click on the nick opens their page, as /whois does.
      Button {
        if let whois { session.show(.person(whois)) }
      } label: {
        nick
          .lineLimit(1)
          .truncationMode(.head)
      }
      .buttonStyle(.plain)
      .disabled(whois == nil)
      .help(whois == nil ? "" : "/whois")
      .frame(width: Self.nickWidth, alignment: .trailing)
      Text("│").foregroundStyle(theme.faint)
      text()
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(Theme.font(fontSize))
    .padding(.horizontal, 12)
    .padding(.vertical, 1)
  }

  private func nick(_ user: User, mine: Bool) -> Text {
    let person = session.people[user.id]
    let mode = person?.role == .administrator ? "@" : person?.role == .bot || person?.agent == true ? "+" : " "
    return Text(mode).foregroundStyle(theme.dim) + Text(person?.name ?? user.name).foregroundStyle(mine ? theme.text : theme.nick(user.id)).bold()
  }

  private func eventMark(_ kind: BufferLine.EventKind) -> String {
    switch kind {
    case .join: "-->"
    case .part: "<--"
    case .info: "--"
    case .error: "-!-"
    }
  }

  private func eventColor(_ kind: BufferLine.EventKind) -> Color {
    switch kind {
    case .join: theme.join
    case .part, .error: theme.part
    case .info: theme.dim
    }
  }

  @ViewBuilder
  private func menu(_ message: Message, mine: Bool) -> some View {
    let context = MessageAction.Context(mine: mine, administrator: session.me?.administrator == true, inThread: inThread)
    let name = session.people[message.creator.id]?.name ?? message.creator.name
    if !inThread {
      Button("Reply in thread") { openThread(message.parentId ?? message.id) }
    }
    if message.huddle == nil {
      Menu("React") {
        ForEach(Reactions.all, id: \.emoji) { reaction in
          Button("\(reaction.emoji) \(reaction.name)") { room.react(reaction.emoji, to: message) }
        }
        Divider()
        Button("New boost\u{2026}") { room.request = .boost(message) }
      }
    }
    ForEach(MessageAction.menu(for: message, context), id: \.self) { action in
      switch action {
      case .quote: Button("Quote") { room.quote(message, into: room.composer(thread: inThread ? room.thread?.parentId : nil)) }
      case .copyText:
        Button("Copy text") { Pasteboard.copy(message.plainText) }
        Button("Copy nick") { Pasteboard.copy(name) }
      case .copyLink:
        Button("Copy link") { Pasteboard.copy(room.permalink(message)) }
        Divider()
      case .block:
        let blocked = session.isBlocked(message.creator.id)
        Button(blocked ? "Unblock \(name)" : "Block \(name)") { room.setBlocked(!blocked, message.creator.id) }
      case .report: Button("Report message") { room.request = .report(message) }
      case .edit: Button("Edit message") { room.request = .editLine(message, inThread: inThread) }
      case .delete: Button("Delete message", role: .destructive) { room.request = .delete(message) }
      default: EmptyView()
      }
    }
    if let file = message.attachment {
      Divider()
      Button("Download \(file.name)") { openURL(session.api.url(file.downloadUrl)) }
      ShareLink("Share \(file.name)", item: session.api.url(file.url))
    }
  }
}
