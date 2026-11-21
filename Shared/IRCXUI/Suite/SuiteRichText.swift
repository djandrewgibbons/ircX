import AppCoreUI
import EmberKit
import SwiftUI

/**
 * A message's text as the web's message-body.tsx draws it: paragraphs, headings, lists, quotes, code
 * blocks with Copy code, rules, tables and link previews, with mentions by the name the directory has now.
 * A message of nothing but emoji shows large.
 */
struct SuiteMessageBody: View {
  let session: InstanceSession
  let blocks: [RichBlock]
  var mentions: [User] = []
  var emoji = false
  /** Small gray type, as a card's context shows text. */
  var small = false
  /** What follows the text, in its last paragraph, as a follow-up's "(edited)". */
  var trailing: String?
  /** Where the text sits across its width: leading, but for a card table's centered or right-aligned column. */
  var alignment: Alignment = .leading

  var body: some View {
    VStack(alignment: alignment.horizontal, spacing: Spacing.sm) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
        SuiteBlock(session: session, block: block, mentions: mentions, emoji: emoji, small: small, trailing: index == blocks.count - 1 ? trailing : nil)
      }
      if let trailing, !(blocks.last.map(Self.takesTrailing) == true) {
        Text(trailing).font(DesignFont.detail).foregroundStyle(.secondary)
      }
    }
    .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
    .frame(maxWidth: .infinity, alignment: alignment)
  }

  static func takesTrailing(_ block: RichBlock) -> Bool {
    if case .paragraph = block { return true }
    return false
  }
}

struct SuiteBlock: View {
  let session: InstanceSession
  let block: RichBlock
  let mentions: [User]
  var emoji = false
  var small = false
  var trailing: String?
  var depth = 0
  @Environment(\.suiteTheme) private var theme

  var body: some View {
    switch block {
    case let .paragraph(runs):
      Text(paragraph(runs))
        .font(emoji ? DesignFont.scaled(34) : small ? DesignFont.detail : DesignFont.body)
        .foregroundStyle(small ? .secondary : .primary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    case let .heading(level, runs):
      Text(SuiteInline(session: session, mentions: mentions, accent: theme.accent).attributed(runs))
        .font(level == 1 ? DesignFont.title : level == 2 ? DesignFont.cardTitle : DesignFont.bodyEmphasized)
        .textSelection(.enabled)
    case let .list(ordered, start, items):
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
          HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(item.bare ? "" : ordered ? "\(start + index)." : Self.bullets[depth % Self.bullets.count])
              .font(small ? DesignFont.detail : DesignFont.body)
              .foregroundStyle(.secondary)
              .frame(minWidth: Spacing.xl, alignment: .trailing)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
              ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, inner in
                SuiteBlock(session: session, block: inner, mentions: mentions, small: small, depth: depth + 1)
              }
            }
          }
        }
      }
    case let .quote(blocks):
      HStack(alignment: .top, spacing: Spacing.md) {
        RoundedRectangle(cornerRadius: Radius.small).fill(SemanticColor.separator).frame(width: Spacing.xs)
        VStack(alignment: .leading, spacing: Spacing.xs) {
          ForEach(Array(blocks.enumerated()), id: \.offset) { _, inner in
            SuiteBlock(session: session, block: inner, mentions: mentions, small: small, depth: depth)
          }
        }
        .foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
    case let .code(code, language, runs):
      SuiteCodeBlock(code: code, language: language, fallback: SuiteInline(session: session, mentions: mentions, accent: theme.accent).attributed(runs))
    case .rule:
      Rectangle().fill(SemanticColor.separator).frame(height: 1).padding(.vertical, Spacing.xs)
    case let .table(rows):
      ScrollView(.horizontal) {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            GridRow {
              ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                Text(SuiteInline(session: session, mentions: mentions, accent: theme.accent).attributed(cell.runs))
                  .font(DesignFont.body)
                  .padding(.horizontal, Spacing.md)
                  .padding(.vertical, Spacing.xs)
                  .frame(maxWidth: 320, alignment: .leading)
                  .border(SemanticColor.separator)
              }
            }
          }
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel("Table")
    case let .preview(preview):
      SuiteLinkPreview(session: session, preview: preview, mentions: mentions)
    }
  }

  static let bullets = ["\u{2022}", "\u{25E6}", "\u{25AA}"]

  private func paragraph(_ runs: [RichRun]) -> AttributedString {
    var text = SuiteInline(session: session, mentions: mentions, accent: theme.accent).attributed(runs)
    if let trailing {
      var mark = AttributedString(" " + trailing)
      mark.font = DesignFont.detail
      mark.foregroundColor = SemanticColor.secondaryLabel
      text += mark
    }
    return text
  }
}

