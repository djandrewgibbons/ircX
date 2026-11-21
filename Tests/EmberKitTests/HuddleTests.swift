@testable import EmberKit
import Foundation
import XCTest

/** Huddles: the web's words, tile layout, reactions, ringing, the /huddle command, and the signalling with a fake SFU. */
@MainActor
final class HuddleTests: XCTestCase {
  // MARK: - Words (lib/huddle-people.test.ts)

  func testWords() {
    XCTAssertEqual(HuddleWords.invitedOnceItStarts(["Priya Patel"]), "Priya is invited once it starts.")
    XCTAssertEqual(HuddleWords.invitedOnceItStarts(["Priya Patel", "Sam Rivera", "Leo Park", "Maya Chen"]), "Priya, Sam, Leo, and 1 other are invited once it starts.")
    XCTAssertEqual(HuddleWords.invitedNow(["Priya Patel", "Sam Rivera"]), "Priya and Sam are invited.")
    XCTAssertEqual(HuddleWords.inItNow(["Sam Rivera"], count: 3), "Sam and 2 others are in it now.")
    XCTAssertEqual(HuddleWords.inItNow([], count: 1), "1 person is in it now.")
    XCTAssertEqual(HuddleWords.inItNow(["  Sam   Rivera "], count: 1), "Sam is in it now.")
    XCTAssertEqual(HuddleWords.sharingScreens([], you: true), "You're sharing your screen")
    XCTAssertEqual(HuddleWords.sharingScreens(["Sam Rivera"], you: false), "Sam is sharing a screen")
    XCTAssertEqual(HuddleWords.sharingScreens(["Sam Rivera"], you: true), "Sam and you are sharing screens")
    XCTAssertNil(HuddleWords.sharingScreens([], you: false))
    XCTAssertEqual(MessageWords.inTheHuddle(["Sam Rivera", "Priya Patel"]), "Sam, Priya, and you are in the huddle")
    XCTAssertEqual(MessageWords.inItsHuddle(["Sam Rivera"], count: 1, you: false), "Sam is in the huddle")
    XCTAssertEqual(HuddleRules.place(Room(id: "r", kind: .open, name: "Launch"), name: "Launch"), "in Launch")
    XCTAssertEqual(HuddleRules.place(Room(id: "d", kind: .direct), name: "Priya Patel"), "with Priya Patel")
    XCTAssertEqual(HuddleWords.ending(.full), "That huddle is full. A huddle takes 50 people.")
  }

  /** Foundation reports Ember's own close codes as invalid; the close's reason names them (`CLOSE_REASONS`). */
  func testCloseCodesFromReasons() {
    XCTAssertEqual(EmberSocket.code(0, reason: Data("Full".utf8)), HuddleCloseCode.full.rawValue)
    XCTAssertEqual(EmberSocket.code(0, reason: Data("Off".utf8)), HuddleCloseCode.off.rawValue)
    XCTAssertEqual(EmberSocket.code(0, reason: Data("Moved".utf8)), HuddleCloseCode.moved.rawValue)
    XCTAssertEqual(EmberSocket.code(0, reason: Data("NotFound".utf8)), CloseCode.notFound.rawValue)
    XCTAssertEqual(EmberSocket.code(4005, reason: nil), 4005)
    XCTAssertEqual(EmberSocket.code(1006, reason: Data("Message too big".utf8)), 1006)
    XCTAssertEqual(EmberSocket.code(0, reason: nil), 0)
  }

  func testHuddleStarted() {
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let calendar = Calendar.current
    XCTAssertTrue(MessageWords.huddleStarted(now.addingTimeInterval(-60), now: now, calendar: calendar).hasPrefix(
      calendar.isDate(now.addingTimeInterval(-60), inSameDayAs: now) ? "Today at " : "Yesterday at "))
    let lastYear = calendar.date(byAdding: .year, value: -1, to: now)!
    XCTAssertTrue(MessageWords.huddleStarted(lastYear, now: now, calendar: calendar).contains(String(calendar.component(.year, from: lastYear))))
    XCTAssertFalse(MessageWords.huddleStarted(lastYear, now: now, calendar: calendar).hasPrefix("on "))
  }

