import Foundation

// packages/richtext/src/previews.ts: the attachment a composer adds below a link it unfurls.

public enum Previews {
  /**
   * `previewContent`: a preview's markup as the composer writes it, the content of its attachment: its
   * title, linked when it has an address, its description, and its image.
   */
  public static func content(href: String?, url: String?, filename: String?, description: String?) -> String {
    let twitter = Display.isTwitterAvatar(url) ? " og-embed--twitter-avatar" : ""
    let name = filename.map { Autolink.htmlEscape(Display.strip(Display.truncate($0, 280))) }
    let linked = href.map { "<a href=\"\(Autolink.htmlEscape($0))\" rel=\"noreferrer\" target=\"_blank\">\(name ?? Autolink.htmlEscape($0))</a>" } ?? name
    let title = linked.map { "<div class=\"og-embed__title\">\($0)</div>" } ?? ""
    let image = url.map { "<div class=\"og-embed__image\"><img src=\"\(Autolink.htmlEscape($0))\" class=\"image center\" alt=\"\"></div>" } ?? ""
    let shownDescription = Autolink.htmlEscape(Display.strip(Display.truncate(description ?? "", 560)))
    return "<actiontext-opengraph-embed><div class=\"og-embed gap\(twitter)\"><div class=\"og-embed__content\">\(title)"
      + "<div class=\"og-embed__description\">\(shownDescription)</div></div>\(image)</div></actiontext-opengraph-embed>"
  }

  /** The attachment for an unfurled link's `preview`, as the web composer inserts it (`useLinkPreviews.pasted`). */
  public static func attachment(_ preview: LinkPreview) -> String {
    let content = content(href: preview.url, url: preview.image, filename: preview.title, description: preview.description)
    return "<action-text-attachment content-type=\"\(Display.previewContentType)\" content=\"\(Autolink.htmlEscape(content))\"></action-text-attachment>"
  }
}
