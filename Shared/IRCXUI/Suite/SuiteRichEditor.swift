import AppCoreUI
import EmberKit
import SwiftUI
#if os(macOS)
import AppKit
typealias EditorFont = NSFont
typealias EditorColor = NSColor
#else
import UIKit
typealias EditorFont = UIFont
typealias EditorColor = UIColor
#endif

// The Suite composer's rich editor (web Lexxy, as Ember configures it): a platform text view whose
// text carries each line's block and each run's marks, link or mention as attributes, read back as a
// `ComposerDocument`. List and quote markers are text the editor writes and keeps, never what's sent.

extension NSAttributedString.Key {
  static let emberBlock = NSAttributedString.Key("ai.dxnd.ircX.block")
  static let emberMarks = NSAttributedString.Key("ai.dxnd.ircX.marks")
  static let emberMention = NSAttributedString.Key("ai.dxnd.ircX.mention")
  static let emberMarker = NSAttributedString.Key("ai.dxnd.ircX.marker")
}

/** A line's block, as an attribute value. */
final class BlockBox: NSObject {
  let block: ComposerBlock
  init(_ block: ComposerBlock) { self.block = block }
  override func isEqual(_ object: Any?) -> Bool { (object as? BlockBox)?.block == block }
  override var hash: Int { block.hashValue }
}

/** A mention, as an attribute value: whom, and the text it showed, so text typed into it unmakes it. */
final class MentionToken: NSObject {
  let id: UserID
  let text: String
  init(id: UserID, text: String) {
    self.id = id
    self.text = text
  }
  override func isEqual(_ object: Any?) -> Bool { (object as? MentionToken).map { $0.id == id && $0.text == text } == true }
  override var hash: Int { id.hashValue ^ text.hashValue }
}

/** How the editor draws what it holds. */
enum EditorStyle {
  static var bodySize: CGFloat {
    #if os(macOS)
    NSFont.preferredFont(forTextStyle: .body).pointSize
    #else
    UIFont.preferredFont(forTextStyle: .body).pointSize
    #endif
  }

  static func font(marks: Set<ComposerMark>, block: ComposerBlock) -> EditorFont {
    var size = bodySize
    var bold = marks.contains(.bold)
    if case let .heading(level) = block {
      size *= level == 1 ? 1.6 : level == 2 ? 1.35 : 1.15
      bold = true
    }
    if case .cite = block { size *= 0.9 }
    if block.isCode || marks.contains(.code) {
      return EditorFont.monospacedSystemFont(ofSize: size * 0.95, weight: bold ? .semibold : .regular)
    }
    let base = EditorFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    guard marks.contains(.italic) else { return base }
    #if os(macOS)
    return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? base
    #else
    guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) else { return base }
    return UIFont(descriptor: descriptor, size: size)
    #endif
  }

  static var text: EditorColor {
    #if os(macOS)
    .labelColor
    #else
    .label
    #endif
  }

  static var secondary: EditorColor {
    #if os(macOS)
    .secondaryLabelColor
    #else
    .secondaryLabel
    #endif
  }

  static var accent: EditorColor { EditorColor(SemanticColor.accent) }
  static var codeFill: EditorColor { EditorColor(SemanticColor.secondaryFill) }

  static func attributes(marks: Set<ComposerMark>, block: ComposerBlock, link: String? = nil, mention: MentionToken? = nil) -> [NSAttributedString.Key: Any] {
    let marks = block.isCode ? [] : marks
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font(marks: marks, block: block),
      .foregroundColor: mention != nil || link != nil ? accent : quiet(block) ? secondary : text,
      .emberBlock: BlockBox(block),
      .emberMarks: marks.map(\.rawValue).sorted().joined(separator: ","),
    ]
    if marks.contains(.underline) || link != nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
    if marks.contains(.strike) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    if marks.contains(.code) || block.isCode { attributes[.backgroundColor] = codeFill }
    if let link { attributes[.link] = link }
    if let mention { attributes[.emberMention] = mention }
    return attributes
  }

  static func marks(_ attributes: [NSAttributedString.Key: Any]) -> Set<ComposerMark> {
    guard let raw = attributes[.emberMarks] as? String else { return [] }
    return Set(raw.split(separator: ",").compactMap { ComposerMark(rawValue: String($0)) })
  }

  static func link(_ attributes: [NSAttributedString.Key: Any]) -> String? {
    if let link = attributes[.link] as? String { return link }
    return (attributes[.link] as? URL)?.absoluteString
  }

  static func quiet(_ block: ComposerBlock) -> Bool {
    switch block {
    case .quote, .cite, .rule, .attachment: true
    default: false
    }
  }

  /** What starts a line of `block`, the `number`th of its list. */
  static func marker(_ block: ComposerBlock, number: Int) -> String? {
    switch block {
    case .bullet: "\u{2022} "
    case .ordered: "\(number). "
    case .quote: "\u{258E} "
    case .cite: "\u{2014} "
    case .rule: "\u{2015}\u{2015}\u{2015}"
    case .attachment: "\u{2197} "
    default: nil
    }
  }

  static func markerAttributes(_ block: ComposerBlock) -> [NSAttributedString.Key: Any] {
    [.font: font(marks: [], block: .paragraph), .foregroundColor: secondary, .emberBlock: BlockBox(block), .emberMarker: true, .emberMarks: ""]
  }
}

