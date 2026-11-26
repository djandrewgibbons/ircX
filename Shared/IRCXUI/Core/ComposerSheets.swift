import AppCoreUI
import EmberKit
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import ImageIO
import PhotosUI
#endif

/** Create a text snippet (web `SnippetDialog`): a title and its content, which go with the next message as a text file. */
struct SnippetSheet: View {
  let composer: ComposerModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var title: String
  @State private var content = ""
  @FocusState private var editing: Bool

  init(composer: ComposerModel, title: String = "") {
    self.composer = composer
    _title = State(initialValue: title)
  }

  private var blank: Bool { content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    switch look {
    case .suite: suite
    case .irc: classic
    }
  }

  private var suite: some View {
    SheetFrame(title: "Create a text snippet", systemImage: "doc.plaintext") {
      VStack(alignment: .leading, spacing: Spacing.md) {
        LabeledField("Title (optional)") { titleField.textFieldStyle(.plain) }
        LabeledField("Content") {
          contentEditor
            .frame(minHeight: 220)
        }
      }
    } footer: {
      EditorFooter(
        canSave: !blank, canCancel: true, saveHelp: "Create snippet", saveTitle: "Create snippet", bindsKeyboard: true, submitShortcut: .commandReturn,
        onCancel: { dismiss() }, onSave: create)
    }
    .frame(minWidth: 560)
  }

  private var classic: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("/snippet").font(Theme.font(18, weight: .bold)).foregroundStyle(irc.ember)
      titleField.textFieldStyle(.roundedBorder)
      contentEditor
        .frame(minHeight: 220)
        .background(irc.input)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
        Button("Create snippet", action: create)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(blank)
      }
    }
    .font(Theme.font(13))
    .padding(24)
    .frame(minWidth: 560)
    .background(irc.buffer)
    .preferredColorScheme(.dark)
  }

  private var titleField: some View {
    TextField("Title (optional)", text: $title)
      .onChange(of: title) { _, new in if new.count > Snippets.maxTitleLength { title = String(new.prefix(Snippets.maxTitleLength)) } }
  }

  private var contentEditor: some View {
    TextEditor(text: $content)
      .font(look == .suite ? DesignFont.monoBody : Theme.font(13))
      .autocorrectionDisabled()
      .scrollContentBackground(.hidden)
      .focused($editing)
      .onAppear { editing = true }
      .accessibilityLabel("Content")
  }

  private func create() {
    guard !blank else { return }
    composer.addSnippet(title: title, content: content)
    dismiss()
  }
}

/**
 * Report (web `ReportDialog`), for someone else's message or for someone: why, any details, then who'll
 * look, and an offer to block them too unless you have. Nobody is told who reported it.
 */
struct ReportSheet: View {
  enum Target {
    case message(RoomModel, Message)
    case person(Person)
  }

  let session: InstanceSession?
  let target: Target
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var reason: ReportReason?
  @State private var note = ""
  @State private var sending = false
  @State private var error: String?
  @State private var reported = false

  init(room: RoomModel, message: Message) {
    session = room.instance
    target = .message(room, message)
  }

  init(session: InstanceSession, person: Person) {
    self.session = session
    target = .person(person)
  }

  private var personId: UserID {
    switch target {
    case let .message(_, message): message.creator.id
    case let .person(person): person.id
    }
  }

  private var name: String {
    if let listed = session?.people[personId] { return listed.name }
    switch target {
    case let .message(_, message): return message.creator.name
    case let .person(person): return person.name
    }
  }

  private var isMessage: Bool {
    if case .message = target { return true }
    return false
  }

  private var title: String { reported ? "Reported" : isMessage ? "Report message" : "Report \(name)" }
  private var explained: String { isMessage ? PeopleText.reportMessageExplained(name) : PeopleText.reportPersonExplained }
  private var question: String { isMessage ? "Why are you reporting it?" : "Why are you reporting them?" }
  private var blocked: Bool { session?.isBlocked(personId) == true }

