import EmberKit
import Foundation
import OSLog
import SwiftUI

/**
 * What a message's text shows, laid out in blocks both themes draw (web message-body.tsx): paragraphs,
 * headings, lists, quotes, code blocks, rules, tables and link previews, each holding runs of text with
 * the formats they're in.
 */
indirect enum RichBlock: Hashable {
  case paragraph([RichRun])
  case heading(level: Int, [RichRun])
  /** `bare` items hold only a list, as Lexxy nests one, and show no marker of their own. */
  case list(ordered: Bool, start: Int, items: [RichItem])
  case quote([RichBlock])
  /** `code` is nil where the block holds more than text, as a linked address, which then doesn't highlight. */
  case code(code: String?, language: String?, runs: [RichRun])
  case rule
  case table(rows: [[RichCell]])
  case preview(DisplayPreview)
}

struct RichItem: Hashable {
  var blocks: [RichBlock]
  var bare: Bool
}

struct RichCell: Hashable {
  var runs: [RichRun]
  var header: Bool
}

/** A run of text in the formats around it. */
struct RichRun: Hashable {
  struct Style: Hashable {
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var code = false
    var mark = false
    var link: String?
  }

  enum Content: Hashable {
    case text(String)
    case mention(UserID)
  }

  var content: Content
  var style: Style
}

enum RichLayout {
  static let blockNames: Set<String> = [
    "p", "div", "address", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "hr", "table", "thead", "tbody", "tfoot",
    "tr", "dl", "dt", "dd", "figure", "figcaption",
  ]

  /** A stored body as it shows, or nil where it can't, which is logged (web `shownBody`). Kept, as a timeline asks on every draw. */
  static func shown(_ body: String, plainText: String, host: String) -> [DisplayNode]? {
    let key = "\(host)\u{0}\(plainText)\u{0}\(body)" as NSString
    if let kept = cache.object(forKey: key) { return kept.nodes }
    let nodes: [DisplayNode]?
    do {
      nodes = try Display.body(body, plainText: plainText, host: host)
    } catch {
      logger.error("A message couldn't be shown: \(error.localizedDescription, privacy: .public)")
      nodes = nil
    }
    cache.setObject(Shown(nodes), forKey: key)
    return nodes
  }

  /** Shown text, by what it's shown from. */
  final class Shown {
    let nodes: [DisplayNode]?
    init(_ nodes: [DisplayNode]?) { self.nodes = nodes }
  }

  nonisolated(unsafe) static let cache: NSCache<NSString, Shown> = {
    let cache = NSCache<NSString, Shown>()
    cache.countLimit = 2000
    return cache
  }()

  /** Laid out, where it shows. */
  static func blocks(_ body: String, plainText: String, host: String) -> [RichBlock]? {
    shown(body, plainText: plainText, host: host).map(blocks)
  }

  /** `nodes` laid out in blocks. */
  static func blocks(_ nodes: [DisplayNode]) -> [RichBlock] {
    var blocks: [RichBlock] = []
    var inline: [DisplayNode] = []
    func flush() {
      let runs = self.runs(inline)
      if !isBlank(runs) { blocks.append(.paragraph(trimmed(runs))) }
      inline = []
    }
    for node in nodes {
      switch node {
      case let .preview(preview):
        flush()
        blocks.append(.preview(preview))
      case let .element(name, attrs, children) where blockNames.contains(name):
        flush()
        blocks.append(contentsOf: block(name, attrs, children))
      default:
        if containsBlock(node) {
          // An inline element around blocks, as a link around a paragraph: its blocks show, in its formats.
          flush()
          blocks.append(contentsOf: Self.blocks(children(of: node)))
        } else {
          inline.append(node)
        }
      }
    }
    flush()
    return blocks
  }

  static func children(of node: DisplayNode) -> [DisplayNode] {
    if case let .element(_, _, children) = node { return children }
    return []
  }

  static func containsBlock(_ node: DisplayNode) -> Bool {
    guard case let .element(name, _, children) = node else {
      if case .preview = node { return true }
      return false
    }
    return blockNames.contains(name) || children.contains(where: containsBlock)
  }

