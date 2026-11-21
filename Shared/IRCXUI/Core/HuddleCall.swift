import AVFoundation
import EmberKit
import Foundation
import HuddleMedia
import Observation
import OSLog
#if os(iOS)
import UIKit
#endif

let huddleLog = Logger(subsystem: "ai.dxnd.ircX", category: "huddle")

/**
 * The huddle the app is in (web lib/huddle.ts `joinHuddle`, and huddle-store.ts's `JoinedHuddle`): its
 * socket to the room, who's in it, and the app's own side, its microphone, camera and screen, which go
 * to Cloudflare's Realtime SFU over a sending connection each, while everyone else's come over a
 * receiving connection each. The room relays the session descriptions. The app is in one huddle at most.
 */
@MainActor
@Observable
public final class HuddleCall {
  public let session: InstanceSession
  public let roomId: RoomID
  /** Whether the room has let the app in: not as it joins, nor while its link to the room is down. */
  public private(set) var connected = false
  /** This app's person, once the room has said who they are. */
  public private(set) var you: User?
  /** Everyone in the huddle, in the order they joined, as the room last said. */
  public private(set) var roster: [HuddlePerson] = []
  public private(set) var muted: Bool
  public private(set) var sticker: HuddleSticker?
  /** Whether the app has a microphone to unmute. Without one its person only listens. */
  public private(set) var microphone: Bool
  /** The app's camera while it's on. */
  public private(set) var camera: HuddlePicture?
  /** The others' cameras the app watches, by whose each is. */
  public private(set) var watched: [UserID: HuddlePicture] = [:]
  /** The screen the app's person shares. */
  public private(set) var screen: HuddlePicture?
  /** The screens the others share that the app watches. */
  public private(set) var screens: [UserID: HuddlePicture] = [:]
  /** Whether the huddle shows opened, a tile for each person, rather than as its bar. Only then are cameras and screens watched. */
  public private(set) var isOpen = true
  /** The room's message of the huddle, whose thread is the huddle's. */
  public private(set) var messageId: String?
  /** Whether the opened huddle shows its thread beside the people in it. */
  public var showsThread = true
  /** Who's speaking now, as far as the app can hear. */
  public private(set) var speaking: Set<UserID> = []
  /** The reactions that rise now. */
  public private(set) var reactions = HuddleReactions()
  /** Set once the huddle is left, for good. */
  public private(set) var over = false
  /** Whether the app is asking for a camera, or what to share. */
  public private(set) var openingCamera = false
  public private(set) var choosingScreen = false
  /** What the person has to let ircX use in Settings, after the system wouldn't: its button opens the place. */
  public var privacy: HuddlePrivacy?

  @ObservationIgnored private let invite: [UserID]
  @ObservationIgnored private var socket: EmberSocket?
  private var engine: HuddleEngine { HuddleEngine.shared }
  @ObservationIgnored private let clock = HuddleRealClock()
  @ObservationIgnored private var relayedAt: Date?
  @ObservationIgnored private var sending: [HuddleTrackKind: HuddleSending] = [:]
  @ObservationIgnored private var receiving: [HuddleTrackKind: HuddleReceiving] = [:]
  /** The voices the app receives, by whose each is, by their tracks' ids, which their levels are measured by. */
  @ObservationIgnored private var voices: [UserID: String] = [:]
  /** The voices played, by whose each is, which go silent once their person's forgotten. */
  @ObservationIgnored private var played: [UserID: AnyObject] = [:]
  @ObservationIgnored private var speakingMeter = HuddleSpeaking()
  @ObservationIgnored private var metering: Task<Void, Never>?
  @ObservationIgnored private var smallTiles = false
  @ObservationIgnored private let sounds: HuddleSoundPlayer
  @ObservationIgnored private var awake: NSObjectProtocol?
  #if os(iOS)
  @ObservationIgnored private var interruption: NSObjectProtocol?
  #endif
  /** Called once the huddle is over, however it ended. */
  @ObservationIgnored var onOver: (() -> Void)?

