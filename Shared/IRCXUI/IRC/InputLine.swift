import EmberKit
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import PhotosUI
#endif

/**
 * The input line, the room's or a thread's (`parentId`): `[nick(#room)] ▸` or `reply ▸`, Return to send,
 * Shift+Return for a new line, Tab to complete a nick (from who the room's @ prompt offers, cycling on),
 * `@` to list whom it offers, ↑ and ↓ for what you sent before, the IRC commands `InputCommand` reads, and
 * the Markdown-style formatting the web editor takes, sent as Ember markup. Files picked, dropped or
 * pasted go first, each its own message.
 */
struct InputLine: View {
  let app: AppModel
  let session: InstanceSession
  let room: RoomModel
  var parentId: String?
  @Environment(\.theme) private var theme
  @AppStorage(Preferences.fontSize) private var fontSize = 13.0
  @State private var history: [String] = []
  @State private var historyIndex: Int?
  /** The message `/edit` put on the line, which Return saves and Esc lets go. */
  @State private var editing: Message?
  /** Tab's completions for the word being completed, and which it's on. */
  @State private var completion: (word: String, candidates: [String], index: Int)?
  @State private var completing: Task<Void, Never>?
  @State private var picking = false
  #if os(macOS)
  /** Picks pasted files, which a text field would write as their names. */
  @State private var pasteMonitor: Any?
  #else
  @State private var pickingPhotos = false
  @State private var photos: [PhotosPickerItem] = []
  #endif
  @FocusState private var focused: Bool

  init(app: AppModel, session: InstanceSession, room: RoomModel, parentId: String? = nil, draft: String = "", refusal: String? = nil) {
    self.app = app
    self.session = session
    self.room = room
    self.parentId = parentId
    if !draft.isEmpty {
      let composer = room.composer(thread: parentId)
      composer.line = draft
      composer.refusal = refusal
    }
  }

  private var composer: ComposerModel { room.composer(thread: parentId) }

