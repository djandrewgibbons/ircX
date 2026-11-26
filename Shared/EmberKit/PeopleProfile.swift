import Foundation
import ImageIO
import UniformTypeIdentifiers

// The profile form's changes, the cookies a flow elsewhere carries, the photo variant forms send, and
// the people pages' words.

/** A cookie an Ember answer set, such as the OAuth state a Memberful or SSO callback checks. */
public struct StateCookie: Equatable, Sendable {
  public var name: String
  public var value: String
  public var path: String
  public var secure: Bool
  public var httpOnly: Bool
  public var maxAge: Int?

  public init(name: String, value: String, path: String = "/", secure: Bool = false, httpOnly: Bool = false, maxAge: Int? = nil) {
    self.name = name
    self.value = value
    self.path = path
    self.secure = secure
    self.httpOnly = httpOnly
    self.maxAge = maxAge
  }

  /** Every cookie a response's `Set-Cookie` sets: Foundation joins several headers with commas. */
  public static func all(in response: HTTPURLResponse) -> [StateCookie] {
    for (key, value) in response.allHeaderFields {
      guard let key = key as? String, key.caseInsensitiveCompare("Set-Cookie") == .orderedSame, let header = value as? String else { continue }
      return parse(header)
    }
    return []
  }

  /** The cookies in a `Set-Cookie` value, several joined by commas (an `Expires` date's comma isn't a cookie's end). */
  public static func parse(_ header: String) -> [StateCookie] {
    header.split(separator: #/,\s*(?=[^;,=\s]+=)/#).compactMap { cookie in
      let fields = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
      guard let pair = fields.first, let equals = pair.firstIndex(of: "=") else { return nil }
      var parsed = StateCookie(name: String(pair[..<equals]), value: String(pair[pair.index(after: equals)...]))
      guard !parsed.name.isEmpty else { return nil }
      for field in fields.dropFirst() {
        let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
        guard let attribute = parts.first else { continue }
        switch attribute.lowercased() {
        case "path": if parts.count > 1 { parsed.path = parts[1] }
        case "secure": parsed.secure = true
        case "httponly": parsed.httpOnly = true
        case "max-age": if parts.count > 1 { parsed.maxAge = Int(parts[1]) }
        default: continue
        }
      }
      return parsed
    }
  }
}

/** Where to connect an account elsewhere, and the cookies the browser must hold when it comes back. */
public struct ElsewhereStart: Equatable, Sendable {
  public var connection: ElsewhereConnection
  public var cookies: [StateCookie]

  public init(connection: ElsewhereConnection, cookies: [StateCookie]) {
    self.connection = connection
    self.cookies = cookies
  }
}

/**
 * The profile form's fields as typed (`Fields`), but for the passwords, which only their fields hold, with
 * the web's `changesOf` and `settled`.
 */
public struct ProfileFields: Equatable, Sendable {
  public var name: String
  public var username: String
  public var emailAddress: String
  public var bio: String

  public init(name: String, username: String, emailAddress: String, bio: String) {
    self.name = name
    self.username = username
    self.emailAddress = emailAddress
    self.bio = bio
  }

  /** `fieldsOf` */
  public init(_ profile: Profile) {
    // None saved shows as an empty field, which saving empty keeps none.
    name = profile.name
    username = Self.shown(profile.username)
    emailAddress = Self.shown(profile.emailAddress)
    bio = Self.shown(profile.bio)
  }

  private static func shown(_ saved: String?) -> String {
    guard let saved else { return String() }
    return saved
  }

  /**
   * `changesOf`: the fields typed differently from `saved`, and the passwords if they're typed. Only they're
   * sent, so a save doesn't put back what another device saved since.
   */
  public func changes(from saved: ProfileFields, password: String, currentPassword: String) -> ProfileChanges {
    var changes = ProfileChanges()
    if !password.isEmpty { changes.password = password }
    if !currentPassword.isEmpty { changes.currentPassword = currentPassword }
    if name != saved.name { changes.name = name }
    if username != saved.username { changes.username = username }
    if emailAddress != saved.emailAddress { changes.emailAddress = emailAddress }
    if bio != saved.bio { changes.bio = bio }
    return changes
  }

  /** `settled`: the form once `sent` is saved as `saved`; each field typed since stays as typed. */
  public func settled(sent: ProfileFields, saved: ProfileFields) -> ProfileFields {
    var fields = self
    if name == sent.name { fields.name = saved.name }
    if username == sent.username { fields.username = saved.username }
    if emailAddress == sent.emailAddress { fields.emailAddress = saved.emailAddress }
    if bio == sent.bio { fields.bio = saved.bio }
    return fields
  }
}

extension ProfileChanges {
  /** Whether it changes nothing. */
  public var isEmpty: Bool {
    name == nil && username == nil && emailAddress == nil && password == nil && bio == nil && currentPassword == nil
  }
}

extension ElsewhereAccount {
  /** `describe`: "Grace Hopper (grace@example.com)", or whichever of the two it gave, or nil for neither. */
  public var described: String? {
    let named = name.flatMap { $0.isEmpty ? nil : $0 }
    let addressed = emailAddress.flatMap { $0.isEmpty ? nil : $0 }
    if let named, let addressed { return "\(named) (\(addressed))" }
    return named ?? addressed
  }
}

extension Avatars {
  /**
   * A photo ready to send (`avatarVariantOf`): the file as chosen, and its variant within 512 by 512, JPEG
   * for an opaque photo and PNG for one with transparency, as ImageIO draws it; no variant where ImageIO
   * can't read the file, which the server then stores and shows initials for.
   */
  public static func chosenPhoto(_ data: Data, fileName: String, contentType: String) -> ChosenPhoto {
    guard let made = variant(of: data) else {
      return ChosenPhoto(data: data, fileName: fileName, contentType: contentType, variant: nil, variantContentType: "image/png")
    }
    return ChosenPhoto(data: data, fileName: fileName, contentType: contentType, variant: made.data, variantContentType: made.contentType)
  }

  /** The variant, within `box` pixels on its longest side. */
  public static func variant(of data: Data, box: Int = avatarBox) -> (data: Data, contentType: String)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: box,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let opaque: Bool
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: opaque = true
    default: opaque = false
    }
    let type = opaque ? UTType.jpeg : UTType.png
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
    let properties: [CFString: Any] = opaque ? [kCGImageDestinationLossyCompressionQuality: 0.85] : [:]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return (output as Data, opaque ? "image/jpeg" : "image/png")
  }
}

extension RoomList {
  /**
   * Conversation notifications' order (`profileOrder`): rooms by name, then DMs in the sidebar's order,
   * without the quiet welcome DMs the sidebar leaves out. Hidden rooms stay, to be shown again.
   */
  public static func profileOrder(_ rooms: [SidebarRoom], me: UserID?) -> (shared: [SidebarRoom], directs: [SidebarRoom]) {
    let listed = rooms.filter { !isQuietWelcome($0.room, me: me) }
    let keyed: [(room: SidebarRoom, key: String)] = listed.filter { !$0.room.isDirect }.map { item in
      (item, PeopleList.folded(item.room.name ?? item.id))
    }
    let shared = keyed.sorted { $0.key != $1.key ? $0.key < $1.key : $0.room.id < $1.room.id }.map(\.room)
    let directs = inDirectOrder(listed.filter(\.room.isDirect)) { item in item.room.activeAt ?? item.id }
    return (shared, directs)
  }
}