  init(session: InstanceSession, roomId: RoomID, muted: Bool, microphone: Bool, invite: [UserID], sounds: HuddleSoundPlayer) {
    self.session = session
    self.roomId = roomId
    self.microphone = microphone
    self.muted = muted || !microphone
    self.invite = invite
    self.sounds = sounds
  }

  // MARK: - What it shows

  /** The room, while it's among this person's. */
  public var room: Room? { session.rooms.first { $0.id == roomId }?.room }

  /** What the huddle is called: "Huddle in Launch", "Huddle with Priya", or Huddle once the room's gone. */
  public var name: String {
    guard let room else { return "Huddle" }
    return HuddleRules.name(room, roomName: session.title(of: room))
  }

  /** Everyone in the huddle, the app's own person as the app has them: as muted as it is, with its sticker. */
  public var people: [HuddlePerson] {
    roster.map { person in
      guard person.user.id == you?.id else { return person }
      var mine = person
      mine.muted = muted
      mine.sticker = sticker
      return mine
    }
  }

  /** Everyone else in it whose track of `kind` can be received. */
  public func receivable(_ kind: HuddleTrackKind) -> [UserID] {
    roster.filter { $0.user.id != you?.id && $0.has(kind) }.map(\.user.id)
  }

  /** Whether the app's person is the only one in the huddle, as far as the room has said (`isAlone`). */
  public var isAlone: Bool { connected && roster.allSatisfy { $0.user.id == you?.id } }

  /** What it says of who's in it, on its bar: who's sharing screens first, else who's in it, or Connecting. */
  public var status: String {
    if let waiting = HuddleWords.waitingToJoin(connected: connected, letIn: you != nil) { return waiting }
    let others = people.filter { $0.user.id != you?.id }
    let sharers = others.filter(\.screen).map { session.people[$0.user.id]?.name ?? $0.user.name }
    if let sharing = HuddleWords.sharingScreens(sharers, you: screen != nil) { return sharing }
    return MessageWords.inTheHuddle(others.map { session.people[$0.user.id]?.name ?? $0.user.name })
  }

  // MARK: - Joining and leaving

