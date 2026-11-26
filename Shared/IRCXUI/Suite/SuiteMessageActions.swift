import AppCoreUI
import EmberKit
import SwiftUI

/**
 * A message's options bar (web `MessageActionsMenu`): the first three reactions, More reactions, Reply in
 * thread, a file's Download and Share, Edit, and Message options with More actions.
 */
struct SuiteMessageActionsBar: View {
  let session: InstanceSession
  let room: RoomModel
  let message: Message
  let inThread: Bool
  let openThread: (String) -> Void
  @State private var showingTray = false
  @Environment(\.openURL) private var openURL

  private var context: MessageAction.Context {
    MessageAction.Context(mine: message.creator.id == session.me?.id, administrator: session.me?.administrator == true, inThread: inThread)
  }

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      if message.huddle == nil {
        ForEach(Reactions.quick, id: \.emoji) { reaction in
          Button(reaction.emoji) { room.react(reaction.emoji, to: message) }
            .buttonStyle(CompactPillHoverButtonStyle())
            .help(reaction.name)
        }
        PaneIconButton(systemImage: "face.smiling", help: "More reactions") { showingTray = true }
          .popover(isPresented: $showingTray) { SuiteReactionTray(room: room, message: message) { showingTray = false } }
      }
      ForEach(MessageAction.bar(for: message, context), id: \.self) { action in
        switch action {
        case .replyInThread:
          PaneIconButton(systemImage: "bubble.left", help: "Reply in thread") { openThread(message.parentId ?? message.id) }
        case .download:
          if let file = message.attachment {
            PaneIconButton(systemImage: "arrow.down.to.line", help: "Download \(file.name)") { openURL(session.api.url(file.downloadUrl)) }
          }
        case .share:
          if let file = message.attachment {
            ShareLink(item: session.api.url(file.url)) { Image(systemName: "square.and.arrow.up") }
              .buttonStyle(IconHoverButtonStyle())
              .help("Share \(file.name)")
          }
        case .edit:
          PaneIconButton(systemImage: "pencil", help: "Edit") { room.editing.insert(message.id) }
        default: EmptyView()
        }
      }
      Menu {
        SuiteMessageMenu(session: session, room: room, message: message, inThread: inThread, openThread: openThread)
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuIndicator(.hidden)
      .buttonStyle(IconHoverButtonStyle())
      .fixedSize()
      .help("Message options")
    }
    .padding(Spacing.xs)
    .glassEffect(.regular, in: Capsule())
  }
}

/** More actions (web): Quote, Copy text, Copy link, Block or Unblock, Report message, Edit message, Delete message. */
struct SuiteMessageMenu: View {
  let session: InstanceSession
  let room: RoomModel
  let message: Message
  let inThread: Bool
  let openThread: (String) -> Void

  var body: some View {
    let context = MessageAction.Context(mine: message.creator.id == session.me?.id, administrator: session.me?.administrator == true, inThread: inThread)
    let name = session.people[message.creator.id]?.name ?? message.creator.name
    if !inThread {
      Button("Reply in thread", systemImage: "bubble.left") { openThread(message.parentId ?? message.id) }
    }
    if message.huddle == nil {
      Menu("React", systemImage: "face.smiling") {
        ForEach(Reactions.all, id: \.emoji) { reaction in
          Button("\(reaction.emoji) \(reaction.name)") { room.react(reaction.emoji, to: message) }
        }
      }
    }
    ForEach(MessageAction.menu(for: message, context), id: \.self) { action in
      switch action {
      case .quote:
        Button("Quote", systemImage: "text.quote") { room.quote(message, into: room.composer(thread: inThread ? room.thread?.parentId : nil)) }
      case .copyText:
        Button("Copy text", systemImage: "doc.on.doc") { Pasteboard.copy(message.plainText) }
      case .copyLink:
        Button("Copy link", systemImage: "link") { Pasteboard.copy(room.permalink(message)) }
        Divider()
      case .block:
        let blocked = session.isBlocked(message.creator.id)
        Button(blocked ? "Unblock \(name)" : "Block \(name)", systemImage: "hand.raised") { room.setBlocked(!blocked, message.creator.id) }
      case .report:
        Button("Report message", systemImage: "flag") { room.request = .report(message) }
      case .edit:
        Button("Edit message", systemImage: "pencil") { room.editing.insert(message.id) }
      case .delete:
        Button("Delete message", systemImage: "trash", role: .destructive) { room.request = .delete(message) }
      default: EmptyView()
      }
    }
  }
}

