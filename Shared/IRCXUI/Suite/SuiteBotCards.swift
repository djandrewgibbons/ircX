import AppCoreUI
import EmberKit
import SwiftUI

/**
 * A bot's cards under its message (web bot-card.tsx): an attachment's pretext, then a frame with a bar down
 * its left side in the attachment's color, holding its parts and its thumbnail. Addresses on the instance's
 * own host aren't shown. A button that acts tells the room it was clicked and waits, disabled, for the answer.
 */
struct SuiteBotCards: View {
  let session: InstanceSession
  let cards: [Card]
  /** Clicks a button that acts, answering whether the bot took it; nil where a click has nowhere to go. */
  let onAction: ((CardAction) async -> Bool)?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
        SuiteBotCard(session: session, card: card, onAction: onAction)
      }
    }
  }
}

/** Where a card's addresses may go: not to the instance, which every reader would fetch signed in. */
struct CardAddresses {
  let host: String

  func shown(_ url: String?) -> String? { url.flatMap { Display.cardAddress($0, host: host) } }

  func image(_ image: CardImage?) -> CardImage? {
    guard let image, let url = shown(image.url) else { return nil }
    return CardImage(url: url, alt: image.alt)
  }

  /** Card text as it shows, or nil where it can't, which is logged, as a message's text that can't show. */
  func blocks(_ html: String) -> [RichBlock]? { RichLayout.blocks(html, plainText: "", host: host) }

  /** A link button's address where it may go; an acting button always shows. */
  func shownButtons(_ buttons: [CardButton]) -> [CardButton] {
    buttons.compactMap { button in
      if button.action != nil { return button }
      guard let href = shown(button.href) else { return nil }
      var kept = button
      kept.href = href
      return kept
    }
  }
}

/** The bar colors of Slack's named colors, in the suite's: positive, warning and destructive; `#rrggbb` as it says. */
enum CardColors {
  static func bar(_ color: String?) -> Color {
    switch color {
    case nil: return SemanticColor.separator
    case "good"?: return SemanticColor.positive
    case "warning"?: return SemanticColor.warning
    case "danger"?: return SemanticColor.destructive
    case let hex?:
      // A bot's own color, the one color not from the suite's tokens, as the web shows it.
      guard hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return SemanticColor.separator }
      return Color(hex: value)
    }
  }
}

struct SuiteBotCard: View {
  let session: InstanceSession
  let card: Card
  let onAction: ((CardAction) async -> Bool)?

