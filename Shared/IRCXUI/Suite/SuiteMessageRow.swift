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
  /** A blocked person's message, shown anyway after a click. */
  @State private var shownAnyway = false

  private static let avatarSize: CGFloat = 36

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
      if message.deleted == true {
        // A message deleted while its thread has replies keeps its place for them (web `DeletedMessage`).
        standIn(message) {
          Text(EmberText.messageDeleted).font(DesignFont.body).foregroundStyle(.secondary)
        }
      } else if room.isCollapsed(message) && !shownAnyway {
        standIn(message) {
          Button(EmberText.blockedMessage) { shownAnyway = true }
            .buttonStyle(.plain)
            .font(DesignFont.body)
            .foregroundStyle(.secondary)
        }
      } else if let blocks = shownBlocks(message) {
        messageRow(message, blocks: blocks, pending: pending, failed: pending && room.isFailed(message))
          .opacity(pending ? 0.6 : 1)
      } else {
        // A body that can't be shown (web `UnrenderableMessage`): no author, time, actions or reactions.
        Text(Display.failedToLoad)
          .font(DesignFont.detail)
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.xs)
          .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(SemanticColor.destructive, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
          .opacity(0.5)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.xs)
      }
    case let .event(_, _, text, kind):
      // Notices show over the composer, as the web's room notice; joins and parts as lines.
      if kind == .join || kind == .part {
        Label(text, systemImage: kind.symbol)
          .font(DesignFont.detail)
          .foregroundStyle(.secondary)
          .padding(.leading, PaneGrid.leadingEdge + Self.avatarSize + Spacing.md)
          .padding(.vertical, Spacing.xxs)
      }
    }
  }

  /** What a message's text shows, laid out; an empty body (a file's, a huddle's, cards alone) shows nothing. */
  private func shownBlocks(_ message: Message) -> [RichBlock]? {
    if message.attachment != nil || message.huddle != nil { return [] }
    return RichLayout.blocks(message.body, plainText: message.plainText, host: session.instance.host)
  }

  /** A message that keeps its place without showing itself: a blank square for its avatar, and its thread's summary. */
  private func standIn(_ message: Message, @ViewBuilder content: () -> some View) -> some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      RoundedRectangle(cornerRadius: Self.avatarSize * 0.25, style: .continuous)
        .fill(SemanticColor.secondaryFill)
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Spacing.xs) {
        content()
        if !inThread, let thread = message.thread { threadSummary(message, thread) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, PaneGrid.leadingEdge)
    .padding(.vertical, Spacing.xs)
  }

  private func messageRow(_ message: Message, blocks: [RichBlock], pending: Bool, failed: Bool) -> some View {
    // Any message that mentions you, yours too, as the web marks them.
    let mentioned = session.me.map { message.mentions($0.id) } == true
    let liveHuddle = message.huddle.map { $0.endedAt == nil } == true
    // A reply says where it's from under its author's name, so it never follows on without one.
    let context = message.parentId != nil && (!inThread || message.alsoSent == true)
    // A blocked person's message shown anyway always names its author (web `threaded`).
    let follows = continues && !context && !room.isCollapsed(message)
    let edited = message.editedAt != nil
    let allEmoji = message.cards == nil && Display.isAllEmoji(message.plainText)
    return HStack(alignment: .top, spacing: Spacing.md) {
      if follows {
        Text(message.createdDate.formatted(date: .omitted, time: .shortened))
          .font(DesignFont.detail)
          .foregroundStyle(.tertiary)
          .frame(width: Self.avatarSize)
          .headerRevealed()
          .help(MessageWords.dateTime(message.createdDate))
      } else if let huddle = message.huddle {
        SuiteHuddleTile(huddle: huddle, size: Self.avatarSize)
      } else {
        // The avatar and the name open the author's page (web `PersonLink`).
        Button { session.show(.person(message.creator.id)) } label: {
          SuiteAvatar(session: session, user: message.creator, size: Self.avatarSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.people[message.creator.id]?.name ?? message.creator.name)
      }
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if !follows {
          HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            if let huddle = message.huddle {
              Text(MessageWords.huddleTitle(huddle)).font(DesignFont.bodyEmphasized)
              if huddle.endedAt == nil { SuiteLiveBadge() }
            } else {
              author(message.creator)
            }
            Text(message.createdDate.formatted(date: .omitted, time: .shortened))
              .font(DesignFont.detail)
              .foregroundStyle(.secondary)
              .help(MessageWords.dateTime(message.createdDate))
            if edited {
              Text("(edited)").font(DesignFont.detail).foregroundStyle(.secondary)
            }
          }
        }
        if context { replyContext(message) }
        if room.editing.contains(message.id), !pending {
          SuiteMessageEditor(session: session, room: room, message: message)
        } else if let upload = room.uploads[message.clientMessageId], pending {
          SuiteUploadCard(upload: upload)
        } else if let huddle = message.huddle {
          SuiteHuddleSummary(session: session, message: message, huddle: huddle)
        } else if let file = message.attachment {
          SuiteAttachment(session: session, file: file)
          if follows, edited { Text("(edited)").font(DesignFont.detail).foregroundStyle(.secondary) }
        } else if !message.body.isEmpty || message.cards == nil {
          SuiteMessageBody(session: session, blocks: blocks, mentions: message.mentions, emoji: allEmoji, trailing: follows && edited ? "(edited)" : nil)
        }
        if let cards = message.cards, !cards.isEmpty {
          SuiteBotCards(session: session, cards: cards, onAction: pending ? nil : { action in await room.click(action, on: message) })
        }
        if failed {
          Text(EmberText.notSent).font(DesignFont.detail).foregroundStyle(SemanticColor.destructive)
        }
        extras(message)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, mentioned ? Spacing.md : 0)
      .background(alignment: .leading) {
        if mentioned {
          HStack(spacing: 0) {
            Rectangle().fill(theme.accent).frame(width: Spacing.xxs)
            theme.accent.opacity(0.08)
          }
        }
      }
    }
    .padding(.horizontal, PaneGrid.leadingEdge)
    .padding(.top, follows ? Spacing.xxs : Spacing.md)
    .padding(.bottom, Spacing.xxs)
    .background(liveHuddle ? SemanticColor.positive.opacity(0.08) : Color.clear)
    .overlay(alignment: .topTrailing) { if !pending, !room.editing.contains(message.id) { actions(message) } }
    .headerHoverReveal()
    .contextMenu { if !pending { SuiteMessageMenu(session: session, room: room, message: message, inThread: inThread, openThread: openThread) } }
  }

  /** The author's name as the directory has it now, their bio on hover, and the Agent or Bot badge. */
  @ViewBuilder
  private func author(_ user: User) -> some View {
    let listed = session.people[user.id]
    Button { session.show(.person(user.id)) } label: {
      Text(listed?.name ?? user.name).font(DesignFont.bodyEmphasized)
    }
    .buttonStyle(.plain)
    .help([listed?.name ?? user.name, listed?.bio].compactMap { $0 }.joined(separator: "\n"))
    if listed?.agent == true || listed?.role == .bot {
      let kind = listed?.agent == true ? "Agent" : "Bot"
      StatusCapsule(text: kind, tint: theme.accent, help: kind)
    }
  }

  /** Over a reply in the room, the start of what it replies to; in the thread, where else it went. */
  @ViewBuilder
  private func replyContext(_ message: Message) -> some View {
    if inThread {
      Text(room.room.isDirect ? "Also sent as direct message" : "Also sent to #\(room.title)")
        .font(DesignFont.detail)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    } else if let parentId = message.parentId {
      Button {
        openThread(parentId)
      } label: {
        Text("replied to a thread: ").foregroundStyle(.secondary) + Text(message.parentText.flatMap { $0.isEmpty ? nil : $0 } ?? EmberText.messageDeleted).foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .font(DesignFont.detail)
      .lineLimit(1)
    }
  }

  @ViewBuilder
  private func extras(_ message: Message) -> some View {
    SuiteBoosts(session: session, room: room, message: message)
    if let thread = message.thread, !inThread {
      threadSummary(message, thread)
    }
  }

  /** The summary of a message's thread under it: the faces of who replied last, how many replies, and when the newest came. */
  private func threadSummary(_ message: Message, _ thread: ThreadSummary) -> some View {
    Button {
      openThread(message.id)
    } label: {
      HStack(spacing: Spacing.sm) {
        ForEach(thread.people.prefix(threadFaces)) { person in
          SuiteAvatar(session: session, user: person, size: 20)
        }
        Text(MessageWords.replies(thread.count))
          .font(DesignFont.detail.weight(.semibold))
          .foregroundStyle(theme.accent)
        if let latest = EmberDate.parse(thread.latestAt) {
          Text("Last reply \(MessageWords.lastReply(latest))").font(DesignFont.detail).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("View thread")
  }

  /** The options bar, shown while the pointer is over the message, in a slot that never moves the message. */
  private func actions(_ message: Message) -> some View {
    SuiteMessageActionsBar(session: session, room: room, message: message, inThread: inThread, openThread: openThread)
      .padding(.trailing, Spacing.lg)
      .offset(y: -Spacing.md)
      .headerRevealed()
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
