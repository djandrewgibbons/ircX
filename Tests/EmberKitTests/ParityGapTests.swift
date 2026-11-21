import XCTest
@testable import EmberKit

// The protocol unit's audit gaps: the outbox's checks and refusals, push subscriptions, huddle close
// codes, and a decoding test for every response type the unit added.

final class OutboxTests: XCTestCase {
  private func pending(_ id: String) throws -> Message {
    try decode(Message.self, message(id))
  }

  func testCheckedRemovesStoredAndFailsMissing() throws {
    var timeline = Timeline()
    timeline.send(try pending("a"))
    timeline.send(try pending("b"))
    timeline.send(try pending("c"))
    timeline.apply(try ServerFrame.decode(#"{"type":"message.checked","stored":["c-a","c-b"],"missing":["c-c"]}"#))
    XCTAssertEqual(Array(timeline.pending.keys), ["c-c"], "a missing message stays, as not sent")
    XCTAssertTrue(timeline.isFailed("c-c"))
    XCTAssertEqual(timeline.sending, [], "a failed message isn't checked again")
    guard case let .event(_, _, text, _)? = timeline.events.last else { return XCTFail("no notice") }
    XCTAssertEqual(text, EmberText.messagesSentScrollUp)
  }

  func testOneStoredSaysScrollUpToSeeIt() throws {
    var timeline = Timeline()
    timeline.send(try pending("a"))
    timeline.apply(.messageChecked(stored: ["c-a"], missing: []))
    guard case let .event(_, _, text, _)? = timeline.events.last else { return XCTFail("no notice") }
    XCTAssertEqual(text, EmberText.messageSentScrollUp)
  }

  func testRewriteKeepsTheMessageToGiveBack() throws {
    var timeline = Timeline()
    timeline.send(try pending("a"))
    timeline.apply(try ServerFrame.decode(#"{"type":"error","message":"That word isn't allowed here.","clientMessageId":"c-a","failed":"message.create","rewrite":true}"#))
    XCTAssertTrue(timeline.isFailed("c-a"))
    XCTAssertEqual(timeline.rewrites["c-a"], "That word isn't allowed here.")
    timeline.giveBack("c-a", taken: true)
    XCTAssertNil(timeline.pending["c-a"])
    XCTAssertTrue(timeline.rewrites.isEmpty)
  }

  func testRewriteNotTakenStaysNotSent() throws {
    var timeline = Timeline()
    timeline.send(try pending("a"))
    timeline.apply(RoomError(message: "No", clientMessageId: "c-a", failed: "message.create", rewrite: true).frame)
    timeline.giveBack("c-a", taken: false)
    XCTAssertNotNil(timeline.pending["c-a"])
    XCTAssertTrue(timeline.isFailed("c-a"))
    XCTAssertTrue(timeline.rewrites.isEmpty)
  }

  func testErrorForMessagesNotSendingHereIsntShown() throws {
    var timeline = Timeline()
    XCTAssertFalse(timeline.apply(RoomError(message: "Too long", clientMessageId: "reply", failed: "message.create").frame))
    XCTAssertTrue(timeline.events.isEmpty)
  }

  func testThreadKeepsRefusedReply() throws {
    var thread = ThreadTimeline(parentId: "m1")
    thread.send(try pending("r"))
    XCTAssertTrue(thread.apply(RoomError(message: "No", clientMessageId: "c-r", rewrite: true).frame))
    XCTAssertTrue(thread.isFailed("c-r"))
    XCTAssertEqual(thread.rewrites["c-r"], "No")
  }

  func testConfirmationClearsFailure() throws {
    var timeline = Timeline()
    timeline.send(try pending("a"))
    timeline.apply(.messageChecked(stored: [], missing: ["c-a"]))
    timeline.apply(.messageCreated(try pending("a"), seq: 1))
    XCTAssertFalse(timeline.isFailed("c-a"))
    XCTAssertTrue(timeline.pending.isEmpty)
  }
}

extension RoomError {
  var frame: ServerFrame { .error(self) }
}

final class PushAndCloseCodeTests: XCTestCase {
  func testPushSubscriptionSaveLeavesOutReplacingUnlessGiven() throws {
    let keys = PushSubscriptionKeys(endpoint: "https://push.example/1", p256dhKey: "p", authKey: "a")
    let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PushSubscriptionSave(keys))) as? [String: String]
    XCTAssertEqual(plain, ["endpoint": "https://push.example/1", "p256dhKey": "p", "authKey": "a"])
    let replacing = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PushSubscriptionSave(keys, replacing: "old"))) as? [String: String]
    XCTAssertEqual(replacing?["replacing"], "old")
  }