  /** Connects to the room's huddle, which starts it when nobody's in it. */
  func start(camera opened: Bool) {
    if microphone {
      engine.openMicrophone()
      engine.setMuted(muted)
    } else {
      privacy = .microphone
    }
    engine.onMicrophoneChanged = { [weak self] gone in
      guard let self else { return }
      if gone { self.microphoneGone() } else { self.speakAfresh() }
    }
    engine.iceServers = [HuddleEngine.stun]
    engine.onCameraEnded = { [weak self] in self?.takeDown(.video) }
    engine.onScreenEnded = { [weak self] in self?.takeDown(.screen) }
    let link = HuddleLink(
      send: { [weak self] frame in self?.socket?.send(frame) == true },
      rejoin: { [weak self] in self?.rejoin() },
      isOver: { [weak self] in self?.over != false },
      relayRunOut: { [weak self] in
        guard let relayedAt = self?.relayedAt else { return false }
        return Date().timeIntervalSince(relayedAt) >= Double(Huddles.relayTTLSeconds)
      })
    for kind in HuddleTrackKind.allCases {
      sending[kind] = HuddleSending(kind: kind, vital: kind == .audio, link: link, clock: clock) { [weak self] in self?.engine.sender(kind) }
      receiving[kind] = HuddleReceiving(
        kind: kind, vital: kind == .audio, byName: kind != .audio, link: link, clock: clock,
        receivable: { [weak self] in self?.receivable(kind) ?? [] },
        wanted: { [weak self] in
          guard let self else { return [] }
          switch kind {
          case .audio: return self.receivable(.audio)
          case .video: return self.isOpen ? Array(self.receivable(.video).prefix(Huddles.maxCameras)) : []
          case .screen: return self.isOpen ? Array(self.receivable(.screen).prefix(Huddles.maxScreens)) : []
          }
        },
        small: kind == .video ? { [weak self] in self?.smallTiles == true } : nil,
        play: { [weak self] userId, track in self?.play(kind, userId, track) },
        stop: { [weak self] userId in self?.stopPlaying(kind, userId) },
        connect: { [weak self] in
          do {
            return try self?.engine.receiver()
          } catch {
            huddleLog.error("Making the \(kind.rawValue, privacy: .public) receiving connection failed: \(error.localizedDescription, privacy: .public)")
            return nil
          }
        })
    }
    let api = session.api
    let socket = EmberSocket { [weak self, api, roomId] in
      api.socketRequest(Huddles.socketPath(roomId, muted: self?.muted == true))
    }
    socket.onText = { [weak self] text in self?.receive(text) }
    socket.onState = { [weak self] state in
      if case .waiting = state { self?.roomLost() }
    }
    socket.onHuddleEnded = { [weak self] code in self?.end(HuddleWords.ending(code)) }
    // Where neither the close's code nor its reason said why, Ember's own pages do.
    socket.onDropped = { [weak self] in
      guard let self else { return }
      let letIn = self.connected
      let clean = self.socket?.closedByPeer == true
      Task { await self.checkWhyDropped(letIn: letIn, clean: clean) }
    }
    socket.onEnded = { [weak self] code in
      switch code {
      case .notFound: self?.end(HuddleWords.roomGone)
      case .revoked, .reconnect: self?.end(nil)
      }
    }
    self.socket = socket
    socket.connect()
    keepAwake()
    // The preview's camera, or, where leaving the huddle before took it down, the camera opened again.
    if opened {
      if let picture = engine.camera { showOwn(.video, picture) } else { setCamera(true) }
    }
    sounds.hears = { [weak self] in
      guard let sounds = self?.session.huddleSounds else { return HuddleSounds.all }
      return sounds
    }
    sounds.startHuddle()
    watchSettings()
  }

  /** Leaves for good: the socket closes, which is how the room hears, and so do the connections and the devices. */
  public func leave() { stop() }

  private func end(_ why: String?) {
    stop()
    if let why { tell(why) }
  }

  private func stop() {
    guard !over else { return }
    over = true
    socket?.disconnect()
    socket = nil
    hangUp()
    metering?.cancel()
    speaking = []
    reactions.stop()
    sounds.endHuddle(letIn: you != nil)
    engine.closeMicrophone()
    engine.closeCamera()
    engine.stopScreen()
    engine.onCameraEnded = nil
    engine.onScreenEnded = nil
    engine.onMicrophoneChanged = nil
    for track in played.values { HuddleVoice.setPlaying(track, false) }
    played = [:]
    session.closeApartBuffer(roomId)
    letSleep()
    onOver?()
  }

  /**
   * Why the socket dropped, where it didn't say: huddles turned off, here or in the room; the room gone;
   * the huddle full, for a join the room never let in; or, for one it did that it closed on purpose, the
   * huddle joined somewhere else, where the app's person is still in it. Anything else connects again.
   */
  private func checkWhyDropped(letIn: Bool, clean: Bool) async {
    let account: Account
    do {
      account = try await session.api.bootstrap().account
    } catch {
      // Unreachable for now: the socket keeps trying, and says so.
      huddleLog.error("Checking why the huddle dropped failed: \(error.localizedDescription, privacy: .public)")
      return
    }
    guard !over else { return }
    session.adoptAccount(account)
    if !account.huddles { return end(HuddleWords.ending(.off)) }
    await session.refreshSidebar()
    guard !over else { return }
    guard let room else { return end(HuddleWords.roomGone) }
    if !room.isDirect, !room.allowsHuddles { return end(HuddleWords.offInRoom) }
    guard clean, let me = session.me?.id, let live = session.huddles[roomId] else { return }
    if !letIn, live.userIds.filter({ $0 != me }).count >= Huddles.maxPeople { return end(HuddleWords.ending(.full)) }
    if letIn, live.userIds.contains(me) { end(HuddleWords.ending(.moved)) }
  }