/** Runs of text as SwiftUI draws them, mentions by the name the directory has for them now. */
@MainActor
struct SuiteInline {
  let session: InstanceSession
  let mentions: [User]
  let accent: Color

  func name(_ id: UserID) -> String? {
    session.people[id]?.name ?? mentions.first { $0.id == id }?.name
  }

  func attributed(_ runs: [RichRun]) -> AttributedString {
    var out = AttributedString()
    for run in runs {
      var piece: AttributedString
      switch run.content {
      case let .text(text):
        piece = AttributedString(text)
      case let .mention(id):
        guard let name = name(id) else {
          out += AttributedString(Display.missingAttachable)
          continue
        }
        piece = AttributedString("@" + name)
        piece.foregroundColor = accent
        piece.inlinePresentationIntent = .stronglyEmphasized
        if id == session.me?.id { piece.backgroundColor = accent.opacity(0.15) }
      }
      var intent = piece.inlinePresentationIntent ?? []
      if run.style.bold { intent.insert(.stronglyEmphasized) }
      if run.style.italic { intent.insert(.emphasized) }
      if run.style.code { intent.insert(.code) }
      if !intent.isEmpty { piece.inlinePresentationIntent = intent }
      if run.style.code { piece.backgroundColor = SemanticColor.secondaryFill }
      if run.style.strike { piece.strikethroughStyle = .single }
      if run.style.underline { piece.underlineStyle = .single }
      if run.style.mark { piece.backgroundColor = SemanticColor.warning.opacity(0.3) }
      if let href = run.style.link, let url = MessageLinks.url(href, api: session.api) {
        piece.link = url
        piece.foregroundColor = accent
      }
      out += piece
    }
    return out
  }
}

/**
 * A code block, highlighted where it holds only text, with Copy code over its top right corner, which
 * turns green once it's copied (web code-block.tsx). A file's text folds past 5 lines or 700 characters.
 */
struct SuiteCodeBlock: View {
  let code: String?
  let language: String?
  var fallback = AttributedString()
  /** What Copy code copies, where it isn't what shows, as a file's text with its line ends. */
  var copied: String?
  /** Highlights only where the file's name says its language. */
  var plain = false
  var folds = false
  @State private var open = false
  @State private var didCopy = false
  @Environment(\.suiteTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      ScrollView(.horizontal) {
        Text(highlighted)
          .font(DesignFont.monoDetail)
          .textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: true)
          .padding(Spacing.lg)
          .padding(.trailing, Spacing.xxl)
      }
      .frame(maxHeight: long && !open ? 112 : long ? 640 : nil, alignment: .top)
      .clipped()
      .background(SemanticColor.secondaryFill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
      .overlay(alignment: .topTrailing) {
        Button {
          Pasteboard.copy(copied ?? code ?? String(fallback.characters))
          didCopy = true
        } label: {
          Label("Copy code", systemImage: didCopy ? "checkmark" : "doc.on.doc").labelStyle(.iconOnly)
        }
        .buttonStyle(IconHoverButtonStyle())
        .foregroundStyle(didCopy ? SemanticColor.positive : .secondary)
        .help("Copy code")
        .padding(Spacing.xs)
        .task(id: didCopy) {
          guard didCopy else { return }
          try? await Task.sleep(for: .seconds(2))
          didCopy = false
        }
      }
      if long {
        Button(open ? "Show less" : "Show more") { open.toggle() }
          .buttonStyle(.plain)
          .font(DesignFont.detail.weight(.medium))
          .foregroundStyle(theme.accent)
      }
    }
  }

  private var long: Bool { folds && code.map(TextPreview.isLong) == true }

  private var highlighted: AttributedString {
    guard let code else { return fallback }
    guard !plain else { return AttributedString(code) }
    var out = AttributedString()
    for token in Highlight.highlight(code, language: language) {
      var piece = AttributedString(token.text)
      if let kind = token.kind { piece.foregroundColor = Self.color(kind, accent: theme.accent) }
      if token.kind == .keyword || token.kind == .tag { piece.inlinePresentationIntent = .stronglyEmphasized }
      out += piece
    }
    return out
  }

  static func color(_ kind: HighlightToken.Kind, accent: Color) -> Color {
    switch kind {
    case .keyword, .tag, .variable: accent
    case .string, .addition: SemanticColor.positive
    case .comment, .meta: SemanticColor.tertiaryLabel
    case .number, .literal, .attribute: SemanticColor.warning
    case .type, .builtIn: SemanticColor.secondaryLabel
    case .deletion: SemanticColor.destructive
    }
  }
}