  func testPushListsDecode() throws {
    let subscriptions = try decode(PushSubscriptions.self, #"{"subscriptions":[{"id":1,"endpoint":"https://push.example/1","browser":"Safari","version":"19","platform":"macOS"}]}"#)
    XCTAssertEqual(subscriptions.subscriptions.first?.browser, "Safari")
    let saved = try decode(SavedPushSubscription.self, #"{"id":2,"endpoint":"e","browser":"","version":"","platform":""}"#)
    XCTAssertEqual(saved.id, 2)
    let tokens = try decode(DeviceTokens.self, #"{"deviceTokens":[{"id":3,"token":"ab12","platform":"ios","environment":"production","origin":"https://irc.dxnd.ai","deviceName":"iPhone","updatedAt":"2026-11-19T00:00:00.000Z"}]}"#)
    XCTAssertEqual(tokens.deviceTokens.first?.platform, .ios)
    XCTAssertEqual(tokens.deviceTokens.first?.origin, "https://irc.dxnd.ai")
  }

  func testHuddleCloseCodesAreTheirOwn() {
    XCTAssertEqual(HuddleCloseCode(rawValue: 4005), .full)
    XCTAssertEqual(HuddleCloseCode(rawValue: 4006), .off)
    XCTAssertEqual(HuddleCloseCode(rawValue: 4007), .moved)
    XCTAssertNil(CloseCode(rawValue: 4005), "a huddle's close code isn't a room's")
    XCTAssertEqual(EmberLimits.reloadAfterHidden, 60)
  }
}

final class ResponseDecodingTests: XCTestCase {
  let room = #"{"id":"general","kind":"open","name":"general","icon":null}"#
  let me = #"{"id":"a","name":"Ann","administrator":true}"#
  let invitation = #"{"id":"i1","emailAddress":"bo@example.com","invitedBy":"a","createdAt":"t","expiresAt":"t2","delivery":{"refusal":"Bounced"}}"#

  func testSignUpAndFiles() throws {
    XCTAssertEqual(try decode(Upload.self, #"{"id":"u1","partSize":5242880,"parts":3}"#).parts, 3)
    let link = try decode(EmailLinkFor.self, #"{"kind":"email_domain","emailAddress":"bo@example.com"}"#)
    XCTAssertEqual(link.kind, .emailDomain)
    XCTAssertEqual(link.kind.joinPath, "/api/join/email")
    let workspace = try decode(NewWorkspace.self, #"{"user":\#(me),"room":\#(room)}"#)
    XCTAssertTrue(workspace.user.administrator)
    XCTAssertEqual(workspace.room.id, "general")
    XCTAssertEqual(try decode(PasswordResetDone.self, #"{"user":\#(me)}"#).user?.id, "a")
    XCTAssertNil(try decode(PasswordResetDone.self, #"{"user":null}"#).user)
    XCTAssertEqual(try decode(StartedDirect.self, #"{"room":{"id":"d1","kind":"direct","members":[\#(ada)],"activeAt":"t"}}"#).room.id, "d1")
    XCTAssertEqual(try decode(NewRoomForm.self, #"{"people":[\#(ada)]}"#).people.first?.name, "Ada")
  }

  func testReleases() throws {
    let check = try decode(ReleaseCheck.self, #"""
    {"release":"2.4.0","beta":false,"newest":{"release":"2.5.0","version":"2.5.0","notes":"Fixes","newer":true},"checkedAt":"t",
    "newestBeta":null,"copy":{"repository":"dxnd/ember","branch":"main","workflow":true,"betaWorkflow":false}}
    """#)
    XCTAssertEqual(check.newest?.newer, true)
    XCTAssertEqual(check.copy?.repository, "dxnd/ember")
    XCTAssertEqual(try decode(Release.self, #"{"release":"r","version":"v","notes":"","newer":false}"#).version, "v")
  }

  func testCustomDomains() throws {
    XCTAssertEqual(try decode(CustomDomainCheck.self, #"{"reaches":"elsewhere"}"#).reaches, .elsewhere)
    let lookup = try decode(CustomDomainLookup.self, #"{"zone":"dxnd.ai","provider":"cloudflare"}"#)
    XCTAssertEqual(lookup.provider, .cloudflare)
    XCTAssertEqual(try decode(CustomDomainReach.self, #""nothing""#), .nothing)
  }

  func testInvitationsAndEmail() throws {
    let invited = try decode(Invited.self, #"{"outcomes":[{"emailAddress":"a@example.com","member":true},{"emailAddress":"bo@example.com","invitation":\#(invitation),"link":"https://x/i"}]}"#)
    XCTAssertEqual(invited.outcomes[0].member, true)
    XCTAssertEqual(invited.outcomes[1].invitation?.delivery, .refused("Bounced"))
    let resent = try decode(ResentInvitation.self, #"{"invitation":{"id":"i1","emailAddress":"b","invitedBy":"a","createdAt":"t","expiresAt":"t","delivery":"sent"},"link":null}"#)
    XCTAssertEqual(resent.invitation.delivery, .sent)
    XCTAssertEqual(try decode(NewJoinCode.self, #"{"joinCode":"aB3d-Ef5h-iJ7k"}"#).joinCode, "aB3d-Ef5h-iJ7k")
    XCTAssertEqual(try decode(SentTestEmail.self, #"{"to":"ann@example.com"}"#).to, "ann@example.com")
    XCTAssertEqual(try decode(SendingDomainCheck.self, #"{"onboarded":true}"#).onboarded, true)
    let email = try decode(EmailSettings.self, #"{"provider":"resend","resendKey":"saved","cloudflare":false,"from":"ember@dxnd.ai"}"#)
    XCTAssertEqual(email.provider, .resend)
    XCTAssertEqual(email.resendKey, .saved)
    XCTAssertEqual(try decode(TurnstileSettings.self, #"{"turnstile":"secret"}"#).turnstile, .secret)
  }

  func testHandledReports() throws {
    let handled = try decode(HandledReports.self, #"""
    {"reports":[{"id":"r2","reporterId":"a","reason":"other","note":"n","reportedAt":"t","subject":{"kind":"person","person":{"id":"b","name":"Bob","bio":null,"accountDeleted":true}},"handled":{"by":"a","at":"t","outcome":"dismissed"}}]}
    """#)
    XCTAssertEqual(handled.reports.first?.handled?.by, "a")
    XCTAssertTrue(handled.reports[0].isOfDeletedAccount)
  }

  func testAgents() throws {
    let base = #""role":"bot","status":"active","avatarUrl":"/a","agent":true,"description":"Answers","access":"admin-dms""#
    let available = try decode(AvailableAgents.self, #"{"agents":[{"id":"g","name":"Guide",\#(base),"rooms":[{"id":"general","name":"general"}]}]}"#)
    XCTAssertEqual(available.agents[0].access, .adminDms)
    XCTAssertEqual(available.agents[0].rooms?.first?.name, "general")
    let agents = try decode(Agents.self, #"{"agents":[{"id":"g","name":"Guide",\#(base),"model":"anthropic/claude","modelName":"Claude","webTools":["search"]}]}"#)
    XCTAssertEqual(agents.agents[0].webTools, [.search])
    let tools = try decode(AgentTools.self, #"{"apps":[{"id":"app1","name":"Digg","tools":[{"name":"digg_get_feed","title":null,"description":"Feed","fingerprint":"f","picked":true,"changed":false,"alwaysAllowed":false}]}]}"#)
    XCTAssertTrue(tools.apps[0].tools[0].picked)
    let trial = try decode(AgentTrialAnswer.self, #"{"body":"<p>Hi</p>","cards":[],"ms":812.5}"#)
    XCTAssertEqual(trial.ms, 812.5)
  }

  func testApps() throws {
    let apps = try decode(Apps.self, #"{"apps":[{"id":"app1","name":"Digg","url":"https://digg.example/mcp","toolCount":4,"setAside":1,"signInEnded":false,"wantsAccess":true}]}"#)
    XCTAssertEqual(apps.apps[0].toolCount, 4)
    let signIn = try decode(AppSignIn.self, #"{"by":{"id":"a","name":"Ann"},"at":"t","ended":false,"clientId":"c","wantsScope":null}"#)
    XCTAssertEqual(signIn.by?.name, "Ann")
    XCTAssertEqual(try decode(AppSignInBegun.self, #"{"authorizationUrl":"https://auth.example/a"}"#).authorizationUrl, "https://auth.example/a")
    let signedOut = try decode(YourAppSignedOut.self, #"{"apps":[{"id":"app1","name":"Digg","signedInAt":null,"ended":true,"wantsMore":false}],"revoked":true}"#)
    XCTAssertTrue(signedOut.revoked)
    XCTAssertTrue(signedOut.apps[0].ended)
  }

  func testModelsAndAssistant() throws {
    let offered = try decode(OfferedModels.self, #"""
    {"models":[{"id":"anthropic/claude","name":"Claude","format":"anthropic","price":{"input":1,"output":5},"thinkingLevels":["off","high"],"webTools":["search","read"]}],
    "suggested":"anthropic/claude","workersAi":null}
    """#)
    XCTAssertEqual(offered.models[0].price?.output, 5)
    XCTAssertEqual(offered.models[0].thinkingLevels, [.off, .high])
    let settings = #"""
    {"accountId":"acc","model":"anthropic/claude","models":[{"id":"anthropic/claude","name":"Claude","format":"messages"}],"most":{"thinking":"medium","length":"long"},
    "webTools":["read"],"instructions":"Be kind","promptTemplate":null,"avatarUrl":"/e","avatar":false}
    """#
    let assistant = try decode(AssistantSettings.self, settings)
    XCTAssertEqual(assistant.most, AnswerLevels(thinking: .medium, length: .long))
    let saved = try decode(AssistantSaved.self, #"{"assistant":\#(settings),"greeting":"Hi, I'm Ember."}"#)
    XCTAssertEqual(saved.greeting, "Hi, I'm Ember.")
  }

  func testOutsideAI() throws {
    let asked = try decode(OutsideAsked.self, #"{"name":"Claude","comesBackTo":"https://claude.ai","workspace":"dxnd","scopes":["read","private"]}"#)
    XCTAssertEqual(asked.scopes, [.read, .private])
    XCTAssertEqual(try decode(OutsideAnswered.self, #"{"redirectTo":"https://claude.ai/cb?code=x"}"#).redirectTo, "https://claude.ai/cb?code=x")
  }

  func testHuddlesAndSignInElsewhere() throws {
    XCTAssertNil(try decode(HuddlesAnswer.self, #"{"huddles":null}"#).huddles)
    XCTAssertEqual(try decode(HuddleSoundsChanged.self, #"{"sounds":{"music":false,"chimes":true,"ring":true}}"#).sounds.music, false)
    XCTAssertNil(try decode(SsoAnswer.self, #"{"sso":null}"#).sso)
    let memberful = try decode(MemberfulSaved.self, #"{"memberfulSite":"dxnd","memberfulWebhooks":true,"memberfulKeys":"saved","memberfulSiteKept":null}"#)
    XCTAssertEqual(memberful.memberfulKeys, .saved)
    let status = try decode(SsoStatus.self, #"{"name":"Okta","ssoOnly":true,"connected":null}"#)
    XCTAssertTrue(status.ssoOnly)
  }

  func testBots() throws {
    let bot = #"{"id":"b","name":"Deploys","role":"bot","status":"active","avatarUrl":"/b","key":"k","rooms":[{"id":"general","name":"general"}]}"#
    XCTAssertEqual(try decode(Bots.self, #"{"bots":[\#(bot)]}"#).bots[0].key, "k")
    let settings = try decode(BotSettings.self, #"{"id":"b","name":"Deploys","role":"bot","status":"active","avatarUrl":"/b","key":"k","rooms":[],"webhookUrl":"https://hook.example","pickedRooms":[{"id":"x","name":"x"}]}"#)
    XCTAssertEqual(settings.webhookUrl, "https://hook.example")
    XCTAssertEqual(settings.pickedRooms?.count, 1)
  }
}
