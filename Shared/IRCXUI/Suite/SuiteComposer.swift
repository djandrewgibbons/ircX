import AppCoreUI
import EmberKit
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

/**
 * The composer under a room or a thread (web `Composer`): who's typing, the files picked, why something
 * was given back, the @ prompt, then a glass card of the formatting row, the rich editor and its
 * buttons: Attach, Show formatting, Emoji, Mention someone, Also send in a thread, and Send.
 */
struct SuiteComposer: View {
  let app: AppModel
  let session: InstanceSession
  let room: RoomModel
  let placeholder: String
  var parentId: String?
  @State private var controller = RichEditorController()
  @State private var previews = DraftPreviews()
  @State private var mentionIndex = 0
  @State private var picking = false
  @State private var writingSnippet = false
  @State private var linking: LinkDraft?
  @State private var showingEmoji = false
  #if os(iOS)
  @State private var pickingPhotos = false
  @State private var photos: [PhotosPickerItem] = []
  #endif
  #if os(macOS)
  @AppStorage("composerFormatting") private var showsFormatting = true
  #else
  @AppStorage("composerFormatting") private var showsFormatting = false
  #endif

  init(app: AppModel, session: InstanceSession, room: RoomModel, placeholder: String, parentId: String? = nil, draft: String = "", refusal: String? = nil) {
    self.app = app
    self.session = session
    self.room = room
    self.placeholder = placeholder
    self.parentId = parentId
    if !draft.isEmpty {
      let composer = room.composer(thread: parentId)
      composer.replace(with: ComposerDocument(plain: draft))
      composer.refusal = refusal
    }
  }

  private var composer: ComposerModel { room.composer(thread: parentId) }

  private var canSend: Bool { !room.offline && (!composer.document.isBlank || !composer.files.isEmpty) }