  /** The socket is gone, and the connections with it; the next welcome starts them again. */
  private func roomLost() {
    hangUp()
    if connected { connected = false }
    sounds.setAlone(false)
  }

  /** Joins again on a new socket, the room having left something unanswered, or the relay's time having run out. */
  private func rejoin() {
    guard !over else { return }
    socket?.disconnect()
    roomLost()
    socket?.connect()
  }

  private func hangUp() {
    for kind in HuddleTrackKind.allCases {
      sending[kind]?.hangUp()
      receiving[kind]?.hangUp()
    }
  }

  private func listen() {
    for kind in HuddleTrackKind.allCases { receiving[kind]?.listen() }
  }

  // MARK: - Controls

  public func setMuted(_ to: Bool) {
    guard microphone, to != muted else { return }
    engine.setMuted(to)
    socket?.send(.mute(to))
    muted = to
  }

  public func setCamera(_ on: Bool) {
    if on { Task { await turnCameraOn(nil) } } else { takeDown(.video) }
  }

  public func setScreen(_ shared: Bool) {
    if shared { Task { await shareScreen() } } else { takeDown(.screen) }
  }

  /** Shows the huddle opened, or as its bar again: only an open huddle watches cameras and screens. */
  public func setOpen(_ open: Bool) {
    guard open != isOpen else { return }
    isOpen = open
    receiving[.video]?.listen()
    receiving[.screen]?.listen()
    // The thread beside it goes with it (web `useRoomApart`), and comes again on a socket of its own as it opens.
    if !open { session.closeApartBuffer(roomId) }
  }

  /** Says whether the opened huddle shows people in tiles small enough for a camera's smaller size. */
  public func setSmall(_ small: Bool) {
    guard small != smallTiles else { return }
    smallTiles = small
    receiving[.video]?.listen()
  }

  /** Asks the room to invite `userIds`, saying whether it could, which it can't while its link is down. */
  public func invite(_ userIds: [UserID]) -> Bool { socket?.send(.invite(Array(userIds.prefix(Huddles.maxInvited)))) == true }

  public func setSticker(_ next: HuddleSticker?) {
    guard next != sticker else { return }
    socket?.send(.sticker(next))
    sticker = next
  }

  /** Reacts: it shows once the room tells everyone of it, this app included. */
  public func react(_ emoji: String) {
    guard emoji.count <= Huddles.maxReactionLength else { return tell("A reaction is one emoji") }
    socket?.send(.react(emoji))
  }

  /** Shows camera `id` in place of the one that's on, or turns it on with it. */
  public func chooseCamera(_ id: String) {
    UserDefaults.standard.set(id, forKey: HuddleDevices.camera)
    guard camera != nil else { return setCamera(true) }
    guard id != engine.cameraDevice?.uniqueID else { return }
    Task { await showInstead { try await self.engine.openCamera(id) } }
  }

  /** Shows the camera facing the other way, or the next listed, in place of the one that's on. */
  public func switchCamera() {
    Task {
      await showInstead { try await self.engine.openOtherCamera() }
      if let id = engine.cameraDevice?.uniqueID { UserDefaults.standard.set(id, forKey: HuddleDevices.camera) }
    }
  }

  /** The camera that's on, by its id. */
  public var cameraId: String? { engine.cameraDevice?.uniqueID }

  /**
   * Speaks through another microphone, staying as muted as before; one that only listened for want of a
   * microphone has one to unmute (`speakThrough`). The next huddle starts with it.
   */
  public func chooseMicrophone(_ id: String) {
    Task {
      UserDefaults.standard.set(id, forKey: HuddleDevices.microphone)
      if microphone, id == HuddleEngine.microphoneId { return }
      guard await HuddleEngine.microphoneAllowed() else {
        privacy = .microphone
        return tell(microphone ? HuddleWords.noOtherMicrophone : HuddleWords.stillNoMicrophone)
      }
      do {
        try HuddleEngine.useMicrophone(id)
      } catch {
        huddleLog.error("Choosing a microphone failed: \(error.localizedDescription, privacy: .public)")
        return tell(microphone ? HuddleWords.noOtherMicrophone : HuddleWords.stillNoMicrophone)
      }
      guard !over, !microphone else { return }
      microphone = true
      privacy = nil
      engine.openMicrophone()
      engine.setMuted(muted)
      if connected { await sending[.audio]?.publish() }
    }
  }

