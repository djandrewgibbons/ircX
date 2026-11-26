import AppCoreUI
import AppCoreUITestSupport
@testable import EmberKit
@testable import IRCXUI
import SwiftUI
import XCTest

/**
 * The navigation gaps closed after the audit, to .build/ui-renders/: the Huddles page, a welcome DM's
 * joined line, here-now faces, and the page history, Activity and star rules behind them.
 */
@MainActor
final class NavigationGapRenderTests: XCTestCase {
  let base = NavigationRenderTests()

  func testPagesGoBackToThePageTheyCameFrom() throws {
    let session = try base.session()
    session.show(.search(Search(q: "deploy"), .newest))
    session.show(.person(base.bob.id))
    session.closePage()
    XCTAssertEqual(session.page, .search(Search(q: "deploy"), .newest))
    // Exit search goes back to the room.
    session.closePage()
    XCTAssertNil(session.page)
    XCTAssertEqual(session.selectedRoomID, "r1")
  }

  func testUnsavedChangesHoldTheAppUntilDiscarded() throws {
    let session = try base.session()
    session.show(.settings("r1"))
    session.holdsChanges = true
    session.open(room: "r2")
    XCTAssertEqual(session.page, .settings("r1"))
    XCTAssertNotNil(session.leaving)
    session.discardAndLeave()
    XCTAssertNil(session.page)
    XCTAssertEqual(session.selectedRoomID, "r2")
  }

  func testActivityOnAPageGoesHomeFirst() throws {
    let session = try base.session()
    session.show(.person(base.bob.id))
    session.toggleActivity()
    XCTAssertNil(session.page)
    XCTAssertTrue(session.showingActivity)
  }

  func testDroppingAStarCountsOnlyStarsShown() throws {
    let session = try base.session()
    session.dropStars(["r2"], before: nil)
    XCTAssertEqual(session.orderStatus, NavigationText.roomMoveCanceled)
  }

  func testHuddlesPage() throws {
    let session = try base.session()
    for look in AppTheme.allCases {
      let view = HuddlesPage(session: session).frame(width: 640, height: 300).environment(\.appTheme, look).environment(\.theme, .irc)
        .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
      try base.render(view, "\(look.rawValue)-huddles-page", width: 640, height: 300)
    }
  }

  func testWelcomeDirectStartsWithJoined() throws {
    let session = try base.session()
    let at = "2026-11-19T14:00:00.000Z"
    let room = RoomModel(
      room: Room(id: "d3", kind: .direct, members: [base.ada, base.grace], activeAt: at, joined: Joined(userId: base.grace.id, at: at)),
      api: session.api, instance: session)
    room.apply(.welcome(you: base.ada, present: [base.ada, base.bob, base.grace], seq: 1, page: TimelinePage(messages: [], hasMore: false, hasNewer: false, around: nil)))
    let suite = SuiteMessageList(session: session, room: room, lines: room.timeline.lines, hasMore: false, onOlder: {}, openThread: { _ in })
      .frame(width: 560, height: 200).background(SemanticColor.background).suiteTheme(.ircX)
    try base.render(suite, "suite-joined-line", width: 560, height: 200)
    let irc = MessageList(session: session, room: room, lines: room.timeline.lines, hasMore: false, onOlder: {}, openThread: { _ in })
      .frame(width: 560, height: 200).environment(\.theme, .irc).environment(\.appTheme, .irc)
    try base.render(irc, "irc-joined-line", width: 560, height: 200)
    let faces = SuiteHereFaces(session: session, present: room.timeline.present).padding().background(SemanticColor.background)
    try base.render(faces, "suite-here-faces", width: 160, height: 60)
  }
}