  func testWhoHuddles() {
    let me = User(id: "me", name: "Me")
    let priya = User(id: "priya", name: "Priya")
    let ember = User(id: "ember", name: "Ember")
    let dm = Room(id: "d", kind: .direct, members: [me, priya, ember])
    let gone = DirectoryUser(id: "priya", name: "Priya", role: .member, status: .deactivated, avatarUrl: "/p")
    XCTAssertTrue(HuddleRules.joinsNone(ember, listed: nil))
    XCTAssertTrue(HuddleRules.joinsNone(priya, listed: gone))
    XCTAssertFalse(HuddleRules.joinsNone(priya, listed: nil))
    XCTAssertEqual(HuddleRules.huddledWith(dm, me: "me", joinsNone: { HuddleRules.joinsNone($0, listed: nil) }).map(\.id), ["priya"])
    XCTAssertFalse(HuddleRules.hasHuddles(Room(id: "d2", kind: .direct, members: [me, ember]), me: "me", joinsNone: { HuddleRules.joinsNone($0, listed: nil) }))
    XCTAssertFalse(HuddleRules.hasHuddles(Room(id: "r", kind: .open, name: "x", huddles: false), me: "me", joinsNone: { _ in false }))
    XCTAssertEqual(HuddleRules.invitable([me, priya, ember], me: "me", inIt: [], joinsNone: { HuddleRules.joinsNone($0, listed: nil) }).map(\.id), ["priya"])
  }

  // MARK: - Tiles (lib/huddle-tiles.test.ts)

  func testTiles() {
    XCTAssertEqual(HuddleLayout.tiles(1, width: 1000, height: 700), HuddleTiles(columns: 1, width: 420, square: false))
    XCTAssertEqual(HuddleLayout.tiles(4, width: 1000, height: 700), HuddleTiles(columns: 2, width: 420, square: false))
    XCTAssertEqual(HuddleLayout.tiles(5, width: 1400, height: 1000).columns, 3)
    XCTAssertEqual(HuddleLayout.tiles(4, width: 1200, height: 260), HuddleTiles(columns: 4, width: 291, square: false))
    XCTAssertEqual(HuddleLayout.tiles(2, width: 296, height: 500), HuddleTiles(columns: 1, width: 244, square: true))
    XCTAssertEqual(HuddleLayout.tiles(4, width: 296, height: 500), HuddleTiles(columns: 2, width: 142, square: true))
    XCTAssertEqual(HuddleLayout.tiles(8, width: 1000, height: 90), HuddleTiles(columns: 7, width: 132, square: false))
    XCTAssertEqual(HuddleLayout.tiles(8, width: 1040, height: 90), HuddleTiles(columns: 7, width: 138, square: false))
    XCTAssertEqual(HuddleLayout.tiles(3, width: 0, height: 0), HuddleTiles(columns: 1, width: 132, square: true))
    XCTAssertEqual(HuddleLayout.tiles(0, width: 1000, height: 700), HuddleTiles(columns: 1, width: 132, square: false))
  }

  func testStage() {
    let wide = 16.0 / 9.0
    XCTAssertEqual(HuddleLayout.stage(3, shape: wide, width: 866, height: 560), HuddleStage(beside: true, screen: 664, tiles: HuddleTiles(columns: 1, width: 190, square: false)))
    XCTAssertEqual(HuddleLayout.stage(2, shape: wide, width: 1600, height: 900), HuddleStage(beside: true, screen: 1368, tiles: HuddleTiles(columns: 1, width: 220, square: false)))
    XCTAssertEqual(HuddleLayout.stage(3, shape: 0.5, width: 866, height: 560), HuddleStage(beside: true, screen: 266, tiles: HuddleTiles(columns: 1, width: 220, square: false)))
    XCTAssertEqual(HuddleLayout.stage(3, shape: wide, width: 850, height: 200), HuddleStage(beside: true, screen: 305, tiles: HuddleTiles(columns: 3, width: 169, square: false)))
  }

  // MARK: - Reactions (lib/huddle-reactions.test.ts)