/** A document as the editor's text, and back. */
enum EditorText {
  static func attributed(_ document: ComposerDocument) -> NSAttributedString {
    let out = NSMutableAttributedString()
    var number = 0
    for (index, line) in document.lines.enumerated() {
      number = line.block == .ordered ? number + 1 : 0
      if let marker = EditorStyle.marker(line.block, number: number) {
        out.append(NSAttributedString(string: marker, attributes: EditorStyle.markerAttributes(line.block)))
      }
      if case let .attachment(_, label) = line.block {
        out.append(NSAttributedString(string: label, attributes: EditorStyle.attributes(marks: [], block: line.block)))
      }
      for run in line.runs {
        let token = run.mention.map { MentionToken(id: $0, text: run.text) }
        out.append(NSAttributedString(string: run.text, attributes: EditorStyle.attributes(marks: run.marks, block: line.block, link: run.link, mention: token)))
      }
      if index < document.lines.count - 1 {
        out.append(NSAttributedString(string: "\n", attributes: EditorStyle.attributes(marks: [], block: line.block)))
      }
    }
    return out
  }

  static func block(at index: Int, in text: NSAttributedString) -> ComposerBlock {
    guard index < text.length, let box = text.attribute(.emberBlock, at: index, effectiveRange: nil) as? BlockBox else { return .paragraph }
    return box.block
  }

  static func document(_ text: NSAttributedString) -> ComposerDocument {
    let string = text.string as NSString
    guard string.length > 0 else { return ComposerDocument() }
    var lines: [ComposerLine] = []
    var location = 0
    while location < string.length {
      let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
      var content = paragraph
      if content.length > 0, string.character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
      let block = self.block(at: paragraph.location, in: text)
      var line = ComposerLine(block)
      if case .attachment = block {
        lines.append(line)
      } else {
        text.enumerateAttributes(in: content) { attributes, range, _ in
          guard attributes[.emberMarker] == nil else { return }
          let run = string.substring(with: range)
          let token = attributes[.emberMention] as? MentionToken
          line.runs.append(ComposerRun(run, marks: EditorStyle.marks(attributes), link: EditorStyle.link(attributes), mention: token?.text == run ? token?.id : nil))
        }
        lines.append(line)
      }
      location = NSMaxRange(paragraph)
    }
    if string.character(at: string.length - 1) == 10 {
      lines.append(ComposerLine(block(at: string.length - 1, in: text)))
    }
    return ComposerDocument(lines: lines)
  }
}

/** What the editor tells its composer. */
@MainActor
struct EditorActions {
  var changed: (ComposerDocument) -> Void = { _ in }
  /** Return (Enter) on a Mac, ⌘Return anywhere: send, or save an edit. */
  var submit: () -> Void = {}
  /** ↑ with nothing written: edit your last message; true if it did. */
  var upArrow: () -> Bool = { false }
  /** Esc: close the editor; true if it did. */
  var escape: () -> Bool = { false }
  var files: ([PickedFile]) -> Void = { _ in }
  var pastedLink: (String) -> Void = { _ in }
  var mentionQuery: (String?) -> Void = { _ in }
  /** ↑, ↓, Return, Tab, Esc while the @ prompt's open; true if the prompt took it. */
  var mentionKey: (MentionKey) -> Bool = { _ in false }
  var linkDialog: () -> Void = {}
  var pickFiles: () -> Void = {}
  var snippet: () -> Void = {}
  /** Whether Return sends (the room's composer on a Mac) or only ⌘Return does (an edit, or a touch keyboard). */
  var returnSends = true
}

enum MentionKey { case up, down, pick, close }

/**
 * What the formatting row and the composer's buttons drive: the format at the caret, to light the
 * buttons, and the commands, applied to the text view on screen.
 */
@MainActor
@Observable
final class RichEditorController {
  var marks: Set<ComposerMark> = []
  var block: ComposerBlock = .paragraph
  var inLink = false
  var isEmpty = true
  var focused = false
  @ObservationIgnored weak var engine: RichTextEngine?

  init() {}

  func perform(_ command: FormattingCommand) { engine?.perform(command) }
  func setBlock(_ block: ComposerBlock) { engine?.setBlock(block, toggle: false) }
  func insert(_ text: String) { engine?.insertPlain(text) }
  func startMention() { engine?.startMention() }
  func pickMention(_ item: MentionPromptItem) { engine?.pickMention(item) }
  func linkSelection() -> (text: String, url: String?) { engine?.linkSelection() ?? (String(), nil) }
  func setLink(text: String, url: String?) { engine?.setLink(text: text, url: url) }
  func focus() { engine?.focus() }
}

