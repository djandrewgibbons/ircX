import AVFoundation
import EmberKit
import Foundation
import OSLog
@preconcurrency import WebRTC

/**
 * What carries a huddle's media, through Google's libwebrtc: the app's microphone, camera and shared
 * screen, and the connections to Cloudflare's Realtime SFU that send them and receive everyone else's.
 * One huddle at a time, so one engine for the app. The signalling (EmberKit's `HuddleSending` and
 * `HuddleReceiving`) decides what's connected when; this only makes and runs it.
 */
@MainActor
public final class HuddleEngine {
  public static let shared = HuddleEngine()

  /** Cloudflare's STUN server, by which a connection learns the address the SFU reaches it at (`CONNECTION`). */
  public static let stun = HuddleIceServer(urls: ["stun:stun.cloudflare.com:3478"], username: nil, credential: nil)

  let factory: RTCPeerConnectionFactory
  nonisolated static let logger = Logger(subsystem: "ai.dxnd.ircX", category: "huddle")

  /** The servers connections go by, as the room's welcome gave them, the relay's among them; STUN alone without. */
  public var iceServers: [HuddleIceServer] = [HuddleEngine.stun]

  /** The microphone's track while the app has one open. */
  public private(set) var microphone: RTCAudioTrack?
  /** The camera's picture while it's on, and which camera it is. */
  public private(set) var camera: HuddlePicture?
  public private(set) var cameraDevice: AVCaptureDevice?
  private var cameraCapturer: RTCCameraVideoCapturer?
  private var cameraSource: RTCVideoSource?
  private var cameraGone: NSObjectProtocol?
  /** Called as the camera that's on is unplugged, or taken by another app. */
  public var onCameraEnded: (() -> Void)?

  /** The screen the app shares, while it does. */
  public private(set) var screen: HuddlePicture?
  #if os(macOS)
  private var screenShare: ScreenShare?
  #endif
  /** Called as sharing stops from outside the app, as from the menu bar's indicator. */
  public var onScreenEnded: (() -> Void)?

  init() {
    RTCInitializeSSL()
    factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
  }

  // MARK: - Permissions and devices

  /** Asks to use the microphone, the first time, and says whether the app may and has one to use. */
  public static func microphoneAllowed() async -> Bool {
    guard await AVCaptureDevice.requestAccess(for: .audio) else { return false }
    return hasMicrophone
  }

  /** Asks to use the camera, the first time, and says whether the app may. */
  public static func cameraAllowed() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

  /** The cameras there are, by id and name. */
  public static var cameras: [HuddleDevice] {
    RTCCameraVideoCapturer.captureDevices().map { HuddleDevice(id: $0.uniqueID, name: $0.localizedName) }
  }

  #if os(iOS)
  /** The microphones there are, by their ports. */
  public static var microphones: [HuddleDevice] {
    (AVAudioSession.sharedInstance().availableInputs ?? []).map { HuddleDevice(id: $0.uid, name: $0.portName) }
  }

  /** The microphone chosen, by its port's id. */
  public static var microphoneId: String? { AVAudioSession.sharedInstance().preferredInput?.uid }

  /** Speaks through the microphone `id`, which is no longer the one before. */
  public static func useMicrophone(_ id: String) throws {
    let session = AVAudioSession.sharedInstance()
    guard let port = (session.availableInputs ?? []).first(where: { $0.uid == id }) else { throw HuddleMediaError.noDevice }
    try session.setPreferredInput(port)
  }

  /** Whether there's a microphone to speak through now. */
  static var hasMicrophone: Bool { AVAudioSession.sharedInstance().isInputAvailable }
  #else
  /**
   * The microphones there are: the Mac's audio devices that take sound in. libwebrtc records from the
   * Mac's default input, so choosing one makes it the default.
   */
  public static var microphones: [HuddleDevice] { CoreAudioDevices.list(input: true) }

  /** The speakers there are, which the huddle plays through: libwebrtc plays through the Mac's default output. */
  public static var speakers: [HuddleDevice] { CoreAudioDevices.list(input: false) }