  #if os(macOS)
  /** Plays the huddle through another speaker, the Mac's default output from now, which the next huddle starts with. */
  public func chooseSpeaker(_ id: String) {
    do {
      try HuddleEngine.useSpeaker(id)
    } catch {
      huddleLog.error("Choosing a speaker failed: \(error.localizedDescription, privacy: .public)")
      return tell(HuddleWords.noOtherSpeaker)
    }
    UserDefaults.standard.set(id, forKey: HuddleDevices.speaker)
    // libwebrtc plays through the output that's the default as its receiving starts, so it starts again.
    receiving[.audio]?.hangUp()
    receiving[.audio]?.listen()
  }
  #endif

  /** The microphone went away (unplugged, or taken back): its person only listens now (`microphoneGone`). */
  private func microphoneGone() {
    guard microphone, !over else { return }
    huddleLog.notice("The huddle's microphone went away")
    engine.setMuted(true)
    socket?.send(.mute(true))
    muted = true
    microphone = false
    if let you { speaking.remove(you.id) }
    tell(HuddleWords.microphoneGone)
  }

  /** Another microphone took the place of the one the huddle spoke through: its connection starts again, to record from it. */
  private func speakAfresh() {
    guard microphone, connected, !over else { return }
    Task { await sending[.audio]?.publish() }
  }

  private func turnCameraOn(_ id: String?) async {
    guard !over, camera == nil, !openingCamera else { return }
    openingCamera = true
    defer { openingCamera = false }
    guard await HuddleEngine.cameraAllowed() else {
      privacy = .camera
      return tell(HuddleWords.noCamera)
    }
    do {
      try await engine.openCamera(id ?? UserDefaults.standard.string(forKey: HuddleDevices.camera))
    } catch {
      huddleLog.error("Opening the camera failed: \(error.localizedDescription, privacy: .public)")
      return tell(HuddleWords.noCamera)
    }
    guard !over else { return engine.closeCamera() }
    guard let picture = engine.camera else { return tell(HuddleWords.noCamera) }
    showOwn(.video, picture)
  }

  /** Shows what `open` opens in place of the camera that's on; where it can't, the one before comes back on (`showInstead`). */
  private func showInstead(_ open: @escaping () async throws -> Void) async {
    guard !over, !openingCamera, camera != nil, let before = engine.cameraDevice?.uniqueID else { return }
    openingCamera = true
    defer { openingCamera = false }
    do {
      try await open()
    } catch {
      huddleLog.error("Opening another camera failed: \(error.localizedDescription, privacy: .public)")
      do {
        try await engine.openCamera(before)
        tell(HuddleWords.noOtherCamera)
      } catch {
        huddleLog.error("Opening the camera again failed: \(error.localizedDescription, privacy: .public)")
        tell(HuddleWords.cameraWentOff)
        return takeDown(.video)
      }
    }
    guard !over, camera != nil else { return engine.closeCamera() }
    camera = engine.camera
    if connected { await sending[.video]?.swap() }
  }

  /** Shares a screen, or a window: the system asks what each time; choosing nothing shares nothing. */
  private func shareScreen() async {
    guard !over, screen == nil, !choosingScreen else { return }
    if receivable(.screen).count >= Huddles.maxScreens { return tell(Huddles.screensFull) }
    choosingScreen = true
    defer { choosingScreen = false }
    do {
      guard try await engine.shareScreen() else { return }
    } catch {
      huddleLog.error("Sharing the screen failed: \(error.localizedDescription, privacy: .public)")
      privacy = .screen
      return tell(HuddleWords.noScreen)
    }
    guard !over else { return engine.stopScreen() }
    guard let picture = engine.screen else { return tell(HuddleWords.noScreen) }
    showOwn(.screen, picture)
  }

