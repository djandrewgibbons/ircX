import Foundation
import OSLog

// A huddle's connections to Cloudflare's Realtime SFU, as the web's lib/huddle.ts makes them: per kind of
// track (audio, video, screen) one sending connection, which publishes the app's own track, and one
// receiving connection, on which the SFU offers everyone else's, a round at a time. The room's socket
// carries the session descriptions between them. Neither the connections nor the tracks are made here:
// the media layer (HuddleMedia) makes them, and this decides what to ask the room for, and when.

/** What a connection's state comes to, as the signalling cares. */
public enum HuddlePeerState: Sendable { case connected, failed, other }

/** A send-only connection, made with the track it sends. */
@MainActor
public protocol HuddleSender: AnyObject {
  var onState: ((HuddlePeerState) -> Void)? { get set }
  /** Makes the offer for its track and sets it as the local description: its SDP, and the track's media section. */
  func offer() async throws -> (sdp: String, mid: String)
  /** Takes the SFU's answer to that offer. */
  func accept(answer sdp: String) async throws
  /** Sends the track the media has now in place of the one it sent, saying whether it could. */
  func swap() async -> Bool
  func close()
}

/** A receive-only connection, on which the SFU offers tracks. */
@MainActor
public protocol HuddleReceiver: AnyObject {
  var onState: ((HuddlePeerState) -> Void)? { get set }
  func take(offer sdp: String) async throws
  /** The track the connection has on media section `mid`, once it has taken the offer naming it. */
  func track(mid: String) -> AnyObject?
  /** Makes the answer to the offer it took and sets it as the local description. */
  func answer() async throws -> String
  func close()
}

/** Something to call off, as a timer that hasn't fired. */
@MainActor
public final class HuddleCancel {
  private var cancelling: (() -> Void)?

  public init(_ cancelling: @escaping () -> Void) { self.cancelling = cancelling }

  public func cancel() {
    cancelling?()
    cancelling = nil
  }
}

/** When something happens later: real time in the app, a hand-turned clock in tests. */
@MainActor
public protocol HuddleClock: AnyObject {
  func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) -> HuddleCancel
}

/** Real time. */
@MainActor
public final class HuddleRealClock: HuddleClock {
  public init() {}

  public func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) -> HuddleCancel {
    let task = Task { @MainActor in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      work()
    }
    return HuddleCancel { task.cancel() }
  }
}

/** What each connection has of the huddle it's part of (`Huddled`). */
@MainActor
public struct HuddleLink {
  /** Sends the room a frame, saying whether it went, which it doesn't while the socket is down. */
  public var send: (HuddleClientFrame) -> Bool
  /** Joins again on a new socket. */
  public var rejoin: () -> Void
  /** Whether the huddle has been left. */
  public var isOver: () -> Bool
  /** Whether what the app was given to use the relay with has run out. */
  public var relayRunOut: () -> Bool

  public init(send: @escaping (HuddleClientFrame) -> Bool, rejoin: @escaping () -> Void, isOver: @escaping () -> Bool, relayRunOut: @escaping () -> Bool) {
    self.send = send
    self.rejoin = rejoin
    self.isOver = isOver
    self.relayRunOut = relayRunOut
  }
}

/** A wait that doubles each time it's taken, from `least` to `most`, until it's started over (`growingWait`). */
public struct GrowingWait: Sendable {
  let least: Double
  let most: Double
  private var next: Double

  public init(_ least: Double, _ most: Double) {
    self.least = least
    self.most = most
    next = least
  }

  public mutating func take() -> Double {
    let wait = next
    next = min(most, next * 2)
    return wait
  }

  public mutating func startOver() { next = least }
}

public enum HuddleTiming {
  /** `ANSWER_TIMEOUT_MS` */
  public static let answerTimeout = 45.0
  /** `LISTEN_AGAIN_MS` */
  public static let listenAgain = (0.5, 8.0)
  /** `PUBLISH_AGAIN_MS` */
  public static let publishAgain = (1.0, 15.0)
  /** `CAMERA_BITRATE` */
  public static let cameraBitrate = 500_000
  /** `SCREEN_BITRATE` */
  public static let screenBitrate = 1_500_000
}

let huddleLogger = Logger(subsystem: "ai.dxnd.ircX", category: "huddle")

/**
 * One of the app's sending connections (`sendingConnection`), which publishes a track: its microphone,
 * its camera while that's on, or its screen while that's shared. It goes out in one size.
 */
@MainActor
public final class HuddleSending {
  public let kind: HuddleTrackKind
  /** Whether the huddle is none without it, as without its voice: an offer left unanswered joins again. */
  let vital: Bool
  /** Makes a connection sending the track there is now, or nil while there's none. */
  let connect: () -> HuddleSender?
  let link: HuddleLink
  let clock: HuddleClock
  private var connection: HuddleSender?
  /** The connection whose offer the room has yet to answer, which the app may have given up since. */
  private var unanswered: HuddleSender?
  private var timer: HuddleCancel?
  private var wait = GrowingWait(HuddleTiming.publishAgain.0, HuddleTiming.publishAgain.1)