  func testReactions() {
    var shown = HuddleReactions()
    let first = shown.show("sam", emoji: "\u{1F389}")
    shown.show("priya", emoji: "\u{1F389}")
    shown.show("priya", emoji: "\u{1F44D}")
    XCTAssertEqual(shown.rising.map(\.place), [2, 0, 4])
    XCTAssertEqual(shown.runs, [ReactionRun(emoji: "\u{1F389}", first: "sam", more: 1), ReactionRun(emoji: "\u{1F44D}", first: "priya", more: 0)])
    shown.forget("sam")
    XCTAssertEqual(shown.runs.first, ReactionRun(emoji: "\u{1F389}", first: "priya", more: 1))
    shown.expire(first)
    shown.stop()
    XCTAssertTrue(shown.rising.isEmpty)
    XCTAssertTrue(shown.runs.isEmpty)
    for _ in 0..<30 { shown.show("sam", emoji: "x") }
    XCTAssertEqual(shown.rising.count, HuddleReactions.mostRising)
  }

  // MARK: - Ringing (lib/huddle-invitations.test.ts)

  func testRinging() {
    let at = Date()
    var ringing = HuddleRinging.invited([], room: "r", by: "sam", at: at)
    ringing = HuddleRinging.invited(ringing, room: "r", by: "priya", at: at)
    XCTAssertEqual(ringing.map(\.by), ["priya"])
    let seen = HuddlesSeen(on: true, me: "me", roomIds: ["r"], live: ["r": LiveHuddle(startedAt: "t", userIds: ["priya"])], joinedRoomId: nil)
    ringing = HuddleRinging.seen(ringing, seen)
    XCTAssertEqual(ringing.first?.listed, true)
    XCTAssertEqual(ringing.first?.live, true)
    // The huddle's over, having been seen going on.
    XCTAssertTrue(HuddleRinging.seen(ringing, HuddlesSeen(on: true, me: "me", roomIds: ["r"], live: [:], joinedRoomId: nil)).isEmpty)
    // Joined here, or anywhere else.
    XCTAssertTrue(HuddleRinging.seen(ringing, HuddlesSeen(on: true, me: "me", roomIds: ["r"], live: seen.live, joinedRoomId: "r")).isEmpty)
    XCTAssertTrue(HuddleRinging.seen(ringing, HuddlesSeen(on: true, me: "me", roomIds: ["r"], live: ["r": LiveHuddle(startedAt: "t", userIds: ["me"])], joinedRoomId: nil)).isEmpty)
    // The room's gone, once it was listed; huddles off.
    XCTAssertTrue(HuddleRinging.seen(ringing, HuddlesSeen(on: true, me: "me", roomIds: [], live: seen.live, joinedRoomId: nil)).isEmpty)
    XCTAssertTrue(HuddleRinging.seen(ringing, HuddlesSeen(on: false, me: "me", roomIds: ["r"], live: seen.live, joinedRoomId: nil)).isEmpty)
    XCTAssertTrue(HuddleRinging.over(ringing, room: "r").isEmpty)
  }

  func testSpeaking() {
    var meter = HuddleSpeaking()
    let now = Date()
    XCTAssertEqual(meter.hear(["sam": 0.2, "priya": 0.001], muted: [], now: now), ["sam"])
    XCTAssertEqual(meter.hear(["sam": 0.0], muted: [], now: now.addingTimeInterval(0.5)), ["sam"])
    XCTAssertEqual(meter.hear(["sam": 0.0], muted: [], now: now.addingTimeInterval(0.7)), [])
    XCTAssertEqual(meter.hear(["sam": 0.5], muted: ["sam"], now: now.addingTimeInterval(1)), [])
  }

  // MARK: - /huddle

  func testCommands() {
    XCTAssertEqual(InputCommand.parse("/huddle"), .huddle(.start(muted: false, camera: false, preview: true)))
    XCTAssertEqual(InputCommand.parse("/huddle -m +cam"), .huddle(.start(muted: true, camera: true, preview: false)))
    XCTAssertEqual(InputCommand.parse("/huddle join #general"), .huddle(.join("general")))
    XCTAssertEqual(InputCommand.parse("/mute"), .huddle(.mute(true)))
    XCTAssertEqual(InputCommand.parse("/huddle cam off"), .huddle(.camera(false)))
    XCTAssertEqual(InputCommand.parse("/huddle sticker yes"), .huddle(.sticker(.thumbsUp)))
    XCTAssertEqual(InputCommand.parse("/huddle sticker off"), .huddle(.sticker(nil)))
    XCTAssertEqual(InputCommand.parse("/huddle invite sam priya"), .huddle(.invite(["sam", "priya"])))
    XCTAssertEqual(InputCommand.parse("/hand"), .huddle(.hand))
  }