/** More reactions (web tray): the other five, and New boost, a word or emoji of up to 16 characters. */
struct SuiteReactionTray: View {
  let room: RoomModel
  let message: Message
  let done: () -> Void
  @State private var custom = ""
  @State private var writing = false
  @FocusState private var focused: Bool

  private var left: Int { EmberLimits.maxBoostLength - custom.count }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(spacing: Spacing.xxs) {
        ForEach(Reactions.all.dropFirst(Reactions.quickCount), id: \.emoji) { reaction in
          Button(reaction.emoji) {
            room.react(reaction.emoji, to: message)
            done()
          }
          .buttonStyle(CompactPillHoverButtonStyle())
          .help(reaction.name)
        }
        PaneIconButton(systemImage: "plus", help: "New boost") {
          writing = true
          focused = true
        }
      }
      if writing {
        HStack(spacing: Spacing.xs) {
          TextField("Emoji or a word", text: $custom)
            .textFieldStyle(.plain)
            .focused($focused)
            .onChange(of: custom) { _, new in
              var kept = String(new.drop { $0 == " " })
              if kept.count > EmberLimits.maxBoostLength { kept = String(kept.prefix(EmberLimits.maxBoostLength)) }
              if kept != new { custom = kept }
            }
            .onSubmit(send)
            .onKeyPress(.escape) {
              writing = false
              custom = ""
              return .handled
            }
          if left <= 5 { Text("\(left) left").font(DesignFont.detail).foregroundStyle(.secondary) }
          if !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            PaneIconButton(systemImage: "arrow.up.circle.fill", help: "Send", action: send)
          }
          PaneIconButton(systemImage: "xmark", help: "Cancel") {
            writing = false
            custom = ""
          }
        }
        .padding(.horizontal, Spacing.sm)
        .background(Capsule().fill(SemanticColor.secondaryFill))
      }
    }
    .padding(Spacing.md)
  }

  private func send() {
    let content = custom.trimmingCharacters(in: .whitespaces)
    guard !content.isEmpty, room.isOpen else { return room.warn(EmberText.notConnected) }
    room.react(content, to: message)
    custom = ""
    writing = false
    done()
  }
}

/**
 * A message's boosts (web `MessageBoosts`): a pill each, oldest first, with its booster's face. Your own
 * shows a red minus on a click, which takes it back; then Add a boost.
 */
struct SuiteBoosts: View {
  let session: InstanceSession
  let room: RoomModel
  let message: Message
  @State private var revealed: String?
  @State private var showingTray = false

  var body: some View {
    if !message.boosts.isEmpty {
      FlowLayout(hSpacing: Spacing.xs, vSpacing: Spacing.xs) {
        ForEach(message.boosts) { boost in
          let mine = boost.booster.id == session.me?.id
          let booster = session.people[boost.booster.id]?.name ?? boost.booster.name
          HStack(spacing: Spacing.xxs) {
            Button {
              if mine { revealed = revealed == boost.id ? nil : boost.id }
            } label: {
              HStack(spacing: Spacing.xxs) {
                SuiteAvatar(session: session, user: boost.booster, size: 16)
                Text(boost.content).font(Display.isAllEmoji(boost.content) ? DesignFont.body : DesignFont.detail)
              }
              .padding(.horizontal, Spacing.sm)
              .padding(.vertical, Spacing.xxs)
              .background(Capsule().fill(mine ? SemanticColor.accent.opacity(0.18) : SemanticColor.secondaryFill))
              .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!mine)
            .help("\(booster) boosted \(boost.content)")
            if revealed == boost.id {
              PaneIconButton(systemImage: "minus.circle.fill", help: "Delete this boost", role: .destructive) {
                revealed = nil
                room.unboost(boost)
              }
            }
          }
        }
        if message.huddle == nil {
          PaneIconButton(systemImage: "face.smiling", help: "Add a boost") { showingTray = true }
            .popover(isPresented: $showingTray) { SuiteReactionTray(room: room, message: message) { showingTray = false } }
        }
      }
    }
  }
}