  var body: some View {
    let composer = composer
    VStack(alignment: .leading, spacing: 2) {
      if let refusal = composer.refusal {
        Text("-!- \(refusal)").foregroundStyle(theme.part).lineLimit(1)
      }
      ForEach(composer.refused, id: \.self) { Text("-!- \($0)").foregroundStyle(theme.part).lineLimit(1) }
      if !composer.files.isEmpty {
        HStack(spacing: 6) {
          Text("[files]").foregroundStyle(theme.dim)
          ForEach(composer.files) { file in
            Button("\(file.name) [x]") { composer.remove(file) }
              .buttonStyle(.plain)
              .foregroundStyle(theme.link)
              .help("Remove \(file.name)")
          }
        }
        .lineLimit(1)
      }
      if composer.quoting != nil {
        Button("[quoting] Esc clears") { composer.quoting = nil }
          .buttonStyle(.plain)
          .foregroundStyle(theme.dim)
      }
      if let completion, completion.candidates.count > 1 {
        Text(completion.candidates.enumerated().map { $0.offset == completion.index ? "[\($0.element)]" : $0.element }.joined(separator: " "))
          .foregroundStyle(theme.dim)
          .lineLimit(1)
      } else if composer.mentionQuery != nil {
        mentionStrip(composer)
      }
      prompt
      if parentId != nil {
        Toggle(room.room.isDirect ? "Also send as direct message" : "Also send to #\(room.title)", isOn: Bindable(composer).alsoSend)
          .font(Theme.font(fontSize - 2))
          .foregroundStyle(theme.dim)
          #if os(macOS)
          .toggleStyle(.checkbox)
          #endif
      }
    }
    .font(Theme.font(fontSize))
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(theme.input)
    .onAppear {
      focused = parentId == nil
      #if os(macOS)
      watchPastes()
      #endif
    }
    #if os(macOS)
    .onDisappear {
      if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
      pasteMonitor = nil
    }
    #endif
    .onChange(of: room.timeline.rewrites) { _, rewrites in
      // A message refused for what it says comes back to an empty line, for its writer to change.
      guard parentId == nil, !rewrites.isEmpty, let given = room.takeBack(composerEmpty: composer.line.isEmpty) else { return }
      composer.giveBack(given)
      focused = true
    }
    .onChange(of: room.thread?.rewrites) { _, rewrites in
      guard parentId != nil, rewrites?.isEmpty == false, let given = room.takeBackReply(composerEmpty: composer.line.isEmpty) else { return }
      composer.giveBack(given)
      focused = true
    }
    .onChange(of: room.request) { _, request in
      guard case let .editLine(message, inThread) = request, inThread == (parentId != nil) else { return }
      room.request = nil
      // Only what the line's Markdown-style text writes back the same can be edited here, so no formatting is lost.
      guard let text = room.editableLine(message) else {
        return room.note("That message's formatting can't be written on the input line; edit it in the Suite theme", kind: .error)
      }
      editing = message
      composer.line = text
      focused = true
    }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
      switch result {
      case let .success(urls): composer.pick(urls: urls)
      case let .failure(error):
        logger.error("The file picker failed: \(error.localizedDescription, privacy: .public)")
        room.warn(error.localizedDescription)
      }
    }
    #if os(iOS)
    .photosPicker(isPresented: $pickingPhotos, selection: $photos, matching: .any(of: [.images, .videos]), photoLibrary: .shared())
    .onChange(of: photos) { _, picked in
      guard !picked.isEmpty else { return }
      photos = []
      Task {
        do {
          composer.pick(try await PhotoLibrary.files(picked))
        } catch {
          logger.error("A photo couldn't be attached: \(error.localizedDescription, privacy: .public)")
          room.warn(error.localizedDescription)
        }
      }
    }
    #endif
  }

  private var prompt: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      if parentId == nil {
        Text("[\(session.me?.name ?? "?")(\(room.room.isDirect ? room.title : "#" + room.title))]")
          .foregroundStyle(theme.dim)
          .lineLimit(1)
      } else {
        Text("reply").foregroundStyle(theme.dim)
      }
      if editing != nil { Text("[edit]").foregroundStyle(theme.ember) }
      Text("▸").foregroundStyle(theme.ember)
      field
      #if os(iOS)
      touchButtons
      #endif
    }
  }

  #if os(iOS)
  /** A touch keyboard's Return sends, so the line's other keys are buttons: attach, a new line, leave [edit], send. */
  @ViewBuilder
  private var touchButtons: some View {
    let composer = composer
    Menu {
      Button("Photo library", systemImage: "photo.on.rectangle") { pickingPhotos = true }
      Button("Upload a file", systemImage: "arrow.up.doc") { picking = true }
      Button("Paste a file", systemImage: "doc.on.clipboard") { pasteFiles() }
      Button("Text snippet", systemImage: "doc.plaintext") { room.request = .snippet(String()) }
    } label: {
      Image(systemName: "plus.circle").font(Theme.font(20))
    }
    .foregroundStyle(theme.dim)
    .disabled(room.offline)
    Button {
      composer.line += "\n"
    } label: {
      Image(systemName: "return").font(Theme.font(16))
    }
    .foregroundStyle(theme.dim)
    .accessibilityLabel("New line")
    if editing != nil || composer.quoting != nil {
      Button(action: cancel) {
        Image(systemName: "xmark.circle").font(Theme.font(20))
      }
      .foregroundStyle(theme.dim)
      .accessibilityLabel(editing != nil ? "Stop editing" : "Clear quote")
    }
    Button(action: submit) {
      Image(systemName: "arrow.up.circle.fill").font(Theme.font(22))
    }
    .foregroundStyle(composer.isEmpty && editing == nil ? theme.dim : theme.ember)
    .disabled((composer.isEmpty && editing == nil) || room.offline)
    .accessibilityLabel(editing != nil ? "Save" : "Send")
  }

  /** Attaches the files on the pasteboard, which a touch keyboard's paste would write as text, or says there are none. */
  private func pasteFiles() {
    guard let files = Pasteboard.pastedFiles() else { return room.warn("There are no files to paste.") }
    composer.pick(files)
  }
  #endif

  @ViewBuilder
  private var field: some View {
    let line = Bindable(composer).line
    TextField(String(), text: line, axis: .vertical)
      .textFieldStyle(.plain)
      .lineLimit(1...8)
      .focused($focused)
      .onSubmit(submit)
      #if os(iOS)
      .submitLabel(.send)
      .autocorrectionDisabled()
      .textInputAutocapitalization(.sentences)
      #endif
      .onChange(of: composer.line) { _, new in
        if parentId == nil, !new.isEmpty, !new.hasPrefix("/"), editing == nil { room.typed() }
        if completion.map({ new.hasSuffix($0.candidates[$0.index] + ": ") || new.hasSuffix($0.candidates[$0.index] + " ") }) != true { completion = nil }
        lookUpMentions(in: new)
      }
      // Hardware keys, on an iPad's keyboard too.
      .onKeyPress(.tab) {
        complete()
        return .handled
      }
      .onKeyPress(.upArrow) { recall(-1) ? .handled : .ignored }
      .onKeyPress(.downArrow) { recall(1) ? .handled : .ignored }
      .onKeyPress(.escape) {
        let composer = composer
        if editing == nil, composer.quoting == nil {
          guard composer.mentionQuery != nil else { return .ignored }
          composer.closeMentions()
          return .handled
        }
        cancel()
        return .handled
      }
      .onKeyPress(.return, phases: .down) { press in
        // Shift+Return starts a new line of the same message.
        guard press.modifiers.contains(.shift) else { return .ignored }
        composer.line += "\n"
        return .handled
      }
  }

  /** Leaves [edit] mode, or lets go of the quote. */
  private func cancel() {
    let composer = composer
    if editing != nil {
      editing = nil
      composer.line = String()
    }
    composer.quoting = nil
  }

  // MARK: Mentions

  /** Looks up whom `@` and what follows it at the end of the line could mention, as the room's @ prompt does. */
  private func lookUpMentions(in line: String) {
    let composer = composer
    if let last = line.split(separator: " ", omittingEmptySubsequences: false).last, last.hasPrefix("@"), !last.contains("\n") {
      composer.lookUpMentions(String(last.dropFirst()), api: session.api, room: room.id)
    } else if composer.mentionQuery != nil {
      composer.closeMentions()
    }
  }

  /** Whom the @ prompt offers, each a click or a tap that writes them in place of what's typed after `@`. */
  private func mentionStrip(_ composer: ComposerModel) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        if composer.candidates.isEmpty {
          Text(composer.searchedMentions ? "-- no matches --" : "-- looking --").foregroundStyle(theme.dim)
        }
        ForEach(composer.candidates) { item in
          Button {
            writeMention(item)
          } label: {
            Text(Self.label(item))
          }
          .buttonStyle(.plain)
          .foregroundStyle(theme.nick(item.id))
          .help("Mention \(item.name)")
        }
      }
    }
    .lineLimit(1)
  }

  private static func label(_ item: MentionPromptItem) -> String {
    var text = item.name
    if let username = item.username { text += " @" + username }
    if item.agent { text += " +agent" }
    return "[" + text + "]"
  }

  private func writeMention(_ item: MentionPromptItem) {
    let composer = composer
    var line = composer.line
    guard let at = line.lastIndex(of: "@") else { return }
    line.removeSubrange(at...)
    composer.line = line + "@" + item.name + " "
    composer.closeMentions()
    focused = true
  }

  // MARK: Sending

  private func submit() {
    let composer = composer
    let text = composer.line
    guard !room.offline else { return room.warn(EmberText.notConnectedNotSent) }
    if let message = editing {
      guard room.edit(message, to: text) else { return }
      editing = nil
      composer.line = String()
      return
    }
    let alsoSend = composer.alsoSend
    let files = composer.takeFiles()
    if !files.isEmpty {
      room.send(files: files, parentId: parentId, alsoSend: alsoSend)
      composer.alsoSend = false
    }
    guard let command = InputCommand.parse(text) else {
      if composer.quoting != nil, room.send(ComposerDocument(), quoting: composer.quoting, parentId: parentId, alsoSend: alsoSend) { sent() }
      return
    }
    history.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
    if history.count > 100 { history.removeFirst() }
    historyIndex = nil
    focused = true
    switch command {
    case let .say(said):
      // A typed `@Name` or `Name:` mentions only whom the room's @ prompt offered.
      let document = ComposerDocument(markdown: said, mentioning: composer.mentionable)
      guard room.send(document, quoting: composer.quoting, parentId: parentId, alsoSend: alsoSend) else { return }
      sent()
    case let .me(action) where parentId != nil:
      room.send(action, action: true, parentId: parentId, alsoSend: alsoSend)
      sent()
    default:
      composer.line = String()
      composer.refusal = nil
      Commander.run(command, app: app, session: session, room: room)
    }
  }

  private func sent() {
    composer.clear()
    composer.alsoSend = false
  }

  /**
   * Completes the nick being typed, as irssi does: `Ad⇥` becomes `Ada: ` at the start of the line, `Ada `
   * after; Tab again goes on to the next who matches. Whom it offers is who the room's @ prompt would:
   * names containing what's typed, or usernames starting with it.
   */
  private func complete() {
    let composer = composer
    if var completion, completion.candidates.count > 1 {
      completion.index = (completion.index + 1) % completion.candidates.count
      self.completion = completion
      write(completion.candidates[completion.index], for: completion.word)
      return
    }
    let words = composer.line.split(separator: " ", omittingEmptySubsequences: false)
    guard let last = words.last, !last.isEmpty else { return }
    let typed = String(last)
    let prefix = typed.hasPrefix("@") ? String(typed.dropFirst()) : typed
    completing?.cancel()
    completing = Task {
      let candidates: [String]
      do {
        candidates = try await composer.complete(prefix, api: session.api, room: room.id).map(\.name).filter { $0 != session.me?.name }
      } catch is CancellationError {
        return
      } catch {
        logger.error("Tab completion couldn't look people up: \(error.localizedDescription, privacy: .public)")
        room.warn(error.localizedDescription)
        return
      }
      guard !Task.isCancelled, let first = candidates.first else { return }
      composer.closeMentions()
      completion = (typed, candidates, 0)
      write(first, for: typed)
    }
  }

  /** Writes a completion in place of the word it completes. */
  private func write(_ name: String, for word: String) {
    let composer = composer
    var line = composer.line
    for suffix in [": ", " "] where completion != nil {
      for candidate in completion?.candidates ?? [] where line.hasSuffix(candidate + suffix) {
        line.removeLast((candidate + suffix).count)
        line += word
      }
    }
    guard line.hasSuffix(word) else { return }
    line.removeLast(word.count)
    let mention = (word.hasPrefix("@") ? "@" : String()) + name
    composer.line = line.isEmpty ? mention + (word.hasPrefix("@") ? " " : ": ") : line + mention + " "
  }

  /** Steps through what was sent before, and says whether it did. */
  private func recall(_ step: Int) -> Bool {
    let composer = composer
    guard !history.isEmpty, composer.line.isEmpty || historyIndex != nil else { return false }
    let next = (historyIndex ?? history.count) + step
    if next >= history.count {
      historyIndex = nil
      composer.line = String()
    } else if next >= 0 {
      historyIndex = next
      composer.line = history[next]
    }
    return true
  }

  #if os(macOS)
  /**
   * ⌘V with files or a picture (and no text) on the pasteboard picks them, as the web does, while this line
   * has the focus; anything else pastes as it would.
   */
  private func watchPastes() {
    guard pasteMonitor == nil else { return }
    let focus = $focused
    let composer = composer
    pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard focus.wrappedValue, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
        event.charactersIgnoringModifiers?.lowercased() == "v"
      else { return event }
      let picked = MainActor.assumeIsolated {
        guard let files = Pasteboard.pastedFiles() else { return false }
        composer.pick(files)
        return true
      }
      return picked ? nil : event
    }
  }
  #endif
}
