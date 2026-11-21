import Foundation

// packages/protocol/src/files.ts: files attached to messages, and the upload protocol.

/** A file a message carries (`StoredFile`). Its addresses are signed, so they load without the session. */
public struct StoredFile: Codable, Hashable, Sendable {
  public var id: String
  public var name: String
  public var contentType: String
  public var byteSize: Int
  public var width: Int?
  public var height: Int?
  public var url: String
  public var downloadUrl: String
  public var previewUrl: String?

  public var isImage: Bool { contentType.hasPrefix("image/") }
  /** Whether Ember makes a preview of it (`isPreviewed`): images it can resize and videos. */
  public var isPreviewed: Bool { Files.isPreviewed(contentType) }
}

/** A file to upload to a room (`NewUpload`), whose message goes to `parentId`'s thread when there's one. */
public struct NewUpload: Codable, Hashable, Sendable {
  public var name: String
  public var type: String
  public var size: Int
  public var clientMessageId: String
  public var parentId: String?
  public var alsoSend: Bool?

  public init(name: String, type: String, size: Int, clientMessageId: String, parentId: String? = nil, alsoSend: Bool? = nil) {
    self.name = name
    self.type = type
    self.size = size
    self.clientMessageId = clientMessageId
    self.parentId = parentId
    self.alsoSend = parentId == nil ? nil : alsoSend
  }
}

/** What `POST /api/rooms/<id>/uploads` answers (`Upload`): send `parts` parts of `partSize` bytes each, the last shorter. */
public struct Upload: Codable, Hashable, Sendable {
  public var id: String
  public var partSize: Int
  public var parts: Int
}

public enum Files {
  public static let maxFileSize = 250_000_000
  public static let fileTooLarge = "Files must be 250 MB or smaller."
  public static let maxFileNameLength = 255
  public static let maxFileTypeLength = 255
  public static let fileNameNotKept = "That file's name can't be kept"
  public static let previewMaxWidth = 1200
  public static let previewMaxHeight = 800
  public static let maxPreviewSize = 5 * 1024 * 1024
  public static let maxPreviewPixels = 250_000_000

  private static let variableTypes: Set<String> = ["image/png", "image/gif", "image/jpeg", "image/tiff", "image/webp", "image/avif", "image/heic", "image/heif"]
  private static let webImageTypes: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/webp"]

  public static func uploadsPath(_ room: RoomID) -> String { "/api/rooms/\(URIComponent.encode(room))/uploads" }
  public static func uploadPartPath(_ room: RoomID, _ uploadId: String, _ n: Int) -> String { "\(uploadsPath(room))/\(uploadId)/parts/\(n)" }
  public static func uploadPreviewPath(_ room: RoomID, _ uploadId: String) -> String { "\(uploadsPath(room))/\(uploadId)/preview" }

  /** `isVariable`: images Ember can resize. */
  public static func isVariable(_ contentType: String) -> Bool { variableTypes.contains(contentType) }
  /** `isPreviewed` */
  public static func isPreviewed(_ contentType: String) -> Bool { isVariable(contentType) || contentType.hasPrefix("video") }
  /** `isWebImage` */
  public static func isWebImage(_ contentType: String) -> Bool { webImageTypes.contains(contentType) }
  /** `isPreviewableSize` */
  public static func isPreviewableSize(width: Int?, height: Int?) -> Bool {
    guard let width, let height else { return false }
    return width > 0 && height > 0 && width * height <= maxPreviewPixels
  }
  /** `isKeepableFileName`: at most 255 UTF-16 units. */
  public static func isKeepableFileName(_ name: String) -> Bool { name.utf16.count <= maxFileNameLength }
}

/** packages/protocol/src/avatars.ts: the placeholder avatars Ember draws, and photo limits. */
public enum Avatars {
  public static let colors = [
    "#AF2E1B", "#CC6324", "#3B4B59", "#BFA07A", "#ED8008", "#ED3F1C", "#BF1B1B", "#736B1E", "#D07B53",
    "#736356", "#AD1D1D", "#BF7C2A", "#C09C6F", "#698F9C", "#7C956B", "#5D618F", "#3B3633", "#67695E",
  ]
  public static let avatarPath = "/api/users/me/avatar"
  public static let avatarBox = 512
  public static let maxAvatarSize = 16_000_000
  public static let avatarTooLarge = "Photos must be 16 MB or smaller."
  public static let logoPath = "/api/account/logo"
  public static let logoBoxes = (large: 512, small: 192)
  public static let maxLogoSize = maxAvatarSize
  public static let logoTooLarge = "Logos must be 16 MB or smaller."

  private static let table: [UInt32] = (0..<256).map { n in
    var c = UInt32(n)
    for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
  }

  /** `crc32` of the UTF-8 of `text`. */
  public static func crc32(_ text: String) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in text.utf8 { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFF_FFFF
  }

  /** `avatarColor`: the placeholder's colour, as `#RRGGBB`. */
  public static func color(for userId: UserID) -> String { colors[Int(crc32(userId) % UInt32(colors.count))] }

  /** `initials`: each ASCII letter, digit or underscore that starts a word, by code point as JavaScript reads it. */
  public static func initials(_ name: String) -> String {
    var found = String.UnicodeScalarView()
    var previous: Unicode.Scalar?
    for scalar in name.unicodeScalars {
      if isASCIIWord(scalar), !(previous.map(isWord) == true) { found.append(scalar) }
      previous = scalar
    }
    return String(found)
  }

  private static func isASCIIWord(_ s: Unicode.Scalar) -> Bool {
    s.isASCII && (("A"..."Z").contains(s) || ("a"..."z").contains(s) || ("0"..."9").contains(s) || s == "_")
  }

  /** `\p{Alphabetic}`, `\p{N}` or `_`. */
  private static func isWord(_ s: Unicode.Scalar) -> Bool {
    switch s.properties.generalCategory {
    case .decimalNumber, .letterNumber, .otherNumber: return true
    default: return s.properties.isAlphabetic || s == "_"
    }
  }
}