/** The text view's model: reads and writes its text, keeps its markers, and runs the formatting commands. */
@MainActor
final class RichTextEngine: NSObject {
  let controller: RichEditorController
  var actions: EditorActions
  var heightChanged: (CGFloat) -> Void = { _ in }
  weak var view: EditorTextView?
  private var normalizing = false
  private var loadedRevision = -1

  init(controller: RichEditorController, actions: EditorActions) {
    self.controller = controller
    self.actions = actions
    super.init()
    controller.engine = self
  }

  private var storage: NSTextStorage? { view?.textStorage }

  private var selection: NSRange {
    get {
      #if os(macOS)
      view?.selectedRange() ?? NSRange(location: 0, length: 0)
      #else
      view?.selectedRange ?? NSRange(location: 0, length: 0)
      #endif
    }
    set {
      #if os(macOS)
      view?.setSelectedRange(newValue)
      #else
      view?.selectedRange = newValue
      #endif
    }
  }

  private var typing: [NSAttributedString.Key: Any] {
    get { view?.typingAttributes ?? [:] }
    set { view?.typingAttributes = newValue }
  }

  static var plainTyping: [NSAttributedString.Key: Any] { EditorStyle.attributes(marks: [], block: .paragraph) }

  func focus() {
    #if os(macOS)
    view?.window?.makeFirstResponder(view)
    #else
    view?.becomeFirstResponder()
    #endif
  }

  /** Shows `document` in place of what's written, the caret at its end, once per revision. */
  func load(_ document: ComposerDocument, revision: Int) {
    guard revision != loadedRevision else { return }
    loadedRevision = revision
    load(document)
  }

  func load(_ document: ComposerDocument) {
    guard let storage else { return }
    normalizing = true
    storage.setAttributedString(EditorText.attributed(document))
    normalizing = false
    selection = NSRange(location: storage.length, length: 0)
    typing = storage.length == 0 ? Self.plainTyping : EditorStyle.attributes(marks: [], block: currentBlock())
    refresh()
    measure()
  }

  // MARK: Changes

  func textChanged() {
    guard !normalizing else { return }
    normalize()
    refresh()
    actions.changed(document)
    lookForMention()
    measure()
  }

  var document: ComposerDocument {
    guard let storage else { return ComposerDocument() }
    return EditorText.document(storage)
  }

  func measure() {
    guard let view else { return }
    #if os(macOS)
    guard let layout = view.textLayoutManager else { return }
    layout.ensureLayout(for: layout.documentRange)
    heightChanged(layout.usageBoundsForTextContainer.height + view.textContainerInset.height * 2)
    #else
    heightChanged(view.sizeThatFits(CGSize(width: max(view.bounds.width, 100), height: .greatestFiniteMagnitude)).height)
    #endif
  }

  /** Lights the formatting row for the caret, keeps the caret out of markers, and stops a mention or link carrying on as you type. */
  func selectionChanged() {
    guard let storage, !normalizing else { return }
    var range = selection
    let string = storage.string as NSString
    if range.length == 0, range.location < string.length {
      let paragraph = string.paragraphRange(for: NSRange(location: range.location, length: 0))
      let end = markerEnd(of: paragraph)
      if range.location < end {
        range = NSRange(location: end, length: 0)
        selection = range
      }
    }
    if range.length == 0 {
      typing = EditorStyle.attributes(marks: EditorStyle.marks(typing), block: currentBlock())
    }
    refresh()
    lookForMention()
  }

  private func refresh() {
    guard let storage else { return }
    let range = selection
    controller.isEmpty = storage.length == 0
    controller.block = currentBlock()
    if range.length > 0, range.location < storage.length {
      let attributes = storage.attributes(at: range.location, effectiveRange: nil)
      controller.marks = EditorStyle.marks(attributes)
      controller.inLink = EditorStyle.link(attributes) != nil
    } else {
      controller.marks = EditorStyle.marks(typing)
      controller.inLink = range.location > 0 && range.location <= storage.length && storage.attribute(.link, at: range.location - 1, effectiveRange: nil) != nil
    }
  }

  private func currentParagraph() -> NSRange {
    guard let storage else { return NSRange(location: 0, length: 0) }
    let string = storage.string as NSString
    return string.paragraphRange(for: NSRange(location: min(selection.location, string.length), length: 0))
  }

  private func currentBlock() -> ComposerBlock {
    guard let storage else { return .paragraph }
    let paragraph = currentParagraph()
    if paragraph.length == 0 || paragraph.location >= storage.length {
      return (typing[.emberBlock] as? BlockBox)?.block ?? .paragraph
    }
    return EditorText.block(at: paragraph.location, in: storage)
  }

  private func markerEnd(of paragraph: NSRange) -> Int {
    guard let storage, paragraph.location < storage.length else { return paragraph.location }
    var end = paragraph.location
    while end < NSMaxRange(paragraph), storage.attribute(.emberMarker, at: end, effectiveRange: nil) != nil { end += 1 }
    return end
  }

  /** The text of the caret's line, from after its marker to the caret. */
  private func lineBeforeCaret() -> (text: String, start: Int) {
    guard let storage else { return (String(), 0) }
    let paragraph = currentParagraph()
    let start = markerEnd(of: paragraph)
    let end = max(start, selection.location)
    return ((storage.string as NSString).substring(with: NSRange(location: start, length: end - start)), start)
  }

