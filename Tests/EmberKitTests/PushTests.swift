import XCTest
@testable import EmberKit

/** Native push: device tokens, what an APNs push carries, and `/push`. */
final class PushTests: XCTestCase {
  func testSavedDeviceTokenDecodes() throws {
    let device = try decode(
      DeviceToken.self,
      #"{"id":7,"token":"0a1b","platform":"macos","environment":"development","origin":"https://irc.dxnd.ai","deviceName":"","updatedAt":"2026-11-20T00:00:00.000Z"}"#)
    XCTAssertEqual(device.id, 7)
    XCTAssertEqual(device.platform, .macos)
    XCTAssertEqual(device.environment, .development)
    XCTAssertEqual(Push.label(device), "ircX on macOS")
  }

  func testDeviceTokenSaveEncodesAsTheWorkerTakesIt() throws {
    let save = DeviceTokenSave(token: "ab", platform: .ios, environment: .production, origin: "https://irc.dxnd.ai", deviceName: "Phone")
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(save)) as? [String: String])
    XCTAssertEqual(json, ["token": "ab", "platform": "ios", "environment": "production", "origin": "https://irc.dxnd.ai", "deviceName": "Phone"])
  }

  func testHexIsLowerCase() {
    XCTAssertEqual(Push.hex(Data([0x00, 0xAB, 0x7F])), "00ab7f")
  }

  func testPushDataReadsAThreadReply() throws {
    let info: [AnyHashable: Any] = [
      "aps": ["alert": ["title": "Thread in general", "body": "ann: hi"], "sound": "default", "thread-id": "r1"],
      "origin": "https://irc.dxnd.ai", "path": "/rooms/r1/threads/p1/@m1", "roomId": "r1", "messageId": "m1", "parentId": "p1",
    ]
    let data = try XCTUnwrap(DevicePushData(userInfo: info))
    XCTAssertEqual(data, DevicePushData(origin: "https://irc.dxnd.ai", path: "/rooms/r1/threads/p1/@m1", roomId: "r1", messageId: "m1", parentId: "p1"))
    XCTAssertEqual(Pages.page(ofLink: data.link, origin: data.origin), .room("r1", threadId: "p1", replyId: "m1"))
  }

  func testPushDataReadsAReportAndRefusesOthers() throws {
    let report = try XCTUnwrap(DevicePushData(userInfo: ["origin": "https://e.example", "path": "/account/edit#membership-settings"]))
    XCTAssertNil(report.roomId)
    XCTAssertNil(DevicePushData(userInfo: ["aps": ["alert": "hi"]]))
  }

  func testPushCommandParses() {
    XCTAssertEqual(InputCommand.parse("/push"), .push(.status))
    XCTAssertEqual(InputCommand.parse("/push on"), .push(.on))
    XCTAssertEqual(InputCommand.parse("/push OFF"), .push(.off))
    XCTAssertEqual(InputCommand.parse("/push list"), .push(.list))
    XCTAssertEqual(InputCommand.parse("/push test"), .push(.test(nil)))
    XCTAssertEqual(InputCommand.parse("/push test d4"), .push(.test(.device(4))))
    XCTAssertEqual(InputCommand.parse("/push delete b4"), .push(.delete(.browser(4))))
    XCTAssertEqual(InputCommand.PushTarget.browser(4).description, "b4")
    let usage = InputCommand.unknown("/push takes on, off, list, test [id] or delete id, where an id is d1 for a device or b1 for a browser")
    XCTAssertEqual(InputCommand.parse("/push delete"), usage)
    XCTAssertEqual(InputCommand.parse("/push test 4"), usage)
  }
}
