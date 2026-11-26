import EmberKit
import SwiftUI

/**
 * A message's text in fixed width, as a terminal client would draw Ember's formatting: paragraphs on the
 * line, lists as `  * item` and ` 1. item`, quotes as `> text`, code blocks indented with `[copy]`,
 * headings bold, rules as `----`, tables in aligned columns, and link previews as one `|` line.
 */
struct IRCMessageBody: View {
  let session: InstanceSession
  let blocks: [RichBlock]
  var mentions: [User] = []
  var dim = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        IRCBlock(session: session, block: block, mentions: mentions, dim: dim)
      }
    }
  }
}

struct IRCBlock: View {
  let session: InstanceSession
  let block: RichBlock
  let mentions: [User]
  var dim = false
  var depth = 0
  @Environment(\.theme) private var theme

  var body: some View {
    switch block {
    case let .paragraph(runs):
      Text(inline.attributed(runs)).foregroundStyle(dim ? theme.dim : theme.text)
    case let .heading(_, runs):
      Text(inline.attributed(runs)).bold().foregroundStyle(theme.text)
    case let .list(ordered, start, items):
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
          HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(item.bare ? "    " : ordered ? String(format: "%3d. ", start + index) : "  \(depth % 2 == 0 ? "*" : "-") ")
              .foregroundStyle(theme.dim)
            VStack(alignment: .leading, spacing: 0) {
              ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, inner in
                IRCBlock(session: session, block: inner, mentions: mentions, dim: dim, depth: depth + 1)
              }
            }
          }
        }
      }
    case let .quote(blocks):
      HStack(alignment: .top, spacing: 0) {
        Text("> ").foregroundStyle(theme.dim)
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(blocks.enumerated()), id: \.offset) { _, inner in
            IRCBlock(session: session, block: inner, mentions: mentions, dim: true, depth: depth)
          }
        }
      }
    case let .code(code, language, runs):
      IRCCode(code: code, language: language, fallback: inline.attributed(runs))
    case .rule:
      Text("----").foregroundStyle(theme.faint)
    case let .table(rows):
      IRCTable(rows: rows.map { $0.map { RichLayout.text($0.runs, name: inline.shownName) } }, header: rows.first?.first?.header == true)
    case let .preview(preview):
      IRCPreview(session: session, preview: preview)
    }
  }

  private var inline: IRCInline { IRCInline(session: session, mentions: mentions, theme: theme) }
}

/** Runs of text in the IRC theme's palette: mentions in their nick's color, yours in Ember's orange. */
@MainActor
struct IRCInline {
  let session: InstanceSession
  let mentions: [User]
  let theme: Theme

  func shownName(_ id: UserID) -> String {
    if let name = session.people[id]?.name ?? mentions.first(where: { $0.id == id })?.name { return name }
    return Display.missingAttachable
  }

  func attributed(_ runs: [RichRun]) -> AttributedString {
    var out = AttributedString()
    for run in runs {
      var piece: AttributedString
      switch run.content {
      case let .text(text):
        piece = AttributedString(text)
      case let .mention(id):
        piece = AttributedString("@" + shownName(id))
        piece.foregroundColor = id == session.me?.id ? theme.ember : theme.nick(id)
        piece.inlinePresentationIntent = .stronglyEmphasized
      }
      var intent = piece.inlinePresentationIntent ?? []
      if run.style.bold { intent.insert(.stronglyEmphasized) }
      if run.style.italic { intent.insert(.emphasized) }
      if !intent.isEmpty { piece.inlinePresentationIntent = intent }
      if run.style.code { piece.foregroundColor = theme.action }
      if run.style.strike { piece.strikethroughStyle = .single }
      if run.style.underline { piece.underlineStyle = .single }
      if run.style.mark { piece.backgroundColor = theme.highlight }
      if let href = run.style.link, let url = MessageLinks.url(href, api: session.api) {
        piece.link = url
        piece.foregroundColor = theme.link
        piece.underlineStyle = .single
      }
      out += piece
    }
    return out
  }
}