  /** The microphone huddles speak through: the Mac's default input. */
  public static var microphoneId: String? { CoreAudioDevices.defaultDevice(input: true).flatMap(CoreAudioDevices.uid) }

  /** The speaker huddles play through: the Mac's default output. */
  public static var speakerId: String? { CoreAudioDevices.defaultDevice(input: false).flatMap(CoreAudioDevices.uid) }

  /** Speaks through the microphone `id`, which becomes the Mac's default input. */
  public static func useMicrophone(_ id: String) throws { try CoreAudioDevices.makeDefault(id, input: true) }

  /** Plays through the speaker `id`, which becomes the Mac's default output. */
  public static func useSpeaker(_ id: String) throws { try CoreAudioDevices.makeDefault(id, input: false) }

  /** Whether there's a microphone to speak through now. */
  static var hasMicrophone: Bool { CoreAudioDevices.defaultDevice(input: true) != nil }
  #endif

  // MARK: - Microphone

  /**
   * Called as the microphone the huddle speaks through changes under it: `gone` once there's none, as
   * one unplugged leaves, else another took its place (a Mac's default input changed), which the
   * sending connection has to start again to record from.
   */
  public var onMicrophoneChanged: ((_ gone: Bool) -> Void)?
  private var unwatchMicrophone: (() -> Void)?

  /** Opens the microphone's track, which the audio connection sends. */
  @discardableResult
  public func openMicrophone() -> RTCAudioTrack {
    if let microphone { return microphone }
    let source = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
    let track = factory.audioTrack(with: source, trackId: "microphone")
    microphone = track
    watchMicrophone()
    return track
  }

  public func closeMicrophone() {
    microphone?.isEnabled = false
    microphone = nil
    unwatchMicrophone?()
    unwatchMicrophone = nil
  }