  /** The paragraphs of the text, each with its line break. */
  private func paragraphs() -> [NSRange] {
    guard let storage else { return [] }
    let string = storage.string as NSString
    var ranges: [NSRange] = []
    var location = 0
    while location < string.length {
      let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
      ranges.append(paragraph)
      location = NSMaxRange(paragraph)
    }
    return ranges
  }

  /** Writes each line's marker afresh (numbering lists again), keeping the caret where it was in its line's text. */
  private func normalize() {
    guard let storage else { return }
    normalizing = true
    defer { normalizing = false }
    let before = selection
    let lengthBefore = storage.length
    let lines = paragraphs()
    var caretLine = lines.count
    var caretOffset = 0
    for (index, paragraph) in lines.enumerated() where before.location >= paragraph.location && (before.location < NSMaxRange(paragraph) || index == lines.count - 1 && !(storage.string as NSString).hasSuffix("\n")) {
      caretLine = index
      caretOffset = max(0, before.location - markerEnd(of: paragraph))
      break
    }
    storage.beginEditing()
    var location = 0
    var index = 0
    var number = 0
    var caretAt = before.location
    while location < storage.length {
      let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
      var end = NSMaxRange(paragraph)
      var cursor = paragraph.location
      while cursor < end {
        var effective = NSRange(location: 0, length: 0)
        if storage.attribute(.emberMarker, at: cursor, effectiveRange: &effective) != nil {
          let cut = NSIntersectionRange(effective, NSRange(location: cursor, length: end - cursor))
          storage.deleteCharacters(in: cut)
          end -= cut.length
        } else {
          cursor = NSMaxRange(effective)
        }
      }
      let block = end > paragraph.location ? EditorText.block(at: paragraph.location, in: storage) : .paragraph
      number = block == .ordered ? number + 1 : 0
      var markerLength = 0
      if end > paragraph.location, let marker = EditorStyle.marker(block, number: number) {
        storage.insert(NSAttributedString(string: marker, attributes: EditorStyle.markerAttributes(block)), at: paragraph.location)
        markerLength = (marker as NSString).length
        end += markerLength
      }
      if index == caretLine { caretAt = min(paragraph.location + markerLength + caretOffset, end) }
      location = end
      index += 1
    }
    storage.endEditing()
    if caretLine >= index { caretAt = storage.length }
    if storage.length == lengthBefore, NSMaxRange(before) <= storage.length {
      selection = before
    } else {
      selection = NSRange(location: min(caretAt, storage.length), length: 0)
    }
  }

  // MARK: Edits from keys

  /**
   * Whether a change the view's about to make goes as it is: a mention goes whole, taking back a list or
   * quote line's marker makes it a paragraph, and the Markdown-style shortcuts turn into blocks.
   */
  func shouldChange(_ range: NSRange, _ text: String) -> Bool {
    guard let storage, !normalizing else { return true }
    if text.isEmpty, range.length > 0, range.location < storage.length {
      if storage.attribute(.emberMarker, at: range.location, effectiveRange: nil) != nil {
        setBlock(.paragraph, toggle: false)
        return false
      }
      var effective = NSRange(location: 0, length: 0)
      if storage.attribute(.emberMention, at: range.location, effectiveRange: &effective) != nil, effective != range {
        let whole = NSUnionRange(effective, range)
        storage.deleteCharacters(in: whole)
        selection = NSRange(location: whole.location, length: 0)
        textChanged()
        return false
      }
    }
    if text == "\n" {
      lineBreak()
      return false
    }
    if text == " ", range.length == 0, currentBlock() == .paragraph {
      let (before, start) = lineBeforeCaret()
      let shortcuts: [String: ComposerBlock] = [
        "-": .bullet, "*": .bullet, "+": .bullet, "1.": .ordered, ">": .quote, "#": .heading(1), "##": .heading(2), "###": .heading(3), "```": .code(language: nil),
      ]
      if let block = shortcuts[before] {
        normalizing = true
        storage.deleteCharacters(in: NSRange(location: start, length: (before as NSString).length))
        normalizing = false
        selection = NSRange(location: start, length: 0)
        setBlock(block, toggle: false)
        return false
      }
    }
    return true
  }

