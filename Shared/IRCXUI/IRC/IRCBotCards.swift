import EmberKit
import SwiftUI

/**
 * A bot's cards as indented blocks under its message, a bar in the card's color down their left: titles
 * bold, fields as `key: value`, images as `[img alt]`, tiles numbered, tables in columns, footers dim,
 * and buttons as `[Approve]`, which a click runs (or, for a link, opens).
 */
struct IRCBotCards: View {
  let session: InstanceSession
  let cards: [Card]
  let onAction: ((CardAction) async -> Bool)?
  @Environment(\.theme) private var theme

  var body: some View {
    let addresses = CardAddresses(host: session.instance.host)
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
        VStack(alignment: .leading, spacing: 2) {
          if let pretext = card.pretext, let blocks = addresses.blocks(pretext) {
            IRCMessageBody(session: session, blocks: blocks)
          }
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
              ForEach(Array(card.parts.enumerated()), id: \.offset) { _, part in
                IRCCardPart(session: session, part: part, addresses: addresses, onAction: onAction)
              }
            }
            if let thumb = addresses.image(card.thumb) {
              RemoteImage(url: thumb.url, fill: true).frame(width: 48, height: 48).clipped().accessibilityLabel(thumb.alt)
            }
          }
          .padding(.leading, 10)
          .overlay(alignment: .leading) { Rectangle().fill(bar(card)).frame(width: 2) }
        }
      }
    }
  }

  /** The bar: Slack's named colors in the theme's palette, a bot's own `#rrggbb` as it says. */
  private func bar(_ card: Card) -> Color {
    guard card.source == .attachment else { return theme.faint }
    switch card.color {
    case "good"?: return theme.join
    case "warning"?: return theme.ember
    case "danger"?: return theme.part
    case let hex? where hex.hasPrefix("#") && hex.count == 7:
      guard let value = UInt32(hex.dropFirst(), radix: 16) else { return theme.faint }
      return Color(hex: value)
    default: return theme.faint
    }
  }
}

struct IRCCardPart: View {
  let session: InstanceSession
  let part: CardPart
  let addresses: CardAddresses
  let onAction: ((CardAction) async -> Bool)?
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL

  var body: some View {
    switch part {
    case let .author(name, href, _):
      linked(name, href: href).foregroundStyle(theme.dim)
    case let .title(text, href):
      linked(text, href: href).bold()
    case let .header(text):
      Text(text).bold().foregroundStyle(theme.text)
    case let .text(html):
      IRCCardText(session: session, html: html, addresses: addresses, folds: true)
    case let .section(html, fields, thumb, button):
      VStack(alignment: .leading, spacing: 1) {
        if let html { IRCCardText(session: session, html: html, addresses: addresses, folds: true) }
        if let fields { IRCCardFields(session: session, fields: fields, addresses: addresses) }
        if let thumb = addresses.image(thumb) { imageLink(thumb) }
        if let button { IRCCardButtons(buttons: addresses.shownButtons([button]), onAction: onAction) }
      }
    case let .fields(fields):
      IRCCardFields(session: session, fields: fields, addresses: addresses)
    case let .image(image, title):
      if let shown = addresses.image(image) {
        HStack(spacing: 6) {
          if let title { Text(title).foregroundStyle(theme.dim) }
          imageLink(shown)
        }
      }
    case let .context(items):
      HStack(spacing: 6) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          switch item {
          case let .html(html): IRCCardText(session: session, html: html, addresses: addresses, dim: true)
          case let .image(image): if let shown = addresses.image(image) { imageLink(shown) }
          }
        }
      }
    case .divider:
      Text("\u{2500}\u{2500}\u{2500}\u{2500}").foregroundStyle(theme.faint)
    case let .buttons(buttons):
      IRCCardButtons(buttons: addresses.shownButtons(buttons), onAction: onAction)
    case let .table(rows, columns):
      IRCTable(rows: rows.map { $0.map { cellText($0) } }, columns: columns)
    case let .tiles(tiles):
      VStack(alignment: .leading, spacing: 2) {
        ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
          VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
              Text("\(index + 1))").foregroundStyle(theme.dim)
              if let title = tile.title { Text(title).bold().foregroundStyle(theme.text) }
              if let subtitle = tile.subtitle { Text("- " + subtitle).foregroundStyle(theme.dim) }
              if let hero = addresses.image(tile.hero) { imageLink(hero) }
            }
            Group {
              if let body = tile.body { IRCCardText(session: session, html: body, addresses: addresses) }
              if let subtext = tile.subtext { IRCCardText(session: session, html: subtext, addresses: addresses, dim: true) }
              if let buttons = tile.buttons { IRCCardButtons(buttons: addresses.shownButtons(buttons), onAction: onAction) }
            }
            .padding(.leading, 24)
          }
        }
      }
    case let .footer(text, _, at):
      Text([text, at.map { MessageWords.dateTime(Date(timeIntervalSince1970: $0)) }].compactMap { $0 }.joined(separator: " \u{B7} "))
        .foregroundStyle(theme.dim)
    case .unknown:
      EmptyView()
    }
  }

  private func cellText(_ html: String) -> String {
    guard let nodes = RichLayout.shown(html, plainText: "", host: addresses.host) else { return Display.failedToLoad }
    return nodes.map { $0.plainText(name: { session.people[$0]?.name ?? Display.missingAttachable }) }.joined()
  }

  private func imageLink(_ image: CardImage) -> some View {
    Button("[img\(image.alt.isEmpty ? "" : " " + image.alt)]") {
      if let url = URL(string: image.url) { openURL(url) }
    }
    .buttonStyle(.plain)
    .foregroundStyle(theme.link)
    .help(image.url)
  }

  @ViewBuilder
  private func linked(_ text: String, href: String?) -> some View {
    if let shown = addresses.shown(href), let url = URL(string: shown) {
      Button(text) { openURL(url) }.buttonStyle(.plain).foregroundStyle(theme.link).help(shown)
    } else {
      Text(text).foregroundStyle(theme.text)
    }
  }
}