  static func block(_ name: String, _ attrs: [String: String], _ children: [DisplayNode]) -> [RichBlock] {
    switch name {
    case "h1", "h2", "h3", "h4", "h5", "h6":
      guard let level = Int(name.dropFirst()) else { return [] }
      return [.heading(level: level, trimmed(runs(children)))]
    case "ul", "ol":
      let items = children.compactMap { child -> RichItem? in
        guard case let .element(itemName, _, itemChildren) = child else { return nil }
        let shown = itemChildren.filter { node in
          if case let .text(text) = node { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
          return true
        }
        var bare = false
        if shown.count == 1, case let .element(inner, _, _) = shown[0], inner == "ul" || inner == "ol" { bare = true }
        return RichItem(blocks: itemName == "li" ? blocks(itemChildren) : blocks([child]), bare: bare)
      }
      let start = attrs["start"].flatMap { Int($0) } ?? 1
      return [.list(ordered: name == "ol", start: start, items: items)]
    case "blockquote":
      return [.quote(blocks(children))]
    case "pre":
      return [.code(code: Display.codeOf(children), language: attrs["data-language"], runs: runs(children, style: RichRun.Style(code: true)))]
    case "hr":
      return [.rule]
    case "table", "thead", "tbody", "tfoot":
      var rows: [[RichCell]] = []
      collectRows(children, into: &rows)
      return rows.isEmpty ? [] : [.table(rows: rows)]
    case "tr":
      var rows: [[RichCell]] = []
      collectRows([.element(name: "tr", attrs: attrs, children: children)], into: &rows)
      return [.table(rows: rows)]
    default:
      // p, div and the rest: a paragraph, or the blocks they hold.
      if children.contains(where: containsBlock) { return blocks(children) }
      let runs = trimmed(runs(children))
      return isBlank(runs) ? [] : [.paragraph(runs)]
    }
  }

  static func collectRows(_ nodes: [DisplayNode], into rows: inout [[RichCell]]) {
    for node in nodes {
      guard case let .element(name, _, children) = node else { continue }
      if name == "tr" {
        rows.append(children.compactMap { cell in
          guard case let .element(cellName, _, cellChildren) = cell, cellName == "td" || cellName == "th" else { return nil }
          return RichCell(runs: trimmed(runs(cellChildren, style: RichRun.Style(bold: cellName == "th"))), header: cellName == "th")
        })
      } else {
        collectRows(children, into: &rows)
      }
    }
  }

  /** The runs of inline nodes, a `<br>` as a newline, blocks inside read as lines. */
  static func runs(_ nodes: [DisplayNode], style: RichRun.Style = RichRun.Style()) -> [RichRun] {
    var out: [RichRun] = []
    for node in nodes {
      switch node {
      case let .text(text): out.append(RichRun(content: .text(text), style: style))
      case let .mention(id): out.append(RichRun(content: .mention(id), style: style))
      case .preview: break
      case let .element(name, attrs, children):
        var inner = style
        switch name {
        case "br":
          out.append(RichRun(content: .text("\n"), style: style))
          continue
        case "strong", "b", "th": inner.bold = true
        case "em", "i", "cite", "dfn", "var": inner.italic = true
        case "u", "ins": inner.underline = true
        case "s", "del": inner.strike = true
        case "code", "kbd", "samp", "tt": inner.code = true
        case "mark": inner.mark = true
        case "a": inner.link = attrs["href"]
        default: break
        }
        if blockNames.contains(name), !out.isEmpty, !endsWithNewline(out) { out.append(RichRun(content: .text("\n"), style: style)) }
        out.append(contentsOf: runs(children, style: inner))
      }
    }
    return out
  }

  static func endsWithNewline(_ runs: [RichRun]) -> Bool {
    guard case let .text(text)? = runs.last?.content else { return false }
    return text.hasSuffix("\n")
  }

  static func isBlank(_ runs: [RichRun]) -> Bool {
    runs.allSatisfy { run in
      if case let .text(text) = run.content { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      return false
    }
  }

  /** Runs without the newlines and spaces a block's markup starts and ends with. */
  static func trimmed(_ runs: [RichRun]) -> [RichRun] {
    var runs = runs
    while case let .text(text)? = runs.first?.content {
      let kept = String(text.drop(while: { $0 == "\n" || $0 == "\r" }))
      if kept.isEmpty { runs.removeFirst() } else {
        runs[0].content = .text(kept)
        break
      }
    }
    while case let .text(text)? = runs.last?.content {
      var kept = text
      while kept.last == "\n" || kept.last == "\r" { kept.removeLast() }
      if kept.isEmpty { runs.removeLast() } else {
        runs[runs.count - 1].content = .text(kept)
        break
      }
    }
    return runs
  }

  /** The plain text of runs, mentions as `@name`, as Copy and IRC's lines read them. */
  static func text(_ runs: [RichRun], name: (UserID) -> String) -> String {
    runs.map { run in
      switch run.content {
      case let .text(text): text
      case let .mention(id): "@" + name(id)
      }
    }.joined()
  }
}

/**
 * Where a link in a message goes: a relative one is on the instance; `opener` opens the instance's own
 * rooms, messages and threads in place, and anything else in the browser.
 */
enum MessageLinks {
  static func url(_ href: String, api: EmberAPI) -> URL? {
    guard let url = URL(string: href) else { return nil }
    return url.scheme == nil ? api.url(href) : url
  }

  /** The `openURL` a message list puts its messages under, which opens the instance's pages in place (web `MessageLink`). */
  @MainActor
  static func opener(_ session: InstanceSession) -> OpenURLAction {
    OpenURLAction { url in session.open(link: url) ? .handled : .systemAction }
  }
}