  private func showOwn(_ kind: HuddleTrackKind, _ picture: HuddlePicture) {
    if kind == .video { camera = picture } else { screen = picture }
    sending[kind]?.startOver()
    if connected { Task { await sending[kind]?.publish() } }
  }

  /** Takes down the camera or the screen, and has the room take down what was published of it. */
  private func takeDown(_ kind: HuddleTrackKind) {
    switch kind {
    case .audio: return
    case .video:
      guard camera != nil else { return }
      engine.closeCamera()
      camera = nil
    case .screen:
      guard screen != nil else { return }
      engine.stopScreen()
      screen = nil
    }
    sending[kind]?.close()
    socket?.send(.unpublish(kind))
  }

  private func play(_ kind: HuddleTrackKind, _ userId: UserID, _ track: AnyObject) {
    switch kind {
    case .audio:
      if let before = played[userId], before !== track { HuddleVoice.setPlaying(before, false) }
      played[userId] = track
      HuddleVoice.setPlaying(track, true)
      voices[userId] = HuddleVoice.trackId(track)
    case .video: watched[userId] = HuddlePicture(remote: track)
    case .screen: screens[userId] = HuddlePicture(remote: track)
    }
  }

  private func stopPlaying(_ kind: HuddleTrackKind, _ userId: UserID) {
    switch kind {
    case .audio:
      voices.removeValue(forKey: userId)
      if let track = played.removeValue(forKey: userId) { HuddleVoice.setPlaying(track, false) }
    case .video: watched.removeValue(forKey: userId)
    case .screen: screens.removeValue(forKey: userId)
    }
  }

  /** Tells the app's person something of their huddle. */
  func tell(_ what: String) {
    huddleLog.notice("\(what, privacy: .public)")
    session.notice = what
  }

  // MARK: - The room's frames

  private func receive(_ text: String) {
    guard !over else { return }
    let frame: HuddleServerFrame
    do {
      frame = try HuddleServerFrame.decode(text)
    } catch {
      huddleLog.error("Reading the huddle socket failed: \(error.localizedDescription, privacy: .public)")
      return
    }
    hear(frame)
  }