  var body: some View {
    let addresses = CardAddresses(host: session.instance.host)
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let pretext = card.pretext, let blocks = addresses.blocks(pretext) {
        SuiteMessageBody(session: session, blocks: blocks)
      }
      HStack(alignment: .top, spacing: Spacing.lg) {
        VStack(alignment: .leading, spacing: Spacing.sm) {
          ForEach(Array(card.parts.enumerated()), id: \.offset) { _, part in
            SuiteCardPart(session: session, part: part, addresses: addresses, onAction: onAction)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let thumb = addresses.image(card.thumb) {
          SuiteCardThumb(image: thumb)
        }
      }
      .padding(.vertical, Spacing.lg)
      .padding(.horizontal, Spacing.lg)
      .padding(.leading, card.source == .attachment ? Spacing.xs : 0)
      .overlay(alignment: .leading) {
        if card.source == .attachment {
          Rectangle().fill(CardColors.bar(card.color)).frame(width: Spacing.xs)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(SemanticColor.separator))
      .accessibilityElement(children: .contain)
      .accessibilityLabel(cardTitle)
    }
    .frame(maxWidth: 608, alignment: .leading)
  }

  /** The card's first title or header, which names it. */
  private var cardTitle: String {
    for part in card.parts {
      if case let .title(text, _) = part { return text }
      if case let .header(text) = part { return text }
    }
    return ""
  }
}

struct SuiteCardThumb: View {
  let image: CardImage

  var body: some View {
    RemoteImage(url: image.url, fill: true)
      .frame(width: 75, height: 75)
      .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
      .accessibilityLabel(image.alt)
  }
}

struct SuiteCardPart: View {
  let session: InstanceSession
  let part: CardPart
  let addresses: CardAddresses
  let onAction: ((CardAction) async -> Bool)?
  @Environment(\.suiteTheme) private var theme
  @Environment(\.openURL) private var openURL

  var body: some View {
    switch part {
    case let .author(name, href, icon):
      HStack(spacing: Spacing.xs) {
        if let icon = addresses.shown(icon) { RemoteImage(url: icon, fill: true).frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: Radius.small)) }
        linked(name, href: href).font(DesignFont.detail.weight(.semibold)).foregroundStyle(.secondary)
      }
    case let .title(text, href):
      linked(text, href: href).font(DesignFont.cardTitle).foregroundStyle(addresses.shown(href) == nil ? Color.primary : theme.accent)
    case let .header(text):
      Text(text).font(DesignFont.title)
    case let .text(html):
      SuiteCardText(session: session, html: html, addresses: addresses, folds: true)
    case let .section(html, fields, thumb, button):
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: Spacing.lg) {
          sectionText(html, fields)
          if let thumb = addresses.image(thumb) { SuiteCardThumb(image: thumb) }
          if let button { SuiteCardButtons(buttons: addresses.shownButtons([button]), onAction: onAction).fixedSize() }
        }
        VStack(alignment: .leading, spacing: Spacing.sm) {
          sectionText(html, fields)
          if let thumb = addresses.image(thumb) { SuiteCardThumb(image: thumb) }
          if let button { SuiteCardButtons(buttons: addresses.shownButtons([button]), onAction: onAction) }
        }
      }
    case let .fields(fields):
      SuiteCardFields(session: session, fields: fields, addresses: addresses)
    case let .image(image, title):
      if let shown = addresses.image(image) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          if let title { Text(title).font(DesignFont.detail).foregroundStyle(.secondary) }
          Button {
            if let url = URL(string: shown.url) { openURL(url) }
          } label: {
            RemoteImage(url: shown.url)
              .frame(maxWidth: 360, maxHeight: 500, alignment: .leading)
              .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(shown.alt.isEmpty ? "Image from \(URL(string: shown.url)?.host() ?? shown.url)" : shown.alt)
        }
      }
    case let .context(items):
      FlowLayout(hSpacing: Spacing.sm, vSpacing: Spacing.xs) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          switch item {
          case let .html(html):
            SuiteCardText(session: session, html: html, addresses: addresses, small: true)
          case let .image(image):
            if let shown = addresses.image(image) {
              RemoteImage(url: shown.url, fill: true).frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: Radius.small)).accessibilityLabel(shown.alt)
            }
          }
        }
      }
    case .divider:
      Rectangle().fill(SemanticColor.separator).frame(height: 1).padding(.vertical, Spacing.xs)
    case let .buttons(buttons):
      SuiteCardButtons(buttons: addresses.shownButtons(buttons), onAction: onAction)
    case let .table(rows, columns):
      ScrollView(.horizontal) {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            GridRow {
              ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                let column = index < columns.count ? columns[index] : nil
                SuiteCardText(session: session, html: cell, addresses: addresses, oneLine: column?.wrap != true, alignment: Self.alignment(column?.align))
                  .frame(maxWidth: 320, alignment: Self.alignment(column?.align))
                  .padding(.horizontal, Spacing.md)
                  .padding(.vertical, Spacing.xs)
                  .border(SemanticColor.separator)
              }
            }
          }
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel("Table")
    case let .tiles(tiles):
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: Spacing.md) {
          ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
            SuiteCardTile(session: session, tile: tile, addresses: addresses, onAction: onAction)
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.viewAligned)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(tiles.count > 1 ? "Cards" : "")
    case let .footer(text, icon, at):
      HStack(spacing: Spacing.xs) {
        if let icon = addresses.shown(icon) { RemoteImage(url: icon, fill: true).frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: Radius.small)) }
        if let text { Text(text) }
        if text != nil, at != nil { Text("\u{B7}").accessibilityHidden(true) }
        if let at { Text(MessageWords.dateTime(Date(timeIntervalSince1970: at))) }
      }
      .font(DesignFont.detail)
      .foregroundStyle(.secondary)
    case .unknown:
      EmptyView()
    }
  }

  private func sectionText(_ html: String?, _ fields: [CardField]?) -> some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      if let html { SuiteCardText(session: session, html: html, addresses: addresses, folds: true) }
      if let fields { SuiteCardFields(session: session, fields: fields, addresses: addresses) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /** `text`, linked where the card may link there. */
  @ViewBuilder
  private func linked(_ text: String, href: String?) -> some View {
    if let shown = addresses.shown(href), let url = URL(string: shown) {
      Link(text, destination: url)
    } else {
      Text(text)
    }
  }

  static func alignment(_ align: CardColumn.Align?) -> Alignment {
    switch align {
    case .center?: .center
    case .right?: .trailing
    default: .leading
    }
  }
}

/** Rich text in a card, folding past 700 characters or 5 line breaks where it `folds`. */
struct SuiteCardText: View {
  let session: InstanceSession
  let html: String
  let addresses: CardAddresses
  var folds = false
  var small = false
  var oneLine = false
  /** Where the text sits across its width, as a table's column aligns its cells. */
  var alignment: Alignment = .leading
  @State private var open = false
  @Environment(\.suiteTheme) private var theme

  var body: some View {
    if let nodes = RichLayout.shown(html, plainText: "", host: addresses.host) {
      let long = folds && Display.isLong(nodes)
      VStack(alignment: .leading, spacing: Spacing.xs) {
        SuiteMessageBody(session: session, blocks: RichLayout.blocks(nodes), small: small, alignment: alignment)
          .lineLimit(oneLine ? 1 : nil)
          .frame(maxHeight: long && !open ? 110 : nil, alignment: .top)
          .clipped()
        if long {
          Button(open ? "Show less" : "Show more") { open.toggle() }
            .buttonStyle(.plain)
            .font(DesignFont.detail.weight(.medium))
            .foregroundStyle(theme.accent)
        }
      }
    }
  }
}

