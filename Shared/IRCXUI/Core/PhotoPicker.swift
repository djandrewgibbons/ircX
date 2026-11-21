import AppCoreUI
import EmberKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/**
 * Choosing a photo for an avatar (web `PhotoField`, `PicturePicker`): Photos on iOS, a file on the Mac,
 * refused over 16 MB, and sent with its variant within 512 by 512.
 */
struct PhotoPickerButton<Label: View>: View {
  let onPick: (ChosenPhoto) -> Void
  let onRefused: (String) -> Void
  @ViewBuilder var label: () -> Label
  @State private var picking = false
  #if os(iOS)
  @State private var item: PhotosPickerItem?
  #endif

  var body: some View {
    #if os(iOS)
    PhotosPicker(selection: $item, matching: .images, label: label)
      .onChange(of: item) { _, picked in
        guard let picked else { return }
        item = nil
        Task { await load(picked) }
      }
    #else
    Button(action: { picking = true }, label: label)
      .fileImporter(isPresented: $picking, allowedContentTypes: [.image]) { result in
        switch result {
        case let .success(url): read(url)
        case let .failure(error):
          logger.error("Choosing a photo failed: \(error.localizedDescription, privacy: .public)")
          onRefused(error.localizedDescription)
        }
      }
    #endif
  }

  #if os(iOS)
  private func load(_ picked: PhotosPickerItem) async {
    do {
      guard let data = try await picked.loadTransferable(type: Data.self) else {
        onRefused("That photo couldn't be read.")
        return
      }
      let type = picked.supportedContentTypes.first { $0.conforms(to: .image) }
      guard let type, let mime = type.preferredMIMEType, let ext = type.preferredFilenameExtension else {
        onRefused("That photo couldn't be read.")
        return
      }
      chosen(data, name: "photo.\(ext)", type: mime)
    } catch {
      logger.error("Loading a photo failed: \(error.localizedDescription, privacy: .public)")
      onRefused(error.localizedDescription)
    }
  }
  #endif

  private func read(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try Data(contentsOf: url)
      guard let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType else {
        onRefused("That file isn't a photo.")
        return
      }
      chosen(data, name: url.lastPathComponent, type: mime)
    } catch {
      logger.error("Reading a photo failed: \(error.localizedDescription, privacy: .public)")
      onRefused(error.localizedDescription)
    }
  }

  private func chosen(_ data: Data, name: String, type: String) {
    guard data.count <= Avatars.maxAvatarSize else {
      onRefused(Avatars.avatarTooLarge)
      return
    }
    onPick(Avatars.chosenPhoto(data, fileName: name, contentType: type))
  }
}

/** A photo field for a form (web `PhotoField`): the round preview, Upload photo, and Optional or why it was refused. */
struct PhotoField: View {
  @Binding var photo: ChosenPhoto?
  @Binding var refusal: String?
  /** What shows before a photo is picked, such as the person's avatar on the welcome page. */
  var current: AnyView?
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    HStack(spacing: Spacing.lg) {
      preview
        .frame(width: 64, height: 64)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: Spacing.xs) {
        PhotoPickerButton(onPick: { photo = $0; refusal = nil }, onRefused: { photo = nil; refusal = $0 }) {
          Label(look == .irc ? "[upload photo]" : "Upload Photo", systemImage: "camera")
        }
        Text(refusal ?? "Optional")
          .font(look == .irc ? Theme.font(11) : DesignFont.detail)
          .foregroundStyle(refusal == nil ? Color.secondary : SemanticColor.warning)
      }
    }
  }

  @ViewBuilder
  private var preview: some View {
    if let photo, let image = PlatformImage(data: photo.variant ?? photo.data) {
      #if os(macOS)
      Image(nsImage: image).resizable().scaledToFill()
      #else
      Image(uiImage: image).resizable().scaledToFill()
      #endif
    } else if let current {
      current
    } else {
      ZStack {
        Circle().fill(look == .irc ? irc.bar : SemanticColor.secondaryFill)
        Image(systemName: "person.fill").font(.title).foregroundStyle(.secondary)
      }
    }
  }
}