  /** What the room says (`hear`). */
  func hear(_ frame: HuddleServerFrame) {
    switch frame {
    case let .welcome(you, people, _, messageId, iceServers):
      if let iceServers, !iceServers.isEmpty {
        engine.iceServers = iceServers
        relayedAt = Date()
      } else {
        engine.iceServers = [HuddleEngine.stun]
        relayedAt = nil
      }
      for kind in HuddleTrackKind.allCases {
        sending[kind]?.startOver()
        receiving[kind]?.startOver()
      }
      // The address said whether the app was muted as it asked to join, which it may not be now.
      if let mine = people.first(where: { $0.user.id == you.id }) {
        if mine.muted != muted { socket?.send(.mute(muted)) }
        if mine.sticker != sticker { socket?.send(.sticker(sticker)) }
      }
      if self.you == nil {
        sounds.joined()
        // Whoever starts a DM's huddle invites the others in it, which being let back in doesn't do again.
        if !invite.isEmpty, people.allSatisfy({ $0.user.id == you.id }) { socket?.send(.invite(invite)) }
      }
      for gone in roster where !people.contains(where: { $0.user.id == gone.user.id }) { reactions.forget(gone.user.id) }
      self.you = you
      roster = people
      self.messageId = messageId
      connected = true
      sounds.setAlone(isAlone)
      for kind in HuddleTrackKind.allCases { Task { await sending[kind]?.publish() } }
      listen()
      meter()
    case let .joined(person), let .changed(person):
      for kind in HuddleTrackKind.allCases where !person.has(kind) { receiving[kind]?.forget(person.user.id) }
      if let index = roster.firstIndex(where: { $0.user.id == person.user.id }) {
        roster[index] = person
      } else {
        sounds.joined()
        roster.append(person)
      }
      sounds.setAlone(isAlone)
      listen()
    case let .left(userId):
      for kind in HuddleTrackKind.allCases { receiving[kind]?.forget(userId) }
      reactions.forget(userId)
      if roster.contains(where: { $0.user.id == userId }) { sounds.left() }
      roster.removeAll { $0.user.id == userId }
      sounds.setAlone(isAlone)
    case let .reacted(userId, emoji):
      guard roster.contains(where: { $0.user.id == userId }) else { return }
      let nth = reactions.show(userId, emoji: emoji)
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(HuddleReactions.showsFor))
        self?.reactions.expire(nth)
      }
    case let .published(kind, sdp):
      Task { await sending[kind]?.published(sdp) }
    case let .unpublished(kind):
      sending[kind]?.unpublished()
    case let .offer(kind, sdp, tracks):
      Task { await receiving[kind]?.offered(sdp, tracks: tracks) }
    case let .listening(kind):
      receiving[kind]?.listening()
    case let .error(message, failed, kind, refused):
      couldNot(message: message, failed: failed, kind: kind ?? .audio, refused: refused)
    case .pong, .unknown:
      break
    }
  }

  /** The room couldn't do what a frame asked (`couldNot`). */
  private func couldNot(message: String, failed: String?, kind: HuddleTrackKind, refused: Bool) {
    huddleLog.error("The huddle refused \(failed ?? "a frame", privacy: .public): \(message, privacy: .public)")
    switch failed {
    case "huddle.invite": tell(message)
    case "huddle.listen", "huddle.answer": receiving[kind]?.failed()
    case "huddle.publish":
      if refused, kind != .audio {
        takeDown(kind)
        tell(message)
      }
      sending[kind]?.failed()
    default:
      tell(message)
    }
  }

  // MARK: - Speaking

  /** Measures the voices every tenth of a second, the app's own from what it sends. */
  private func meter() {
    guard metering == nil else { return }
    metering = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(HuddleSpeaking.measuredEvery))
        guard let self, !self.over else { return }
        await self.measure()
      }
    }
  }

  private func measure() async {
    var levels: [UserID: Double] = [:]
    if let receiver = receiving[.audio]?.current as? PeerReceiver {
      let byTrack = await receiver.levels()
      for (userId, trackId) in voices { if let level = byTrack[trackId] { levels[userId] = level } }
    }
    if let you, microphone, let sender = sending[.audio]?.current as? PeerSender, let level = await sender.level() { levels[you.id] = level }
    let silent = Set(people.filter(\.muted).map(\.user.id))
    let now = speakingMeter.hear(levels, muted: silent, now: Date())
    if now != speaking { speaking = now }
  }

  // MARK: - Settings that end things

  /**
   * Follows what administrators change meanwhile: huddles turned off here, or in the room, end it, and
   * cameras turned off take the camera down (web workspace.tsx).
   */
  private func watchSettings() {
    withObservationTracking {
      _ = session.account?.huddles
      _ = session.account?.huddleCameras
      _ = session.account?.huddleScreens
      _ = room?.allowsHuddles
      _ = session.huddleSounds
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, !self.over else { return }
        // Music turned off stops at once, and turned on starts as if the person had just found themselves alone.
        self.sounds.cueMusic()
        self.checkSettings()
        self.watchSettings()
      }
    }
  }

  private func checkSettings() {
    guard let account = session.account else { return }
    if !account.huddles { return end(HuddleWords.ending(.off)) }
    if room?.allowsHuddles == false { return end(HuddleWords.offInRoom) }
    if !account.huddleCameras, camera != nil {
      takeDown(.video)
      tell(Huddles.camerasOff)
    }
    // A screen shared as administrators turn sharing off is taken down (web `sharesScreenUnallowed`).
    if !account.huddleScreens, screen != nil {
      takeDown(.screen)
      tell(Huddles.screensOff)
    }
  }

  // MARK: - Staying awake

  private func keepAwake() {
    #if os(iOS)
    UIApplication.shared.isIdleTimerDisabled = true
    interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
      guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
      MainActor.assumeIsolated {
        guard let self, !self.muted else { return }
        self.setMuted(true)
        self.tell(HuddleWords.microphoneInterrupted)
      }
    }
    #else
    awake = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "In a huddle")
    #endif
  }

  private func letSleep() {
    #if os(iOS)
    UIApplication.shared.isIdleTimerDisabled = false
    if let interruption { NotificationCenter.default.removeObserver(interruption) }
    interruption = nil
    #else
    if let awake { ProcessInfo.processInfo.endActivity(awake) }
    awake = nil
    #endif
  }

  // MARK: - Showing it without joining (render tests)

  /** A huddle as it would show, never connected to anything, for render tests. */
  static func shown(
    session: InstanceSession, roomId: RoomID, you: User, people: [HuddlePerson], muted: Bool = false, open: Bool = true, messageId: String? = nil,
    speaking: Set<UserID> = [], reactions: [(UserID, String)] = [], sharing: [UserID] = []
  ) -> HuddleCall {
    let call = HuddleCall(session: session, roomId: roomId, muted: muted, microphone: true, invite: [], sounds: HuddleSoundPlayer())
    call.you = you
    call.roster = people
    call.connected = true
    call.isOpen = open
    call.messageId = messageId
    call.speaking = speaking
    for (who, emoji) in reactions { call.reactions.show(who, emoji: emoji) }
    for who in sharing {
      if who == you.id { call.screen = HuddleEngine.shared.stillPicture() } else { call.screens[who] = HuddleEngine.shared.stillPicture() }
    }
    return call
  }
}

