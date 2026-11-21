import Foundation

// packages/protocol/src/cards.ts: what bots and agents show under a message's text, from Slack's
// attachments and blocks, as the Worker keeps it. Text marked `html` is rich text in the stored form,
// like a message's body.

public struct Card: Codable, Hashable, Sendable {
  public enum Source: String, Codable, Sendable {
    case attachment, blocks
  }

  public var source: Source
  /** `good`, `warning`, `danger` or `#rrggbb`: the bar down an attachment's left side. */
  public var color: String?
  public var pretext: String?
  public var thumb: CardImage?
  public var parts: [CardPart]
}

public struct CardImage: Codable, Hashable, Sendable {
  public var url: String
  public var alt: String

  public init(url: String, alt: String) {
    self.url = url
    self.alt = alt
  }
}

public struct CardField: Codable, Hashable, Sendable {
  public var title: String?
  public var html: String
  public var short: Bool
}

public struct CardAction: Codable, Hashable, Sendable {
  public var id: String
  public var blockId: String?
  public var value: String?
  /** The connected app that answers the click, for an agent's card. */
  public var appId: String?
}

public struct CardButton: Codable, Hashable, Sendable {
  public enum Style: String, Codable, Sendable {
    case primary, danger
  }

  public var text: String
  public var href: String?
  public var action: CardAction?
  public var style: Style?
}

public struct CardColumn: Codable, Hashable, Sendable {
  public enum Align: String, Codable, Sendable {
    case left, center, right
  }

  public var align: Align
  public var wrap: Bool
}

public struct CardTile: Codable, Hashable, Sendable {
  public var hero: CardImage?
  public var icon: CardImage?
  public var title: String?
  public var subtitle: String?
  public var body: String?
  public var subtext: String?
  public var buttons: [CardButton]?
}

/** `CardContextItem = { html } | { image }` */
public enum CardContextItem: Codable, Hashable, Sendable {
  case html(String)
  case image(CardImage)

  private enum Keys: String, CodingKey { case html, image }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    if let image = try c.decodeIfPresent(CardImage.self, forKey: .image) {
      self = .image(image)
    } else {
      self = .html(try c.decode(String.self, forKey: .html))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    switch self {
    case let .html(html): try c.encode(html, forKey: .html)
    case let .image(image): try c.encode(image, forKey: .image)
    }
  }
}

/** One part of a card, top to bottom (`CardPart`, by its `kind`). */
public enum CardPart: Codable, Hashable, Sendable {
  case author(name: String, href: String?, icon: String?)
  case title(text: String, href: String?)
  case header(text: String)
  case text(html: String)
  case section(html: String?, fields: [CardField]?, thumb: CardImage?, button: CardButton?)
  case fields([CardField])
  case image(CardImage, title: String?)
  case context([CardContextItem])
  case divider
  case buttons([CardButton])
  case table(rows: [[String]], columns: [CardColumn])
  case tiles([CardTile])
  /** `at` is in Unix seconds. */
  case footer(text: String?, icon: String?, at: Double?)
  /** A kind this client doesn't know, which it leaves out. */
  case unknown(String)