  var body: some View {
    let composer = composer
    VStack(alignment: .leading, spacing: Spacing.xs) {
      typingLine
      ForEach(composer.refused, id: \.self) { why in
        Text(why).font(DesignFont.detail).foregroundStyle(SemanticColor.destructive).padding(.leading, Spacing.lg)
      }
      if !composer.files.isEmpty { chips(composer) }
      if let refusal = composer.refusal {
        Text(refusal).font(DesignFont.detail).foregroundStyle(SemanticColor.destructive).padding(.leading, Spacing.lg)
      }
      if composer.mentionQuery != nil {
        SuiteMentionPrompt(session: session, composer: composer, selected: mentionIndex) { controller.pickMention($0) }
      }
      VStack(alignment: .leading, spacing: Spacing.sm) {
        if showsFormatting {
          SuiteFormattingRow(controller: controller)
        }
        SuiteRichEditor(controller: controller, placeholder: placeholder, document: composer.document, revision: composer.revision, actions: actions(composer))
        buttons(composer)
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.md)
      .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
      if let shown = composer.linkPreview {
        // The pasted link's preview, which goes below its paragraph unless it's taken out.
        SuiteLinkPreview(session: session, preview: DisplayPreview(shown.preview))
          .overlay(alignment: .topTrailing) {
            PaneIconButton(systemImage: "xmark", help: "Remove preview") { previews.remove(from: composer) }
              .padding(Spacing.xs)
          }
          .padding(.horizontal, Spacing.lg)
      }
    }
    .padding(Spacing.lg)
    .dropDestination(for: URL.self) { urls, _ in
      composer.pick(urls: urls)
      return true
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
    .sheet(isPresented: $writingSnippet, onDismiss: controller.focus) {
      SnippetSheet(composer: composer).environment(\.appTheme, .suite)
    }
    .sheet(item: $linking, onDismiss: controller.focus) { draft in
      SuiteLinkSheet(draft: draft) { text, url in controller.setLink(text: text, url: url) }
    }
    .onChange(of: room.timeline.rewrites) { _, rewrites in
      if parentId == nil, !rewrites.isEmpty { takeBack() }
    }
    .onChange(of: room.thread?.rewrites) { _, rewrites in
      if parentId != nil, rewrites?.isEmpty == false { takeBack() }
    }
    .onChange(of: composer.candidates) { _, _ in mentionIndex = 0 }
    #if os(iOS)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        if controller.focused { SuiteFormattingRow(controller: controller, compact: true) }
      }
    }
    #endif
  }

  // MARK: Parts

  private var typingLine: some View {
    // Always laid out, so the composer doesn't move as people start and stop typing.
    HStack(spacing: Spacing.xs) {
      if let typing = parentId == nil ? room.typingText : room.threadTypingText {
        SuiteTypingDots()
        Text(typing)
      } else {
        Text(" ")
      }
    }
    .font(DesignFont.detail)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .truncationMode(.tail)
    .padding(.leading, Spacing.lg)
  }

  private func chips(_ composer: ComposerModel) -> some View {
    FlowLayout(hSpacing: Spacing.xs, vSpacing: Spacing.xs) {
      ForEach(composer.files) { file in
        HStack(spacing: Spacing.xs) {
          if file.isImage {
            PickedFileThumbnail(file: file)
          } else {
            Image(systemName: "doc").foregroundStyle(.secondary)
          }
          Text(file.name)
            .font(DesignFont.detail)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 220)
          PaneIconButton(systemImage: "xmark.circle.fill", help: "Remove \(file.name)") { composer.remove(file) }
        }
        .padding(.leading, Spacing.sm)
        .background(Capsule().fill(SemanticColor.secondaryFill))
      }
    }
    .padding(.horizontal, Spacing.lg)
  }


  private func buttons(_ composer: ComposerModel) -> some View {
    HStack(spacing: Spacing.xs) {
      Menu {
        Button("Text snippet", systemImage: "doc.plaintext") { writingSnippet = true }
          .keyboardShortcut(.return, modifiers: [.command, .shift])
        #if os(iOS)
        Button("Photo library", systemImage: "photo.on.rectangle") { pickingPhotos = true }
        Button("Upload a file", systemImage: "arrow.up.doc") { picking = true }
          .keyboardShortcut("o")
        #else
        Button("Upload from your computer", systemImage: "arrow.up.doc") { picking = true }
          .keyboardShortcut("o")
        #endif
      } label: {
        Image(systemName: "plus")
      }
      .menuIndicator(.hidden)
      .buttonStyle(IconHoverButtonStyle())
      .fixedSize()
      .help("Attach")
      .disabled(room.offline)
      PaneIconButton(systemImage: "textformat", help: showsFormatting ? "Hide formatting" : "Show formatting") { showsFormatting.toggle() }
      PaneIconButton(systemImage: "face.smiling", help: "Emoji") { showingEmoji = true }
        .disabled(room.offline)
        .popover(isPresented: $showingEmoji, arrowEdge: .top) {
          SuiteEmojiPanel { emoji in
            controller.insert(emoji)
            showingEmoji = false
          }
        }
      PaneIconButton(systemImage: "at", help: "Mention someone") { controller.startMention() }
        .disabled(room.offline)
      if parentId != nil {
        Toggle(room.room.isDirect ? "Also send as direct message" : "Also send to #\(room.title)", isOn: Bindable(composer).alsoSend)
          .font(DesignFont.detail)
          #if os(macOS)
          .toggleStyle(.checkbox)
          #endif
      }
      Spacer(minLength: Spacing.sm)
      Button("Send message", systemImage: "paperplane.fill", action: send)
        .labelStyle(.iconOnly)
        .buttonStyle(.glassProminent)
        .disabled(!canSend)
        .help("Send message")
    }
  }

  // MARK: Actions

  private func actions(_ composer: ComposerModel) -> EditorActions {
    var actions = EditorActions()
    actions.changed = { document in
      composer.document = document
      if parentId == nil, !document.isBlank { room.typed() }
    }
    actions.submit = send
    actions.upArrow = {
      guard let message = room.newestOwn(inThread: parentId != nil) else { return false }
      room.editing.insert(message.id)
      return true
    }
    actions.files = { composer.pick($0) }
    actions.pastedLink = { previews.pasted($0, api: session.api, room: room, composer: composer) }
    actions.mentionQuery = { composer.lookUpMentions($0, api: session.api, room: room.id) }
    actions.mentionKey = { SuiteMentionPrompt.key($0, composer: composer, controller: controller, index: $mentionIndex) }
    actions.linkDialog = {
      let selected = controller.linkSelection()
      linking = LinkDraft(text: selected.text, url: selected.url)
    }
    actions.pickFiles = { picking = true }
    actions.snippet = { writingSnippet = true }
    #if os(iOS)
    actions.returnSends = false
    #endif
    return actions
  }

  /** Puts a message the room refused for what it says back in an empty composer, for its writer to change. */
  private func takeBack() {
    let empty = composer.document.isBlank
    let given = parentId == nil ? room.takeBack(composerEmpty: empty) : room.takeBackReply(composerEmpty: empty)
    if let given {
      composer.giveBack(given)
      controller.focus()
    }
  }

  private func send() {
    let composer = composer
    // A slash command typed here runs as the input line's would.
    let text = composer.document.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    if parentId == nil, composer.files.isEmpty, composer.document.lines.count == 1, text.hasPrefix("/"), let command = InputCommand.parse(text) {
      if case .say = command {} else {
        composer.clear()
        Commander.run(command, app: app, session: session, room: room)
        return
      }
    }
    // The pasted link's preview stays with what's written until it has gone.
    if room.submit(composer, parentId: parentId, previews: previews.sending(composer)) {
      previews.sent()
      controller.focus()
    }
  }
}