  private static let inlinePatterns: [(NSRegularExpression, ComposerMark)] = {
    let sources: [(String, ComposerMark)] = [
      (#"\*\*([^*]+)\*\*$"#, .bold), (#"__([^_]+)__$"#, .bold), (#"~~([^~]+)~~$"#, .strike), (#"`([^`]+)`$"#, .code),
      (#"(?<![*\w])\*([^*\s][^*]*)\*$"#, .italic), (#"(?<![_\w])_([^_\s][^_]*)_$"#, .italic),
    ]
    return sources.compactMap { source, mark in
      do {
        return (try NSRegularExpression(pattern: source), mark)
      } catch {
        logger.error("A formatting shortcut's pattern didn't compile: \(error.localizedDescription, privacy: .public)")
        return nil
      }
    }
  }()

  /** After a mark's closing character, `**bold**`, `_italic_`, `~~strike~~` and `` `code` `` become what they say. */
  func inlineShortcut() {
    guard let storage, !currentBlock().isCode else { return }
    let (before, start) = lineBeforeCaret()
    for (regex, mark) in Self.inlinePatterns {
      guard let match = regex.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) else { continue }
      let inner = (before as NSString).substring(with: match.range(at: 1))
      let range = NSRange(location: start + match.range.location, length: match.range.length)
      var marks = EditorStyle.marks(storage.attributes(at: range.location, effectiveRange: nil))
      marks.insert(mark)
      normalizing = true
      storage.replaceCharacters(in: range, with: NSAttributedString(string: inner, attributes: EditorStyle.attributes(marks: marks, block: currentBlock())))
      normalizing = false
      selection = NSRange(location: range.location + (inner as NSString).length, length: 0)
      marks.remove(mark)
      typing = EditorStyle.attributes(marks: marks, block: currentBlock())
      textChanged()
      return
    }
  }

  /**
   * Shift+Return (and Return where it doesn't send): a new line, a list's next item, or, on an empty item,
   * the end of the list; a heading's next line is a paragraph (web `startNewBlock`).
   */
  func lineBreak() {
    guard let storage else { return }
    let block = currentBlock()
    let paragraph = currentParagraph()
    let start = markerEnd(of: paragraph)
    let lineText = (storage.string as NSString).substring(with: NSRange(location: start, length: max(0, NSMaxRange(paragraph) - start))).trimmingCharacters(in: .newlines)
    if [ComposerBlock.bullet, .ordered, .quote].contains(block), lineText.isEmpty {
      setBlock(.paragraph, toggle: false)
      return
    }
    let next: ComposerBlock
    switch block {
    case .heading, .cite, .rule, .attachment: next = .paragraph
    default: next = block
    }
    let at = selection
    normalizing = true
    storage.replaceCharacters(in: at, with: NSAttributedString(string: "\n", attributes: EditorStyle.attributes(marks: [], block: block)))
    normalizing = false
    selection = NSRange(location: at.location + 1, length: 0)
    typing = EditorStyle.attributes(marks: next.isCode ? [] : EditorStyle.marks(typing), block: next)
    if next != block, at.location + 1 < storage.length {
      restyle(currentParagraph(), as: next)
    }
    textChanged()
  }

  // MARK: Formatting

  func perform(_ command: FormattingCommand) {
    if command.notInCodeBlocks, currentBlock().isCode { return }
    switch command {
    case .bold: toggle(.bold)
    case .italic: toggle(.italic)
    case .underline: toggle(.underline)
    case .strikethrough: toggle(.strike)
    case .code: toggle(.code)
    case .link: actions.linkDialog()
    case .orderedList: setBlock(.ordered, toggle: true)
    case .bulletedList: setBlock(.bullet, toggle: true)
    case .blockquote: setBlock(.quote, toggle: true)
    case .codeBlock: setBlock(.code(language: nil), toggle: true)
    }
  }

  /** Toggles a mark on what's selected, or on what's typed next. */
  func toggle(_ mark: ComposerMark) {
    guard let storage else { return }
    let range = selection
    if range.length == 0 {
      var marks = EditorStyle.marks(typing)
      if marks.contains(mark) { marks.remove(mark) } else { marks.insert(mark) }
      typing = EditorStyle.attributes(marks: marks, block: currentBlock())
      refresh()
      return
    }
    var all = true
    storage.enumerateAttributes(in: range) { attributes, _, _ in
      if attributes[.emberMarker] == nil, !EditorStyle.marks(attributes).contains(mark) { all = false }
    }
    storage.beginEditing()
    storage.enumerateAttributes(in: range) { attributes, sub, _ in
      guard attributes[.emberMarker] == nil else { return }
      var marks = EditorStyle.marks(attributes)
      if all { marks.remove(mark) } else { marks.insert(mark) }
      let block = (attributes[.emberBlock] as? BlockBox)?.block ?? .paragraph
      storage.setAttributes(EditorStyle.attributes(marks: marks, block: block, link: EditorStyle.link(attributes), mention: attributes[.emberMention] as? MentionToken), range: sub)
    }
    storage.endEditing()
    textChanged()
  }

  /** Sets the block of the selected lines, or takes it off (to a paragraph) where they have it and `toggle`. */
  func setBlock(_ block: ComposerBlock, toggle: Bool) {
    guard let storage else { return }
    let string = storage.string as NSString
    let target = toggle && currentBlock() == block ? ComposerBlock.paragraph : block
    let start = min(selection.location, string.length)
    let lines = string.paragraphRange(for: NSRange(location: start, length: min(selection.length, string.length - start)))
    typing = EditorStyle.attributes(marks: target.isCode ? [] : EditorStyle.marks(typing), block: target)
    guard lines.length > 0, lines.location < storage.length else {
      refresh()
      return
    }
    storage.beginEditing()
    var location = lines.location
    while location < NSMaxRange(lines) {
      let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
      restyle(paragraph, as: target)
      location = NSMaxRange(paragraph)
    }
    storage.endEditing()
    textChanged()
  }

  private func restyle(_ paragraph: NSRange, as block: ComposerBlock) {
    guard let storage else { return }
    storage.enumerateAttributes(in: paragraph) { attributes, sub, _ in
      if attributes[.emberMarker] != nil {
        storage.setAttributes(EditorStyle.markerAttributes(block), range: sub)
      } else {
        storage.setAttributes(
          EditorStyle.attributes(marks: EditorStyle.marks(attributes), block: block, link: EditorStyle.link(attributes), mention: attributes[.emberMention] as? MentionToken),
          range: sub)
      }
    }
  }

  // MARK: Links, mentions, text

  /** The selected text and the link it's in, for the Link dialog. */
  func linkSelection() -> (text: String, url: String?) {
    guard let storage else { return (String(), nil) }
    var range = selection
    var url: String?
    let at = range.length > 0 ? range.location : max(0, range.location - 1)
    var effective = NSRange(location: 0, length: 0)
    if at < storage.length, let link = EditorStyle.link(storage.attributes(at: at, effectiveRange: &effective)) {
      url = link
      range = effective
      selection = range
    }
    return ((storage.string as NSString).substring(with: range), url)
  }

  /** Writes the link from the Link dialog over the selection; nil `url` takes the link off. */
  func setLink(text: String, url: String?) {
    guard let storage else { return }
    let range = selection
    let marks = range.location < storage.length ? EditorStyle.marks(storage.attributes(at: range.location, effectiveRange: nil)) : EditorStyle.marks(typing)
    var written = text
    if written.isEmpty, let url { written = url }
    normalizing = true
    storage.replaceCharacters(in: range, with: NSAttributedString(string: written, attributes: EditorStyle.attributes(marks: marks, block: currentBlock(), link: url)))
    normalizing = false
    selection = NSRange(location: range.location + (written as NSString).length, length: 0)
    typing = EditorStyle.attributes(marks: marks, block: currentBlock())
    textChanged()
    focus()
  }

  /** Writes plain text at the caret, as an emoji picked from the panel or a paste. */
  func insertPlain(_ text: String) {
    guard let storage else { return }
    let range = selection
    var attributes = typing
    attributes[.emberMention] = nil
    attributes[.emberMarker] = nil
    normalizing = true
    storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
    normalizing = false
    selection = NSRange(location: range.location + (text as NSString).length, length: 0)
    textChanged()
    focus()
  }

  /** Mention someone: types `@`, after a space if it follows a word (web `startMention`). */
  func startMention() {
    let (before, _) = lineBeforeCaret()
    insertPlain(before.isEmpty || before.last?.isWhitespace == true ? "@" : " @")
  }

  /** Puts the person picked in the @ prompt in place of what was typed after `@`. */
  func pickMention(_ item: MentionPromptItem) {
    guard let storage, let query = mentionRange() else { return }
    let text = "@" + item.name
    let marks = EditorStyle.marks(typing)
    let mention = NSMutableAttributedString(string: text, attributes: EditorStyle.attributes(marks: marks, block: currentBlock(), mention: MentionToken(id: item.id, text: text)))
    mention.append(NSAttributedString(string: " ", attributes: EditorStyle.attributes(marks: marks, block: currentBlock())))
    normalizing = true
    storage.replaceCharacters(in: query, with: mention)
    normalizing = false
    selection = NSRange(location: query.location + mention.length, length: 0)
    typing = EditorStyle.attributes(marks: marks, block: currentBlock())
    actions.mentionQuery(nil)
    textChanged()
    focus()
  }

  /** The `@` and what's typed after it before the caret, while it's a mention being typed. */
  private func mentionRange() -> NSRange? {
    guard selection.length == 0 else { return nil }
    let (before, start) = lineBeforeCaret()
    guard let match = before.firstMatch(of: #/(?:^|\s)(@[^\s@]*)$/#) else { return nil }
    let length = (String(match.output.1) as NSString).length
    let location = start + (before as NSString).length - length
    if let storage, location < storage.length, storage.attribute(.emberMention, at: location, effectiveRange: nil) != nil { return nil }
    return NSRange(location: location, length: length)
  }

  private func lookForMention() {
    guard let range = mentionRange(), let storage else { return actions.mentionQuery(nil) }
    actions.mentionQuery(String((storage.string as NSString).substring(with: range).dropFirst()))
  }

  // MARK: Keys

  /** Return: picks from the @ prompt, sends where Return sends, else a new line. */
  func returnKey(shift: Bool, command: Bool) -> Bool {
    if !shift, actions.mentionKey(.pick) { return true }
    if command || (!shift && actions.returnSends) {
      actions.submit()
      return true
    }
    lineBreak()
    return true
  }

  func upKey() -> Bool {
    if actions.mentionKey(.up) { return true }
    if controller.isEmpty { return actions.upArrow() }
    return false
  }

  func downKey() -> Bool { actions.mentionKey(.down) }

  func escapeKey() -> Bool {
    if actions.mentionKey(.close) { return true }
    return actions.escape()
  }

  /** The formatting shortcuts and the composer's own keys (web `FORMATTING_KEYS`, `keyboard.ts`). */
  func shortcut(_ key: String, command: Bool, shift: Bool, option: Bool) -> Bool {
    guard command else { return false }
    switch (key.lowercased(), shift, option) {
    case ("b", false, false): perform(.bold)
    case ("i", false, false): perform(.italic)
    case ("u", false, false): perform(.underline)
    case ("x", true, false): perform(.strikethrough)
    case ("u", true, false), ("k", false, false): perform(.link)
    case ("7", true, false), ("&", true, false): perform(.orderedList)
    case ("8", true, false), ("*", true, false): perform(.bulletedList)
    case ("9", true, false), ("(", true, false): perform(.blockquote)
    case ("c", true, false): perform(.code)
    case ("c", true, true), ("ç", true, true): perform(.codeBlock)
    case ("o", false, false): actions.pickFiles()
    case ("\r", true, false): actions.snippet()
    case ("\r", false, false): actions.submit()
    default: return false
    }
    return true
  }
}

// MARK: - The text views

#if os(macOS)
final class EditorTextView: NSTextView {
  weak var engine: RichTextEngine?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window?.firstResponder === self, let engine, let key = event.charactersIgnoringModifiers else { return super.performKeyEquivalent(with: event) }
    let flags = event.modifierFlags
    if engine.shortcut(key, command: flags.contains(.command), shift: flags.contains(.shift), option: flags.contains(.option)) { return true }
    return super.performKeyEquivalent(with: event)
  }

  override func paste(_ sender: Any?) {
    let pasteboard = NSPasteboard.general
    if let files = Pasteboard.pastedFiles() {
      engine?.actions.files(files)
      return
    }
    guard let text = pasteboard.string(forType: .string) else { return super.paste(sender) }
    engine?.insertPlain(text)
    if let link = Autolink.linkedUrls(text).first(where: { $0.lowercased().hasPrefix("http") }) { engine?.actions.pastedLink(link) }
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
      engine?.actions.files(urls.compactMap(PickedFile.at))
      return true
    }
    return super.performDragOperation(sender)
  }