  private enum Keys: String, CodingKey {
    case kind, name, href, icon, text, html, fields, thumb, button, image, title, items, buttons, rows, columns, tiles, at
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    let kind = try c.decode(String.self, forKey: .kind)
    switch kind {
    case "author":
      self = .author(name: try c.decode(String.self, forKey: .name), href: try c.decodeIfPresent(String.self, forKey: .href), icon: try c.decodeIfPresent(String.self, forKey: .icon))
    case "title": self = .title(text: try c.decode(String.self, forKey: .text), href: try c.decodeIfPresent(String.self, forKey: .href))
    case "header": self = .header(text: try c.decode(String.self, forKey: .text))
    case "text": self = .text(html: try c.decode(String.self, forKey: .html))
    case "section":
      self = .section(
        html: try c.decodeIfPresent(String.self, forKey: .html), fields: try c.decodeIfPresent([CardField].self, forKey: .fields),
        thumb: try c.decodeIfPresent(CardImage.self, forKey: .thumb), button: try c.decodeIfPresent(CardButton.self, forKey: .button))
    case "fields": self = .fields(try c.decode([CardField].self, forKey: .fields))
    case "image": self = .image(try c.decode(CardImage.self, forKey: .image), title: try c.decodeIfPresent(String.self, forKey: .title))
    case "context": self = .context(try c.decode([CardContextItem].self, forKey: .items))
    case "divider": self = .divider
    case "buttons": self = .buttons(try c.decode([CardButton].self, forKey: .buttons))
    case "table": self = .table(rows: try c.decode([[String]].self, forKey: .rows), columns: try c.decode([CardColumn].self, forKey: .columns))
    case "tiles": self = .tiles(try c.decode([CardTile].self, forKey: .tiles))
    case "footer":
      self = .footer(text: try c.decodeIfPresent(String.self, forKey: .text), icon: try c.decodeIfPresent(String.self, forKey: .icon), at: try c.decodeIfPresent(Double.self, forKey: .at))
    default: self = .unknown(kind)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    switch self {
    case let .author(name, href, icon):
      try c.encode("author", forKey: .kind)
      try c.encode(name, forKey: .name)
      try c.encodeIfPresent(href, forKey: .href)
      try c.encodeIfPresent(icon, forKey: .icon)
    case let .title(text, href):
      try c.encode("title", forKey: .kind)
      try c.encode(text, forKey: .text)
      try c.encodeIfPresent(href, forKey: .href)
    case let .header(text):
      try c.encode("header", forKey: .kind)
      try c.encode(text, forKey: .text)
    case let .text(html):
      try c.encode("text", forKey: .kind)
      try c.encode(html, forKey: .html)
    case let .section(html, fields, thumb, button):
      try c.encode("section", forKey: .kind)
      try c.encodeIfPresent(html, forKey: .html)
      try c.encodeIfPresent(fields, forKey: .fields)
      try c.encodeIfPresent(thumb, forKey: .thumb)
      try c.encodeIfPresent(button, forKey: .button)
    case let .fields(fields):
      try c.encode("fields", forKey: .kind)
      try c.encode(fields, forKey: .fields)
    case let .image(image, title):
      try c.encode("image", forKey: .kind)
      try c.encode(image, forKey: .image)
      try c.encodeIfPresent(title, forKey: .title)
    case let .context(items):
      try c.encode("context", forKey: .kind)
      try c.encode(items, forKey: .items)
    case .divider:
      try c.encode("divider", forKey: .kind)
    case let .buttons(buttons):
      try c.encode("buttons", forKey: .kind)
      try c.encode(buttons, forKey: .buttons)
    case let .table(rows, columns):
      try c.encode("table", forKey: .kind)
      try c.encode(rows, forKey: .rows)
      try c.encode(columns, forKey: .columns)
    case let .tiles(tiles):
      try c.encode("tiles", forKey: .kind)
      try c.encode(tiles, forKey: .tiles)
    case let .footer(text, icon, at):
      try c.encode("footer", forKey: .kind)
      try c.encodeIfPresent(text, forKey: .text)
      try c.encodeIfPresent(icon, forKey: .icon)
      try c.encodeIfPresent(at, forKey: .at)
    case let .unknown(kind):
      try c.encode(kind, forKey: .kind)
    }
  }
}

public enum Cards {
  public static let maxCards = 101
  public static let maxActionIdLength = 255
  public static let maxActionValueLength = 2000

  /** `isActionId` */
  public static func isActionId(_ value: String) -> Bool { !value.isEmpty && value.utf16.count <= maxActionIdLength }
  /** `isActionValue` */
  public static func isActionValue(_ value: String) -> Bool { value.utf16.count <= maxActionValueLength }
  /** `showsAnything`: whether parts show more than dividers. */
  public static func showsAnything(_ parts: [CardPart]) -> Bool { parts.contains { $0 != .divider } }

  // Errors a room sends about cards and clicks (W/chat-room.ts).
  public static let hasCards = "Messages with cards can't be edited."
  public static let buttonGone = "That button is no longer there"
  public static let tooManyClicks = "Wait for your earlier clicks to be answered"
  public static let webhooksFull = "Too much is waiting for bots here. Try again in a moment."
  public static let clickFailed = "That click couldn't be delivered"
  public static let callAnswered = "Someone has answered that already"
  public static let callLate = "That waited too long to be allowed. Ask again"
  public static let roomBusy = "Too many questions are waiting for answers in this room. Try again in a moment"
  public static let cardBusy = "That card is answering another click. Try again in a moment"
  public static let assistantGone = "Ember AI has been turned off, or @ember is no longer in the room"
  public static let agentGone = "Ember AI has been turned off, or the agent has been deleted or is no longer in the room"
}