  /** The active administrators but you (`administratorsNamed`). */
  private var administrators: String? {
    guard let session else { return nil }
    let names = session.people.values.filter { $0.role == .administrator && $0.status == .active && $0.id != session.me?.id }.map(\.name).sorted()
    return PeopleText.administratorsNamed(names)
  }

  var body: some View {
    switch look {
    case .suite: suite
    case .irc: classic
    }
  }

  private var suite: some View {
    SheetFrame(title: title, systemImage: "flag") {
      VStack(alignment: .leading, spacing: Spacing.md) {
        if reported {
          Text(EmberText.reported).font(DesignFont.body)
          if let administrators { Text(administrators).font(DesignFont.body) }
          if !blocked {
            Text(PeopleText.blockOffer(name)).font(DesignFont.detail).foregroundStyle(.secondary)
            Button("Block \(name)", systemImage: "hand.raised", action: block)
          }
        } else {
          Text(explained).font(DesignFont.detail).foregroundStyle(.secondary)
          LabeledField(question) { reasons }
          LabeledField("Details (optional)") { noteField.textFieldStyle(.plain) }
          if let error { Notice(error, systemImage: "exclamationmark.triangle.fill", tint: SemanticColor.warning) }
        }
      }
    } footer: {
      if reported {
        EditorFooter(canSave: true, canCancel: false, saveHelp: "Done", saveTitle: "Done", onCancel: { dismiss() }, onSave: { dismiss() })
      } else {
        EditorFooter(
          canSave: reason != nil && !sending, canCancel: !sending, saveHelp: "Report", saveTitle: EditorActionTitle(sending ? "Reporting…" : "Report", widest: "Reporting…"),
          onCancel: { dismiss() }, onSave: send)
      }
    }
    .frame(minWidth: 440)
    .interactiveDismissDisabled(sending)
  }

  private var classic: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("/report").font(Theme.font(18, weight: .bold)).foregroundStyle(irc.ember)
      if reported {
        Text(EmberText.reported)
        if let administrators { Text(administrators) }
        if !blocked { Text(PeopleText.blockOffer(name)).foregroundStyle(irc.dim) }
        HStack {
          if !blocked { Button("/ignore \(name)", action: block) }
          Spacer()
          Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
      } else {
        Text(explained).foregroundStyle(irc.dim)
        Text(question)
        reasons
        noteField.textFieldStyle(.roundedBorder)
        if let error { Text("-!- \(error)").foregroundStyle(irc.part) }
        HStack {
          Spacer()
          Button("Cancel", role: .cancel) { dismiss() }.disabled(sending)
          Button(sending ? "Reporting…" : "Report", action: send)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(reason == nil || sending)
        }
      }
    }
    .font(Theme.font(13))
    .padding(24)
    .frame(minWidth: 440)
    .background(irc.buffer)
    .preferredColorScheme(.dark)
    .interactiveDismissDisabled(sending)
  }

  private var reasons: some View {
    Picker(question, selection: $reason) {
      ForEach(ReportReason.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
    }
    .pickerStyle(.inline)
    .labelsHidden()
  }

  private var noteField: some View {
    TextField("Details (optional)", text: $note, axis: .vertical)
      .lineLimit(2...5)
      .onChange(of: note) { _, new in if new.count > EmberLimits.maxReportNoteLength { note = String(new.prefix(EmberLimits.maxReportNoteLength)) } }
  }

  private func block() {
    guard let session else { return }
    let id = personId
    session.attempt("Blocking") { try await session.setBlocked(true, id) }
    dismiss()
  }

  private func send() {
    guard let reason, let session else { return }
    sending = true
    error = nil
    let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    Task {
      defer { sending = false }
      do {
        switch target {
        case let .message(room, message): try await room.report(message, reason: reason, note: note)
        case let .person(person): try await session.api.report(person: person.id, NewReport(reason: reason, note: note))
        }
        reported = true
      } catch let EmberError.problem(answer) where (400..<500).contains(answer.status) {
        logger.error("A report was refused: \(answer.message, privacy: .public)")
        error = answer.status == 404 ? (isMessage ? PeopleText.messageGone : PeopleText.personGone) : answer.message
      } catch {
        logger.error("A report didn't go: \(error.localizedDescription, privacy: .public)")
        self.error = PeopleText.notReported
      }
    }
  }
}