  override func becomeFirstResponder() -> Bool {
    engine?.controller.focused = true
    return super.becomeFirstResponder()
  }

  override func resignFirstResponder() -> Bool {
    engine?.controller.focused = false
    return super.resignFirstResponder()
  }
}

extension RichTextEngine: NSTextViewDelegate {
  func textDidChange(_ notification: Notification) {
    textChanged()
    if let last = view?.string.last, "*_~`".contains(last) { inlineShortcut() }
  }

  func textViewDidChangeSelection(_ notification: Notification) { selectionChanged() }

  func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
    guard let text else { return true }
    return shouldChange(range, text)
  }

  func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    let flags = NSApp.currentEvent?.modifierFlags ?? []
    switch selector {
    case #selector(NSResponder.insertNewline(_:)):
      return returnKey(shift: flags.contains(.shift), command: flags.contains(.command))
    case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
      lineBreak()
      return true
    case #selector(NSResponder.moveUp(_:)): return upKey()
    case #selector(NSResponder.moveDown(_:)): return downKey()
    case #selector(NSResponder.cancelOperation(_:)): return escapeKey()
    case #selector(NSResponder.insertTab(_:)): return actions.mentionKey(.pick)
    default: return false
    }
  }
}

struct RichTextView: NSViewRepresentable {
  let engine: RichTextEngine
  let actions: EditorActions
  let editable: Bool

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    let view = EditorTextView(usingTextLayoutManager: true)
    view.engine = engine
    view.delegate = engine
    view.isRichText = true
    view.allowsUndo = true
    view.drawsBackground = false
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticLinkDetectionEnabled = false
    view.isContinuousSpellCheckingEnabled = true
    view.textContainerInset = NSSize(width: 0, height: Spacing.xxs)
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.textContainer?.widthTracksTextView = true
    view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.typingAttributes = RichTextEngine.plainTyping
    view.registerForDraggedTypes([.fileURL])
    view.isEditable = editable
    scroll.documentView = view
    engine.view = view
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    engine.actions = actions
    (scroll.documentView as? NSTextView)?.isEditable = editable
    DispatchQueue.main.async { engine.measure() }
  }
}
#else
final class EditorTextView: UITextView {
  weak var engine: RichTextEngine?

