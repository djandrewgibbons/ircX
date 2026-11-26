import AppCoreUI
import AppCoreUITestSupport
@testable import EmberKit
@testable import IRCXUI
import SwiftUI
import XCTest

/**
 * The people screens as each theme draws them, to .build/ui-renders/: your profile, sign-in with its ways
 * in, joining, resetting a password, first run, and Report.
 */
@MainActor
final class PeopleRenderTests: XCTestCase {
  let base = NavigationRenderTests()

  private func bootstrap(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> Bootstrap {
    var account = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(MessageRenderTests.account.utf8)) as? [String: Any])
    account["openSignUp"] = true
    var json: [String: Any] = [
      "setup": "complete", "setupAccess": "closed", "setupPlaceholders": ["name": "Ada Lovelace", "emailAddress": "ada@example.com"],
      "guestSignIn": true, "signInWithMemberful": true, "signInWithSso": "Okta", "turnstileSiteKey": NSNull(), "passwordResetCodes": true,
      "account": account, "version": "1", "vapidPublicKey": NSNull(), "apnsPush": false,
      "platform": ["ios": false, "android": false, "desktop": true, "windows": false, "chrome": false, "firefox": false, "safari": false, "edge": false,
        "browser": "", "operatingSystem": ""],
    ]
    edit(&json)
    return try JSONDecoder().decode(Bootstrap.self, from: JSONSerialization.data(withJSONObject: json))
  }

  private func signedOut(_ bootstrap: Bootstrap) -> InstanceSession {
    let session = InstanceSession(instance: Instance(baseURL: URL(string: "https://chat.example.com")!, name: "Example"), tokens: MemoryTokenStore())
    session.showSignedOutForRendering(bootstrap)
    return session
  }

  private func themed(_ view: some View, _ look: AppTheme) -> some View {
    view.environment(\.appTheme, look).environment(\.theme, .irc)
      .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
      .suiteTheme(.ircX)
  }

  func testProfilePage() throws {
    let session = try base.session()
    session.changeBlocksForRendering(Blocks(userIds: [base.grace.id], version: 1))
    let json = """
      {"profile":{"name":"Ada Lovelace","username":"ada","emailAddress":"ada@example.com","bio":"Analyst.","avatarUrl":"/a","avatar":true,
      "password":true,"membershipNeeded":false,"memberful":null,"sso":{"name":"Okta","ssoOnly":false,"connected":null},
      "assistant":{"levels":{"thinking":"low","length":"medium"},"most":{"thinking":"high","length":"long"},"model":null,"defaultModel":"m1",
      "models":[{"id":"m1","name":"Llama","format":"workers"},{"id":"m2","name":"Claude","format":"anthropic"}]},
      "apps":[{"id":"gh","name":"GitHub","signedInAt":null,"ended":false,"wantsMore":false}],
      "outsideAi":[{"id":"o1","name":"Claude","comesBackTo":"claude.ai","scopes":["read","write"],"connectedAt":"2026-11-19T14:00:00.000Z","usedAt":null}]},
      "transferId":"t1"}
      """
    let answer = try JSONDecoder().decode(ProfileAnswer.self, from: Data(json.utf8))
    for look in AppTheme.allCases {
      let model = ProfileModel(session: session)
      model.adopt(answer)
      model.say(PeopleText.saved)
      try base.render(themed(ProfilePage(session: session, model: model).frame(width: 640, height: 2400), look), "\(look.rawValue)-profile", width: 640, height: 2400)
    }
  }

  func testSignIn() throws {
    let session = signedOut(try bootstrap())
    session.signInForm.problem = EmberText.signInRejected
    let app = AppModel(tokens: MemoryTokenStore())
    try base.render(themed(SuiteSignInView(app: app, session: session).frame(width: 560, height: 760), .suite), "suite-sign-in", width: 560, height: 760)
    try base.render(themed(IRCSignInView(app: app, session: session).frame(width: 560, height: 640), .irc), "irc-sign-in", width: 560, height: 640)
  }

  func testSignInWhileSingleSignOnIsTheOnlyWayIn() throws {
    let session = signedOut(try bootstrap { json in
      var account = json["account"] as! [String: Any]
      account["ssoSignIn"] = true
      json["account"] = account
      json["guestSignIn"] = false
    })
    XCTAssertEqual(session.signInForm.onlyElsewhere?.name, "Okta")
    // Memberful's link sits beside single sign-on's only while both are the only ways in (web `eitherOnly`).
    XCTAssertEqual(session.signInForm.otherElsewhere.map(\.title), [])
    XCTAssertNil(session.signInForm.backToElsewhere)
    XCTAssertFalse(session.signInForm.offersSignUp)
    let app = AppModel(tokens: MemoryTokenStore())
    try base.render(themed(SuiteSignInView(app: app, session: session).frame(width: 560, height: 520), .suite), "suite-sign-in-sso", width: 560, height: 520)
    try base.render(themed(IRCSignInView(app: app, session: session).frame(width: 560, height: 420), .irc), "irc-sign-in-sso", width: 560, height: 420)
    // The password form, for administrators and invited people, links back to single sign-on alone.
    session.signInForm.showsPasswordForm = true
    XCTAssertEqual(session.signInForm.otherElsewhere.map(\.title), [])
    XCTAssertEqual(session.signInForm.backToElsewhere, "Use single sign-on? Sign in with Okta")
    try base.render(themed(SuiteSignInView(app: app, session: session).frame(width: 560, height: 620), .suite), "suite-sign-in-sso-password", width: 560, height: 620)
    try base.render(themed(IRCSignInView(app: app, session: session).frame(width: 560, height: 520), .irc), "irc-sign-in-sso-password", width: 560, height: 520)
  }

  func testSignInWhileMemberfulAndSingleSignOnAreTheOnlyWaysIn() throws {
    let session = signedOut(try bootstrap { json in
      var account = json["account"] as! [String: Any]
      account["ssoSignIn"] = true
      account["memberfulSignIn"] = true
      json["account"] = account
      json["guestSignIn"] = false
    })
    XCTAssertEqual(session.signInForm.otherElsewhere.map(\.title), ["Member? Sign in with Memberful"])
    session.signInForm.showsPasswordForm = true
    XCTAssertEqual(session.signInForm.otherElsewhere.map(\.title), [])
    XCTAssertEqual(session.signInForm.backToElsewhere, "No password? Sign in with Okta or Memberful")
  }

  func testGoneEmailDomainLinkAsksForAnother() throws {
    let session = signedOut(try bootstrap { json in
      var account = json["account"] as! [String: Any]
      account["openSignUp"] = false
      account["emailDomainSignUp"] = true
      account["emailDomains"] = ["example.com"]
      json["account"] = account
    })
    let gone = EmailLinkModel(session: session, gone: true)
    XCTAssertTrue(gone.on)
    for look in AppTheme.allCases {
      let link = EmailLinkModel(session: session, gone: true)
      try base.render(themed(EmailLinkSheet(model: link).frame(width: 480, height: 440), look), "\(look.rawValue)-email-link-gone", width: 480, height: 440)
    }
  }

  func testPasswordResetKeepsItsCodeStep() throws {
    let session = signedOut(try bootstrap())
    let form = session.signInForm
    form.openReset(emailAddress: "ada@example.com")
    guard case let .reset(first)? = form.sheet else { return XCTFail("No reset sheet") }
    first.asked = "ada@example.com"
    form.sheet = nil
    form.openReset(emailAddress: "")
    guard case let .reset(again)? = form.sheet else { return XCTFail("No reset sheet") }
    XCTAssertTrue(first === again)
    form.openReset(emailAddress: "bob@example.com")
    guard case let .reset(other)? = form.sheet else { return XCTFail("No reset sheet") }
    XCTAssertFalse(first === other)
    XCTAssertNil(other.asked)
  }

  func testJoinAndReset() throws {
    let session = signedOut(try bootstrap())
    for look in AppTheme.allCases {
      let join = JoinModel(session: session, kind: .code("abc"))
      join.problems["password"] = EmberText.passwordTooShort
      try base.render(themed(JoinSheet(model: join).frame(width: 480, height: 600), look), "\(look.rawValue)-join", width: 480, height: 600)
      let reset = PasswordResetModel(session: session, emailAddress: "ada@example.com")
      reset.asked = "ada@example.com"
      try base.render(themed(PasswordResetSheet(model: reset).frame(width: 480, height: 440), look), "\(look.rawValue)-reset", width: 480, height: 440)
      let link = EmailLinkModel(session: session)
      link.sent = "ada@example.com"
      try base.render(themed(EmailLinkSheet(model: link).frame(width: 480, height: 440), look), "\(look.rawValue)-email-link", width: 480, height: 440)
    }
  }

  func testFirstRun() throws {
    let session = signedOut(try bootstrap { json in
      json["setup"] = "pending"
      json["setupAccess"] = "password"
    })
    XCTAssertEqual(session.phase, .notSetUp)
    for look in AppTheme.allCases {
      try base.render(themed(SetupView(session: session).frame(width: 600, height: 420), look), "\(look.rawValue)-setup", width: 600, height: 420)
    }
  }

  func testReportSomeone() throws {
    let session = try base.session()
    let person = Person(id: base.bob.id, name: base.bob.name, username: "bob", bio: nil, role: .member, status: .active, avatarUrl: "/b")
    for look in AppTheme.allCases {
      try base.render(themed(ReportSheet(session: session, person: person).frame(width: 480, height: 460), look), "\(look.rawValue)-report-person", width: 480, height: 460)
    }
  }

  func testFollowingLinksWaitsForTheSession() throws {
    let session = signedOut(try bootstrap())
    session.follow(.join(code: "abc"))
    guard case let .join(model) = session.signInForm.sheet else { return XCTFail("No join form") }
    XCTAssertEqual(model.kind, .code("abc"))
    session.follow(.signIn(emailAddress: "ada@example.com", problem: EmberText.joiningProblems["closed"]))
    XCTAssertEqual(session.signInForm.email, "ada@example.com")
    XCTAssertEqual(session.signInForm.problem, EmberText.joiningProblems["closed"])
  }
}