/** Keyboard shortcuts (web `KeyboardShortcutsDialog`), from one catalog so the list can't drift from the keys. */
struct ShortcutsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    switch look {
    case .suite:
      SheetFrame(title: "Keyboard shortcuts", systemImage: "keyboard", onClose: { dismiss() }) {
        ScrollView { list }
          .frame(minHeight: 420)
      }
      .frame(minWidth: 460)
    case .irc:
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("/help shortcuts").font(Theme.font(18, weight: .bold)).foregroundStyle(irc.ember)
          Spacer()
          Button("[x]") { dismiss() }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
        }
        ScrollView { list }
      }
      .font(Theme.font(13))
      .padding(24)
      .frame(minWidth: 460, minHeight: 480)
      .background(irc.buffer)
      .preferredColorScheme(.dark)
    }
  }

  private var list: some View {
    VStack(alignment: .leading, spacing: look == .suite ? Spacing.lg : 12) {
      ForEach(ShortcutCatalog.groups) { group in
        VStack(alignment: .leading, spacing: look == .suite ? Spacing.xs : 4) {
          Text(group.name)
            .font(look == .suite ? DesignFont.detail : Theme.font(12, weight: .bold))
            .foregroundStyle(look == .suite ? AnyShapeStyle(.secondary) : AnyShapeStyle(irc.dim))
          ForEach(group.rows, id: \.self) { row in
            HStack {
              Text(row.action)
              Spacer(minLength: Spacing.md)
              HStack(spacing: 2) {
                ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                  Text(key)
                    .font(look == .suite ? DesignFont.monoDetail : Theme.font(11))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).strokeBorder(look == .suite ? AnyShapeStyle(.tertiary) : AnyShapeStyle(irc.faint)))
                }
              }
            }
            .font(look == .suite ? DesignFont.body : Theme.font(13))
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension View {
  /**
   * What a room's commands and actions ask for, the same in both themes: the file picker, a snippet,
   * a report, keyboard shortcuts, and the question before deleting a message.
   */
  /**
   * `active` false leaves the requests to another view, as the conversation does to its thread while
   * the thread is a sheet over it on a phone, where the conversation can't show anything more.
   */
  func roomRequests(_ room: RoomModel, composer: ComposerModel, printsShortcuts: Bool = false, active: Bool = true) -> some View {
    modifier(RoomRequests(room: room, composer: composer, printsShortcuts: printsShortcuts, active: active))
  }
}

private struct RoomRequests: ViewModifier {
  @Bindable var room: RoomModel
  let composer: ComposerModel
  let printsShortcuts: Bool
  let active: Bool
  #if os(iOS)
  @State private var photos: [PhotosPickerItem] = []
  #endif
  @State private var boost = String()

  func body(content: Content) -> some View {
    content
      .alert("New boost", isPresented: Binding(get: { if active, case .boost = room.request { true } else { false } }, set: { if !$0 { room.request = nil } })) {
        TextField("Emoji or a word", text: $boost)
        Button("Boost") {
          if case let .boost(message) = room.request { room.react(boost, to: message) }
          boost = String()
          room.request = nil
        }
        Button("Cancel", role: .cancel) {
          boost = String()
          room.request = nil
        }
      } message: {
        Text("Up to \(EmberLimits.maxBoostLength) characters")
      }
      #if os(iOS)
      .photosPicker(isPresented: shows(.photos), selection: $photos, matching: .any(of: [.images, .videos]), photoLibrary: .shared())
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
      .fileImporter(isPresented: shows(.upload), allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
        switch result {
        case let .success(urls): composer.pick(urls: urls)
        case let .failure(error):
          logger.error("The file picker failed: \(error.localizedDescription, privacy: .public)")
          room.warn(error.localizedDescription)
        }
      }
      .sheet(isPresented: Binding(get: { if active, case .snippet = room.request { true } else { false } }, set: { if !$0 { room.request = nil } })) {
        if case let .snippet(title) = room.request { SnippetSheet(composer: composer, title: title) }
      }
      .sheet(isPresented: Binding(get: { if active, case .report = room.request { true } else { false } }, set: { if !$0 { room.request = nil } })) {
        if case let .report(message) = room.request { ReportSheet(room: room, message: message) }
      }
      .sheet(isPresented: Binding(get: { active && room.request == .shortcuts && !printsShortcuts }, set: { if !$0 { room.request = nil } })) {
        ShortcutsSheet()
      }
      .confirmationDialog(
        MessageAction.deleteQuestion, isPresented: Binding(get: { if active, case .delete = room.request { true } else { false } }, set: { if !$0 { room.request = nil } }),
        titleVisibility: .visible
      ) {
        Button("Delete message", role: .destructive) {
          if case let .delete(message) = room.request { room.delete(message) }
          room.request = nil
        }
      }
      .onChange(of: room.request) { _, request in
        guard active, request == .shortcuts, printsShortcuts else { return }
        room.print(ShortcutCatalog.lines)
        room.request = nil
      }
  }

  private func shows(_ request: ComposerRequest) -> Binding<Bool> {
    Binding(get: { active && room.request == request }, set: { if !$0, room.request == request { room.request = nil } })
  }
}

#if os(iOS)
/**
 * Photos and videos picked from the photo library, as files to send, as Safari's file input gives them:
 * a HEIC photo as a JPEG, which every browser shows, anything else as it is; a video as its file.
 */
enum PhotoLibrary {
  struct Failure: LocalizedError {
    var errorDescription: String?
  }

  /** A video, copied out of the photo library before it's gone. */
  private struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
      FileRepresentation(importedContentType: .movie) { received in
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(received.file.lastPathComponent)
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: received.file, to: copy)
        return Movie(url: copy)
      }
    }
  }

  static func files(_ items: [PhotosPickerItem]) async throws -> [PickedFile] {
    var files: [PickedFile] = []
    for (index, item) in items.enumerated() {
      if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
        guard let movie = try await item.loadTransferable(type: Movie.self) else { throw Failure(errorDescription: "A video couldn't be read.") }
        guard let file = PickedFile.at(movie.url) else { throw Failure(errorDescription: "A video couldn't be read.") }
        files.append(file)
        continue
      }
      guard let data = try await item.loadTransferable(type: Data.self) else { throw Failure(errorDescription: "A photo couldn't be read.") }
      if item.supportedContentTypes.contains(where: { $0.conforms(to: .heic) || $0.conforms(to: .heif) }) {
        let jpeg = try jpeg(from: data)
        files.append(PickedFile(name: "Photo \(index + 1).jpeg", type: "image/jpeg", size: jpeg.count, source: .data(jpeg)))
        continue
      }
      guard let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }), let ext = type.preferredFilenameExtension, let mime = type.preferredMIMEType else {
        throw Failure(errorDescription: "That photo's type isn't one ircX can send.")
      }
      files.append(PickedFile(name: "Photo \(index + 1).\(ext)", type: mime, size: data.count, source: .data(data)))
    }
    return files
  }

  private static func jpeg(from heic: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(heic as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw Failure(errorDescription: "A photo couldn't be read.")
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
    let out = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure(errorDescription: "A photo couldn't be converted.") }
    var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
    if let orientation = (properties as? [CFString: Any])?[kCGImagePropertyOrientation] { options[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw Failure(errorDescription: "A photo couldn't be converted.") }
    return out as Data
  }
}
#endif
