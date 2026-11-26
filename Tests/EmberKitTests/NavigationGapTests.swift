@testable import EmberKit
import XCTest

/** Search addresses, the Huddles row's count, release updates and `/report nick`, as the web has them. */
final class NavigationGapTests: XCTestCase {
  func testSearchOfQueryRoundTrips() {
    var search = Search(q: "lunch plans", in: "r1", from: "u2")
    search.set(.hasLink, true)
    search.set(.inThread, true)
    let (parsed, sort) = Searches.search(ofQuery: Searches.query(search, sort: .oldest))
    XCTAssertEqual(parsed, search)
    XCTAssertEqual(sort, .oldest)
    let (plain, newest) = Searches.search(ofQuery: "q=hello%20world&has=nothing")
    XCTAssertEqual(plain, Search(q: "hello world"))
    XCTAssertEqual(newest, .newest)
  }

  func testHuddlesGoingOnLeaveOutHiddenRoomsAndPutTheLatestFirst() {
    let rooms = [
      SidebarRoom(room: Room(id: "a", kind: .open, name: "a"), unread: false, involvement: .mentions),
      SidebarRoom(room: Room(id: "b", kind: .open, name: "b"), unread: false, involvement: .invisible),
      SidebarRoom(room: Room(id: "c", kind: .open, name: "c"), unread: false, involvement: .mentions),
    ]
    let live = [
      "a": LiveHuddle(startedAt: "2026-01-01T00:00:00.000Z", userIds: ["x"]),
      "b": LiveHuddle(startedAt: "2026-01-03T00:00:00.000Z", userIds: ["x"]),
      "c": LiveHuddle(startedAt: "2026-01-02T00:00:00.000Z", userIds: ["x"]),
    ]
    XCTAssertEqual(HuddleList.goingOn(rooms, live: live).map(\.room.id), ["c", "a"])
  }

  func testReportTakesANumberOrANick() {
    XCTAssertEqual(InputCommand.parse("/report"), .report(nil))
    XCTAssertEqual(InputCommand.parse("/report 2"), .report(2))
    XCTAssertEqual(InputCommand.parse("/report ada"), .reportPerson("ada"))
  }

  func testOpenReportsAndReleaseWords() {
    XCTAssertEqual(NavigationText.openReports(1), "1 open report")
    XCTAssertEqual(NavigationText.openReports(3), "3 open reports")
    XCTAssertEqual(NavigationText.releaseAvailable("0.2"), "Ember 0.2 is available")
  }
}
