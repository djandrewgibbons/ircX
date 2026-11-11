import EmberKit
import SwiftUI
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
    guard let data = try? await api.data(at: path), let loaded = PlatformImage(data: data) else {
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