/** A card's fields: short ones two to a row, the rest the whole width, each title in small bold over its value. */
struct SuiteCardFields: View {
  let session: InstanceSession
  let fields: [CardField]
  let addresses: CardAddresses

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(alignment: .top, spacing: Spacing.xl) {
          ForEach(Array(row.enumerated()), id: \.offset) { _, field in
            VStack(alignment: .leading, spacing: Spacing.xxs) {
              if let title = field.title { Text(title).font(DesignFont.detail.weight(.semibold)).foregroundStyle(.secondary) }
              if !field.html.isEmpty { SuiteCardText(session: session, html: field.html, addresses: addresses) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }

  /** Short fields paired, others alone. */
  private var rows: [[CardField]] {
    var rows: [[CardField]] = []
    for field in fields {
      if field.short, let last = rows.last, last.count == 1, last[0].short {
        rows[rows.count - 1].append(field)
      } else {
        rows.append([field])
      }
    }
    return rows
  }
}

/** A card's buttons: bordered, filled for `primary`, red for `danger`; links, and those that act. */
struct SuiteCardButtons: View {
  let buttons: [CardButton]
  let onAction: ((CardAction) async -> Bool)?

  var body: some View {
    if !buttons.isEmpty {
      FlowLayout(hSpacing: Spacing.sm, vSpacing: Spacing.sm) {
        ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
          SuiteCardButton(button: button, onAction: onAction)
        }
      }
    }
  }
}

struct SuiteCardButton: View {
  let button: CardButton
  let onAction: ((CardAction) async -> Bool)?
  @State private var waiting = false
  @Environment(\.openURL) private var openURL

  var body: some View {
    Group {
      if let action = button.action {
        styled(Button(role: button.style == .danger ? .destructive : nil) {
          guard let onAction else { return }
          waiting = true
          Task {
            _ = await onAction(action)
            waiting = false
          }
        } label: {
          Text(button.text).lineLimit(1)
        })
        .disabled(onAction == nil || waiting)
        .loadingActivity(waiting)
      } else if let href = button.href, let url = URL(string: href) {
        styled(Button(role: button.style == .danger ? .destructive : nil) { openURL(url) } label: { Text(button.text).lineLimit(1) })
          .help(href)
      }
    }
    .controlSize(.small)
    .font(DesignFont.detail.weight(.medium))
  }

  private func styled(_ base: some View) -> some View {
    base.buttonStyle(SuiteCardButtonStyle(style: button.style))
  }
}

/** A card's button as the web draws it: outlined, filled with the accent for `primary`, and red for `danger`. */
struct SuiteCardButtonStyle: ButtonStyle {
  let style: CardButton.Style?
  @Environment(\.suiteTheme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    configuration.label
      .foregroundStyle(style == nil ? Color.primary : Color.white)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)
      .background(fill, in: shape)
      .overlay(shape.strokeBorder(style == nil ? SemanticColor.separator : Color.clear))
      .opacity(configuration.isPressed ? 0.75 : isEnabled ? 1 : 0.5)
      .contentShape(shape)
  }

  private var fill: Color {
    switch style {
    case .primary?: theme.accent
    case .danger?: SemanticColor.destructive
    case nil: Color.clear
    }
  }
}

/** A small card in a row (web `Tile`): its hero, its icon beside its title and subtitle, its body, subtext and buttons. */
struct SuiteCardTile: View {
  let session: InstanceSession
  let tile: CardTile
  let addresses: CardAddresses
  let onAction: ((CardAction) async -> Bool)?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let hero = addresses.image(tile.hero) {
        RemoteImage(url: hero.url, fill: true).aspectRatio(2, contentMode: .fill).frame(width: 280, height: 140).clipped().accessibilityLabel(hero.alt)
      }
      VStack(alignment: .leading, spacing: Spacing.sm) {
        if tile.title != nil || tile.subtitle != nil {
          HStack(spacing: Spacing.sm) {
            if let icon = addresses.image(tile.icon) {
              RemoteImage(url: icon.url, fill: true).frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: Radius.control)).accessibilityLabel(icon.alt)
            }
            VStack(alignment: .leading, spacing: 0) {
              if let title = tile.title { Text(title).font(DesignFont.bodyEmphasized) }
              if let subtitle = tile.subtitle { Text(subtitle).font(DesignFont.detail).foregroundStyle(.secondary) }
            }
          }
        }
        if let body = tile.body { SuiteCardText(session: session, html: body, addresses: addresses) }
        if let subtext = tile.subtext { SuiteCardText(session: session, html: subtext, addresses: addresses, small: true) }
        if let buttons = tile.buttons {
          let shown = addresses.shownButtons(buttons)
          HStack {
            SuiteCardButtons(buttons: shown.filter { $0.style == .danger }, onAction: onAction)
            Spacer(minLength: Spacing.sm)
            SuiteCardButtons(buttons: shown.filter { $0.style != .danger }.sorted { ($0.style == .primary ? 1 : 0) < ($1.style == .primary ? 1 : 0) }, onAction: onAction)
          }
        }
      }
      .padding(Spacing.lg)
    }
    .frame(width: 280, alignment: .leading)
    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(SemanticColor.separator))
  }
}