  /** Watches for the microphone going away, or another taking its place. */
  private func watchMicrophone() {
    #if os(iOS)
    let token = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.microphone != nil, !Self.hasMicrophone else { return }
        self.onMicrophoneChanged?(true)
      }
    }
    unwatchMicrophone = { NotificationCenter.default.removeObserver(token) }
    #else
    var was = CoreAudioDevices.defaultDevice(input: true)
    let watch = CoreAudioDevices.Watch { [weak self] in
      guard let self, self.microphone != nil else { return }
      let now = CoreAudioDevices.defaultDevice(input: true)
      guard now != was else { return }
      was = now
      self.onMicrophoneChanged?(now == nil)
    }
    unwatchMicrophone = { watch.stop() }
    #endif
  }

  /** Mutes or unmutes the microphone: a muted track sends silence. */
  public func setMuted(_ muted: Bool) { microphone?.isEnabled = !muted }

  // MARK: - Camera

  /** Whether the camera that's on faces away from its person, as a phone's back camera does, which isn't mirrored. */
  public var cameraFacesAway: Bool { cameraDevice?.position == .back }

  /** Opens camera `id`, or the first there is, at about 640 by 360, in place of any open. */
  public func openCamera(_ id: String?) async throws {
    let devices = RTCCameraVideoCapturer.captureDevices()
    guard let device = devices.first(where: { $0.uniqueID == id }) ?? devices.first else { throw HuddleMediaError.noDevice }
    closeCamera()
    let source = factory.videoSource()
    let capturer = RTCCameraVideoCapturer(delegate: source)
    let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
    guard let format = Self.format(near: (640, 360), in: formats), let most = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() else {
      throw HuddleMediaError.noDevice
    }
    let fps = min(30, Int(most))
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
      capturer.startCapture(with: device, format: format, fps: fps) { error in
        if let error { done.resume(throwing: error) } else { done.resume() }
      }
    }
    source.adaptOutputFormat(toWidth: 640, height: 360, fps: Int32(fps))
    cameraCapturer = capturer
    cameraSource = source
    cameraDevice = device
    camera = HuddlePicture(track: factory.videoTrack(with: source, trackId: "camera"), mirrored: device.position != .back)
    cameraGone = NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.closeCamera()
        self?.onCameraEnded?()
      }
    }
  }

  /** Opens the camera facing the other way from the one that's on, else the next listed (`openOtherCamera`). */
  public func openOtherCamera() async throws {
    let devices = RTCCameraVideoCapturer.captureDevices()
    guard let shown = cameraDevice, let at = devices.firstIndex(of: shown), devices.count > 1 else { throw HuddleMediaError.noDevice }
    let turned = devices.first { $0.position != shown.position && $0.position != .unspecified && shown.position != .unspecified }
    try await openCamera((turned ?? devices[(at + 1) % devices.count]).uniqueID)
  }

  public func closeCamera() {
    if let cameraGone { NotificationCenter.default.removeObserver(cameraGone) }
    cameraGone = nil
    cameraCapturer?.stopCapture()
    cameraCapturer = nil
    cameraSource = nil
    cameraDevice = nil
    camera = nil
  }

  static func format(near size: (Int32, Int32), in formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
    formats.min { a, b in
      let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
      let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
      return abs(da.width - size.0) + abs(da.height - size.1) < abs(db.width - size.0) + abs(db.height - size.1)
    }
  }

  // MARK: - Screen

  /** Whether this platform shares screens: a Mac does, a phone or iPad doesn't (as the web's phones don't). */
  public static var sharesScreens: Bool {
    #if os(macOS)
    true
    #else
    false
    #endif
  }

  /** Shares the screen, or a window, the person picks with the system's picker; false when they pick nothing. */
  public func shareScreen() async throws -> Bool {
    #if os(macOS)
    guard screenShare == nil else { return true }
    let source = factory.videoSource(forScreenCast: true)
    let share = ScreenShare(source: source)
    share.onEnded = { [weak self] in
      guard let self, self.screenShare === share else { return }
      self.stopScreen()
      self.onScreenEnded?()
    }
    guard try await share.start() else { return false }
    screenShare = share
    screen = HuddlePicture(track: factory.videoTrack(with: source, trackId: "screen"), mirrored: false)
    return true
    #else
    throw HuddleMediaError.noScreen
    #endif
  }

  public func stopScreen() {
    #if os(macOS)
    screenShare?.stop()
    screenShare = nil
    #endif
    screen = nil
  }

  // MARK: - Connections

  func configuration() -> RTCConfiguration {
    let configuration = RTCConfiguration()
    configuration.iceServers = iceServers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
    configuration.sdpSemantics = .unifiedPlan
    configuration.bundlePolicy = .maxBundle
    configuration.continualGatheringPolicy = .gatherContinually
    return configuration
  }

  func makePeer() throws -> Peer {
    let peer = Peer()
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    if let connection = factory.peerConnection(with: configuration(), constraints: constraints, delegate: peer) {
      peer.connection = connection
      return peer
    }
    // A configuration the library can't make sense of goes by STUN alone, as a browser's refusal does (`connectionBy`).
    Self.logger.error("A huddle connection couldn't take the room's servers; it goes by STUN alone")
    let plain = configuration()
    plain.iceServers = [RTCIceServer(urlStrings: Self.stun.urls)]
    guard let connection = factory.peerConnection(with: plain, constraints: constraints, delegate: peer) else { throw HuddleMediaError.noConnection }
    peer.connection = connection
    return peer
  }

  /** The track there is now for `kind`, or nil while there's none: a camera that's off, a screen not shared. */
  func track(_ kind: HuddleTrackKind) -> RTCMediaStreamTrack? {
    switch kind {
    case .audio: microphone
    case .video: camera?.track
    case .screen: screen?.track
    }
  }

  /** A connection sending what there is now of `kind`, or nil while there's nothing. */
  public func sender(_ kind: HuddleTrackKind) -> PeerSender? {
    guard let track = track(kind) else { return nil }
    do {
      let peer = try makePeer()
      let options = RTCRtpTransceiverInit()
      options.direction = .sendOnly
      options.streamIds = [kind.rawValue]
      switch kind {
      case .audio: break
      case .video:
        let encoding = RTCRtpEncodingParameters()
        encoding.maxBitrateBps = NSNumber(value: HuddleTiming.cameraBitrate)
        options.sendEncodings = [encoding]
      case .screen:
        let encoding = RTCRtpEncodingParameters()
        encoding.maxBitrateBps = NSNumber(value: HuddleTiming.screenBitrate)
        encoding.maxFramerate = 15
        options.sendEncodings = [encoding]
      }
      guard let transceiver = peer.connection.addTransceiver(with: track, init: options) else { throw HuddleMediaError.noConnection }
      return PeerSender(peer: peer, transceiver: transceiver) { [weak self] in self?.track(kind) }
    } catch {
      Self.logger.error("Making the \(kind.rawValue, privacy: .public) sending connection failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /** A connection on which the SFU offers everyone else's tracks of a kind. */
  public func receiver() throws -> PeerReceiver { PeerReceiver(peer: try makePeer()) }

  /** A picture nothing plays into, as render tests show a screen shared. */
  public func stillPicture() -> HuddlePicture {
    HuddlePicture(track: factory.videoTrack(with: factory.videoSource(), trackId: "still-\(UUID().uuidString)"), mirrored: false, still: true)
  }
}

/** A camera or microphone there is, by id. */
public struct HuddleDevice: Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
}

public enum HuddleMediaError: LocalizedError {
  case noDevice, noConnection, noOffer, noScreen
  case coreAudio(Int32)

  public var errorDescription: String? {
    switch self {
    case let .coreAudio(status): "The Mac's audio couldn't change (\(status))"
    case .noDevice: "There's no such device"
    case .noConnection: "The connection couldn't be made"
    case .noOffer: "The connection made no session description"
    case .noScreen: "This device can't share its screen"
    }
  }
}

/** A picture: someone's camera or screen, or the app's own, which a video view shows. */
@MainActor
public final class HuddlePicture: Identifiable {
  let track: RTCVideoTrack
  /** Whether it's shown mirrored, as the app's own front camera is. */
  public let mirrored: Bool
  /** Whether nothing plays into it, as render tests' pictures, which show as a still in place of a video view. */
  let still: Bool

  init(track: RTCVideoTrack, mirrored: Bool, still: Bool = false) {
    self.track = track
    self.mirrored = mirrored
    self.still = still
  }

  /** Someone else's picture, from what a receiving connection plays; nil for a voice. */
  public convenience init?(remote: AnyObject) {
    guard let track = remote as? RTCVideoTrack else { return nil }
    self.init(track: track, mirrored: false)
  }

  public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/** A voice the app receives, by its track's id, which the connection's statistics measure it by. */
public enum HuddleVoice {
  public static func trackId(_ remote: AnyObject) -> String? { (remote as? RTCAudioTrack)?.trackId }

  /**
   * Plays a voice received, or stops playing it: libwebrtc plays every voice a connection receives,
   * so one the huddle doesn't play (its person left, or can't be heard for now) is turned off.
   */
  @MainActor
  public static func setPlaying(_ remote: AnyObject, _ playing: Bool) { (remote as? RTCAudioTrack)?.isEnabled = playing }
}

/** An RTCPeerConnection and what it tells, on the main actor. */
final class Peer: NSObject, RTCPeerConnectionDelegate {
  var connection: RTCPeerConnection!
  var onState: ((HuddlePeerState) -> Void)?

  func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
    let state: HuddlePeerState =
      switch newState {
      case .connected: .connected
      case .failed: .failed
      default: .other
      }
    DispatchQueue.main.async {
      MainActor.assumeIsolated { self.onState?(state) }
    }
  }

  func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

  static let noConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

  func setLocal(_ description: RTCSessionDescription) async throws {
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
      connection.setLocalDescription(description) { error in
        if let error { done.resume(throwing: error) } else { done.resume() }
      }
    }
  }

  func setRemote(_ description: RTCSessionDescription) async throws {
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
      connection.setRemoteDescription(description) { error in
        if let error { done.resume(throwing: error) } else { done.resume() }
      }
    }
  }

  func made(_ make: (@escaping @Sendable (RTCSessionDescription?, (any Error)?) -> Void) -> Void) async throws -> RTCSessionDescription {
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<RTCSessionDescription, Error>) in
      make { description, error in
        if let description {
          done.resume(returning: description)
        } else if let error {
          done.resume(throwing: error)
        } else {
          done.resume(throwing: HuddleMediaError.noOffer)
        }
      }
    }
  }

  /** What the connection's statistics say of `type` entries of audio: their level, by `key`. */
  func audioLevels(type: String, key: String) async -> [String: Double] {
    await withCheckedContinuation { (done: CheckedContinuation<[String: Double], Never>) in
      connection.statistics { report in
        var levels: [String: Double] = [:]
        for stats in report.statistics.values where stats.type == type {
          guard (stats.values["kind"] as? String) == "audio", let level = stats.values["audioLevel"] as? NSNumber, let id = stats.values[key] as? String else { continue }
          levels[id] = level.doubleValue
        }
        done.resume(returning: levels)
      }
    }
  }
}

