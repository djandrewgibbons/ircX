import AppCoreUI
import EmberKit
import SwiftUI

/**
 * A message as Slack shows one: the author's avatar and name over the first of a run of messages,
 * then the text, a file, reactions and the thread's replies, with hover actions on the right.
 */
struct SuiteMessageRow: View {
  let session: InstanceSession
  let room: RoomModel
  let line: BufferLine
  /** Follows a message by the same author, so its avatar and name are left out. */
  let continues: Bool
  let openThread: (String) -> Void
  var inThread = false
  @Environment(\.suiteTheme) private var theme

  private static let avatarSize: CGFloat = 36

  var body: some View {
    switch line {
    case let .message(message, pending):
      messageRow(message)
        .opacity(pending ? 0.5 : 1)
    case let .event(_, _, text, kind):
      Label(text, systemImage: kind.symbol)
        .font(DesignFont.detail)
        .foregroundStyle(kind == .error ? SemanticColor.destructive : .secondary)
        .padding(.leading, PaneGrid.leadingEdge + Self.avatarSize + Spacing.md)
        .padding(.vertical, Spacing.xxs)
    }
  }

  private func messageRow(_ message: Message) -> some View {
    let highlighted = message.creator.id != session.me?.id && session.me.map { message.mentions($0.id) } == true
    return HStack(alignment: .top, spacing: Spacing.md) {
      if continues {
        Text(message.createdDate.formatted(date: .omitted, time: .shortened))
          .font(DesignFont.detail)
          .foregroundStyle(.tertiary)
          .frame(width: Self.avatarSize)
          .headerRevealed()
      } else {
        SuiteAvatar(session: session, user: message.creator, size: Self.avatarSize)
      }
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if !continues {
          HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(session.people[message.creator.id]?.name ?? message.creator.name).font(DesignFont.bodyEmphasized)
            if session.people[message.creator.id]?.agent == true || session.people[message.creator.id]?.role == .bot {
              let kind = session.people[message.creator.id]?.agent == true ? "Agent" : "Bot"
              StatusCapsule(text: kind, tint: theme.accent, help: kind)
            }
            Text(message.createdDate.formatted(date: .omitted, time: .shortened))
              .font(DesignFont.detail)
              .foregroundStyle(.secondary)
          }
        }
        content(message)
        extras(message)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, PaneGrid.leadingEdge)
    .padding(.top, continues ? Spacing.xxs : Spacing.md)
    .padding(.bottom, Spacing.xxs)
    .background(highlighted ? theme.accent.opacity(0.08) : Color.clear)
    .overlay(alignment: .topTrailing) { actions(message) }
    .headerHoverReveal()
    .contextMenu { menu(message) }
  }

  @ViewBuilder
  private func content(_ message: Message) -> some View {
    if let parentText = message.parentText, message.parentId != nil, !inThread {
      Label(parentText, systemImage: "arrowshape.turn.up.left")
        .font(DesignFont.detail)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    if message.deleted == true {
      Text("This message was deleted.").font(DesignFont.body).foregroundStyle(.secondary)
    } else if let file = message.attachment {
      SuiteAttachment(session: session, file: file)
    } else if message.isAction {
      Text(message.plainText).font(DesignFont.body).italic().textSelection(.enabled)
    } else {
      SuiteText(text: message.plainText, mentions: message.mentions, me: session.me?.id)
    }
    if message.editedAt != nil {
      Text("Edited").font(DesignFont.detail).foregroundStyle(.tertiary)
    }
  }

  @ViewBuilder
  private func extras(_ message: Message) -> some View {
    let reactions = Dictionary(grouping: message.boosts, by: \.content).sorted { $0.value.count > $1.value.count }
    if !reactions.isEmpty {
      FlowLayout(hSpacing: Spacing.xs, vSpacing: Spacing.xs) {
        ForEach(reactions, id: \.key) { reaction in
          let mine = reaction.value.contains { $0.booster.id == session.me?.id }
          Button {
            room.react(reaction.key, to: message)
          } label: {
            Text("\(reaction.key) \(reaction.value.count)")
              .font(DesignFont.detail)
              .padding(.horizontal, Spacing.sm)
              .padding(.vertical, Spacing.xxs)
              .background(Capsule().fill(mine ? theme.accent.opacity(0.18) : SemanticColor.secondaryFill))
              .overlay(Capsule().strokeBorder(mine ? theme.accent : Color.clear, lineWidth: 1))
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .help(reaction.value.map(\.booster.name).joined(separator: ", "))
        }
      }
    }
    if let thread = message.thread, !inThread {
      Button {
        openThread(message.id)
      } label: {
        HStack(spacing: Spacing.sm) {
          ForEach(thread.people.prefix(threadFaces)) { person in
            SuiteAvatar(session: session, user: person, size: 20)
          }
          Text(thread.count == 1 ? "1 Reply" : "\(thread.count) Replies")
            .font(DesignFont.detail.weight(.semibold))
            .foregroundStyle(theme.accent)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  /** React and reply, shown while the pointer is over the message, in a slot that never moves the message. */
  private func actions(_ message: Message) -> some View {
    HStack(spacing: Spacing.xxs) {
      ForEach(["👍", "❤️", "😂"], id: \.self) { emoji in
        Button(emoji) { room.react(emoji, to: message) }
          .buttonStyle(CompactPillHoverButtonStyle())
      }
      if !inThread, message.parentId == nil {
        PaneIconButton(systemImage: "bubble.left", help: "Reply in Thread") { openThread(message.id) }
      }
    }
    .padding(Spacing.xs)
    .glassEffect(.regular, in: Capsule())
    .padding(.trailing, Spacing.lg)
    .offset(y: -Spacing.md)
    .headerRevealed()
  }

  @ViewBuilder
  private func menu(_ message: Message) -> some View {
    if !inThread, message.parentId == nil {
      Button("Reply in Thread", systemImage: "bubble.left") { openThread(message.id) }
    }
    Menu("React") {
      ForEach(["👍", "❤️", "😂", "🎉", "👀", "🔥"], id: \.self) { emoji in
        Button(emoji) { room.react(emoji, to: message) }
      }
    }
    Button("Copy Text", systemImage: "doc.on.doc") { Pasteboard.copy(message.plainText) }
    if message.creator.id == session.me?.id || session.me?.administrator == true {
      Divider()
      Button("Delete", systemImage: "trash", role: .destructive) { room.delete(message) }
    }
  }
}

private let threadFaces = 4

/** Someone's avatar from their instance, over their initial until it loads. */
struct SuiteAvatar: View {
  let session: InstanceSession
  let user: User
  let size: CGFloat
  @Environment(\.suiteTheme) private var theme

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
    ZStack {
      shape.fill(SemanticColor.secondaryFill)
      Text(user.name.prefix(1).uppercased())
        .font(DesignFont.scaled(size * 0.45, weight: .semibold))
        .foregroundStyle(.secondary)
      if let path = session.people[user.id]?.avatarUrl {
        AuthImage(api: session.api, path: path)
      }
    }
    .frame(width: size, height: size)
    .clipShape(shape)
    .accessibilityHidden(true)
  }
}

/** Plain text with its links and mentions picked out. */
struct SuiteText: View {
  let text: String
  let mentions: [User]
  let me: UserID?
  @Environment(\.suiteTheme) private var theme

  var body: some View {
    Text(attributed).font(DesignFont.body).textSelection(.enabled)
  }

  private var attributed: AttributedString {
    var string = AttributedString(text)
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
      for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let url = match.url, let range = Range(match.range, in: text), let attributedRange = Range(range, in: string) else { continue }
        string[attributedRange].link = url
      }
    }
    for person in mentions {
      var searchRange = string.startIndex..<string.endIndex
      while let found = string[searchRange].range(of: person.name) {
        string[found].swiftUI.foregroundColor = theme.accent
        string[found].swiftUI.backgroundColor = person.id == me ? theme.accent.opacity(0.15) : nil
        string[found].inlinePresentationIntent = .stronglyEmphasized
        searchRange = found.upperBound..<string.endIndex
      }
    }
    return string
  }
}

struct SuiteAttachment: View {
  let session: InstanceSession
  let file: StoredFile
  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let preview = file.previewUrl ?? (file.isImage ? file.url : nil) {
        AuthImage(api: session.api, path: preview)
          .frame(maxWidth: 360, maxHeight: 240, alignment: .leading)
          .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
      }
      Button {
        openURL(session.api.url(file.downloadUrl))
      } label: {
        Label("\(file.name) · \(file.byteSize.byteText)", systemImage: "doc")
          .font(DesignFont.detail)
      }
      .buttonStyle(.glass)
    }
  }
}

extension BufferLine.EventKind {
  var symbol: String {
    switch self {
    case .join: "arrow.right.circle"
    case .part: "arrow.left.circle"
    case .info: "info.circle"
    case .error: "exclamationmark.triangle"
    }
  }
}
