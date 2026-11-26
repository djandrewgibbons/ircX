import Foundation

// packages/protocol/src/huddles.ts: huddles' settings, people, sounds, and the huddle socket's frames.

/** The huddle going on in a room (`LiveHuddle`). */
public struct LiveHuddle: Codable, Hashable, Sendable {
  public var startedAt: String
  public var userIds: [UserID]
}

/** The huddle a room's message stands for (`MessageHuddle`): `endedAt` once it's over. */
public struct MessageHuddle: Codable, Hashable, Sendable {
  public var startedAt: String
  public var endedAt: String?
  public var people: [User]?
}

/** A huddle that's over, as the Huddles page lists it (`PastHuddle`). */
public struct PastHuddle: Codable, Hashable, Sendable {
  public var roomId: RoomID
  public var messageId: String
  public var startedAt: String
  public var endedAt: String
  public var userIds: [UserID]
  public var replies: Int
}

/** What `GET /api/huddles` answers (`PastHuddles`). */
public struct PastHuddles: Codable, Sendable {
  public var huddles: [PastHuddle]
}

/** Which huddle sounds someone hears (`HuddleSounds`, `HUDDLE_SOUNDS`). */
public struct HuddleSounds: Codable, Hashable, Sendable {
  public var music: Bool
  public var chimes: Bool
  public var ring: Bool

  public init(music: Bool, chimes: Bool, ring: Bool) {
    self.music = music
    self.chimes = chimes
    self.ring = ring
  }

  /** `ALL_HUDDLE_SOUNDS` */
  public static let all = HuddleSounds(music: true, chimes: true, ring: true)
  /** `hearsAllHuddleSounds` */
  public var hearsAll: Bool { music && chimes && ring }
}

/** What `PATCH /api/users/me/huddle-sounds` changes (`HuddleSoundChanges`). */
public struct HuddleSoundChanges: Codable, Hashable, Sendable {
  public var music: Bool?
  public var chimes: Bool?
  public var ring: Bool?

  public init(music: Bool? = nil, chimes: Bool? = nil, ring: Bool? = nil) {
    self.music = music
    self.chimes = chimes
    self.ring = ring
  }
}

/** `HuddleSoundsChanged` */
public struct HuddleSoundsChanged: Codable, Sendable {
  public var sounds: HuddleSounds
}

/** Huddles as the Huddles tab's card shows administrators (`HuddlesSettings`). */
public struct HuddlesSettings: Codable, Hashable, Sendable {
  public var appId: String
  public var relayKeyId: String?
}

/** `HuddlesSetup`: the Realtime SFU app's keys. */
public struct HuddlesSetup: Codable, Sendable {
  public var appId: String
  public var appSecret: String

  public init(appId: String, appSecret: String) {
    self.appId = appId
    self.appSecret = appSecret
  }
}

/** `HuddleRelaySetup`: the TURN key for strict networks. */
public struct HuddleRelaySetup: Codable, Sendable {
  public var keyId: String
  public var apiToken: String

  public init(keyId: String, apiToken: String) {
    self.keyId = keyId
    self.apiToken = apiToken
  }
}

/** `HuddlesSaved` / `HuddlesForgotten`: the settings, or nil once huddles are off. */
public struct HuddlesAnswer: Codable, Sendable {
  public var huddles: HuddlesSettings?
}

public enum HuddleTrackKind: String, Codable, Sendable, CaseIterable {
  case audio, video, screen
}

public struct HuddleTrack: Codable, Hashable, Sendable {
  public var mid: String
  public var kind: HuddleTrackKind

  public init(mid: String, kind: HuddleTrackKind) {
    self.mid = mid
    self.kind = kind
  }
}

/** `OfferedHuddleTrack`: a track the SFU offers, and whose it is. */
public struct OfferedHuddleTrack: Codable, Hashable, Sendable {
  public var mid: String
  public var kind: HuddleTrackKind
  public var userId: UserID
}

/** `HUDDLE_STICKERS` */
public enum HuddleSticker: String, Codable, Sendable, CaseIterable {
  case hand, brb, thumbsUp = "thumbs-up", thumbsDown = "thumbs-down", done
}

/** Someone in a huddle (`HuddlePerson`): `audio`, `video` and `screen` once they can be received. */
public struct HuddlePerson: Codable, Hashable, Sendable {
  public var user: User
  public var muted: Bool
  public var audio: Bool
  public var video: Bool
  public var screen: Bool
  public var sticker: HuddleSticker?

  public func has(_ kind: HuddleTrackKind) -> Bool {
    switch kind {
    case .audio: audio
    case .video: video
    case .screen: screen
    }
  }
}

/** `HuddleIceServer` */
public struct HuddleIceServer: Codable, Hashable, Sendable {
  public var urls: [String]
  public var username: String?
  public var credential: String?