/** A send-only connection (`HuddleSender`). */
@MainActor
public final class PeerSender: HuddleSender {
  let peer: Peer
  let transceiver: RTCRtpTransceiver
  let current: () -> RTCMediaStreamTrack?

  init(peer: Peer, transceiver: RTCRtpTransceiver, current: @escaping () -> RTCMediaStreamTrack?) {
    self.peer = peer
    self.transceiver = transceiver
    self.current = current
  }

  public var onState: ((HuddlePeerState) -> Void)? {
    get { peer.onState }
    set { peer.onState = newValue }
  }

  public func offer() async throws -> (sdp: String, mid: String) {
    let offer = try await peer.made { peer.connection.offer(for: Peer.noConstraints, completionHandler: $0) }
    try await peer.setLocal(offer)
    guard let sdp = peer.connection.localDescription?.sdp, !transceiver.mid.isEmpty else { throw HuddleMediaError.noOffer }
    return (sdp, transceiver.mid)
  }

  public func accept(answer sdp: String) async throws {
    try await peer.setRemote(RTCSessionDescription(type: .answer, sdp: sdp))
  }

  public func swap() async -> Bool {
    guard let track = current() else { return false }
    transceiver.sender.track = track
    return true
  }

  public func close() {
    peer.onState = nil
    peer.connection.close()
  }