/**
 * A message open in its editor, in place (web `MessageEditor`): the formatting row on a Mac, the rich
 * editor seeded with its body, Save changes, Delete message and Close; ⌘Return saves, Esc closes. A
 * file's, a bot's cards' or a huddle's shows itself with only Delete and Close (`FixedMessageEditor`).
 */
struct SuiteMessageEditor: View {
  let session: InstanceSession
  let room: RoomModel
  let message: Message
  @State private var controller = RichEditorController()
  @State private var mentionIndex = 0

  /** What the editor holds, which the room keeps while it's open, so scrolling it away loses nothing. */
  private var composer: ComposerModel { room.editor(for: message) }

  var body: some View {
    let composer = composer
    VStack(alignment: .leading, spacing: Spacing.sm) {
      if composer.mentionQuery != nil {
        SuiteMentionPrompt(session: session, composer: composer, selected: mentionIndex) { controller.pickMention($0) }
      }
      if MessageAction.editsFixed(message) {
        Text(message.attachment?.name ?? message.plainText).font(DesignFont.body).lineLimit(3)
          .onKeyPress(.escape) {
            close()
            return .handled
          }
      } else {
        #if os(macOS)
        SuiteFormattingRow(controller: controller)
        #endif
        SuiteRichEditor(controller: controller, placeholder: "", document: composer.document, revision: composer.revision, actions: actions(composer))
      }
      HStack(spacing: Spacing.xs) {
        Spacer()
        PaneIconButton(systemImage: "xmark", help: "Close editor and discard changes", action: close)
          .keyboardShortcut(.cancelAction)
        PaneIconButton(systemImage: "trash", help: "Delete message", role: .destructive) { room.request = .delete(message) }
        if !MessageAction.editsFixed(message) {
          Button("Save changes", systemImage: "checkmark", action: save)
            .labelStyle(.iconOnly)
            .buttonStyle(.glassProminent)
            .help("Save changes")
        }
      }
    }
    .padding(Spacing.md)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .onChange(of: composer.candidates) { _, _ in mentionIndex = 0 }
  }

  private func actions(_ composer: ComposerModel) -> EditorActions {
    var actions = EditorActions()
    actions.changed = { composer.document = $0 }
    // ⌘Return saves, but not while the @ prompt is open (web `MessageEditor`).
    actions.submit = { if composer.mentionQuery == nil { save() } }
    actions.mentionQuery = { composer.lookUpMentions($0, api: session.api, room: room.id) }
    actions.mentionKey = { SuiteMentionPrompt.key($0, composer: composer, controller: controller, index: $mentionIndex) }
    actions.escape = {
      close()
      return true
    }
    actions.returnSends = false
    return actions
  }

  private func save() {
    room.edit(message, to: composer.document)
  }

  private func close() {
    room.editing.remove(message.id)
  }
}

/** A file on its way to becoming a message (web `UploadCard`): its name and size, then how much has gone, or why it failed. */
struct SuiteUploadCard: View {
  let upload: UploadState

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(alignment: .firstTextBaseline) {
        Text(upload.name).font(DesignFont.bodyEmphasized)
        Spacer()
        Text(UploadWords.size(upload.size)).font(DesignFont.detail).foregroundStyle(.secondary)
      }
      if let error = upload.error {
        Text(upload.status).font(DesignFont.detail).foregroundStyle(SemanticColor.destructive)
        Text(error).font(DesignFont.detail).foregroundStyle(.secondary)
      } else {
        MeterBar(fraction: Double(upload.percent) / 100, tint: SemanticColor.accent)
        Text(upload.status).font(DesignFont.detail).foregroundStyle(.secondary)
      }
    }
    .padding(Spacing.md)
    .frame(maxWidth: 380, alignment: .leading)
    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(upload.error == nil ? SemanticColor.separator : SemanticColor.destructive))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Upload \(upload.name)")
  }
}