/** Card text in the theme, folding past 700 characters or 5 line breaks behind `[more]` where it `folds`. */
struct IRCCardText: View {
  let session: InstanceSession
  let html: String
  let addresses: CardAddresses
  var folds = false
  var dim = false
  @State private var open = false
  @Environment(\.theme) private var theme

  var body: some View {
    if let nodes = RichLayout.shown(html, plainText: "", host: addresses.host) {
      let long = folds && Display.isLong(nodes)
      VStack(alignment: .leading, spacing: 0) {
        IRCMessageBody(session: session, blocks: RichLayout.blocks(nodes), dim: dim)
          .frame(maxHeight: long && !open ? 90 : nil, alignment: .top)
          .clipped()
        if long {
          Button(open ? "[less]" : "[more]") { open.toggle() }.buttonStyle(.plain).foregroundStyle(theme.link)
        }
      }
    }
  }
}

struct IRCCardFields: View {
  let session: InstanceSession
  let fields: [CardField]
  let addresses: CardAddresses
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          if let title = field.title { Text(title + ":").bold().foregroundStyle(theme.dim) }
          if !field.html.isEmpty { IRCCardText(session: session, html: field.html, addresses: addresses) }
        }
      }
    }
  }
}

/** Buttons as `[Text]`: Ember's orange for primary, red for danger; one that acts waits for its answer as `[Text...]`. */
struct IRCCardButtons: View {
  let buttons: [CardButton]
  let onAction: ((CardAction) async -> Bool)?

  var body: some View {
    if !buttons.isEmpty {
      HStack(spacing: 6) {
        ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
          IRCCardButton(button: button, onAction: onAction)
        }
      }
    }
  }
}

struct IRCCardButton: View {
  let button: CardButton
  let onAction: ((CardAction) async -> Bool)?
  @State private var waiting = false
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL

  var body: some View {
    if let action = button.action {
      Button(waiting ? "[\(button.text)\u{2026}]" : "[\(button.text)]") {
        guard let onAction else { return }
        waiting = true
        Task {
          _ = await onAction(action)
          waiting = false
        }
      }
      .buttonStyle(.plain)
      .foregroundStyle(onAction == nil || waiting ? theme.dim : color)
      .disabled(onAction == nil || waiting)
    } else if let href = button.href, let url = URL(string: href) {
      Button("[\(button.text)]") { openURL(url) }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .underline()
        .help(href)
    }
  }

  private var color: Color {
    switch button.style {
    case .primary?: theme.ember
    case .danger?: theme.part
    case nil: theme.link
    }
  }
}
