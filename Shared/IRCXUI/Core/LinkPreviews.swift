import EmberKit
import Foundation
import Observation

/** What a composer knew of its links' previews as its message went (web `DraftPreviews`), for the late preview. */
public struct SentPreviews {
  /** The preview shown below the link it's of, which goes in the message. */
  public var shown: (preview: LinkPreview, link: String)?
  /** The preview asked for of the link pasted last, which goes after the message if it went with it. */
  public var asking: (url: String, preview: Task<LinkPreview?, Never>)?
  /** The links whose previews were asked for as they were pasted. */
  public var asked: Set<String> = []
  /** Whether a preview was added to what was written, so one taken out stays out. */
  public var added = false

  public init() {}
}

/**
 * A composer's link previews (web `useLinkPreviews`): a link pasted gets the preview of the page it goes
 * to below its paragraph, unless another is pasted first, and the writer can take it out. The preview
 * shown is the composer's (`ComposerModel.linkPreview`), kept with its draft. Previews that can't be had
 * are left out, logged; too many asked for says so as the room's notice.
 */
@MainActor
@Observable
public final class DraftPreviews {
  @ObservationIgnored private var asking: (url: String, preview: Task<LinkPreview?, Never>)?
  @ObservationIgnored private var asked: Set<String> = []
  @ObservationIgnored private var added = false

  public init() {}

  /** Asks for the preview of the link `url` just pasted, in place of any asked for before. */
  public func pasted(_ url: String, api: EmberAPI, room: RoomModel, composer: ComposerModel) {
    asking?.preview.cancel()
    let link = Autolink.linkedUrls(url).first ?? url
    let task = Task<LinkPreview?, Never> { [weak room] in
      do {
        guard let preview = try await api.linkPreview(url) else { return nil }
        let blank = { (text: String) in text.trimmingCharacters(in: .whitespaces).isEmpty }
        return blank(preview.title) || blank(preview.url) ? nil : preview
      } catch is CancellationError {
        return nil
      } catch let error as EmberError where error.problem?.status == 429 {
        room?.warn(error.localizedDescription)
        return nil
      } catch {
        logger.error("Couldn't preview a pasted link: \(error.localizedDescription, privacy: .public)")
        return nil
      }
    }
    asking = (link, task)
    asked.insert(link)
    Task { [weak self, weak composer] in
      guard let preview = await task.value, let self, self.asking?.url == link, !task.isCancelled else { return }
      self.added = true
      composer?.linkPreview = DraftLinkPreview(preview: preview, link: link)
    }
  }

  /** The web address a paste put in `new`, which `old` didn't have; typing one a letter at a time isn't a paste. */
  static func pastedLink(_ old: String, _ new: String) -> String? {
    guard new.count - old.count > 1 else { return nil }
    var before = Autolink.linkedUrls(old)
    for link in Autolink.linkedUrls(new) {
      if let index = before.firstIndex(of: link) {
        before.remove(at: index)
      } else if link.lowercased().hasPrefix("http://") || link.lowercased().hasPrefix("https://") {
        return link
      }
    }
    return nil
  }

  /** Takes the preview out of what's written; none goes after the message either. */
  public func remove(from composer: ComposerModel) {
    composer.linkPreview = nil
    added = true
  }

  /** What goes with the message about to be sent; nothing changes until it has (`sent`). */
  public func sending(_ composer: ComposerModel) -> SentPreviews {
    var sent = SentPreviews()
    sent.shown = composer.linkPreview.map { ($0.preview, $0.link) }
    sent.asking = composer.linkPreview == nil ? asking : nil
    sent.asked = asked
    // A preview kept with a draft was added to what was written.
    sent.added = added || composer.linkPreview != nil
    return sent
  }

  /** A fresh start for the next message, once one has gone; the composer let go of its preview as it cleared. */
  public func sent() {
    asking = nil
    asked = []
    added = false
  }
}

/**
 * Why the room gave back what's in a composer, until the next send (web `refusal`). A composer's state
 * holds it in this wrapper, as an optional `@State` can't take a value its view is made with.
 */
struct Refusal: Equatable {
  var why: String?
}