  override var keyCommands: [UIKeyCommand]? {
    var commands = [
      UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(submit)),
      UIKeyCommand(input: "\r", modifierFlags: [.command, .shift], action: #selector(snippet)),
      UIKeyCommand(input: "o", modifierFlags: .command, action: #selector(pickFiles)),
      UIKeyCommand(input: "k", modifierFlags: .command, action: #selector(link)),
    ]
    for command in FormattingCommand.allCases {
      guard let key = command.keys.last?.lowercased() else { continue }
      var flags: UIKeyModifierFlags = .command
      if command.keys.contains("⇧") { flags.insert(.shift) }
      if command.keys.contains("⌥") { flags.insert(.alternate) }
      let keyCommand = UIKeyCommand(title: command.name, action: #selector(format(_:)), input: key, modifierFlags: flags, propertyList: command.rawValue)
      keyCommand.wantsPriorityOverSystemBehavior = true
      commands.append(keyCommand)
    }
    return commands
  }

  @objc private func submit() { engine?.actions.submit() }
  @objc private func snippet() { engine?.actions.snippet() }
  @objc private func pickFiles() { engine?.actions.pickFiles() }
  @objc private func link() { engine?.perform(.link) }
  @objc private func format(_ sender: UIKeyCommand) {
    guard let name = sender.propertyList as? String, let command = FormattingCommand(rawValue: name) else { return }
    engine?.perform(command)
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard let key = presses.first?.key, let engine, key.modifierFlags.subtracting(.numericPad).isEmpty else { return super.pressesBegan(presses, with: event) }
    switch key.keyCode {
    case .keyboardUpArrow where engine.upKey(): return
    case .keyboardDownArrow where engine.downKey(): return
    case .keyboardEscape where engine.escapeKey(): return
    case .keyboardTab where engine.actions.mentionKey(.pick): return
    default: super.pressesBegan(presses, with: event)
    }
  }

  override func paste(_ sender: Any?) {
    let pasteboard = UIPasteboard.general
    if let files = Pasteboard.pastedFiles() {
      engine?.actions.files(files)
      return
    }
    guard let text = pasteboard.string else { return super.paste(sender) }
    engine?.insertPlain(text)
    if let link = Autolink.linkedUrls(text).first(where: { $0.lowercased().hasPrefix("http") }) { engine?.actions.pastedLink(link) }
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(paste(_:)) { return UIPasteboard.general.numberOfItems > 0 }
    return super.canPerformAction(action, withSender: sender)
  }
}

extension RichTextEngine: UITextViewDelegate {
  func textViewDidChange(_ textView: UITextView) {
    textChanged()
    if let last = textView.text.last, "*_~`".contains(last) { inlineShortcut() }
  }

  func textViewDidChangeSelection(_ textView: UITextView) { selectionChanged() }

  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    if text == "\n" {
      // The touch keyboard's Return starts a line; ⌘Return or Send sends.
      if actions.mentionKey(.pick) { return false }
      if actions.returnSends {
        actions.submit()
        return false
      }
      lineBreak()
      return false
    }
    return shouldChange(range, text)
  }

  func textViewDidBeginEditing(_ textView: UITextView) { controller.focused = true }
  func textViewDidEndEditing(_ textView: UITextView) { controller.focused = false }
}

struct RichTextView: UIViewRepresentable {
  let engine: RichTextEngine
  let actions: EditorActions
  let editable: Bool

  func makeUIView(context: Context) -> EditorTextView {
    let view = EditorTextView(usingTextLayoutManager: true)
    view.engine = engine
    view.delegate = engine
    view.backgroundColor = .clear
    view.isScrollEnabled = true
    view.textContainerInset = UIEdgeInsets(top: Spacing.xxs, left: 0, bottom: Spacing.xxs, right: 0)
    view.textContainer.lineFragmentPadding = 0
    view.typingAttributes = RichTextEngine.plainTyping
    view.smartQuotesType = .no
    view.smartDashesType = .no
    view.isEditable = editable
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    engine.view = view
    return view
  }

  func updateUIView(_ view: EditorTextView, context: Context) {
    engine.actions = actions
    view.isEditable = editable
    DispatchQueue.main.async { engine.measure() }
  }
}
#endif

/**
 * The rich editor as SwiftUI lays it out: the text view, its placeholder, growing with what's written
 * from one line to `maxHeight`, and scrolling past it.
 */
struct SuiteRichEditor: View {
  let controller: RichEditorController
  let placeholder: String
  let document: ComposerDocument
  let revision: Int
  var actions: EditorActions
  var minHeight: CGFloat = 22
  var maxHeight: CGFloat = 220
  @State private var engine: RichTextEngine?
  @State private var height: CGFloat = 22

  var body: some View {
    ZStack(alignment: .topLeading) {
      if let engine {
        RichTextView(engine: engine, actions: actions, editable: true)
          .frame(height: min(max(height, minHeight), maxHeight))
          .onAppear {
            engine.load(document, revision: revision)
            #if os(macOS)
            engine.focus()
            #endif
          }
          .onChange(of: revision) { _, new in engine.load(document, revision: new) }
      } else {
        Color.clear.frame(height: minHeight)
      }
      if controller.isEmpty {
        Text(placeholder)
          .font(DesignFont.body)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .padding(.top, Spacing.xxs)
          .allowsHitTesting(false)
      }
    }
    .onAppear {
      guard engine == nil else { return }
      let made = RichTextEngine(controller: controller, actions: actions)
      let height = $height
      made.heightChanged = { new in if abs(new - height.wrappedValue) > 0.5 { height.wrappedValue = new } }
      engine = made
    }
  }
}