/** The @ prompt over an editor (web Lexxy prompt): whom `/api/autocompletable/users` offers, the one the arrows are on lit. */
struct SuiteMentionPrompt: View {
  let session: InstanceSession
  let composer: ComposerModel
  let selected: Int
  let pick: (MentionPromptItem) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if composer.candidates.isEmpty {
        Text(composer.searchedMentions ? "No matches" : " ")
          .font(DesignFont.detail)
          .foregroundStyle(.secondary)
          .padding(Spacing.md)
      }
      ForEach(Array(composer.candidates.enumerated()), id: \.element.id) { index, item in
        SelectableListRow(isSelected: index == selected) {
          pick(item)
        } label: {
          HStack(spacing: Spacing.sm) {
            SuiteAvatar(session: session, user: User(id: item.id, name: item.name), size: 20)
            Text(item.name).font(DesignFont.body)
            if let username = item.username { Text("@" + username).font(DesignFont.detail).foregroundStyle(.secondary) }
            if item.agent { StatusCapsule(text: "Agent", tint: SemanticColor.accent, help: "Agent") }
          }
        }
      }
    }
    .frame(maxWidth: 360, alignment: .leading)
    .padding(Spacing.xs)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .padding(.horizontal, Spacing.lg)
  }

  /** ↑, ↓, Return, Tab and Esc while the prompt's open; true if it took the key. */
  @MainActor
  static func key(_ key: MentionKey, composer: ComposerModel, controller: RichEditorController, index: Binding<Int>) -> Bool {
    guard composer.mentionQuery != nil else { return false }
    switch key {
    case .up: index.wrappedValue = max(0, index.wrappedValue - 1)
    case .down: index.wrappedValue = min(max(0, composer.candidates.count - 1), index.wrappedValue + 1)
    case .pick:
      guard composer.candidates.indices.contains(index.wrappedValue) else { return !composer.candidates.isEmpty }
      controller.pickMention(composer.candidates[index.wrappedValue])
    case .close: composer.closeMentions()
    }
    return true
  }
}

/** A picked picture's chip shows the picture (web `FileChip`): a pasted one at once, a file's read off the main thread. */
struct PickedFileThumbnail: View {
  let file: PickedFile
  @State private var image: CGImage?

  init(file: PickedFile) {
    self.file = file
    if case .data = file.source { _image = State(initialValue: Uploader.thumbnail(of: file, pixels: 96)) }
  }

  var body: some View {
    Group {
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFill()
      } else {
        Image(systemName: "photo").foregroundStyle(.secondary)
      }
    }
    .frame(width: 24, height: 24)
    .clipShape(RoundedRectangle(cornerRadius: Radius.control / 2))
    .task(id: file.id) {
      guard image == nil, case .url = file.source else { return }
      let file = file
      image = await Task.detached { Uploader.thumbnail(of: file, pixels: 96) }.value
    }
  }
}

/** The formatting row (web `FormattingToolbar`): marks, the paragraph menu, link, lists, quote, code, code block and divider. */
struct SuiteFormattingRow: View {
  let controller: RichEditorController
  var compact = false

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.xxs) {
        ForEach([FormattingCommand.bold, .italic, .underline, .strikethrough]) { button($0) }
        if !compact { paragraphMenu }
        Divider().frame(height: 16)
        ForEach([FormattingCommand.link, .orderedList, .bulletedList]) { button($0) }
        Divider().frame(height: 16)
        ForEach([FormattingCommand.blockquote, .code, .codeBlock]) { button($0) }
        if !compact {
          Button {
            controller.setBlock(.rule)
          } label: {
            Image(systemName: "minus")
          }
          .buttonStyle(IconHoverButtonStyle())
          .help("Divider")
          .disabled(controller.block.isCode)
        }
      }
    }
    .font(DesignFont.body)
  }

  private func active(_ command: FormattingCommand) -> Bool {
    switch command {
    case .bold: controller.marks.contains(.bold)
    case .italic: controller.marks.contains(.italic)
    case .underline: controller.marks.contains(.underline)
    case .strikethrough: controller.marks.contains(.strike)
    case .code: controller.marks.contains(.code)
    case .link: controller.inLink
    case .orderedList: controller.block == .ordered
    case .bulletedList: controller.block == .bullet
    case .blockquote: controller.block == .quote
    case .codeBlock: controller.block.isCode
    }
  }

  private func button(_ command: FormattingCommand) -> some View {
    Button {
      controller.perform(command)
    } label: {
      Image(systemName: command.symbol)
        .foregroundStyle(active(command) ? AnyShapeStyle(SemanticColor.accent) : AnyShapeStyle(.secondary))
        .frame(width: 22, height: 22)
    }
    .buttonStyle(IconHoverButtonStyle())
    .help(command.help)
    .accessibilityLabel(command.name)
    .disabled(command.notInCodeBlocks && controller.block.isCode)
  }

  private var paragraphMenu: some View {
    Menu {
      ForEach([(ComposerBlock.paragraph, "Paragraph"), (.heading(1), "Big heading"), (.heading(2), "Medium heading"), (.heading(3), "Small heading")], id: \.1) { block, name in
        Button {
          controller.setBlock(block)
        } label: {
          if controller.block == block { Label(name, systemImage: "checkmark") } else { Text(name) }
        }
      }
    } label: {
      Image(systemName: "textformat.size")
    }
    .menuIndicator(.hidden)
    .buttonStyle(IconHoverButtonStyle())
    .fixedSize()
    .help("Paragraph style")
  }
}

