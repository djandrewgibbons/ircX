import AppCoreUI
import AppCoreUITestSupport
@testable import EmberKit
@testable import IRCXUI
import SwiftUI
import XCTest

/**
 * Server Settings as each theme draws it, to .build/ui-renders/: each section for an administrator, the
 * member's view, and the setup dialogs.
 */
@MainActor
final class AdminRenderTests: XCTestCase {
  let base = NavigationRenderTests()

  static let settingsJSON = #"""
    {"account":ACCOUNT,"joinCode":"aB3d","canAdminister":true,"memberfulSite":"https://example.memberful.com","memberfulWebhooks":true,"memberfulKeys":"saved",
    "memberfulSiteKept":null,
    "sso":{"source":"saved","issuer":"https://auth.example.com","clientId":"ember","name":"Okta","scopes":["offline_access"],"groupsClaim":"groups","allowedGroups":["staff"],"linksVerifiedEmails":false},
    "turnstile":null,"email":{"provider":"resend","resendKey":"saved","cloudflare":true,"from":"Example <ember@example.com>"},
    "invitations":[{"id":"i1","emailAddress":"bea@example.com","invitedBy":"ada0000000000001","createdAt":"2026-11-19T10:00:00.000Z","expiresAt":"2026-11-26T10:00:00.000Z","delivery":"sent"},
    {"id":"i2","emailAddress":"cy@example.com","invitedBy":"ada0000000000001","createdAt":"2026-11-18T10:00:00.000Z","expiresAt":"2026-11-25T10:00:00.000Z","delivery":{"refusal":"Mailbox full"}}],
    "emailDomains":["example.com","gmail.com"],"blockedWords":["fudge","drat"],"addresses":{"deployed":"ember.someone.workers.dev","others":["old.example.com"]},
    "assistant":null,"huddles":null,"outsideAi":false,"cloudflareAccountId":null}
    """#

  static let reportsJSON = #"""
    {"open":[{"id":"r1","reporterId":"bob0000000000002","reason":"spam","note":"Keeps posting this","reportedAt":"2026-11-20T09:00:00.000Z",
    "subject":{"kind":"message","roomId":"r1","room":{"kind":"open","name":"general"},"message":{"id":"m","creator":{"id":"gra0000000000003","name":"Grace Hopper"},
    "body":"<p>Buy now</p>","plainText":"Buy now","mentions":[],"createdAt":"2026-11-20T08:00:00.000Z","editedAt":null}},"handled":null}],
    "handled":[{"id":"r2","reporterId":"bob0000000000002","reason":"other","note":"","reportedAt":"2026-11-19T09:00:00.000Z",
    "subject":{"kind":"person","person":{"id":"gra0000000000003","name":"Grace","bio":null}},"handled":{"by":"ada0000000000001","at":"2026-11-19T10:00:00.000Z","outcome":"dismissed"}}]}
    """#

  static let releaseJSON = #"""
    {"release":"0.5.0","beta":false,"newest":{"release":"0.6.0","version":"v0.6.0","notes":"https://github.com/x/releases/0.6.0","newer":true},
    "checkedAt":"2026-11-20T00:00:00.000Z","newestBeta":null,"copy":{"repository":"me/ember","branch":"main","workflow":true,"betaWorkflow":false}}
    """#

  private func session(administrator: Bool = true) throws -> InstanceSession {
    let session = try base.session()
    var account = try XCTUnwrap(session.account)
    account.openSignUp = false
    account.emailDomainSignUp = true
    account.emailDomains = ["example.com", "gmail.com"]
    account.memberfulJoin = true
    account.ssoJoin = true
    let encoded = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
    var settings = try JSONDecoder().decode(WorkspaceSettings.self, from: Data(Self.settingsJSON.replacingOccurrences(of: "ACCOUNT", with: encoded).utf8))
    settings.canAdminister = administrator
    if !administrator {
      session.showForRendering(me: Me(id: base.bob.id, name: base.bob.name, administrator: false), people: Array(session.people.values), account: account)
    }
    session.admin.settings = settings
    session.admin.answered(account)
    session.admin.reports = try JSONDecoder().decode(Reports.self, from: Data(Self.reportsJSON.utf8))
    session.adoptRelease(try JSONDecoder().decode(ReleaseCheck.self, from: Data(Self.releaseJSON.utf8)))
    return session
  }

  private func themed(_ view: some View, _ look: AppTheme) -> some View {
    view.environment(\.appTheme, look).environment(\.theme, .irc)
      .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
      .suiteTheme(.ircX)
  }

  func testSections() throws {
    let app = AppModel(tokens: MemoryTokenStore())
    for look in AppTheme.allCases {
      for section in AdminSection.allCases {
        let session = try session()
        session.adminSection = section
        session.admin.section = section
        if section == .general { session.admin.say(AdminText.saved) }
        let height: CGFloat = section == .membership ? 3000 : 1100
        try base.render(
          themed(ServerSettingsView(app: app, session: session).frame(width: 860, height: height), look), "\(look.rawValue)-admin-\(section.rawValue)",
          width: 860, height: height)
      }
    }
  }

  func testMemberView() throws {
    let app = AppModel(tokens: MemoryTokenStore())
    for look in AppTheme.allCases {
      let session = try session(administrator: false)
      session.adminSection = .membership
      session.admin.section = .membership
      XCTAssertEqual(session.admin.sections, [.general, .rooms, .membership])
      try base.render(themed(ServerSettingsView(app: app, session: session).frame(width: 760, height: 900), look), "\(look.rawValue)-admin-member", width: 760, height: 900)
    }
  }

  func testSetups() throws {
    for look in AppTheme.allCases {
      for setup in [AdminSetup.email, .turnstile, .memberful, .sso] {
        let session = try session()
        try base.render(
          themed(AdminSetupSheet(session: session, admin: session.admin, setup: setup).frame(width: 600, height: 900), look),
          "\(look.rawValue)-admin-setup-\(setup.rawValue)", width: 600, height: 900)
      }
    }
  }

  /** Membership's entry counts open reports for administrators: on iOS's list and IRC Classic's tab strip. */
  func testMembershipCount() throws {
    let app = AppModel(tokens: MemoryTokenStore())
    for look in AppTheme.allCases {
      let session = try session()
      session.countReportsForRendering(3)
      XCTAssertEqual(session.admin.badge(.membership), 3)
      XCTAssertEqual(session.admin.badge(.general), 0)
      session.adminSection = .membership
      session.admin.section = .membership
      try base.render(themed(ServerSettingsView(app: app, session: session).frame(width: 860, height: 900), look), "\(look.rawValue)-admin-count", width: 860, height: 900)
    }
  }

  /** The navigation icon picker: the recommendations first, in its tabs. */
  func testNavigationIconPicker() throws {
    for look in AppTheme.allCases {
      let session = try session()
      try base.render(
        themed(IconCatalogGrid(api: session.api, context: .navigation, current: "house", choose: { _ in }, defaultLabel: "Default Icon").padding().frame(width: 460, height: 520), look),
        "\(look.rawValue)-admin-icon-picker", width: 460, height: 520)
    }
  }
}