  /** How loud the microphone it sends is, 0 to 1, or nil before the statistics say. */
  public func level() async -> Double? {
    await peer.audioLevels(type: "media-source", key: "trackIdentifier").values.first
  }
}

/** A receive-only connection (`HuddleReceiver`). */
@MainActor
public final class PeerReceiver: HuddleReceiver {
  let peer: Peer

  init(peer: Peer) { self.peer = peer }

  public var onState: ((HuddlePeerState) -> Void)? {
    get { peer.onState }
    set { peer.onState = newValue }
  }

  /** The media sections the connection has taken offers of, whose voices the huddle turns on as it plays them. */
  private var known: Set<String> = []

  public func take(offer sdp: String) async throws {
    try await peer.setRemote(RTCSessionDescription(type: .offer, sdp: sdp))
    // A voice newly offered stays silent until the huddle plays it, as it does only someone in it who can be heard.
    for transceiver in peer.connection.transceivers where !known.contains(transceiver.mid) {
      known.insert(transceiver.mid)
      (transceiver.receiver.track as? RTCAudioTrack)?.isEnabled = false
    }
  }

  public func track(mid: String) -> AnyObject? {
    peer.connection.transceivers.first { $0.mid == mid }?.receiver.track
  }

  public func answer() async throws -> String {
    let answer = try await peer.made { peer.connection.answer(for: Peer.noConstraints, completionHandler: $0) }
    try await peer.setLocal(answer)
    guard let sdp = peer.connection.localDescription?.sdp else { throw HuddleMediaError.noOffer }
    return sdp
  }

  public func close() {
    peer.onState = nil
    peer.connection.close()
  }

  /** How loud each voice it receives is, 0 to 1, by its track's id. */
  public func levels() async -> [String: Double] {
    await peer.audioLevels(type: "inbound-rtp", key: "trackIdentifier")
  }
}