  public init(urls: [String], username: String?, credential: String?) {
    self.urls = urls
    self.username = username
    self.credential = credential
  }
}

/** What a huddle closes its socket with (`HuddleCloseCode`), none of which is retried. */
public enum HuddleCloseCode: Int, Sendable {
  case full = 4005
  case off = 4006
  case moved = 4007
}

public enum Huddles {
  public static let maxPeople = 50
  public static let maxCameras = 25
  public static let maxScreens = 2
  public static let maxInvited = maxPeople
  public static let maxReactionLength = 16
  public static let relayTTLSeconds = 86_400
  public static let maxSDPLength = 500_000
  public static let pastHuddlesListed = 50
  /** `CAMERA_SIZES`: the simulcast encodings' rids. */
  public static let cameraSizes = (large: "a", small: "b")

  /** `huddleSocketQuery` */
  public static func socketQuery(muted: Bool) -> String { muted ? "?muted=1" : "" }
  /** The huddle socket's path, with its query. */
  public static func socketPath(_ room: RoomID, muted: Bool) -> String { "/api/rooms/\(URIComponent.encode(room))/huddle\(socketQuery(muted: muted))" }

  /** `appIdOf`: 32 letters and digits. */
  public static func appId(of text: String) -> String? {
    let appId = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return appId.count == 32 && isAlphanumeric(appId) ? appId : nil
  }

  /** `appSecretOf`: 64 letters and digits. */
  public static func appSecret(of text: String) -> String? {
    let secret = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return secret.count == 64 && isAlphanumeric(secret) ? secret : nil
  }

  /** `relayKeyIdOf` */
  public static func relayKeyId(of text: String) -> String? {
    let keyId = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return keyId.count <= 64 && isAlphanumeric(keyId) ? keyId : nil
  }

  /** `relayApiTokenOf` */
  public static func relayApiToken(of text: String) -> String? {
    let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return token.utf16.count <= 256 && token.wholeMatch(of: #/[A-Za-z0-9._~+\/-]+=*/#) != nil ? token : nil
  }

  private static func isAlphanumeric(_ text: String) -> Bool {
    !text.isEmpty && text.unicodeScalars.allSatisfy { $0.isASCII && (("0"..."9").contains($0) || ("a"..."z").contains($0) || ("A"..."Z").contains($0)) }
  }

  public static let appIdRefused = "An App ID is 32 letters and digits. Copy it from your app under Realtime's Serverless SFU in the Cloudflare dashboard."
  public static let appSecretRefused = "An App Secret is 64 letters and digits. Copy it from your app under Realtime's Serverless SFU in the Cloudflare dashboard."
  public static let appIdUnknown = "Cloudflare doesn't know that App ID. Copy it again from your app, or try again in a minute if you've just made it."
  public static let appSecretUnknown = "Cloudflare didn't take that App Secret for this app. Copy both from the same app."
  public static let unchecked = "Ember couldn't reach Cloudflare to check the app's keys. Try again."
  public static let forbidden = "Only administrators can set up huddles"
  public static let relayKeyIdRefused = "A TURN Token ID is letters and digits. Copy it from your TURN key under Realtime in the Cloudflare dashboard."
  public static let relayApiTokenRefused = "That can't be a TURN key's API Token. Copy it from your TURN key under Realtime in the Cloudflare dashboard."
  public static let relayKeyIdUnknown = "Cloudflare doesn't know that TURN Token ID. Copy it again from your TURN key, or try again in a minute if you've just made it."
  public static let relayApiTokenUnknown = "Cloudflare didn't take that API Token for this TURN key. Copy both from the same key."
  public static let relayUnchecked = "Ember couldn't reach Cloudflare to check the TURN key. Try again."
  public static let relayWithoutHuddles = "Huddles are off. Turn them on before setting up their relay."
  public static let soundsRefused = "Each of music, chimes and ring must be true or false"
  public static let failed = "The huddle couldn't connect. Trying again."
  public static let camerasOff = "Cameras are turned off for huddles here."
  public static let camerasFull = "25 cameras are on in this huddle, which is as many as one shows. Yours can go on once someone turns theirs off."
  public static let screensOff = "Screen sharing is turned off for huddles here."
  public static let screensFull = "2 people are sharing their screens in this huddle, which is as many as one shows. You can share yours once one of them stops."
  public static let nobodyInvited = "Ember couldn't invite anyone to the huddle just now."
  public static let invitedTooOften = "You've invited people to this huddle a lot in the last minute. Wait a moment before inviting anyone else."
}

/** A frame the app sends on a huddle socket (`HuddleClientFrame`). */
public enum HuddleClientFrame: Sendable, Equatable, SocketFrame {
  case publish(sdp: String, track: HuddleTrack)
  case connected(HuddleTrackKind)
  case unpublish(HuddleTrackKind)
  /** `watch` is for video and screen only, `small` for video only. */
  case listen(HuddleTrackKind, fresh: Bool = false, watch: [UserID]? = nil, small: Bool = false)
  case answer(HuddleTrackKind, sdp: String)
  case mute(Bool)
  case invite([UserID])
  case sticker(HuddleSticker?)
  case react(String)
  case ping

