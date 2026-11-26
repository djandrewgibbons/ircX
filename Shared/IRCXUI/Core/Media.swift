import AVKit
import EmberKit
import OSLog
import SwiftUI

/**
 * An image another site serves, as a link preview's or a bot card's is: loaded with no cookies and no
 * referrer, so the site doesn't learn which Ember shows it (web `RemoteImage`).
 */
struct RemoteImage: View {
  let url: String
  var fill = false
  @State private var image: PlatformImage?
  @State private var failed = false

  var body: some View {
    Group {
      if let image {
        Self.image(image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
      } else if failed {
        EmptyView()
      } else {
        Color.clear
      }
    }
    .task(id: url) { await load() }
  }

  static func image(_ image: PlatformImage) -> Image {
    #if os(macOS)
    Image(nsImage: image)
    #else
    Image(uiImage: image)
    #endif
  }

  /** An ephemeral session: nothing it fetches sends or keeps cookies, and URLSession sends no referrer. */
  static let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.httpCookieStorage = nil
    return URLSession(configuration: config)
  }()

  private func load() async {
    guard let address = URL(string: url), address.scheme == "https" || address.scheme == "http" else {
      failed = true
      return
    }
    if let cached = ImageCache.shared.object(forKey: address as NSURL) {
      image = cached
      return
    }
    do {
      let (data, _) = try await Self.session.data(from: address)
      guard let loaded = PlatformImage(data: data) else {
        logger.error("An image at \(address.host() ?? "another site", privacy: .public) didn't decode")
        failed = true
        return
      }
      ImageCache.shared.setObject(loaded, forKey: address as NSURL)
      image = loaded
    } catch {
      logger.error("An image didn't load: \(error.localizedDescription, privacy: .public)")
      failed = true
    }
  }
}

/** What loads a file a message holds near the view, once: its text, or an SVG's picture (attachment.tsx `useLoadedNearView`). */
@MainActor
enum FileLoads {
  /** Text files' text as loaded, by file, so scrolling back shows it at once. */
  private(set) static var texts: [String: (shown: String, copied: String)] = [:]
  /** SVGs as loaded, by file. */
  static let svgs: NSCache<NSString, PlatformImage> = NSCache()

  /** A text file's text as it loaded before, if it did. */
  static func loadedText(_ file: StoredFile) -> (shown: String, copied: String)? { texts[file.id] }

  /** An SVG as it loaded before, if it did. */
  static func loadedSVG(_ file: StoredFile) -> PlatformImage? { svgs.object(forKey: file.id as NSString) }

  /** Keeps a file's text as loaded. */
  static func keep(_ text: (shown: String, copied: String), for file: StoredFile) { texts[file.id] = text }

  /** A text file's text as it shows, and as Copy copies it, or nil for bytes that aren't text. */
  static func text(_ file: StoredFile, api: EmberAPI) async -> (shown: String, copied: String)? {
    if let kept = texts[file.id] { return kept }
    do {
      let data = try await api.data(at: file.downloadUrl)
      guard let text = TextPreview.shown(data) else {
        logger.info("\(file.name, privacy: .private) isn't text that shows")
        return nil
      }
      keep(text, for: file)
      return text
    } catch {
      logger.error("A file's text didn't load: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /** An SVG as a picture, once it decodes; nil for one that doesn't, which keeps its card alone. */
  static func svg(_ file: StoredFile, api: EmberAPI) async -> PlatformImage? {
    if let kept = loadedSVG(file) { return kept }
    do {
      let data = try await api.data(at: file.downloadUrl)
      guard data.count <= Files.maxPreviewSize, let image = PlatformImage(data: data) else {
        logger.info("\(file.name, privacy: .private) didn't decode as a picture")
        return nil
      }
      svgs.setObject(image, forKey: file.id as NSString)
      return image
    } catch {
      logger.error("An SVG didn't load: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}

/** A picture to show in the image viewer, with the file it's of. */
struct ViewedImage: Identifiable, Hashable {
  /** The picture's path on the instance. */
  var path: String
  var name: String
  var downloadPath: String
  var id: String { path }
}

/**
 * The image viewer (web `Lightbox`): the picture as large as fits, with Close, Download and Share in the
 * corners. Escape closes it. IRC Classic shows it chromeless on its buffer's black.
 */
struct ImageViewer: View {
  let api: EmberAPI
  let image: ViewedImage
  var classic = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(\.theme) private var theme
  @State private var zoom: CGFloat = 1

  var body: some View {
    ZStack {
      (classic ? theme.buffer : Color.black.opacity(0.92)).ignoresSafeArea()
      AuthImage(api: api, path: image.path)
        .scaleEffect(zoom)
        .gesture(MagnifyGesture().onChanged { zoom = max(1, $0.magnification) }.onEnded { _ in withAnimation { zoom = 1 } })
        .accessibilityLabel(image.name)
        .padding()
    }
    .overlay(alignment: .topTrailing) {
      corner("Close image viewer", systemImage: "xmark") { dismiss() }
        .keyboardShortcut(.cancelAction)
    }
    .overlay(alignment: .bottomTrailing) {
      corner("Download file", systemImage: "arrow.down.to.line") { openURL(api.url(image.downloadPath)) }
    }
    .overlay(alignment: .topLeading) {
      ShareLink(item: api.url(image.downloadPath)) {
        Label("Share file", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
      }
      .modifier(CornerStyle(classic: classic))
    }
    #if os(macOS)
    .frame(minWidth: 640, idealWidth: 960, minHeight: 480, idealHeight: 720)
    #endif
  }

  private func corner(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage).labelStyle(.iconOnly)
    }
    .help(title)
    .modifier(CornerStyle(classic: classic))
  }
}

private struct CornerStyle: ViewModifier {
  let classic: Bool
  @Environment(\.theme) private var theme

  func body(content: Content) -> some View {
    if classic {
      content.buttonStyle(.plain).foregroundStyle(theme.text).font(Theme.font(14)).padding()
    } else {
      content.buttonStyle(.glass).controlSize(.large).padding()
    }
  }
}

extension View {
  /** Presents the image viewer for `image` while it's set. */
  func imageViewer(_ image: Binding<ViewedImage?>, api: EmberAPI, classic: Bool = false) -> some View {
    #if os(macOS)
    sheet(item: image) { ImageViewer(api: api, image: $0, classic: classic) } // suite-ui:ok
    #else
    fullScreenCover(item: image) { ImageViewer(api: api, image: $0, classic: classic) }
    #endif
  }
}

/** A video that plays in place, from its signed address, behind its poster (web `VideoPreview`). */
struct InlineVideo: View {
  let api: EmberAPI
  let file: StoredFile
  @State private var player: AVPlayer?

  var body: some View {
    let size = AttachmentShown.shownSize(file)
    Group {
      if let player {
        VideoPlayer(player: player)
      } else {
        ZStack {
          if let poster = file.previewUrl {
            AuthImage(api: api, path: poster)
          } else {
            Color.black
          }
          Button {
            let player = AVPlayer(url: api.url(file.url))
            self.player = player
            player.play()
          } label: {
            Label("Play \(file.name)", systemImage: "play.circle.fill").labelStyle(.iconOnly).font(.largeTitle)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.white)
        }
      }
    }
    .aspectRatio(size.map { $0.width / $0.height } ?? 16 / 9, contentMode: .fit)
    .frame(maxWidth: size.map { $0.width / 2 } ?? 360)
    .accessibilityLabel(file.name)
  }
}
