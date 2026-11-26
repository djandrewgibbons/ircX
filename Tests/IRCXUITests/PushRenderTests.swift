import AppCoreUI
import AppCoreUITestSupport
@testable import EmberKit
@testable import IRCXUI
import SwiftUI
import XCTest

/** Notifications: the page in both themes, to .build/ui-renders/, and the links a notification opens. */
@MainActor
final class PushRenderTests: XCTestCase {
  let base = NavigationRenderTests()

  func testNotificationsPage() throws {
    let session = try base.session()
    let devices = try JSONDecoder().decode([DeviceToken].self, from: Data(#"""
      [{"id":3,"token":"00ab","platform":"ios","environment":"production","origin":"https://chat.example.com","deviceName":"Ada's iPhone","updatedAt":"2026-11-19T00:00:00.000Z"},
       {"id":4,"token":"00cd","platform":"macos","environment":"development","origin":"https://chat.example.com","deviceName":"","updatedAt":"2026-11-20T00:00:00.000Z"}]
      """#.utf8))
    let browsers = try JSONDecoder().decode([SavedPushSubscription].self, from: Data(#"""
      [{"id":5,"endpoint":"https://web.push.apple.com/QGf2x9v1","browser":"Safari","version":"19","platform":"macOS"}]
      """#.utf8))
    for look in AppTheme.allCases {
      let view = PushSubscriptionsPage(session: session, devices: devices, browsers: browsers).frame(width: 640, height: 460)
        .environment(\.appTheme, look).environment(\.theme, .irc)
        .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
      try base.render(view, "\(look.rawValue)-notifications-page", width: 640, height: 460)
    }
  }

  func testWithoutAPNsTheSwitchSaysNotConfigured() throws {
    let session = try base.session()
    XCTAssertEqual(PushCenter.shared.state(of: session), .unconfigured)
    XCTAssertEqual(PushText.state(.unconfigured), "Notifications aren't configured")
  }

  /** IRC Classic's status bar says where notifications are while they aren't on. */
  func testStatusBarSaysNotificationsAreOff() throws {
    let compose = ComposeRenderTests()
    let session = compose.session()
    let room = compose.room(session)
    let view = StatusBar(session: session, room: room).frame(width: 900).environment(\.theme, .irc)
    try compose.render(view, "irc-status-notify", height: 22)
  }

  func testTurningOffWaitsForTheServer() async throws {
    let session = InstanceSession(instance: Instance(baseURL: URL(string: "https://chat.example.com")!, name: "Example"), tokens: MemoryTokenStore())
    do {
      try await PushCenter.shared.turnOff(session)
      XCTFail("Turned off while checking")
    } catch let error as PushCenter.NotConnected {
      XCTAssertEqual(error.localizedDescription, "Connect to Example to turn its notifications off")
    }
  }

  func testNotificationPathsOpen() throws {
    let session = try base.session()
    XCTAssertTrue(session.open(link: URL(string: "https://chat.example.com/users/me/push_subscriptions")!))
    XCTAssertEqual(session.page, .pushSubscriptions)
    XCTAssertTrue(session.open(link: URL(string: "https://chat.example.com/account/edit#membership-settings")!))
    XCTAssertTrue(session.showingWorkspaceSettings)
    XCTAssertEqual(session.adminSection, .membership)
  }
}
