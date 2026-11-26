import EmberKit
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/** A picture on an instance, fetched with its session, since Ember serves files only to who may see them. */
struct AuthImage: View {
  let api: EmberAPI
  let path: String
  @State private var image: PlatformImage?
  @State private var failed = false

  init(api: EmberAPI, path: String) {
    self.api = api
    self.path = path
    // One already loaded shows at once, as it does scrolling back to it.
    self.image = ImageCache.shared.object(forKey: api.url(path) as NSURL)
  }

  var body: some View {
    Group {
      if let image {
        #if os(macOS)
        Image(nsImage: image).resizable().scaledToFit()
        #else
        Image(uiImage: image).resizable().scaledToFit()
        #endif
      } else if failed {
        EmptyView()
      } else {
        Rectangle().fill(.quaternary).frame(width: 160, height: 100)
      }
    }
    .task(id: path) { await load() }
  }

  private func load() async {
    let url = api.url(path)
    if let cached = ImageCache.shared.object(forKey: url as NSURL) {
      image = cached
      return
    }
    let loaded: PlatformImage
    do {
      guard let decoded = PlatformImage(data: try await api.data(at: path)) else {
        logger.error("A picture didn't decode")
        failed = true
        return
      }
      loaded = decoded
    } catch {
      logger.error("A picture didn't load: \(error.localizedDescription, privacy: .public)")
      failed = true
      return
    }
    ImageCache.shared.setObject(loaded, forKey: url as NSURL)
    image = loaded
  }
}

enum ImageCache {
  nonisolated(unsafe) static let shared: NSCache<NSURL, PlatformImage> = {
    let cache = NSCache<NSURL, PlatformImage>()
    cache.countLimit = 300
    return cache
  }()
}

enum Pasteboard {
  static func copy(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
  }

  /**
   * The files a paste would put in a message, as the web picks pasted files rather than writing them:
   * files copied in Finder or Files, or a picture copied without text; nil where the paste is text.
   */
  static func pastedFiles() -> [PickedFile]? {
    #if os(macOS)
    let pasteboard = NSPasteboard.general
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
      return urls.compactMap(PickedFile.at)
    }
    guard pasteboard.string(forType: .string) == nil, let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return nil }
    let png = pasteboard.data(forType: .png) != nil
    return [PickedFile(name: png ? "Pasted image.png" : "Pasted image.tiff", type: png ? "image/png" : "image/tiff", size: data.count, source: .data(data))]
    #else
    let pasteboard = UIPasteboard.general
    if let urls = pasteboard.urls?.filter(\.isFileURL), !urls.isEmpty { return urls.compactMap(PickedFile.at) }
    guard !pasteboard.hasStrings else { return nil }
    var files: [PickedFile] = []
    for (index, item) in pasteboard.items.enumerated() {
      // Each copied file is an item: its data under its type, which names it.
      guard let (identifier, value) = item.first(where: { UTType($0.key)?.conforms(to: .data) == true }), let type = UTType(identifier) else { continue }
      let data: Data
      if let bytes = value as? Data {
        data = bytes
      } else if let image = value as? UIImage, let png = image.pngData() {
        data = png
      } else {
        logger.error("A pasted item of type \(identifier, privacy: .public) couldn't be read")
        continue
      }
      let isImage = type.conforms(to: .image)
      let png = value is UIImage
      guard let ext = png ? "png" : type.preferredFilenameExtension, let mime = png ? "image/png" : type.preferredMIMEType else {
        logger.error("A pasted item of type \(identifier, privacy: .public) has no file type")
        continue
      }
      let name = (isImage ? "Pasted image" : "Pasted file") + (index > 0 ? " \(index + 1)" : "") + "." + ext
      files.append(PickedFile(name: name, type: mime, size: data.count, source: .data(data)))
    }
    return files.isEmpty ? nil : files
    #endif
  }
}

enum Clock {
  static func time(_ date: Date, seconds: Bool) -> String {
    let formatter = seconds ? withSeconds : withoutSeconds
    return formatter.string(from: date)
  }

  private static let withSeconds: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
  }()

  private static let withoutSeconds: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
  }()

  static func day(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
  }
}

extension Int {
  var byteText: String { ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file) }
}
