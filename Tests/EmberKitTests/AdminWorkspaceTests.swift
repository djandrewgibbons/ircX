@testable import EmberKit
import XCTest

/** Workspace administration's rules, as the web's settings pages and packages/protocol have them. */
final class AdminWorkspaceTests: XCTestCase {
  static let accountJSON = #"""
    {"name":"Example","tagline":"","hideTranslationButtons":false,"customStyles":"","restrictRoomCreation":false,"joinLink":true,"openSignUp":false,
    "memberfulJoin":false,"memberfulSignIn":false,"ssoJoin":false,"ssoSignIn":false,"emailDomainSignUp":false,"emailDomains":[],"navigationIcons":{},
    "huddles":true,"huddleCameras":true,"huddleScreens":true}
    """#

  func account(_ change: (inout Account) -> Void = { _ in }) throws -> Account {
    var account = try JSONDecoder().decode(Account.self, from: Data(Self.accountJSON.utf8))
    change(&account)
    return account
  }

  // MARK: Ways to join

  func testOpenSetsTheOthersAside() throws {
    let ways = WaysToJoin(account: try account { $0.openSignUp = true }, memberfulSetUp: false, ssoSetUp: false)
    XCTAssertNil(ways.openSetAside)
    XCTAssertEqual(ways.linkSetAside, AdminText.openOverrides)
    XCTAssertEqual(ways.emailDomainSetAside, AdminText.openOverrides)
    XCTAssertEqual(ways.memberfulSetAside, AdminText.openOverrides)
    XCTAssertEqual(ways.ssoSetAside, AdminText.openOverrides)
  }

  func testOpenStaysSetAsideUntilTurningItOffIsSaved() throws {
    let ways = WaysToJoin(account: try account { $0.openSignUp = true }, moved: [.openSignUp: false], memberfulSetUp: false, ssoSetUp: false)
    XCTAssertFalse(ways.open)
    XCTAssertEqual(ways.linkSetAside, AdminText.openOverrides)
  }

  func testOnlySwitchesSetTheOthersAside() throws {
    let membersOnly = WaysToJoin(
      account: try account {
        $0.memberfulJoin = true
        $0.memberfulSignIn = true
      }, memberfulSetUp: true, ssoSetUp: false)
    XCTAssertEqual(membersOnly.openSetAside, AdminText.membersOnlyOverrides)
    XCTAssertEqual(membersOnly.linkSetAside, AdminText.membersOnlyOverrides)
    XCTAssertNil(membersOnly.memberfulSetAside)
    XCTAssertEqual(membersOnly.ssoBeside, AdminText.ssoOnlyBesideMemberful)
    XCTAssertEqual(membersOnly.ssoClosed, AdminText.ssoClosed)
    XCTAssertFalse(membersOnly.ssoChecked)

    let both = WaysToJoin(
      account: try account {
        $0.memberfulJoin = true
        $0.memberfulSignIn = true
        $0.ssoJoin = true
        $0.ssoSignIn = true
      }, memberfulSetUp: true, ssoSetUp: true)
    XCTAssertEqual(both.openSetAside, AdminText.eitherOnlyOverrides)
    XCTAssertNil(both.memberfulClosed)
    XCTAssertTrue(both.ssoChecked)

    let ssoOnly = WaysToJoin(
      account: try account {
        $0.ssoJoin = true
        $0.ssoSignIn = true
      }, memberfulSetUp: false, ssoSetUp: true)
    XCTAssertEqual(ssoOnly.linkSetAside, AdminText.ssoOnlyOverrides)
  }

  func testTurningAnOnlySwitchOnTurnsItsWayOn() throws {
    let ways = WaysToJoin(account: try account(), moved: [.memberfulSignIn: true], memberfulSetUp: true, ssoSetUp: false)
    XCTAssertTrue(ways.memberful)
    XCTAssertTrue(ways.membersOnly)
  }

  func testBesideTheOtherOnlySwitchTheMainSwitchMovesItsOwnOnly() throws {
    let ways = WaysToJoin(
      account: try account {
        $0.ssoJoin = true
        $0.ssoSignIn = true
      }, memberfulSetUp: true, ssoSetUp: true)
    XCTAssertEqual(ways.memberfulFlip(true)?.way, .memberfulSignIn)
    XCTAssertEqual(ways.memberfulFlip(true)?.asks, false)
    XCTAssertEqual(ways.memberfulFlip(false)?.way, .memberfulJoin)
    var saving = ways
    saving.moved[.memberfulSignIn] = true
    XCTAssertNil(saving.memberfulFlip(true))
    XCTAssertEqual(WaysToJoin(account: try account(), memberfulSetUp: false, ssoSetUp: false).memberfulFlip(true)?.way, .memberfulJoin)
  }

  func testQuestionsWarnWhenTheyCloseTheOtherWay() throws {
    let ways = WaysToJoin(account: try account(), memberfulSetUp: true, ssoSetUp: true)
    XCTAssertEqual(ways.question(turningOn: .openSignUp), AdminText.confirmOpen)
    XCTAssertEqual(ways.question(turningOn: .ssoSignIn), AdminText.confirmSsoOnly + AdminText.closesMemberful)
    XCTAssertEqual(ways.question(turningOn: .memberfulSignIn), AdminText.confirmMembersOnly + AdminText.closesSso)
    XCTAssertNil(ways.question(turningOn: .joinLink))
    XCTAssertEqual(WaysToJoin(account: try account(), memberfulSetUp: false, ssoSetUp: false).question(turningOn: .ssoSignIn), AdminText.confirmSsoOnly)
  }

  // MARK: Addresses

  func testMailbox() {
    XCTAssertEqual(Mailbox("ember@example.com"), Mailbox(name: nil, address: "ember@example.com"))
    XCTAssertEqual(Mailbox("Ember <ember@example.com>"), Mailbox(name: "Ember", address: "ember@example.com"))
    XCTAssertEqual(Mailbox("\"Ember, Inc.\" <ember@example.com>")?.text, "\"Ember, Inc.\" <ember@example.com>")
    XCTAssertEqual(Mailbox("Ember <ember@example.com>")?.domain, "example.com")
    XCTAssertNil(Mailbox("not an address"))
    XCTAssertNil(Mailbox("Em<ber <ember@example.com>"))
    XCTAssertNil(Mailbox("ember@localhost"))
  }

  func testHostsAndCustomDomains() {
    XCTAssertTrue(WorkspaceRules.isHost("chat.example.com"))
    XCTAssertTrue(WorkspaceRules.isHost("localhost:8787"))
    XCTAssertFalse(WorkspaceRules.isHost("Chat.example.com"))
    XCTAssertFalse(WorkspaceRules.isHost("chat.example.com:0"))
    XCTAssertFalse(WorkspaceRules.isHost("chat.example.com:70000"))
    XCTAssertFalse(WorkspaceRules.canBeCustomDomain("ember.someone.workers.dev"))
    XCTAssertFalse(WorkspaceRules.canBeCustomDomain("localhost"))
    XCTAssertFalse(WorkspaceRules.canBeCustomDomain("127.0.0.1"))
    XCTAssertTrue(WorkspaceRules.canBeCustomDomain("chat.localhost"))
    XCTAssertEqual(try WorkspaceRules.domainTyped("https://Chat.Example.com/path").get(), "chat.example.com")
    XCTAssertEqual(try WorkspaceRules.domainTyped("chat.example.com:8443").get(), "chat.example.com:8443")
    XCTAssertEqual(WorkspaceRules.domainTyped("ember.a.workers.dev"), .failure(CustomDomainRefusal(message: WorkspaceRules.notACustomDomain)))
    XCTAssertEqual(WorkspaceRules.domainTyped("not a host"), .failure(CustomDomainRefusal(message: WorkspaceRules.customDomainNotAHost)))
    XCTAssertEqual(WorkspaceRules.registeredGuess("chat.example.co.uk"), "example.co.uk")
    XCTAssertEqual(WorkspaceRules.registeredGuess("chat.example.com"), "example.com")
    XCTAssertEqual(WorkspaceRules.worker(at: "ember.someone.workers.dev"), "ember")
    XCTAssertEqual(
      WorkspaceRules.othersAfterMove(["old.example.com", "a.example.com"], left: ["new.example.com", "ember.x.workers.dev"], to: "a.example.com"),
      ["new.example.com", "old.example.com"])
    XCTAssertEqual(WorkspaceRules.domainsInWords(["a.com", "b.com", "c.com"]), "a.com, b.com or c.com")
    XCTAssertEqual(WorkspaceRules.domainsInWords(["a.com"]), "a.com")
  }

  func testEmailDomainsTyped() {
    let typed = WorkspaceRules.emailDomainsTyped("@Example.com, example.org; nope/x")
    XCTAssertEqual(typed.domains, ["example.com", "example.org"])
    XCTAssertEqual(typed.refused, ["nope/x"])
  }

  func testMemberfulSite() {
    XCTAssertEqual(Memberful.site(of: "yoursite"), "https://yoursite.memberful.com")
    XCTAssertEqual(Memberful.site(of: "yoursite.memberful.com"), "https://yoursite.memberful.com")
    XCTAssertEqual(Memberful.site(of: "https://members.example.com/admin"), "https://members.example.com")
    XCTAssertEqual(Memberful.site(of: "http://localhost:3000"), "http://localhost:3000")
    XCTAssertNil(Memberful.site(of: "http://example.com"))
    XCTAssertNil(Memberful.site(of: ""))
    XCTAssertEqual(Memberful.newAppPage("https://yoursite.memberful.com"), "https://yoursite.memberful.com/admin/settings/custom_applications/new")
    XCTAssertNil(Memberful.newAppPage("https://members.example.com"))
    XCTAssertEqual(Memberful.refusal(site: "yoursite", apiKey: "k", clientId: "", clientSecret: "s", webhookSecret: "w")?.field, "clientId")
  }

  func testSsoSetup() throws {
    let setup = try SSO.setup(
      issuer: " https://auth.example.com ", clientId: "c", clientSecret: "", name: "", scopes: "groups  groups offline_access", groupsClaim: "",
      allowedGroups: "a\n\n b \na", linksVerifiedEmails: true
    ).get()
    XCTAssertEqual(setup.issuer, "https://auth.example.com")
    XCTAssertNil(setup.clientSecret)
    XCTAssertEqual(setup.name, SSO.defaultName)
    XCTAssertEqual(setup.scopes, ["groups", "offline_access"])
    XCTAssertEqual(setup.groupsClaim, SSO.defaultGroupsClaim)
    XCTAssertEqual(setup.allowedGroups, ["a", "b"])
    let refusals: [(String?, String?, String, String, String)] = [
      ("ftp://x", "c", "n", "", "issuer"), ("https://x", "", "n", "", "clientId"), ("https://x", "c", String(repeating: "n", count: 41), "", "name"),
      ("https://x", "c", "n", "has space", "groupsClaim"),
    ]
    for (issuer, clientId, name, claim, field) in refusals {
      let parsed = SSO.setup(issuer: issuer, clientId: clientId, clientSecret: nil, name: name, scopes: "", groupsClaim: claim, allowedGroups: "", linksVerifiedEmails: false)
      guard case let .failure(refusal) = parsed else { return XCTFail("\(field) wasn't refused") }
      XCTAssertEqual(refusal.field, field)
    }
  }

  // MARK: Invitations

  func testInvitationsGoTwentyAtATime() {
    let addresses = (1...45).map { "p\($0)@example.com" }
    let batches = Invitations.batches(addresses)
    XCTAssertEqual(batches.map(\.count), [20, 20, 5])
    XCTAssertEqual(batches.flatMap { $0 }, addresses)
  }

  func testInvitationWords() throws {
    XCTAssertEqual(Invitations.refusal([]), "Give an email address to invite.")
    XCTAssertEqual(Invitations.refusal(["x"]), "This isn't an email address: x. Fix or remove it, then send again.")
    let outcomes = try JSONDecoder().decode([InvitationOutcome].self, from: Data(#"""
      [{"emailAddress":"a@x.com","invitation":{"id":"1","emailAddress":"a@x.com","invitedBy":"u","createdAt":"t","expiresAt":"t","delivery":"sent"},"link":null},
      {"emailAddress":"b@x.com","invitation":{"id":"2","emailAddress":"b@x.com","invitedBy":"u","createdAt":"t","expiresAt":"t","delivery":null},"link":"https://x/join/invitation#token=t"},
      {"emailAddress":"c@x.com","member":true}]
      """#.utf8))
    XCTAssertEqual(Invitations.summary(outcomes), "Sent 1 invitation. Made 1 invite link. Copy each below and send it yourself. c@x.com has an account already.")
  }

  // MARK: Release checks

  func testReleaseCard() throws {
    let decode = { (json: String) in try JSONDecoder().decode(ReleaseCheck.self, from: Data(json.utf8)) }
    let behind = try decode(#"""
      {"release":"0.5.0","beta":false,"newest":{"release":"0.6.0","version":"v0.6.0","notes":"https://n","newer":true},"checkedAt":"2026-11-20T00:00:00.000Z",
      "newestBeta":null,"copy":{"repository":"me/ember","branch":"irc/main","workflow":false,"betaWorkflow":true}}
      """#)
    XCTAssertEqual(behind.heading, "Ember 0.6.0 is available")
    XCTAssertEqual(behind.note, "This is Ember 0.5.0.")
    XCTAssertEqual(behind.updating.label, "Add GitHub action to update")
    XCTAssertTrue(behind.updating.url.hasPrefix("https://github.com/me/ember/new/irc/main?filename=.github%2Fworkflows%2Fupdate-ember.yml&value=name%3A+Update+Ember"))
    let current = try decode(#"""
      {"release":"0.6.0","beta":false,"newest":{"release":"0.6.0","version":"v0.6.0","notes":"https://n","newer":false},"checkedAt":null,
      "newestBeta":{"release":"0.7.0-beta.1","version":"v0.7.0-beta.1","notes":"https://b","newer":true},"copy":null}
      """#)
    XCTAssertNil(current.update)
    XCTAssertEqual(current.betaToTry?.release, "0.7.0-beta.1")
    XCTAssertEqual(current.note, "This is the newest release.")
    XCTAssertEqual(current.trying.label, "How to try a beta")
    let merged = ReleaseCheck.together(behind, try decode(#"""
      {"release":"0.5.0","beta":false,"newest":null,"checkedAt":null,"newestBeta":null,"copy":null}
      """#))
    XCTAssertEqual(merged.newest?.release, "0.6.0")
    XCTAssertEqual(merged.checkedAt, "2026-11-20T00:00:00.000Z")
  }

  // MARK: Commands

  func testAdminCommands() {
    XCTAssertEqual(InputCommand.parse("/admin membership"), .admin(.open("membership")))
    XCTAssertEqual(InputCommand.parse("/set tagline Ship it"), .admin(.set(.tagline("Ship it"))))
    XCTAssertEqual(InputCommand.parse("/set icon home default"), .admin(.set(.icon(.home, nil))))
    XCTAssertEqual(InputCommand.parse("/join-mode members-only on"), .admin(.joinMode(.memberfulSignIn, true)))
    XCTAssertEqual(InputCommand.parse("/order #general 2"), .admin(.order(.move("general", to: 2))))
    XCTAssertEqual(InputCommand.parse("/domains add a.com, b.org"), .admin(.domains(.add(["a.com", "b.org"]))))
    XCTAssertEqual(InputCommand.parse("/reports 2 ban"), .admin(.reports(2, .banned)))
    XCTAssertEqual(InputCommand.parse("/memberful keys"), .admin(.memberful(.setup)))
    XCTAssertEqual(InputCommand.parse("/sso only off"), .admin(.sso(.only(false))))
    XCTAssertEqual(InputCommand.parse("/op bob"), .admin(.role("bob", administrator: true)))
    XCTAssertEqual(InputCommand.parse("/mail from Ember <e@x.com>"), .admin(.mail(.from("Ember <e@x.com>"))))
    XCTAssertEqual(InputCommand.parse("/domain use"), .admin(.domain(.use(nil))))
    XCTAssertEqual(InputCommand.parse("/domain setup chat.example.com"), .admin(.domain(.setup("chat.example.com"))))
    XCTAssertEqual(InputCommand.parse("/domain setup"), .admin(.domain(.setup(nil))))
    XCTAssertEqual(InputCommand.parse("/admin ai"), .admin(.open("ai")))
    XCTAssertEqual(InputCommand.parse("/admin bots"), .admin(.open("bots")))
    XCTAssertEqual(InputCommand.parse("/email ann@example.com"), .setProfile(.emailAddress, "ann@example.com"))
    if case .unknown = InputCommand.parse("/admin nowhere") {} else { XCTFail("/admin nowhere wasn't refused") }
  }

  // MARK: Icon catalog

  /** The navigation context ranks the catalog's recommendations for the rail first (web `IconDialog` in `navigation`). */
  func testIconCatalogNavigationOrder() {
    let all = RoomIcons.search("", context: .navigation)
    XCTAssertEqual(all.count, RoomIcons.names.count)
    XCTAssertEqual(all.prefix(4).map(\.name), ["house", "iconoir:regular:home-simple", "messages-circle", "iconoir:regular:chat-bubble"])
    XCTAssertEqual(RoomIcons.search("", context: .navigation, collection: .iconoir).first?.name, "iconoir:regular:home-simple")
    XCTAssertEqual(RoomIcons.search("", context: .room).prefix(3).map(\.name), ["messages-circle", "iconoir:regular:megaphone", "code-xml"])
  }

  /** A search puts exact names first, then names holding every word, then tags (web `searchIcons`). */
  func testIconCatalogSearch() {
    XCTAssertEqual(RoomIcons.search("home", context: .navigation).prefix(2).map(\.name), ["iconoir:regular:home", "iconoir:regular:home-simple"])
    XCTAssertEqual(RoomIcons.search("coffee", context: .room).prefix(2).map(\.name), ["coffee", "iconoir:regular:coffee-cup"])
    // Two letters or fewer match whole words only, so "hr" doesn't find thrush.
    XCTAssertFalse(RoomIcons.search("hr", context: .room).contains { $0.name.contains("thrush") })
    XCTAssertTrue(RoomIcons.search("coffee", context: .room, collection: .lucide).allSatisfy { !$0.name.hasPrefix("iconoir:") })
  }
}