  public var json: [String: Any] {
    switch self {
    case let .publish(sdp, track): ["type": "huddle.publish", "sdp": sdp, "tracks": [["mid": track.mid, "kind": track.kind.rawValue]]]
    case let .connected(kind): ["type": "huddle.connected", "kind": kind.rawValue]
    case let .unpublish(kind): ["type": "huddle.unpublish", "kind": kind.rawValue]
    case let .listen(kind, fresh, watch, small):
      {
        var frame: [String: Any] = ["type": "huddle.listen", "kind": kind.rawValue]
        if fresh { frame["fresh"] = true }
        if kind != .audio { frame["watch"] = watch ?? [] }
        if kind == .video, small { frame["small"] = true }
        return frame
      }()
    case let .answer(kind, sdp): ["type": "huddle.answer", "kind": kind.rawValue, "sdp": sdp]
    case let .mute(muted): ["type": "huddle.mute", "muted": muted]
    case let .invite(userIds): ["type": "huddle.invite", "userIds": userIds]
    case let .sticker(sticker): ["type": "huddle.sticker", "sticker": sticker.map { $0.rawValue as Any } ?? NSNull()]
    case let .react(emoji): ["type": "huddle.react", "emoji": emoji]
    case .ping: ["type": "ping"]
    }
  }
}

/** A frame a huddle sends (`HuddleServerFrame`). */
public enum HuddleServerFrame: Sendable, Equatable {
  case welcome(you: User, people: [HuddlePerson], startedAt: String, messageId: String?, iceServers: [HuddleIceServer]?)
  case joined(HuddlePerson)
  case changed(HuddlePerson)
  case left(UserID)
  case reacted(userId: UserID, emoji: String)
  case published(HuddleTrackKind, sdp: String)
  case offer(HuddleTrackKind, sdp: String, tracks: [OfferedHuddleTrack])
  case listening(HuddleTrackKind)
  case unpublished(HuddleTrackKind)
  /** `refused` on a failed publish means not to try again. */
  case error(message: String, failed: String?, kind: HuddleTrackKind?, refused: Bool)
  case pong
  case unknown(String)

  public static func decode(_ text: String) throws -> HuddleServerFrame {
    try JSONDecoder().decode(Envelope.self, from: Data(text.utf8)).frame
  }

  private struct Envelope: Decodable {
    let frame: HuddleServerFrame

    enum Keys: String, CodingKey {
      case type, you, people, startedAt, messageId, iceServers, person, userId, emoji, kind, sdp, tracks, message, failed, refused
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: Keys.self)
      let type = try c.decode(String.self, forKey: .type)
      switch type {
      case "huddle.welcome":
        frame = .welcome(
          you: try c.decode(User.self, forKey: .you), people: try c.decode([HuddlePerson].self, forKey: .people),
          startedAt: try c.decode(String.self, forKey: .startedAt), messageId: try c.decodeIfPresent(String.self, forKey: .messageId),
          iceServers: try c.decodeIfPresent([HuddleIceServer].self, forKey: .iceServers))
      case "huddle.joined": frame = .joined(try c.decode(HuddlePerson.self, forKey: .person))
      case "huddle.changed": frame = .changed(try c.decode(HuddlePerson.self, forKey: .person))
      case "huddle.left": frame = .left(try c.decode(String.self, forKey: .userId))
      case "huddle.reacted": frame = .reacted(userId: try c.decode(String.self, forKey: .userId), emoji: try c.decode(String.self, forKey: .emoji))
      case "huddle.published": frame = .published(try c.decode(HuddleTrackKind.self, forKey: .kind), sdp: try c.decode(String.self, forKey: .sdp))
      case "huddle.offer":
        frame = .offer(try c.decode(HuddleTrackKind.self, forKey: .kind), sdp: try c.decode(String.self, forKey: .sdp), tracks: try c.decode([OfferedHuddleTrack].self, forKey: .tracks))
      case "huddle.listening": frame = .listening(try c.decode(HuddleTrackKind.self, forKey: .kind))
      case "huddle.unpublished": frame = .unpublished(try c.decode(HuddleTrackKind.self, forKey: .kind))
      case "error":
        frame = .error(
          message: try c.decode(String.self, forKey: .message), failed: try c.decodeIfPresent(String.self, forKey: .failed),
          kind: try c.decodeIfPresent(HuddleTrackKind.self, forKey: .kind), refused: try c.decodeIfPresent(Bool.self, forKey: .refused) == true)
      case "pong": frame = .pong
      default: frame = .unknown(type)
      }
    }
  }
}