  public init(kind: HuddleTrackKind, vital: Bool, link: HuddleLink, clock: HuddleClock, connect: @escaping () -> HuddleSender?) {
    self.kind = kind
    self.vital = vital
    self.link = link
    self.clock = clock
    self.connect = connect
  }

  /** Publishes the track from a new connection, in place of the one there was, unless an offer awaits its answer. */
  public func publish() async {
    close()
    guard unanswered == nil, let made = connect() else { return }
    connection = made
    made.onState = { [weak self, weak made] state in
      guard let self, let made, self.connection === made else { return }
      switch state {
      case .failed: self.link.relayRunOut() ? self.link.rejoin() : self.publishLater()
      case .connected:
        self.wait.startOver()
        _ = self.link.send(.connected(self.kind))
      case .other: break
      }
    }
    let offer: (sdp: String, mid: String)?
    do {
      offer = try await made.offer()
    } catch {
      huddleLogger.error("Making the \(self.kind.rawValue, privacy: .public) offer failed: \(error.localizedDescription, privacy: .public)")
      offer = nil
    }
    guard connection === made else { return }
    guard let offer else { return publishLater() }
    // Unsent, the socket is down, and the room's welcome on the next one publishes.
    guard link.send(.publish(sdp: offer.sdp, track: HuddleTrack(mid: offer.mid, kind: kind))) else { return }
    unanswered = made
    timer = clock.after(HuddleTiming.answerTimeout) { [weak self] in self?.leftUnanswered() }
  }

  /** Publishes again in a while, longer each time until a connection has connected. */
  func publishLater() {
    close()
    guard unanswered == nil, !link.isOver() else { return }
    timer = clock.after(wait.take()) { [weak self] in
      guard let self else { return }
      Task { await self.publish() }
    }
  }

  private func leftUnanswered() {
    if vital { return link.rejoin() }
    unanswered = nil
    publishLater()
  }

  /** The SFU's answer to the offer published. One to an offer given up is dropped, and what there is now goes out. */
  public func published(_ sdp: String) async {
    guard let answered = unanswered else { return }
    unanswered = nil
    timer?.cancel()
    guard answered === connection else { return await publish() }
    do {
      try await answered.accept(answer: sdp)
    } catch {
      huddleLogger.error("Taking the \(self.kind.rawValue, privacy: .public) answer failed: \(error.localizedDescription, privacy: .public)")
      if connection === answered { publishLater() }
    }
  }

  /** Sends the track there is now in place of the one sent; without a connection, or one that can't, publishes anew. */
  public func swap() async {
    let swapping = connection
    let swapped = await swapping?.swap() == true
    if !swapped, connection === swapping { await publish() }
  }

  /** Closes the connection. What the room owes an answer to, it still owes. */
  public func close() {
    if unanswered == nil { timer?.cancel() }
    connection?.close()
    connection = nil
  }

  /** The room couldn't publish what it was asked to. */
  public func failed() {
    guard let answered = unanswered else { return }
    unanswered = nil
    timer?.cancel()
    if answered === connection { publishLater() } else { Task { await publish() } }
  }

  /** The SFU has lost what was published. */
  public func unpublished() {
    if unanswered == nil { Task { await publish() } }
  }

  /** The socket is gone, and with it what the room owed an answer to. */
  public func hangUp() {
    unanswered = nil
    close()
  }

  public func startOver() { wait.startOver() }

  /** Whether it has a connection, for tests and the speaking meter. */
  public var current: HuddleSender? { connection }
}

/**
 * One of the app's receiving connections (`receivingConnection`), on which the SFU offers whoever the app
 * would receive, a round at a time: the app asks (`huddle.listen`), answers the offer if one comes, and
 * the room says `huddle.listening`.
 */
@MainActor
public final class HuddleReceiving {
  public let kind: HuddleTrackKind
  let vital: Bool
  /** Everyone else whose connection for this kind has connected. */
  let receivable: () -> [UserID]
  /** Whom of them the app would receive now: nobody's camera or screen while the huddle is closed to its bar. */
  let wanted: () -> [UserID]
  /** Whether the room is asked for them by name, as for cameras and screens. */
  let byName: Bool
  let small: (() -> Bool)?
  let play: (UserID, AnyObject) -> Void
  let stop: (UserID) -> Void
  let connect: () -> HuddleReceiver?
  let link: HuddleLink
  let clock: HuddleClock

  private var connection: HuddleReceiver?
  /** Whom the app has been offered, and so receives. */
  public private(set) var heard: Set<UserID> = []
  private var askedSmall = false
  private final class Round {
    var offered = false
    var givenUp = false
  }
  private var round: Round?
  private var timer: HuddleCancel?
  private var wait = GrowingWait(HuddleTiming.listenAgain.0, HuddleTiming.listenAgain.1)