/** What the Link dialog starts from: the selected text, and the link it's in, if it's in one. */
struct LinkDraft: Identifiable {
  let id = UUID()
  var text: String
  var url: String?
}

/** Add link / Edit link (web `LinkDialog`): Text and Link; Remove link when editing one. */
struct SuiteLinkSheet: View {
  let draft: LinkDraft
  let save: (String, String?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var text: String
  @State private var address: String

  init(draft: LinkDraft, save: @escaping (String, String?) -> Void) {
    self.draft = draft
    self.save = save
    _text = State(initialValue: draft.text)
    var address = String()
    if let url = draft.url { address = url }
    _address = State(initialValue: address)
  }

  var body: some View {
    SheetFrame(title: draft.url == nil ? "Add link" : "Edit link", systemImage: "link") {
      VStack(alignment: .leading, spacing: Spacing.md) {
        LabeledField("Text") { TextField("Text", text: $text).textFieldStyle(.plain) }
        LabeledField("Link") {
          TextField("https://", text: $address)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .onSubmit(commit)
        }
      }
    } footer: {
      EditorFooter(
        canSave: !address.trimmingCharacters(in: .whitespaces).isEmpty, canCancel: true, saveHelp: "Save", onCancel: { dismiss() }, onSave: commit
      ) {
        if draft.url != nil {
          Button("Remove link", role: .destructive) {
            save(text, nil)
            dismiss()
          }
        }
      }
    }
    .frame(minWidth: 420)
  }

  private func commit() {
    let link = LinkAddress.normalized(address)
    guard !link.isEmpty else { return }
    save(text.trimmingCharacters(in: .whitespaces).isEmpty ? link : text, link)
    dismiss()
  }
}

/** `linkAddress`: an address without a scheme becomes https; `scheme://`, `mailto:` and `tel:` stay. */
enum LinkAddress {
  static func normalized(_ typed: String) -> String {
    let address = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !address.isEmpty else { return address }
    if address.firstMatch(of: #/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//#) != nil || address.lowercased().hasPrefix("mailto:") || address.lowercased().hasPrefix("tel:") {
      return address
    }
    return "https://" + address
  }
}

/** The Emoji panel (web `EmojiPanel`): search all emoji, a grid by group, and the skin tone. */
struct SuiteEmojiPanel: View {
  let pick: (String) -> Void
  @State private var query = ""
  @AppStorage("emojiSkinTone") private var tone: EmojiCatalog.SkinTone = .none
  @State private var hovered: EmojiCatalog.Emoji?

  private let columns = Array(repeating: GridItem(.fixed(28), spacing: 2), count: 9)

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      TextField("Search all emoji", text: $query)
        .textFieldStyle(.roundedBorder)
      ScrollView {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
          if query.isEmpty {
            ForEach(EmojiCatalog.groups) { group in
              Section {
                ForEach(group.emoji) { cell($0) }
              } header: {
                Text(group.name).font(DesignFont.detail).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          } else {
            ForEach(EmojiCatalog.search(query)) { cell($0) }
          }
        }
      }
      HStack {
        Text(hovered?.name ?? " ").font(DesignFont.detail).foregroundStyle(.secondary).lineLimit(1)
        Spacer()
        Picker("Skin tone", selection: $tone) {
          ForEach(EmojiCatalog.SkinTone.allCases) { Text($0.sample).tag($0).help($0.label) }
        }
        .labelsHidden()
        .fixedSize()
      }
    }
    .padding(Spacing.md)
    .frame(width: 300, height: 380)
  }

  private func cell(_ emoji: EmojiCatalog.Emoji) -> some View {
    Button {
      pick(emoji.glyph(in: tone))
    } label: {
      Text(emoji.glyph(in: tone)).font(DesignFont.title).frame(width: 28, height: 28)
    }
    .buttonStyle(IconHoverButtonStyle())
    .help(emoji.name)
    .onHover { if $0 { hovered = emoji } }
  }
}
