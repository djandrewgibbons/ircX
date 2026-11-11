import EmberKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
  @AppStorage(Preferences.fontSize) private var fontSize = 13.0
  @AppStorage(Preferences.showSeconds) private var showSeconds = false
  @State private var hovering = false

  private static let nickWidth: CGFloat = 112

  var body: some View {
    switch line {
    case let .message(message, pending):
      messageRow(message, pending: pending)
    case let .event(_, date, text, kind):
      row(date: date, nick: Text(eventMark(kind)).foregroundStyle(eventColor(kind))) {
        Text(text).foregroundStyle(kind == .error ? theme.part : theme.dim)
      }
    }
  }

  private func messageRow(_ message: Message, pending: Bool) -> some View {
    let mine = message.creator.id == session.me?.id
    let highlighted = !mine && session.me.map { message.mentions($0.id) } == true
    return VStack(alignment: .leading, spacing: 2) {
      if message.isAction {
        row(date: message.createdDate, nick: Text("*").foregroundStyle(theme.action)) {
          (Text(message.creator.name).foregroundStyle(theme.nick(message.creator.id)).bold()
            + Text(" " + MessageBody.actionText(plainText: message.plainText, author: message.creator.name)).foregroundStyle(theme.action))
            .italic()
        }
      } else {
        row(date: message.createdDate, nick: nick(message.creator, mine: mine)) {
          VStack(alignment: .leading, spacing: 4) {
            if let parentText = message.parentText, message.parentId != nil, !inThread {
              Text("↳ re: \(parentText)").foregroundStyle(theme.dim).lineLimit(1)
            }
            if message.deleted == true {
              Text("(message deleted)").foregroundStyle(theme.dim).italic()
            } else if let file = message.attachment {
              AttachmentView(session: session, file: file)
            } else {
              LinkedText(text: message.plainText, mentions: message.mentions, me: session.me?.id)
            }
            if message.editedAt != nil {
              Text("(edited)").font(Theme.font(fontSize - 3)).foregroundStyle(theme.dim)
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
    .contextMenu { menu(message, mine: mine) }
  }

  @ViewBuilder
  private func extras(_ message: Message) -> some View {
    let reactions = Dictionary(grouping: message.boosts, by: \.content).sorted { $0.value.count > $1.value.count }
    if !reactions.isEmpty || (message.thread != nil && !inThread) {
      HStack(spacing: 6) {
        ForEach(reactions, id: \.key) { reaction in
          let content = reaction.key
          let boosts = reaction.value
          let mine = boosts.contains { $0.booster.id == session.me?.id }
          Button {
            room.react(content, to: message)
          } label: {
            Text("[\(content) \(boosts.count)]")
              .foregroundStyle(mine ? theme.ember : theme.dim)
          }
          .buttonStyle(.plain)
          .help(boosts.map(\.booster.name).joined(separator: ", "))
        }
        if let thread = message.thread, !inThread {
          Button {
            openThread(message.id)
          } label: {
            Text("└─ \(thread.count) \(thread.count == 1 ? "reply" : "replies") · \(thread.people.map(\.name).joined(separator: ", "))")
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

  private var timeWidth: CGFloat { showSeconds ? 64 : 42 }

  private func row<Content: View>(date: Date, nick: Text, @ViewBuilder text: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(Clock.time(date, seconds: showSeconds))
        .foregroundStyle(theme.dim)
        .frame(width: timeWidth, alignment: .leading)
      nick
        .lineLimit(1)
        .truncationMode(.head)
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
    if !inThread, message.parentId == nil {
      Button("Reply in thread") { openThread(message.id) }
    }
    Menu("React") {
      ForEach(["👍", "❤️", "😂", "🎉", "👀", "🔥"], id: \.self) { emoji in
        Button(emoji) { room.react(emoji, to: message) }
      }
    }
    Button("Copy text") { Pasteboard.copy(message.plainText) }
    Button("Copy nick") { Pasteboard.copy(message.creator.name) }
    if mine || session.me?.administrator == true {
      Divider()
      Button("Delete", role: .destructive) { room.delete(message) }
    }
  }
}

/** Plain text with links and mentions of you picked out. */
struct LinkedText: View {
  let text: String
  let mentions: [User]
  let me: UserID?
  @Environment(\.theme) private var theme

  var body: some View {
    Text(attributed)
  }

  private var attributed: AttributedString {
    var string = AttributedString(text)
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
      for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let url = match.url, let range = Range(match.range, in: text), let attributedRange = Range(range, in: string) else { continue }
        string[attributedRange].link = url
        string[attributedRange].swiftUI.foregroundColor = theme.link
        string[attributedRange].swiftUI.underlineStyle = .single
      }
    }
    for person in mentions {
      var searchRange = string.startIndex..<string.endIndex
      while let found = string[searchRange].range(of: person.name) {
        string[found].swiftUI.foregroundColor = person.id == me ? theme.ember : theme.nick(person.id)
        string[found].inlinePresentationIntent = .stronglyEmphasized
        searchRange = found.upperBound..<string.endIndex
      }
    }
    return string
  }
}

struct AttachmentView: View {
  let session: InstanceSession
  let file: StoredFile
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        openURL(session.api.url(file.downloadUrl))
      } label: {
        Text("[file] \(file.name) (\(file.byteSize.byteText))").foregroundStyle(theme.link).underline()
      }
      .buttonStyle(.plain)
      if let preview = file.previewUrl ?? (file.isImage ? file.url : nil) {
        AuthImage(api: session.api, path: preview)
          .frame(maxWidth: 360, maxHeight: 240, alignment: .leading)
          .clipShape(RoundedRectangle(cornerRadius: 4))
      }
    }
  }
}

enum Pasteboard {
  static func copy(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
  }
}