  public init(
    kind: HuddleTrackKind, vital: Bool, byName: Bool, link: HuddleLink, clock: HuddleClock, receivable: @escaping () -> [UserID],
    wanted: @escaping () -> [UserID], small: (() -> Bool)? = nil, play: @escaping (UserID, AnyObject) -> Void, stop: @escaping (UserID) -> Void,
    connect: @escaping () -> HuddleReceiver?
  ) {
    self.kind = kind
    self.vital = vital
    self.byName = byName
    self.link = link
    self.clock = clock
    self.receivable = receivable
    self.wanted = wanted
    self.small = small
    self.play = play
    self.stop = stop
    self.connect = connect
  }

  private var isUnheard: Bool { wanted().contains { !heard.contains($0) } }
  private var unwanted: [UserID] {
    guard byName else { return [] }
    let wanted = Set(wanted())
    return heard.filter { !wanted.contains($0) }.sorted()
  }
  private var isSmall: Bool { small?() == true }
  private var isResized: Bool { !heard.isEmpty && isSmall != askedSmall }

  private var asking: HuddleClientFrame {
    .listen(kind, fresh: connection == nil, watch: byName ? wanted() : nil, small: isSmall)
  }

  /** Starts a round, unless one is under way: for whoever the app would receive and doesn't, or with `anyone`, whoever the room finds. */
  public func listen(anyone: Bool = false) {
    guard !link.isOver(), round == nil else { return }
    timer?.cancel()
    let dropped = unwanted
    guard anyone || !dropped.isEmpty || isUnheard || isResized else { return }
    guard link.send(asking) else { return }
    askedSmall = isSmall
    dropped.forEach(forget)
    round = Round()
    timer = clock.after(HuddleTiming.answerTimeout) { [weak self] in self?.leftUnanswered() }
  }

  private func listenLater() {
    timer = clock.after(wait.take()) { [weak self] in self?.listen() }
  }

  private func endRound() {
    timer?.cancel()
    round = nil
  }

  private func leftUnanswered() {
    if vital { return link.rejoin() }
    endRound()
    listenAfresh()
  }

  /** Answers the SFU's offer of `tracks`, and plays them. */
  public func offered(_ sdp: String, tracks: [OfferedHuddleTrack]) async {
    guard let asked = round else { return }
    asked.offered = true
    let answer = asked.givenUp ? nil : await answer(to: sdp, tracks: tracks)
    // The socket has gone meanwhile, or the huddle was left.
    guard round === asked else { return }
    if let answer, !asked.givenUp {
      _ = link.send(.answer(kind, sdp: answer))
      return
    }
    endRound()
    close()
    listenLater()
  }

  private func answer(to sdp: String, tracks: [OfferedHuddleTrack]) async -> String? {
    guard let made = connection ?? open() else { return nil }
    connection = made
    let present = Set(receivable())
    for track in tracks where present.contains(track.userId) { heard.insert(track.userId) }
    do {
      try await made.take(offer: sdp)
      guard connection === made else { return nil }
      for track in tracks {
        if let theirs = made.track(mid: track.mid), heard.contains(track.userId) { play(track.userId, theirs) }
      }
      return try await made.answer()
    } catch {
      huddleLogger.error("Answering the \(self.kind.rawValue, privacy: .public) offer failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  private func open() -> HuddleReceiver? {
    guard let made = connect() else { return nil }
    made.onState = { [weak self, weak made] state in
      guard let self, let made, self.connection === made, state == .failed else { return }
      if self.link.relayRunOut() { self.link.rejoin() } else { self.listenAfresh() }
    }
    return made
  }

  /** The room has answered what the app asked, which ends the round. */
  public func listening() {
    guard let ended = round else { return }
    endRound()
    if ended.offered, !ended.givenUp {
      wait.startOver()
      return listen(anyone: true)
    }
    if !unwanted.isEmpty || isResized { return listen() }
    if ended.givenUp || isUnheard { return listenLater() }
    if byName, heard.isEmpty { close() }
  }

  private func listenAfresh() {
    close()
    if let round { round.givenUp = true } else { listenLater() }
  }

  /** Stops receiving `userId`, who left, or can't be received for the moment. */
  public func forget(_ userId: UserID) {
    heard.remove(userId)
    stop(userId)
  }

  private func close() {
    connection?.close()
    connection = nil
    for userId in heard.sorted() { forget(userId) }
  }

  /** The room couldn't do what the round asked, and has let go of its side of the connection. */
  public func failed() {
    guard round != nil else { return }
    endRound()
    listenAfresh()
  }

  /** The socket is gone, and the round with it. */
  public func hangUp() {
    close()
    endRound()
  }

  public func startOver() { wait.startOver() }

  public var current: HuddleReceiver? { connection }
}
