import EmberKit
import SwiftUI

/**
 * The IRC theme: a terminal's palette and a monospaced face, laid out the way Slack lays out a
 * workspace. Ember's own orange marks what's selected and what mentions you.
 */
public struct Theme: Sendable {
  public var rail = Color(hex: 0x0B0C10)
  public var sidebar = Color(hex: 0x12141A)
  public var buffer = Color(hex: 0x16181F)
  public var bar = Color(hex: 0x1D2029)
  public var input = Color(hex: 0x0F1116)
  public var text = Color(hex: 0xD3D7DE)
  public var dim = Color(hex: 0x6B7280)
  public var faint = Color(hex: 0x2A2E39)
  public var ember = Color(hex: 0xFF8A3D)
  public var highlight = Color(hex: 0xFF8A3D).opacity(0.12)
  public var join = Color(hex: 0x5FD38D)
  public var part = Color(hex: 0xE5676B)
  public var action = Color(hex: 0xC792EA)
  public var link = Color(hex: 0x6CB6FF)

  /** mIRC's colors, less the ones that vanish on a dark background. */
  public var nicks: [Color] = [
    0x5FD38D, 0x6CB6FF, 0xE5676B, 0xC792EA, 0xFFCB6B, 0x4DD0E1, 0xF78C6C, 0xA3BE8C,
    0x82AAFF, 0xFF79C6, 0xD4BFFF, 0x89DDFF,
  ].map { Color(hex: $0) }

  public func nick(_ userID: UserID) -> Color {
    nicks[NickColor.index(for: userID, among: nicks.count)]
  }

  public static let irc = Theme()

  public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}

private struct ThemeKey: EnvironmentKey {
  static let defaultValue = Theme.irc
}

extension EnvironmentValues {
  public var theme: Theme {
    get { self[ThemeKey.self] }
    set { self[ThemeKey.self] = newValue }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
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
