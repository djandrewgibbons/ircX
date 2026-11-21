import AppCoreUI
import EmberKit
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension RoomIcons {
  /** Where the instance serves icon `name` (`roomIconUrl`): Lucide's at /lucide/icons/, Iconoir's at /iconoir/icons/<variant>/. */
  static func path(_ name: String) -> String {
    guard name.hasPrefix("iconoir:") else { return "/lucide/icons/\(name).svg" }
    return "/iconoir/icons/\(name.split(separator: ":").dropFirst().joined(separator: "/")).svg"
  }

  /** A name as the picker labels it: "iconoir:regular:home" as "Home", "alarm-clock" as "Alarm Clock". */
  static func label(_ name: String) -> String {
    let last = name.split(separator: ":").last.map(String.init) ?? name
    return last.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
  }

  /** The icons the picker shows for `text` in `context` and `collection`, in the catalog's order for it (web `searchIcons`). */
  static func matching(_ text: String, context: IconContext, collection: IconCollection = .all) -> [CatalogIcon] {
    search(text, context: context, collection: collection)
  }
}

/** Room icons each instance serves, decoded once (SVG, which the 27 SDKs' images read). */
@MainActor
final class RoomIconCache {
  static let shared = RoomIconCache()
  private var images: [String: PlatformImage] = [:]
  private var loading: [String: Task<PlatformImage?, Never>] = [:]

  func cached(_ key: String) -> PlatformImage? { images[key] }

  func image(_ name: String, api: EmberAPI) async -> PlatformImage? {
    let key = api.url(RoomIcons.path(name)).absoluteString
    if let image = images[key] { return image }
    if let running = loading[key] { return await running.value }
    let load = Task<PlatformImage?, Never> {
      do {
        let data = try await api.data(at: RoomIcons.path(name))
        guard let image = PlatformImage(data: data) else {
          logger.error("Room icon \(name, privacy: .public) didn't decode")
          return nil
        }
        #if os(macOS)
        image.isTemplate = true
        return image
        #else
        return image.withRenderingMode(.alwaysTemplate)
        #endif
      } catch {
        logger.error("Room icon \(name, privacy: .public) didn't load: \(error.localizedDescription, privacy: .public)")
        return nil
      }
    }
    loading[key] = load
    let image = await load.value
    loading[key] = nil
    if let image { images[key] = image }
    return image
  }
}

/** A room's icon in the color of the text around it, or its kind's glyph for a room without one (web `RoomIcon`). */
struct RoomIconView: View {
  let api: EmberAPI
  let room: Room
  var size: CGFloat = 16
  @State private var image: PlatformImage?

  var body: some View {
    Group {
      if let image {
        #if os(macOS)
        Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
        #else
        Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
        #endif
      } else {
        Image(systemName: room.symbol).resizable().scaledToFit().padding(size * 0.08)
      }
    }
    .frame(width: size, height: size)
    .task(id: room.icon) {
      guard let icon = room.icon, !room.isDirect else {
        image = nil
        return
      }
      image = await RoomIconCache.shared.image(icon, api: api)
    }
    .accessibilityHidden(true)
  }
}

/** One icon of the catalog, for the picker. */
struct CatalogIconView: View {
  let api: EmberAPI
  let name: String
  var size: CGFloat = 20
  @State private var image: PlatformImage?

  var body: some View {
    Group {
      if let image {
        #if os(macOS)
        Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
        #else
        Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
        #endif
      } else {
        Color.clear
      }
    }
    .frame(width: size, height: size)
    .task(id: name) { image = await RoomIconCache.shared.image(name, api: api) }
  }
}

/**
 * The room form's Icon (web `IconPicker`): `#` or one of the catalog's icons, Lucide's and Iconoir's,
 * in the catalog's room order, searched by name then tag, a page at a time.
 */
struct IconPicker: View {
  let api: EmberAPI
  @Binding var icon: String?
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var choosing = false

  var body: some View {
    HStack(spacing: Spacing.md) {
      Group {
        if let icon {
          CatalogIconView(api: api, name: icon)
        } else {
          Text("#").font(look == .irc ? Theme.font(15, weight: .bold) : DesignFont.bodyEmphasized)
        }
      }
      .frame(width: 24)
      Button(icon == nil ? "Choose Icon" : "Change Icon") { choosing = true }
      if icon != nil {
        Button("Use #") { icon = nil }
      }
    }
    .popover(isPresented: $choosing) { picker }
  }

  private var picker: some View {
    IconCatalogGrid(api: api, context: .room, current: icon, choose: { picked in
      icon = picked
      choosing = false
    })
    .frame(height: 380)
    .padding(Spacing.lg)
    .frame(width: 360)
    .font(look == .irc ? Theme.font(12) : DesignFont.body)
  }
}

/**
 * The icon dialog's body (web `IconDialog`): All, Lucide and Iconoir tabs, a search of the catalog in the
 * context's order, a page of icons at a time, and, where the context has one, Default icon.
 */
struct IconCatalogGrid: View {
  static let page = 80

  let api: EmberAPI
  let context: IconContext
  let current: String?
  let choose: (String?) -> Void
  /** Default icon's title, where choosing none is choosing the default. */
  var defaultLabel: String?
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var query = ""
  @State private var collection: IconCollection = .all
  @State private var shown = Self.page

  var body: some View {
    let matches = RoomIcons.matching(query, context: context, collection: collection)
    VStack(alignment: .leading, spacing: Spacing.md) {
      if context == .navigation { Explanation(AdminText.navigationIconsRecommended) }
      Picker("Collection", selection: $collection) {
        ForEach(IconCollection.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .onChange(of: collection) { shown = Self.page }
      TextField("Search icons", text: $query, prompt: Text("Search icons, e.g. coffee or rocket"))
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
        .onChange(of: query) { shown = Self.page }
      if let defaultLabel {
        Button(defaultLabel) { choose(nil) }
      }
      if matches.isEmpty {
        Text("No icons match your search. Try another word.").foregroundStyle(.secondary)
      }
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36, maximum: 40), spacing: Spacing.sm)], spacing: Spacing.sm) {
          ForEach(matches.prefix(shown), id: \.name) { item in
            let label = RoomIcons.displayLabel(item, context: context)
            Button {
              choose(item.name)
            } label: {
              CatalogIconView(api: api, name: item.name, size: 22)
                .frame(width: 36, height: 36)
                .background(item.name == current ? selectedFill : Color.clear, in: RoundedRectangle(cornerRadius: Radius.small))
            }
            .buttonStyle(.plain)
            .help(item.collection == IconCollection.iconoir.rawValue ? "\(label) · Iconoir" : label)
            .accessibilityLabel(label)
          }
        }
        if matches.count > shown {
          Button("Show More") { shown += Self.page }
        }
      }
    }
  }

  private var selectedFill: Color { look == .irc ? irc.faint : SemanticColor.secondaryFill }
}