/**
 * A link preview (web `LinkPreview`): the page's title in semibold, linking to it, its description cut at
 * six lines, then its image, 16:9 under the text, or beside it on a wide message; an X avatar is small and round.
 */
struct SuiteLinkPreview: View {
  let session: InstanceSession
  let preview: DisplayPreview
  var mentions: [User] = []
  @Environment(\.suiteTheme) private var theme

  var body: some View {
    let inline = SuiteInline(session: session, mentions: mentions, accent: theme.accent)
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: Spacing.lg) {
        text(inline)
        image.frame(width: preview.avatar ? 44 : 200)
      }
      .frame(minWidth: 560)
      VStack(alignment: .leading, spacing: Spacing.lg) {
        text(inline)
        image.frame(maxWidth: preview.avatar ? 44 : 360)
      }
    }
    .padding(Spacing.lg)
    .frame(maxWidth: 640, alignment: .leading)
    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(SemanticColor.separator))
  }

  private func text(_ inline: SuiteInline) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if !preview.title.isEmpty {
        Text(title(inline)).font(DesignFont.bodyEmphasized)
      }
      if !preview.description.isEmpty {
        Text(inline.attributed(RichLayout.runs(preview.description))).font(DesignFont.body).lineLimit(6)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /** The title, linking to the page where the preview has an address. */
  private func title(_ inline: SuiteInline) -> AttributedString {
    var title = inline.attributed(RichLayout.runs(preview.title))
    if let href = preview.href, let url = URL(string: href) {
      title.link = url
      title.foregroundColor = theme.accent
    }
    return title
  }

  @ViewBuilder private var image: some View {
    if let address = preview.image {
      if preview.avatar {
        RemoteImage(url: address, fill: true).frame(width: 44, height: 44).clipShape(Circle())
      } else {
        RemoteImage(url: address).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
      }
    }
  }
}

/** A message's file, as the web's attachment.tsx shows it. */
struct SuiteAttachment: View {
  let session: InstanceSession
  let file: StoredFile
  @State private var viewing: ViewedImage?
  @State private var text: (shown: String, copied: String)?
  @State private var svg: PlatformImage?