/** A code block, indented, highlighted in the theme's palette, with `[copy]`; a file's text folds at 5 lines behind `[more]`. */
struct IRCCode: View {
  let code: String?
  let language: String?
  var fallback = AttributedString()
  var copied: String?
  var plain = false
  var folds = false
  @Environment(\.theme) private var theme
  @State private var open = false
  @State private var didCopy = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        Text(shown).textSelection(.enabled).padding(.leading, 16)
        Button(didCopy ? "[copied]" : "[copy]") {
          Pasteboard.copy(copied ?? code ?? String(fallback.characters))
          didCopy = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(didCopy ? theme.join : theme.link)
        .help("Copy code")
      }
      if long {
        Button(open ? "[less]" : "[more]") { open.toggle() }
          .buttonStyle(.plain)
          .foregroundStyle(theme.link)
          .padding(.leading, 16)
      }
    }
  }

  private var long: Bool { folds && code.map(TextPreview.isLong) == true }

  private var shown: AttributedString {
    guard let code else { return fallback }
    let text = long && !open ? code.split(separator: "\n", omittingEmptySubsequences: false).prefix(TextPreview.foldLines).joined(separator: "\n") : code
    guard !plain else {
      var out = AttributedString(text)
      out.foregroundColor = theme.text
      return out
    }
    var out = AttributedString()
    for token in Highlight.highlight(text, language: language) {
      var piece = AttributedString(token.text)
      piece.foregroundColor = token.kind.map(color) ?? theme.text
      out += piece
    }
    return out
  }

  private func color(_ kind: HighlightToken.Kind) -> Color {
    switch kind {
    case .keyword, .tag: theme.ember
    case .string, .addition: theme.join
    case .comment, .meta: theme.dim
    case .number, .literal, .variable: theme.action
    case .type, .builtIn, .attribute: theme.link
    case .deletion: theme.part
    }
  }
}

/**
 * A table in aligned monospaced columns, each padded to its card column's alignment; a cell is cut at 40
 * characters unless its column wraps, when it goes on over more lines (web card `Table`).
 */
struct IRCTable: View {
  let rows: [[String]]
  var header = false
  var columns: [CardColumn] = []
  @Environment(\.theme) private var theme

  static let widest = 40

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
        ForEach(Array(Self.lines(row, widths: widths, columns: columns).enumerated()), id: \.offset) { _, line in
          Text(line)
            .bold(header && index == 0)
            .foregroundStyle(theme.text)
            .lineLimit(1)
        }
      }
    }
  }

  /** Each column as wide as its widest cell, up to 40 characters. */
  private var widths: [Int] {
    var widths: [Int] = []
    for row in rows {
      for (column, cell) in row.enumerated() {
        if column == widths.count { widths.append(0) }
        widths[column] = min(Self.widest, max(widths[column], cell.count))
      }
    }
    return widths
  }

  /** A row's lines: one, or as many as its wrapping cells take. */
  static func lines(_ row: [String], widths: [Int], columns: [CardColumn]) -> [String] {
    let cells = row.enumerated().map { column, cell -> [String] in
      let width = widths[column]
      if column < columns.count, columns[column].wrap { return wrapped(cell, width: width) }
      return [cell.count > width ? String(cell.prefix(max(0, width - 1))) + "\u{2026}" : cell]
    }
    let height = cells.map(\.count).max() ?? 1
    return (0..<height).map { line in
      cells.enumerated().map { column, pieces in
        padded(line < pieces.count ? pieces[line] : "", width: widths[column], align: column < columns.count ? columns[column].align : .left)
      }.joined(separator: " | ")
    }
  }

  static func padded(_ text: String, width: Int, align: CardColumn.Align) -> String {
    let room = max(0, width - text.count)
    switch align {
    case .left: return text + String(repeating: " ", count: room)
    case .right: return String(repeating: " ", count: room) + text
    case .center: return String(repeating: " ", count: room / 2) + text + String(repeating: " ", count: room - room / 2)
    }
  }

  /** `text` in lines of at most `width` characters, broken between words where it can be. */
  static func wrapped(_ text: String, width: Int) -> [String] {
    guard width > 0, text.count > width else { return [text] }
    var lines: [String] = []
    var line = ""
    for word in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
      var word = word
      while word.count > width {
        if !line.isEmpty { lines.append(line); line = "" }
        lines.append(String(word.prefix(width)))
        word = String(word.dropFirst(width))
      }
      if line.isEmpty {
        line = word
      } else if line.count + 1 + word.count <= width {
        line += " " + word
      } else {
        lines.append(line)
        line = word
      }
    }
    if !line.isEmpty { lines.append(line) }
    return lines
  }
}

/** A link preview as one dim line: `| Title - description`, with `[img]` to open its image. */
struct IRCPreview: View {
  let session: InstanceSession
  let preview: DisplayPreview
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL

  var body: some View {
    let inline = IRCInline(session: session, mentions: [], theme: theme)
    let title = preview.title.map { $0.plainText(name: inline.shownName) }.joined()
    let description = preview.description.map { $0.plainText(name: inline.shownName) }.joined()
    HStack(spacing: 6) {
      Text("|").foregroundStyle(theme.faint)
      if let href = preview.href, let url = URL(string: href) {
        Button(title) { openURL(url) }.buttonStyle(.plain).foregroundStyle(theme.link).bold().help(href)
      } else {
        Text(title).bold().foregroundStyle(theme.text)
      }
      if !description.isEmpty {
        Text("- " + description).foregroundStyle(theme.dim).lineLimit(1)
      }
      if let image = preview.image, let url = URL(string: image) {
        Button("[img]") { openURL(url) }.buttonStyle(.plain).foregroundStyle(theme.link)
      }
    }
  }
}

/** A message's file as a line, `[file] name (size)` with `[open]`, `[save]` and `[share]`, and what the web shows above it. */
struct IRCAttachment: View {
  let session: InstanceSession
  let file: StoredFile
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  @State private var viewing: ViewedImage?
  @State private var text: (shown: String, copied: String)?
  @State private var svg: PlatformImage?
  @State private var playing = false

  var body: some View {
    let shown = AttachmentShown(file)
    VStack(alignment: .leading, spacing: 2) {
      switch shown {
      case .svg:
        if let svg {
          RemoteImage.image(svg).resizable().scaledToFit().frame(maxWidth: min(360, svg.size.width), maxHeight: min(240, svg.size.height), alignment: .leading).accessibilityLabel(file.name)
        }
      case .video:
        if playing { InlineVideo(api: session.api, file: file) }
      case let .text(language):
        if let text { IRCCode(code: text.shown, language: language, copied: text.copied, plain: language == nil, folds: true) }
      case let .picture(path):
        Button {
          viewing = ViewedImage(path: AttachmentShown.viewed(file, shown: path), name: file.name, downloadPath: file.downloadUrl)
        } label: {
          AuthImage(api: session.api, path: path).frame(maxWidth: 360, maxHeight: 240, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(file.name)
        .imageViewer($viewing, api: session.api, classic: true)
      case .card:
        EmptyView()
      }
      HStack(spacing: 6) {
        Text(shown == .video ? "[video]" : "[file]").foregroundStyle(theme.dim)
        Text("\(file.name) (\(file.byteSize.byteText))").foregroundStyle(theme.text)
        if shown == .video {
          Button(playing ? "[stop]" : "[play]") { playing.toggle() }.buttonStyle(.plain).foregroundStyle(theme.link)
        }
        Button("[open]") { openURL(session.api.url(file.url)) }.buttonStyle(.plain).foregroundStyle(theme.link).help("Open \(file.name)")
        Button("[save]") { openURL(session.api.url(file.downloadUrl)) }.buttonStyle(.plain).foregroundStyle(theme.link).help("Download \(file.name)")
        ShareLink(item: session.api.url(file.downloadUrl)) { Text("[share]") }.buttonStyle(.plain).foregroundStyle(theme.link).help("Share \(file.name)")
      }
    }
    .task(id: file.id) {
      switch shown {
      case .svg: svg = await FileLoads.svg(file, api: session.api)
      case .text: text = await FileLoads.text(file, api: session.api)
      default: break
      }
    }
  }
}

/** A huddle's message as a line: `A huddle is happening [LIVE]` and who's in it, or who was and for how long. */
struct IRCHuddle: View {
  let session: InstanceSession
  let message: Message
  let huddle: MessageHuddle
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: 6) {
      Text(MessageWords.huddleTitle(huddle)).bold().foregroundStyle(huddle.endedAt == nil ? theme.join : theme.text)
      if huddle.endedAt == nil { Text("[LIVE]").bold().foregroundStyle(theme.join) }
      if let summary = MessageWords.huddleSummary(huddle, live: session.huddles[message.roomId], me: session.me?.id, name: { session.people[$0]?.name }) {
        Text("- " + summary).foregroundStyle(theme.dim)
      }
      if let center = session.huddleCenter, huddle.endedAt == nil, session.account?.huddles == true,
        center.call.map({ $0.session === session && $0.roomId == message.roomId }) != true
      {
        Button {
          center.preview(message.roomId, in: session)
        } label: {
          Text("[join]").foregroundStyle(theme.join)
        }
        .buttonStyle(.plain)
        .help("Join the huddle (/huddle join)")
      }
    }
  }
}