  // MARK: - Signalling (lib/huddle.ts), against a fake SFU

  final class Clock: HuddleClock {
    var pending: [(at: Double, work: @MainActor () -> Void, live: Bool)] = []
    var now = 0.0

    func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) -> HuddleCancel {
      let index = pending.count
      pending.append((now + seconds, work, true))
      return HuddleCancel { [weak self] in self?.pending[index].live = false }
    }

    func advance(_ seconds: Double) {
      now += seconds
      for index in pending.indices where pending[index].live && pending[index].at <= now {
        pending[index].live = false
        pending[index].work()
      }
    }
  }

  final class FakeSender: HuddleSender {
    var onState: ((HuddlePeerState) -> Void)?
    var closed = false
    var answered: String?
    func offer() async throws -> (sdp: String, mid: String) { ("offer", "0") }
    func accept(answer sdp: String) async throws { answered = sdp }
    func swap() async -> Bool { true }
    func close() { closed = true }
  }

  final class FakeReceiver: HuddleReceiver {
    var onState: ((HuddlePeerState) -> Void)?
    var offers: [String] = []
    func take(offer sdp: String) async throws { offers.append(sdp) }
    func track(mid: String) -> AnyObject? { NSString(string: "track-\(mid)") }
    func answer() async throws -> String { "answer" }
    func close() {}
  }

  func testPublishing() async {
    var sent: [HuddleClientFrame] = []
    let clock = Clock()
    var rejoined = 0
    let link = HuddleLink(send: { sent.append($0); return true }, rejoin: { rejoined += 1 }, isOver: { false }, relayRunOut: { false })
    let sender = FakeSender()
    let sending = HuddleSending(kind: .audio, vital: true, link: link, clock: clock) { sender }
    await sending.publish()
    XCTAssertEqual(sent, [.publish(sdp: "offer", track: HuddleTrack(mid: "0", kind: .audio))])
    await sending.published("answer")
    XCTAssertEqual(sender.answered, "answer")
    sender.onState?(.connected)
    XCTAssertEqual(sent.last, .connected(.audio))
    // An offer left unanswered rejoins, for the voice.
    await sending.publish()
    clock.advance(HuddleTiming.answerTimeout)
    XCTAssertEqual(rejoined, 1)
  }

  func testListening() async {
    var sent: [HuddleClientFrame] = []
    var played: [UserID] = []
    var stopped: [UserID] = []
    let clock = Clock()
    let link = HuddleLink(send: { sent.append($0); return true }, rejoin: {}, isOver: { false }, relayRunOut: { false })
    var open = true
    let receiver = FakeReceiver()
    let receiving = HuddleReceiving(
      kind: .video, vital: false, byName: true, link: link, clock: clock, receivable: { ["sam", "priya"] }, wanted: { open ? ["sam", "priya"] : [] },
      play: { id, _ in played.append(id) }, stop: { stopped.append($0) }, connect: { receiver })
    receiving.listen()
    XCTAssertEqual(sent, [.listen(.video, fresh: true, watch: ["sam", "priya"], small: false)])
    await receiving.offered("sfu-offer", tracks: [OfferedHuddleTrack(mid: "1", kind: .video, userId: "sam"), OfferedHuddleTrack(mid: "2", kind: .video, userId: "priya")])
    XCTAssertEqual(played, ["sam", "priya"])
    XCTAssertEqual(sent.last, .answer(.video, sdp: "answer"))
    // The round with an offer asks again at once.
    receiving.listening()
    XCTAssertEqual(sent.last, .listen(.video, fresh: false, watch: ["sam", "priya"], small: false))
    receiving.listening()
    // Closed to its bar, the next round watches nobody, and forgets whoever it had.
    open = false
    receiving.listen()
    XCTAssertEqual(sent.last, .listen(.video, fresh: false, watch: [], small: false))
    XCTAssertEqual(Set(stopped), ["sam", "priya"])
  }
}