  var body: some View {
    switch AttachmentShown(file) {
    case .svg:
      VStack(alignment: .leading, spacing: Spacing.sm) {
        if let svg {
          RemoteImage.image(svg).resizable().scaledToFit()
            .frame(maxWidth: min(600, svg.size.width), maxHeight: min(400, svg.size.height), alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .accessibilityLabel(file.name)
        }
        SuiteFileCard(session: session, file: file)
      }
      .task(id: file.id) { svg = await FileLoads.svg(file, api: session.api) }
    case .video:
      InlineVideo(api: session.api, file: file).clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    case let .text(language):
      VStack(alignment: .leading, spacing: Spacing.sm) {
        if let text {
          SuiteCodeBlock(code: text.shown, language: language, copied: text.copied, plain: language == nil, folds: true)
        }
        SuiteFileCard(session: session, file: file)
      }
      .task(id: file.id) { text = await FileLoads.text(file, api: session.api) }
    case let .picture(path):
      let size = AttachmentShown.shownSize(file)
      Button {
        viewing = ViewedImage(path: AttachmentShown.viewed(file, shown: path), name: file.name, downloadPath: file.downloadUrl)
      } label: {
        AuthImage(api: session.api, path: path)
          .aspectRatio(size.map { $0.width / $0.height }, contentMode: .fit)
          .frame(maxWidth: min(size.map { $0.width / 2 } ?? 480, 480), maxHeight: 480, alignment: .leading)
          .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(SemanticColor.separator))
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(file.name)
      .help(file.name)
      .imageViewer($viewing, api: session.api)
    case .card:
      SuiteFileCard(session: session, file: file)
    }
  }
}

/** The card for a file a message doesn't show as a picture or a video: its icon, its name, Download and Share (web `FileCard`). */
struct SuiteFileCard: View {
  let session: InstanceSession
  let file: StoredFile
  @Environment(\.openURL) private var openURL

  var body: some View {
    HStack(spacing: Spacing.md) {
      Image(systemName: "doc")
        .frame(width: Spacing.xxxl, height: Spacing.xxxl)
        .background(SemanticColor.secondaryFill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
      Text(file.name).font(DesignFont.bodyEmphasized).lineLimit(2).help("\(file.name), \(file.byteSize.byteText)")
      PaneIconButton(systemImage: "arrow.down.to.line", help: "Download \(file.name)") { openURL(session.api.url(file.downloadUrl)) }
      ShareLink(item: session.api.url(file.downloadUrl)) {
        Label("Share \(file.name)", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
      }
      .buttonStyle(IconHoverButtonStyle())
      .help("Share \(file.name)")
    }
    .padding(Spacing.md)
    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(SemanticColor.separator))
    .fixedSize(horizontal: false, vertical: true)
  }
}

/** What a huddle's message has where its author's face would be: the headphones, on green while it goes on. */
struct SuiteHuddleTile: View {
  let huddle: MessageHuddle
  let size: CGFloat

  var body: some View {
    Image(systemName: "headphones")
      .font(DesignFont.bodyEmphasized)
      .foregroundStyle(huddle.endedAt == nil ? Color.white : SemanticColor.secondaryLabel)
      .frame(width: size, height: size)
      .background(huddle.endedAt == nil ? SemanticColor.positive : SemanticColor.secondaryFill, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
      .accessibilityHidden(true)
  }
}

/** A huddle's heading and what it says of its huddle (web huddle-message.tsx), display only. */
struct SuiteHuddleSummary: View {
  let session: InstanceSession
  let message: Message
  let huddle: MessageHuddle

  var body: some View {
    let people = huddle.endedAt == nil ? live : (huddle.people ?? [])
    HStack(spacing: Spacing.sm) {
      if let summary = MessageWords.huddleSummary(huddle, live: session.huddles[message.roomId], me: session.me?.id, name: { session.people[$0]?.name }) {
        HStack(spacing: -Spacing.sm) {
          ForEach(people.prefix(MessageWords.huddleFaces)) { person in
            SuiteAvatar(session: session, user: person, size: 24)
          }
        }
        Text(summary).font(DesignFont.body)
      }
      SuiteHuddleJoin(session: session, message: message)
    }
  }

  private var live: [User] {
    guard let going = session.huddles[message.roomId], going.startedAt == huddle.startedAt else { return [] }
    return going.userIds.compactMap { session.people[$0]?.user }
  }
}

/** LIVE, on green, which marks a huddle that's going on. */
struct SuiteLiveBadge: View {
  var body: some View {
    Text("LIVE")
      .font(DesignFont.detail.weight(.bold))
      .foregroundStyle(Color.white)
      .padding(.horizontal, Spacing.sm)
      .background(SemanticColor.positive, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
  }
}
