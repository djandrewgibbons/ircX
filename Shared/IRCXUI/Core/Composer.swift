import EmberKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers
#if canImport(AVFoundation)
import AVFoundation
#endif

/** A file picked to go with the next message (web `usePickedFiles`): from the picker, a paste, a drop, or a snippet. */
public struct PickedFile: Identifiable, Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    case url(URL)
    case data(Data)
  }

  public let id = UUID()
  public var name: String
  public var type: String
  public var size: Int
  public var source: Source

  public init(name: String, type: String, size: Int, source: Source) {
    self.name = name
    self.type = type
    self.size = size
    self.source = source
  }

  /** A file on disk, as the picker or a drop gives it; nil, logged, for one that can't be read. */
  public static func at(_ url: URL) -> PickedFile? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
      guard values.isDirectory != true, let size = values.fileSize else {
        logger.error("A picked file isn't one: \(url.lastPathComponent, privacy: .public)")
        return nil
      }
      return PickedFile(name: url.lastPathComponent, type: mimeType(of: url.lastPathComponent), size: size, source: .url(url))
    } catch {
      logger.error("A picked file couldn't be read: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /** The type a browser would give a file of this name: by its extension, or none, which Ember works out from its bytes. */
  public static func mimeType(of name: String) -> String {
    let ext = (name as NSString).pathExtension
    if let type = UTType(filenameExtension: ext)?.preferredMIMEType { return type }
    return String()
  }

  /** Whether it's a picture, which its chip shows. */
  public var isImage: Bool { type.hasPrefix("image/") }

  /** Bytes `range` of the file. */
  func bytes(_ range: Range<Int>) throws -> Data {
    switch source {
    case let .data(data):
      return data.subdata(in: range)
    case let .url(url):
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let handle = try FileHandle(forReadingFrom: url)
      defer {
        do { try handle.close() } catch { logger.error("A file being uploaded didn't close: \(error.localizedDescription, privacy: .public)") }
      }
      try handle.seek(toOffset: UInt64(range.lowerBound))
      guard let data = try handle.read(upToCount: range.count) else { return Data() }
      return data
    }
  }
}

/** A pasted link's preview, shown below its paragraph until the message goes (web `useLinkPreviews.pasted`); kept with the draft. */
public struct DraftLinkPreview: Codable, Hashable, Sendable {
  public var preview: LinkPreview
  /** The link as it was pasted, whose paragraph it goes below. */
  public var link: String
}

/** A file on its way to becoming a message: its card's name, size, how much has gone, and why it failed. */
public struct UploadState: Hashable, Sendable {
  public var name: String
  public var size: Int
  public var percent = 0
  public var error: String?

  public var status: String { UploadWords.status(percent: percent, error: error) }
}

/**
 * One composer's state, the room's or a thread's (web `Composer`): what's written, the files picked to
 * go with it, why the room gave something back, Also send, and the @ prompt's people. What's written is
 * kept per person and room on this device, as the web keeps its draft in local storage.
 */
@MainActor
@Observable
public final class ComposerModel {
  /** What the Suite editor holds. */
  public var document = ComposerDocument() {
    didSet { if !loading { save() } }
  }
  /** What IRC Classic's input line holds. */
  public var line = "" {
    didSet { if !loading { save() } }
  }
  /** Goes up when something other than typing changes what's written (Quote, a refusal given back, a send), so the editor shows it. */
  public private(set) var revision = 0
  public private(set) var files: [PickedFile] = []
  /** Why files weren't added, replaced on the next pick. */
  public private(set) var refused: [String] = []
  /** Why the room gave back what's written, in red over it until the next send (web `refusal`). */
  public var refusal: String?
  public var alsoSend = false
  /** IRC Classic: the quote Quote wrote, which goes before the line. */
  public var quoting: String?
  /** The pasted link's preview, which goes below its paragraph unless it's taken out; part of the draft. */
  public var linkPreview: DraftLinkPreview? {
    didSet { if !loading { save() } }
  }
  /** The @ prompt: what's typed after `@`, and whom it offers. */
  public private(set) var mentionQuery: String?
  public private(set) var candidates: [MentionPromptItem] = []
  public private(set) var searchedMentions = false
  /**
   * Everyone `/api/autocompletable/users` has offered while this was written, which the room let it
   * mention: IRC Classic's typed `@Name` and `Name:` mention whichever of them they name.
   */
  public private(set) var offered: [UserID: MentionPromptItem] = [:]

  @ObservationIgnored private let key: String?
  /** A mention's name as the people directory has it now, for what's read back from markup. */
  @ObservationIgnored private let name: (UserID) -> String
  @ObservationIgnored private var loading = false
  @ObservationIgnored private var lookup: Task<Void, Never>?

  init(key: String?, name: @escaping (UserID) -> String) {
    self.key = key
    self.name = name
    guard let key else { return }
    loading = true
    defer { loading = false }
    let defaults = UserDefaults.standard
    if let html = defaults.string(forKey: key + ".html") {
      do {
        document = try ComposerDocument(html: html, name: name)
      } catch {
        logger.error("A saved draft didn't read: \(error.localizedDescription, privacy: .public)")
      }
    }
    if let saved = defaults.string(forKey: key + ".line") { line = saved }
    if let data = defaults.data(forKey: key + ".preview") {
      do {
        linkPreview = try JSONDecoder().decode(DraftLinkPreview.self, from: data)
      } catch {
        logger.error("A saved draft's link preview didn't read: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /** The people this composer was offered, as a typed mention resolves against them. */
  public var mentionable: [User] { offered.values.map { User(id: $0.id, name: $0.name) } }

  public var isEmpty: Bool { document.isBlank && line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && files.isEmpty && quoting == nil }

  private func save() {
    guard let key else { return }
    let defaults = UserDefaults.standard
    if document.isBlank { defaults.removeObject(forKey: key + ".html") } else { defaults.set(document.html, forKey: key + ".html") }
    if line.isEmpty { defaults.removeObject(forKey: key + ".line") } else { defaults.set(line, forKey: key + ".line") }
    if let linkPreview {
      do {
        defaults.set(try JSONEncoder().encode(linkPreview), forKey: key + ".preview")
      } catch {
        logger.error("A draft's link preview wasn't kept: \(error.localizedDescription, privacy: .public)")
      }
    } else {
      defaults.removeObject(forKey: key + ".preview")
    }
  }

  /** Puts `document` in the editor in place of what's there, the caret at its end (web `Composer.replace`). */
  public func replace(with document: ComposerDocument) {
    self.document = document
    revision += 1
  }

  /** Clears what's written after a send. */
  public func clear() {
    document = ComposerDocument()
    line = ""
    quoting = nil
    refusal = nil
    linkPreview = nil
    offered = [:]
    revision += 1
  }

  /** Gives back what the room refused for what it says (web `giveBack`): its markup where it had some. */
  public func giveBack(_ given: GivenBack) {
    if let html = given.html {
      do {
        document = try ComposerDocument(html: html, name: name)
      } catch {
        logger.error("A message given back didn't read: \(error.localizedDescription, privacy: .public)")
        document = ComposerDocument(plain: given.text)
      }
    } else {
      document = ComposerDocument(plain: given.text)
    }
    line = given.text
    refusal = given.why
    alsoSend = given.alsoSend
    revision += 1
  }

  // MARK: - Files

  /** Adds files, sorted by name, leaving out those past 250 MB, which say so in place of what was said before. */
  public func pick(_ picked: [PickedFile]) {
    refused = picked.filter { $0.size > Files.maxFileSize }.map { EmberText.tooLargeToAttach($0.name) }
    files = (files + picked.filter { $0.size <= Files.maxFileSize }).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
  }

  public func pick(urls: [URL]) {
    pick(urls.compactMap(PickedFile.at))
  }

  /** A text snippet, as a `.txt` (or named) file with what's written in it (web snippet dialog). */
  public func addSnippet(title: String, content: String) {
    let data = Data(content.utf8)
    pick([PickedFile(name: Snippets.name(title), type: "text/plain", size: data.count, source: .data(data))])
  }

  public func remove(_ file: PickedFile) {
    files.removeAll { $0.id == file.id }
  }

  /** The files picked, which go now. */
  public func takeFiles() -> [PickedFile] {
    defer {
      files = []
      refused = []
    }
    return files
  }

  // MARK: - Mentions

  /**
   * Looks up whom the @ prompt offers for what's typed after `@` (nil when no prompt's open), 150 ms
   * after the last keystroke, from `/api/autocompletable/users`, which honours who's in the room.
   */
  public func lookUpMentions(_ query: String?, api: EmberAPI, room: RoomID) {
    lookup?.cancel()
    guard let query else {
      closeMentions()
      return
    }
    mentionQuery = query
    lookup = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      do {
        let found = try await api.mentionable(in: room, filter: query)
        guard !Task.isCancelled, let self, self.mentionQuery == query else { return }
        self.candidates = found
        self.searchedMentions = true
        self.offer(found)
      } catch is CancellationError {
        return
      } catch {
        logger.error("The @ prompt couldn't look people up: \(error.localizedDescription, privacy: .public)")
        self?.candidates = []
        self?.searchedMentions = true
      }
    }
  }

  /** Whom `/api/autocompletable/users` offers for `prefix` now, as IRC Classic's Tab asks; they're offered to this composer. */
  public func complete(_ prefix: String, api: EmberAPI, room: RoomID) async throws -> [MentionPromptItem] {
    let found = try await api.mentionable(in: room, filter: prefix)
    offer(found)
    return found
  }

  func offer(_ found: [MentionPromptItem]) {
    for item in found { offered[item.id] = item }
  }

  public func closeMentions() {
    lookup?.cancel()
    mentionQuery = nil
    candidates = []
    searchedMentions = false
  }
}

// MARK: - Uploads

/**
 * Uploads a file as its own message (web `lib/uploads.ts`): starts it, sends its parts of `partSize`
 * in order, a preview before the last where one can be made, and answers the message the last part posts.
 */
enum Uploader {
  struct Failure: Error, LocalizedError {
    var reason: String
    var errorDescription: String? { reason }
  }

  static func upload(
    _ file: PickedFile, api: EmberAPI, room: RoomID, clientMessageId: String, parentId: String?, alsoSend: Bool,
    progress: @escaping @MainActor (Int) -> Void
  ) async throws -> Message {
    do {
      let upload = try await api.beginUpload(
        NewUpload(name: file.name, type: file.type, size: file.size, clientMessageId: clientMessageId, parentId: parentId, alsoSend: alsoSend), in: room)
      for number in 1...max(1, upload.parts) {
        let start = (number - 1) * upload.partSize
        let end = min(file.size, start + upload.partSize)
        let last = number == max(1, upload.parts)
        if last { await sendPreview(of: file, upload: upload, api: api, room: room) }
        let posted = try await api.uploadPart(try file.bytes(start..<end), number: number, of: upload, in: room)
        await progress(UploadWords.percent(sent: end, of: file.size))
        if last {
          guard let posted else { throw Failure(reason: EmberText.uploadFailed) }
          return posted
        }
      }
      throw Failure(reason: EmberText.uploadFailed)
    } catch let error as EmberError {
      switch error {
      case let .problem(problem): throw Failure(reason: UploadWords.failure(status: problem.status, reason: problem.message))
      case .transport: throw Failure(reason: UploadWords.failure(status: nil, reason: nil))
      default: throw Failure(reason: EmberText.uploadFailed)
      }
    }
  }

  /** Sends a preview Ember can show of a picture or a video; one that can't be made in 5 s, or isn't taken, is left out, logged. */
  private static func sendPreview(of file: PickedFile, upload: Upload, api: EmberAPI, room: RoomID) async {
    guard Files.isPreviewed(file.type) else { return }
    let made: (Data, String)? = await withTaskGroup(of: Optional<(Data, String)>.self) { group in
      group.addTask { await preview(of: file) }
      group.addTask {
        try? await Task.sleep(for: .seconds(5))
        return nil
      }
      let first = await group.next()
      group.cancelAll()
      return first.flatMap { $0 }
    }
    guard let (data, type) = made, data.count <= Files.maxPreviewSize else { return }
    do {
      try await api.uploadPreview(data, contentType: type, of: upload, in: room)
    } catch {
      logger.error("A file's preview wasn't taken: \(error.localizedDescription, privacy: .public)")
    }
  }

  /** A JPEG (PNG where it's transparent) within 1200×800, of a picture or a video's frame at 0.1 s. */
  static func preview(of file: PickedFile) async -> (Data, String)? {
    let image: CGImage?
    if file.type.hasPrefix("video") {
      image = await videoFrame(of: file)
    } else {
      image = pictureThumbnail(of: file)
    }
    guard let image else { return nil }
    let alpha = ![.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo)
    let type: UTType = alpha ? .png : .jpeg
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      logger.error("A preview didn't encode")
      return nil
    }
    return (data as Data, alpha ? "image/png" : "image/jpeg")
  }

  /** A picture's thumbnail within `pixels` on its longest side, as its chip shows it (web `FileChip`); nil for one ImageIO can't read. */
  static func thumbnail(of file: PickedFile, pixels: Int) -> CGImage? {
    let source: CGImageSource?
    switch file.source {
    case let .data(data): source = CGImageSourceCreateWithData(data as CFData, nil)
    case let .url(url):
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      source = CGImageSourceCreateWithURL(url as CFURL, nil)
    }
    guard let source else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  private static func pictureThumbnail(of file: PickedFile) -> CGImage? {
    let source: CGImageSource?
    switch file.source {
    case let .data(data): source = CGImageSourceCreateWithData(data as CFData, nil)
    case let .url(url):
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      source = CGImageSourceCreateWithURL(url as CFURL, nil)
    }
    guard let source, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width * height <= Files.maxPreviewPixels
    else { return nil }
    let scale = min(1, Double(Files.previewMaxWidth) / Double(width), Double(Files.previewMaxHeight) / Double(height))
    let longest = Int((Double(max(width, height)) * scale).rounded(.down))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(1, longest),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  private static func videoFrame(of file: PickedFile) async -> CGImage? {
    #if canImport(AVFoundation)
    guard case let .url(url) = file.source else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: Files.previewMaxWidth, height: Files.previewMaxHeight)
    do {
      let duration = try await asset.load(.duration).seconds
      let at = duration > 0 && duration < 0.2 ? duration / 2 : 0.1
      return try await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)).image
    } catch {
      logger.error("A video's poster couldn't be made: \(error.localizedDescription, privacy: .public)")
      return nil
    }
    #else
    return nil
    #endif
  }
}

// MARK: - Keyboard shortcuts

/**
 * The app's menu commands that have keys, which the scene's menus are built from and the keyboard
 * shortcuts dialog lists, so the two can't drift apart.
 */
public enum ShortcutCommand: String, CaseIterable, Sendable, Identifiable {
  case jumpTo, previousRoom, nextRoom, back, forward, home, search, activity, newMessage, newRoom, moveStarUp, moveStarDown, roomSettings,
    showShortcuts, toggleHuddle, muteHuddle

  public var id: String { rawValue }

  /** Its menu item's title. */
  public var title: String {
    switch self {
    case .jumpTo: "Jump To"
    case .previousRoom: "Previous Room"
    case .nextRoom: "Next Room"
    case .back: "Back"
    case .forward: "Forward"
    case .home: "Home"
    case .search: "Search Messages"
    case .activity: "Activity"
    case .newMessage: "New Message"
    case .newRoom: "New Room"
    case .moveStarUp: "Move Starred Room Up"
    case .moveStarDown: "Move Starred Room Down"
    case .roomSettings: "Conversation Settings"
    case .showShortcuts: "Keyboard Shortcuts"
    case .toggleHuddle: "Start, Join or Leave Huddle"
    case .muteHuddle: "Mute or Unmute"
    }
  }

  /** Its keys, as the dialog shows them. */
  public var keys: [String] {
    switch self {
    case .jumpTo: ["⌘", "K"]
    case .previousRoom: ["⌥", "↑"]
    case .nextRoom: ["⌥", "↓"]
    case .back: ["⌘", "["]
    case .forward: ["⌘", "]"]
    case .home: ["⌘", "⇧", "H"]
    case .search: ["⌘", "F"]
    case .activity: ["⌘", "⇧", "A"]
    case .newMessage: ["⌘", "N"]
    case .newRoom: ["⌘", "⌥", "N"]
    case .moveStarUp: ["⌘", "⌥", "↑"]
    case .moveStarDown: ["⌘", "⌥", "↓"]
    case .roomSettings: ["⌘", "⇧", "I"]
    case .showShortcuts: ["⌘", "/"]
    case .toggleHuddle: ["⌘", "⌥", "⇧", "H"]
    case .muteHuddle: ["⌘", "⇧", "Space"]
    }
  }
}

/** The keyboard shortcuts dialog's groups (web `SHORTCUTS`), which both themes show and `/help shortcuts` prints. */
public enum ShortcutCatalog {
  public struct Row: Hashable, Sendable {
    public var action: String
    public var keys: [String]
    /** The menu commands the row's keys are, which the scene registers; none for keys the composer or editor handles. */
    public var commands: [ShortcutCommand] = []

    init(action: String, keys: [String], commands: [ShortcutCommand] = []) {
      self.action = action
      self.keys = keys
      self.commands = commands
    }

    init(action: String, _ command: ShortcutCommand) {
      self.init(action: action, keys: command.keys, commands: [command])
    }
  }

  public struct Group: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var rows: [Row]
  }

  public static let groups: [Group] = [
    Group(name: "Navigate", rows: [
      Row(action: "Jump to a room", .jumpTo),
      Row(action: "Next or previous room", keys: ["⌥", "↑ ↓"], commands: [.previousRoom, .nextRoom]),
      Row(action: "Go to a server", keys: ["⌘", "1–9"]),
      Row(action: "Go back or forward", keys: ["⌘", "[ ]"], commands: [.back, .forward]),
      Row(action: "Go home", .home),
      Row(action: "Search", .search),
      Row(action: "Show only unread conversations", .activity),
      Row(action: "New direct message", .newMessage),
      Row(action: "New room", .newRoom),
      Row(action: "Move a starred room up or down", keys: ["⌘", "⌥", "↑ ↓"], commands: [.moveStarUp, .moveStarDown]),
      Row(action: "Conversation settings", .roomSettings),
      Row(action: "Show keyboard shortcuts", .showShortcuts),
    ]),
    Group(name: "Huddles", rows: [
      Row(action: "Start, join or leave a huddle", .toggleHuddle),
      Row(action: "Mute or unmute", .muteHuddle),
    ]),
    Group(name: "Write a message", rows: [
      Row(action: "Send", keys: ["Return"]),
      Row(action: "Send, on a touch screen too", keys: ["⌘", "Return"]),
      Row(action: "Start a new line, or a list's next item", keys: ["⇧", "Return"]),
      Row(action: "Add a link", keys: ["⌘", "K"]),
      Row(action: "Upload files", keys: ["⌘", "O"]),
      Row(action: "Write a text snippet", keys: ["⌘", "⇧", "Return"]),
      Row(action: "Edit your last message, with nothing written", keys: ["↑"]),
    ]),
    Group(name: "Format text", rows: FormattingCommand.allCases.map { Row(action: $0.name, keys: $0.keys) }),
    Group(name: "Edit a message", rows: [
      Row(action: "Save", keys: ["⌘", "Return"]),
      Row(action: "Close", keys: ["Esc"]),
    ]),
  ]

  /** The Go menu's commands, in the dialog's order. */
  public static var goCommands: [ShortcutCommand] {
    groups.flatMap(\.rows).flatMap(\.commands).filter { ![.showShortcuts, .newMessage, .newRoom, .toggleHuddle, .muteHuddle].contains($0) }
  }

  /** The list as buffer lines, for IRC Classic's `/help shortcuts`. */
  public static var lines: [String] {
    groups.flatMap { group in ["\(group.name):"] + group.rows.map { "  \($0.keys.joined(separator: " ")) \u{2014} \($0.action)" } }
  }
}

/** The formatting row's commands (web `FORMATTING_NAMES`, `FORMATTING_KEYS`). */
public enum FormattingCommand: String, CaseIterable, Sendable, Identifiable {
  case bold, italic, underline, strikethrough, link, orderedList, bulletedList, blockquote, code, codeBlock

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .bold: "Bold"
    case .italic: "Italic"
    case .underline: "Underline"
    case .strikethrough: "Strikethrough"
    case .link: "Link"
    case .orderedList: "Ordered list"
    case .bulletedList: "Bulleted list"
    case .blockquote: "Blockquote"
    case .code: "Code"
    case .codeBlock: "Code block"
    }
  }

  public var keys: [String] {
    switch self {
    case .bold: ["⌘", "B"]
    case .italic: ["⌘", "I"]
    case .underline: ["⌘", "U"]
    case .strikethrough: ["⌘", "⇧", "X"]
    case .link: ["⌘", "⇧", "U"]
    case .orderedList: ["⌘", "⇧", "7"]
    case .bulletedList: ["⌘", "⇧", "8"]
    case .blockquote: ["⌘", "⇧", "9"]
    case .code: ["⌘", "⇧", "C"]
    case .codeBlock: ["⌘", "⌥", "⇧", "C"]
    }
  }

  public var symbol: String {
    switch self {
    case .bold: "bold"
    case .italic: "italic"
    case .underline: "underline"
    case .strikethrough: "strikethrough"
    case .link: "link"
    case .orderedList: "list.number"
    case .bulletedList: "list.bullet"
    case .blockquote: "text.quote"
    case .code: "chevron.left.forwardslash.chevron.right"
    case .codeBlock: "curlybraces.square"
    }
  }

  /** Whether it greys out inside a code block (`NOT_IN_CODE_BLOCKS`). */
  public var notInCodeBlocks: Bool { [.bold, .italic, .underline, .strikethrough, .link, .code].contains(self) }

  /** Its tooltip: its name and keys. */
  public var help: String { "\(name) (\(keys.joined()))" }
}