/** Where the devices last chosen are kept, which the next huddle starts with (web `ember:huddle-*`). */
enum HuddleDevices {
  static let camera = "huddle.camera"
  static let microphone = "huddle.microphone"
  static let speaker = "huddle.speaker"

  /**
   * Speaks through the microphone chosen last, and on a Mac plays through the speaker chosen last, where
   * they're there (web `rememberedDevice`); one that isn't stays remembered for when it's back.
   */
  @MainActor
  static func useRemembered() {
    if let id = UserDefaults.standard.string(forKey: microphone), id != HuddleEngine.microphoneId, HuddleEngine.microphones.contains(where: { $0.id == id }) {
      do {
        try HuddleEngine.useMicrophone(id)
      } catch {
        huddleLog.error("Speaking through the microphone chosen last failed: \(error.localizedDescription, privacy: .public)")
      }
    }
    #if os(macOS)
    if let id = UserDefaults.standard.string(forKey: speaker), id != HuddleEngine.speakerId, HuddleEngine.speakers.contains(where: { $0.id == id }) {
      do {
        try HuddleEngine.useSpeaker(id)
      } catch {
        huddleLog.error("Playing through the speaker chosen last failed: \(error.localizedDescription, privacy: .public)")
      }
    }
    #endif
  }
}

/** What the person lets ircX use in Settings, and where: the microphone, the camera, or recording the screen. */
public enum HuddlePrivacy: Sendable {
  case microphone, camera, screen

  /** The place in Settings that lets ircX use it. */
  var settings: URL? {
    #if os(iOS)
    URL(string: UIApplication.openSettingsURLString)
    #else
    switch self {
    case .microphone: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    case .camera: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    case .screen: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }
    #endif
  }

  var help: String {
    switch self {
    case .microphone: "Let ircX use your microphone in \(HuddleWords.privacySettings)"
    case .camera: "Let ircX use your camera in \(HuddleWords.privacySettings)"
    case .screen: "Let ircX record the screen in \(HuddleWords.privacySettings)"
    }
  }
}
