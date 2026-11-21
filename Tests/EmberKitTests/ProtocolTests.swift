import XCTest
@testable import EmberKit

// Decoding and encoding against packages/protocol @ 479e3bf9: fixtures in the shapes the Worker sends,
// and the expectations of packages/protocol's own tests where it has them.

let account = #"""
{"name":"dxnd","tagline":"","hideTranslationButtons":true,"customStyles":"","restrictRoomCreation":false,"logo":null,"customDomain":"irc.dxnd.ai","joinLink":true,"openSignUp":false,"memberfulJoin":false,"memberfulSignIn":false,"ssoJoin":false,"ssoSignIn":false,"emailDomainSignUp":false,"emailDomains":[],"navigationIcons":{"home":"coffee"},"huddles":true,"huddleCameras":true,"huddleScreens":false}
"""#
let ada = #"{"id":"0000000000000ada","name":"Ada"}"#

func message(_ id: String, extra: String = "") -> String {
  #"{"id":"\#(id)","clientMessageId":"c-\#(id)","roomId":"general","creator":\#(ada),"body":"<p>hi</p>","plainText":"hi","mentions":[],"createdAt":"2026-11-11T02:00:00.000Z","updatedAt":"2026-11-11T02:00:00.000Z","editedAt":null,"boosts":[]\#(extra)}"#
}

func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
  try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

final class ModelTests: XCTestCase {
  func testSidebarDecodesTheDeployedShape() throws {
    let json = #"""
    {"rooms":[{"id":"general","kind":"open","name":"general","icon":"coffee","huddles":false,"unread":true,"unreadSince":"2026-11-19T01:00:00.000Z","involvement":"nothing"},
    {"id":"d1","kind":"direct","members":[\#(ada)],"activeAt":"2026-11-19T01:00:00.000Z","joined":{"userId":"0000000000000ada","at":"2026-11-18T00:00:00.000Z"},"unread":true,"unreadCount":3,"involvement":"everything"}],
    "favorites":{"rooms":["general"],"version":4},"sharedOrder":["general"],"invitation":{"roomId":"general","joinCode":"aB3d-Ef5h-iJ7k"},
    "huddles":{"general":{"startedAt":"2026-11-19T01:00:00.000Z","userIds":["0000000000000ada"]}},"blocks":{"userIds":["b"],"version":2},
    "openReports":1,"huddleSounds":{"music":false,"chimes":true,"ring":true}}
    """#
    let sidebar = try decode(Sidebar.self, json)
    XCTAssertEqual(sidebar.rooms[0].room.icon, "coffee")
    XCTAssertFalse(sidebar.rooms[0].room.allowsHuddles)
    XCTAssertTrue(sidebar.rooms[0].isMarkedUnread, "a room at nothing is still marked unread")
    XCTAssertEqual(sidebar.rooms[1].unreadCount, 3)
    XCTAssertEqual(sidebar.rooms[1].room.joined?.userId, "0000000000000ada")
    XCTAssertEqual(sidebar.invitation?.joinCode, "aB3d-Ef5h-iJ7k")
    XCTAssertEqual(sidebar.blocks.version, 2)
    XCTAssertEqual(sidebar.openReports, 1)
    XCTAssertEqual(sidebar.huddleSounds?.music, false)
    XCTAssertEqual(sidebar.huddles["general"]?.userIds.count, 1)
  }

  func testSidebarWithoutBlocksDoesntDecode() {
    XCTAssertThrowsError(try decode(Sidebar.self, #"{"rooms":[],"favorites":{"rooms":[],"version":0},"sharedOrder":[],"invitation":null,"huddles":{}}"#))
  }

  func testHiddenRoomIsntMarked() throws {
    let room = try decode(SidebarRoom.self, #"{"id":"x","kind":"open","name":"x","icon":null,"unread":true,"involvement":"invisible"}"#)
    XCTAssertFalse(room.isMarkedUnread)
  }

  func testBootstrapAndAccount() throws {
    let json = #"""
    {"setup":"complete","setupAccess":"closed","setupPlaceholders":{"name":"Ann","emailAddress":"ann@example.com"},"guestSignIn":false,"signInWithMemberful":false,
    "signInWithSso":"Okta","turnstileSiteKey":null,"passwordResetCodes":true,"account":\#(account),"version":"2.4.0","vapidPublicKey":null,"apnsPush":true,
    "platform":{"ios":false,"android":false,"desktop":true,"windows":false,"chrome":false,"firefox":false,"safari":false,"edge":false,"browser":"","operatingSystem":"macOS"},"user":null}
    """#
    let bootstrap = try decode(Bootstrap.self, json)
    XCTAssertEqual(bootstrap.setupAccess, .closed)
    XCTAssertEqual(bootstrap.ssoName, "Okta")
    XCTAssertTrue(bootstrap.passwordResetCodes)
    XCTAssertNil(bootstrap.user)
    XCTAssertEqual(bootstrap.account.icon(for: .home), "coffee")
    XCTAssertEqual(bootstrap.account.icon(for: .search), "iconoir:regular:search")
    XCTAssertTrue(bootstrap.account.joinsWithLink)
    XCTAssertFalse(bootstrap.account.huddleScreens)
    XCTAssertEqual(bootstrap.apnsPush, true)
    let before = try decode(Bootstrap.self, json.replacingOccurrences(of: #""apnsPush":true,"#, with: ""))
    XCTAssertNil(before.apnsPush)
  }

  func testDirectoryUserAndPerson() throws {
    let user = try decode(DirectoryUser.self, #"{"id":"ember","name":"Ember","username":"ember","bio":null,"role":"bot","status":"active","avatarUrl":"/users/t/avatar?v=1","agent":true,"adminsOnly":true}"#)
    XCTAssertEqual(user.username, "ember")
    XCTAssertTrue(user.isAgent)
    XCTAssertTrue(user.isAdminsOnly)
    let person = try decode(PersonAnswer.self, #"""
    {"person":{"id":"a","name":"Ann","bio":"Hi","role":"member","status":"suspended","avatarUrl":"/a","emailAddress":"ann@example.com"},"transferId":"t1",
    "agent":{"description":"Answers","model":"anthropic/claude-haiku-5.5","modelName":"Claude Haiku 5.5","setUpBy":\#(ada)}}
    """#)
    XCTAssertEqual(person.person.emailAddress, "ann@example.com")
    XCTAssertEqual(person.agent?.setUpBy.name, "Ada")
  }

  func testMessageWithCardsAndHuddle() throws {
    let cards = #","cards":[{"source":"attachment","color":"good","parts":[{"kind":"header","text":"Launch"},{"kind":"section","html":"<p>x</p>","fields":[{"title":"Owner","html":"<p>Web</p>","short":true}]},{"kind":"context","items":[{"html":"<p>c</p>"},{"image":{"url":"https://x/i.png","alt":"i"}}]},{"kind":"divider"},{"kind":"buttons","buttons":[{"text":"Approve","action":{"id":"ember.call.allow","value":"1"},"style":"primary"},{"text":"Open","href":"https://x"}]},{"kind":"table","rows":[["a","b"]],"columns":[{"align":"right","wrap":true}]},{"kind":"tiles","tiles":[{"title":"T","buttons":[]}]},{"kind":"footer","text":"f","at":1700000000},{"kind":"sparkle"}]}],"huddle":{"startedAt":"2026-11-19T01:00:00.000Z","endedAt":"2026-11-19T02:00:00.000Z","people":[\#(ada)]}"#
    let decoded = try decode(Message.self, message("m1", extra: cards))
    let parts = try XCTUnwrap(decoded.cards?.first?.parts)
    XCTAssertEqual(parts.first, .header(text: "Launch"))
    XCTAssertEqual(parts[2], .context([.html("<p>c</p>"), .image(CardImage(url: "https://x/i.png", alt: "i"))]))
    guard case let .buttons(buttons) = parts[4] else { return XCTFail("\(parts[4])") }
    XCTAssertEqual(buttons[0].action?.id, AppRules.allowAction)
    XCTAssertEqual(buttons[0].style, .primary)
    XCTAssertEqual(parts.last, .unknown("sparkle"))
    XCTAssertEqual(decoded.huddle?.people?.first?.name, "Ada")
    XCTAssertFalse(decoded.isEditable)
    let again = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(decoded))
    XCTAssertEqual(again, decoded)
  }

  func testRoomSettingsAndChangedBlocks() throws {
    let settings = try decode(RoomSettings.self, #"{"room":{"id":"r","kind":"closed","name":"ops","icon":null},"canAdminister":true,"canChangeHuddles":false,"people":[{"id":"a","name":"Ann","member":true}]}"#)
    XCTAssertEqual(settings.people.first?.member, true)
    let blocks = try decode(ChangedBlocks.self, #"{"blocks":{"userIds":["b"],"version":3},"direct":{"roomId":"d","involvement":"invisible"}}"#)
    XCTAssertEqual(blocks.direct?.involvement, .invisible)
  }

  func testProfile() throws {
    let json = #"""
    {"profile":{"name":"Ann","username":null,"emailAddress":null,"bio":null,"avatarUrl":"/a","avatar":false,"password":false,"membershipNeeded":false,
    "memberful":{"membersOnly":true,"connected":{"name":null,"emailAddress":"a@x"}},"sso":null,
    "assistant":{"levels":{"thinking":"low","length":"medium"},"most":{"thinking":"high","length":"long"},"model":null,"defaultModel":"anthropic/claude-haiku-5.5","models":[{"id":"anthropic/claude-haiku-5.5","name":"Claude Haiku 5.5","format":"anthropic"}]},
    "apps":[{"id":"app1","name":"Linear","signedInAt":null,"ended":false,"wantsMore":false}],
    "outsideAi":[{"id":"o","name":"Claude","comesBackTo":"claude.ai","scopes":["read","private"],"connectedAt":"2026-11-19T01:00:00.000Z","usedAt":null}]},"transferId":"t"}
    """#
    let answer = try decode(ProfileAnswer.self, json)
    XCTAssertEqual(answer.profile.memberful?.connected?.emailAddress, "a@x")
    XCTAssertEqual(answer.profile.assistant?.levels, .default)
    XCTAssertEqual(answer.profile.outsideAi?.first?.scopes, [.read, .private])
  }

  func testWorkspaceSettings() throws {
    let json = #"""
    {"account":\#(account),"joinCode":"aB3d","canAdminister":true,"memberfulSite":null,"memberfulWebhooks":false,"memberfulKeys":null,"memberfulSiteKept":null,
    "sso":{"source":"saved","issuer":"https://a","clientId":"c","name":"Okta","scopes":["openid"],"groupsClaim":"groups","allowedGroups":[],"linksVerifiedEmails":false},
    "turnstile":"secret","email":{"provider":"resend","resendKey":"saved","cloudflare":false,"from":null},
    "invitations":[{"id":"i1","emailAddress":"b@x","invitedBy":"Ada","createdAt":"t","expiresAt":"t","delivery":"sent"},
    {"id":"i2","emailAddress":"c@x","invitedBy":"Ada","createdAt":"t","expiresAt":"t","delivery":{"refusal":"bounced"}},
    {"id":"i3","emailAddress":"d@x","invitedBy":"Ada","createdAt":"t","expiresAt":"t","delivery":null}],
    "emailDomains":["example.com"],"blockedWords":["fudge"],"addresses":{"deployed":"ember.workers.dev","others":[]},"assistant":null,
    "huddles":{"appId":"a","relayKeyId":null},"outsideAi":true,"cloudflareAccountId":null}
    """#
    let settings = try decode(WorkspaceSettings.self, json)
    XCTAssertEqual(settings.turnstile, .secret)
    XCTAssertEqual(settings.invitations.map(\.delivery), [.sent, .refused("bounced"), nil])
    XCTAssertEqual(settings.sso?.name, "Okta")
  }

  func testReportsAndSearchResults() throws {
    let reports = try decode(Reports.self, #"""
    {"open":[{"id":"r1","reporterId":"a","reason":"spam","note":"","reportedAt":"t","subject":{"kind":"message","roomId":"g","room":{"kind":"open","name":"general"},"message":{"id":"m","creator":\#(ada),"body":"<p>x</p>","plainText":"x","mentions":[],"createdAt":"t","editedAt":null,"attachment":{"name":"f","contentType":"text/plain","byteSize":1}}},"handled":null}],
    "handled":[{"id":"r2","reporterId":"a","reason":"other","note":"n","reportedAt":"t","subject":{"kind":"person","person":{"id":"b","name":"Bob","bio":null,"accountDeleted":true}},"handled":{"by":"a","at":"t","outcome":"dismissed"}}]}
    """#)
    XCTAssertEqual(reports.open.first?.reason.label, "Spam")
    XCTAssertTrue(reports.handled[0].isOfDeletedAccount)
    let results = try decode(SearchResults.self, #"{"search":{"q":"eel","withMe":true},"matches":[{"message":\#(message("m1")),"words":["eel"]}],"next":100,"rooms":[],"recent":[{"q":"eel"}]}"#)
    XCTAssertEqual(results.search?.withMe, true)
    XCTAssertEqual(results.next, 100)
  }

  func testAgentsAppsAndBots() throws {
    let agent = try decode(AgentAnswer.self, #"""
    {"agent":{"id":"g","name":"Recap","bio":null,"role":"bot","status":"active","avatarUrl":"/a","agent":true,"description":"Recaps","model":"anthropic/claude-haiku-5.5","modelName":"Claude Haiku 5.5","webTools":["search"],"access":"admin-dms","rooms":null,
    "instructions":"Recap.","promptTemplate":null,"format":"anthropic","levels":{"thinking":"off","length":"short"},"thinkingLevels":null,"avatar":false,"changedBy":\#(ada),"changedAt":"t"}}
    """#)
    XCTAssertEqual(agent.agent.access, .adminDms)
    let app = try decode(AppAnswer.self, #"""
    {"app":{"id":"a","name":"Linear","url":"https://mcp.linear.app","hasToken":false,"serverName":null,"tools":[{"name":"t","title":null,"description":"d"}],"toolsLeftOut":0,"toolsReadAt":"t","connectedBy":null,"setAside":[],"signIn":{"by":null,"at":"t","ended":false,"clientId":null,"wantsScope":null}}}
    """#)
    XCTAssertEqual(app.app.tools.count, 1)
    let finished = try decode(AppSignInFinished.self, #"{"yours":{"id":"a","name":"Linear","signedInAt":"t","ended":false,"wantsMore":false}}"#)
    guard case .yours = finished else { return XCTFail("\(finished)") }
    let bot = try decode(BotAnswer.self, #"{"bot":{"id":"b","name":"CI","bio":null,"role":"bot","status":"active","avatarUrl":"/a","key":"k","rooms":[{"id":"g","name":"general"}],"webhookUrl":null,"pickedRooms":null}}"#)
    XCTAssertNil(bot.bot.pickedRooms)
  }

  func testEncodesNullsWhereTheProtocolSaysNull() throws {
    let rooms = String(decoding: try JSONEncoder().encode(BotChanges(rooms: .everyOpenRoom)), as: UTF8.self)
    XCTAssertEqual(rooms, #"{"rooms":null}"#)
    let template = String(decoding: try JSONEncoder().encode(AssistantChanges(promptTemplate: .some(nil))), as: UTF8.self)
    XCTAssertEqual(template, #"{"promptTemplate":null}"#)
    let none = String(decoding: try JSONEncoder().encode(AccountChanges(name: "x")), as: UTF8.self)
    XCTAssertEqual(none, #"{"name":"x"}"#)
  }

  func testHuddleTypes() throws {
    let past = try decode(PastHuddles.self, #"{"huddles":[{"roomId":"g","messageId":"m","startedAt":"a","endedAt":"b","userIds":["x"],"replies":2}]}"#)
    XCTAssertEqual(past.huddles.first?.replies, 2)
    let person = try decode(HuddlePerson.self, #"{"user":\#(ada),"muted":false,"audio":true,"video":false,"screen":false,"sticker":"thumbs-up"}"#)
    XCTAssertEqual(person.sticker, .thumbsUp)
    XCTAssertTrue(person.has(.audio))
  }
}

final class ProtocolFrameTests: XCTestCase {
  func testRoomFramesTheProtocolAdded() throws {
    XCTAssertEqual(
      try ServerFrame.decode(#"{"type":"history.after","after":"m1","messages":[\#(message("m2"))],"hasNewer":true}"#),
      .historyAfter(after: "m1", messages: [try decode(Message.self, message("m2"))], hasNewer: true))
    XCTAssertEqual(try ServerFrame.decode(#"{"type":"card.clicked","clickId":"k"}"#), .cardClicked(clickId: "k"))
    XCTAssertEqual(
      try ServerFrame.decode(#"{"type":"typing","user":\#(ada),"typing":true,"doing":"is searching this room"}"#),
      .typing(user: User(id: "0000000000000ada", name: "Ada"), typing: true, threadId: nil, doing: EmberText.searchingRoom))
    let error = try ServerFrame.decode(#"{"type":"error","message":"This community doesn't allow one of these words.","clientMessageId":"c1","failed":"message.create","rewrite":true}"#)
    XCTAssertEqual(error, .error(RoomError(message: BlockedWords.refused, clientMessageId: "c1", failed: "message.create", rewrite: true)))
    let checked = try ServerFrame.decode(#"{"type":"error","message":"x","clientMessageIds":["a","b"],"failed":"message.check"}"#)
    guard case let .error(failure) = checked else { return XCTFail("\(checked)") }
    XCTAssertEqual(failure.notSent, ["a", "b"])
    XCTAssertFalse(RoomError(message: "x", failed: "thread.open").showsInRoom)
  }

  func testWorkspaceFrames() throws {
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"room.unread","roomId":"d","at":"2026-11-19T01:00:00.000Z","count":2}"#), .roomUnread("d", at: "2026-11-19T01:00:00.000Z", count: 2))
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"room.unread","roomId":"g","at":"t"}"#), .roomUnread("g", at: "t", count: nil))
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"user.gone","userId":"b"}"#), .userGone("b"))
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"huddle.invited","roomId":"g","by":"a"}"#), .huddleInvited("g", by: "a"))
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"huddle.answered","roomId":"g"}"#), .huddleAnswered("g"))
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"huddle.sounds","sounds":{"music":true,"chimes":false,"ring":true}}"#), .huddleSounds(HuddleSounds(music: true, chimes: false, ring: true)))
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"huddles.changed"}"#), .huddlesChanged)
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"blocks.changed","blocks":{"userIds":["b"],"version":5}}"#), .blocksChanged(Blocks(userIds: ["b"], version: 5)))
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"reports.changed","open":3}"#), .reportsChanged(open: 3))
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"invitation.dismissed"}"#), .invitationDismissed)
    XCTAssertEqual(try WorkspaceFrame.decode(#"{"type":"presence","active":["a"],"away":["b"]}"#), .presence(active: ["a"], away: ["b"]))
    guard case let .welcome(you, decoded) = try WorkspaceFrame.decode(#"{"type":"welcome","you":{"id":"a","name":"Ann","administrator":true},"account":\#(account)}"#) else {
      return XCTFail("welcome")
    }
    XCTAssertTrue(you.administrator)
    XCTAssertTrue(decoded.hideTranslationButtons)
  }

  func testHuddleFrames() throws {
    let welcome = try HuddleServerFrame.decode(#"{"type":"huddle.welcome","you":\#(ada),"people":[],"startedAt":"t","iceServers":[{"urls":["turn:x"],"username":"u","credential":"c"}]}"#)
    guard case let .welcome(_, _, _, messageId, iceServers) = welcome else { return XCTFail("\(welcome)") }
    XCTAssertNil(messageId)
    XCTAssertEqual(iceServers?.first?.credential, "c")
    XCTAssertEqual(
      try HuddleServerFrame.decode(#"{"type":"huddle.offer","kind":"video","sdp":"v=0","tracks":[{"mid":"0","kind":"video","userId":"a"}]}"#),
      .offer(.video, sdp: "v=0", tracks: [OfferedHuddleTrack(mid: "0", kind: .video, userId: "a")]))
    XCTAssertEqual(try HuddleServerFrame.decode(#"{"type":"error","message":"m","failed":"huddle.publish","kind":"screen","refused":true}"#), .error(message: "m", failed: "huddle.publish", kind: .screen, refused: true))
    XCTAssertEqual(try HuddleClientFrame.listen(.audio, fresh: true).encoded(), #"{"fresh":true,"kind":"audio","type":"huddle.listen"}"#)
    XCTAssertEqual(try HuddleClientFrame.listen(.video, watch: ["a"], small: true).encoded(), #"{"kind":"video","small":true,"type":"huddle.listen","watch":["a"]}"#)
    XCTAssertEqual(try HuddleClientFrame.sticker(nil).encoded(), #"{"sticker":null,"type":"huddle.sticker"}"#)
    XCTAssertEqual(try HuddleClientFrame.publish(sdp: "v=0", track: HuddleTrack(mid: "0", kind: .audio)).encoded(), #"{"sdp":"v=0","tracks":[{"kind":"audio","mid":"0"}],"type":"huddle.publish"}"#)
    XCTAssertEqual(Huddles.socketQuery(muted: true), "?muted=1")
    XCTAssertEqual(Huddles.socketQuery(muted: false), "")
  }

  func testClientFrames() throws {
    XCTAssertEqual(try ClientFrame.historyAfter(after: "m1", limit: 40).encoded(), #"{"after":"m1","limit":40,"type":"history.after"}"#)
    XCTAssertEqual(
      try ClientFrame.messagePreview(clientMessageId: "c", preview: LinkPreview(title: "T", url: "https://x", image: nil, description: "")).encoded(),
      #"{"clientMessageId":"c","preview":{"description":"","image":null,"title":"T","url":"https://x"},"type":"message.preview"}"#)
    XCTAssertEqual(try ClientFrame.cardClick(clickId: "k", messageId: "m", actionId: "a").encoded(), #"{"actionId":"a","clickId":"k","messageId":"m","type":"card.click"}"#)
    XCTAssertEqual(try WorkspaceClientFrame.presenceActive(false).encoded(), #"{"active":false,"type":"presence.active"}"#)
    XCTAssertEqual(try WorkspaceClientFrame.presenceVisible(true).encoded(), #"{"type":"presence.visible","visible":true}"#)
  }

  func testSocketQueries() {
    // packages/protocol's index.test.ts.
    XCTAssertEqual(RoomSocketParams(visible: true, apart: true).query, "?visible=1&protocol=4&apart=1")
    XCTAssertEqual(RoomSocketParams(visible: true, around: "01J9 Z/3").query, "?visible=1&protocol=4&around=01J9%20Z%2F3")
    XCTAssertEqual(RoomSocketParams(visible: true, since: 0).query, "?visible=1&protocol=4&since=0")
    XCTAssertEqual(RoomSocketParams(visible: false, since: 42).query, "?visible=0&protocol=4&since=42")
    XCTAssertEqual(workspaceSocketPath(visible: true), "/api/socket?visible=1")
    XCTAssertEqual(workspaceSocketPath(visible: false), "/api/socket?visible=0")
    XCTAssertEqual(roomProtocol, 4)
  }

  func testTimelinePagesForwardAfterAPermalink() throws {
    var timeline = Timeline()
    timeline.apply(try ServerFrame.decode(#"{"type":"history.around","messages":[\#(message("m1"))],"hasMore":true,"hasNewer":true,"around":"m1"}"#))
    XCTAssertTrue(timeline.hasNewer)
    XCTAssertEqual(timeline.around, "m1")
    timeline.apply(.messageCreated(try decode(Message.self, message("m9")), seq: 9))
    XCTAssertEqual(timeline.messages.map(\.id), ["m1"], "a timeline behind shows a new message once it pages to it")
    XCTAssertFalse(timeline.apply(.historyAfter(after: "m0", messages: [], hasNewer: false)), "an answer for another place changes nothing")
    timeline.apply(.historyAfter(after: "m1", messages: [try decode(Message.self, message("m2"))], hasNewer: false))
    XCTAssertEqual(timeline.messages.map(\.id), ["m1", "m2"])
    XCTAssertFalse(timeline.hasNewer)
  }

  func testActivePeopleHearsAFullListThenChanges() {
    var people = ActivePeople()
    people.hear(active: ["a", "b"], away: [])
    people.hear(active: ["c"], away: ["a"])
    XCTAssertEqual(people.active, ["b", "c"])
    people.reconnected()
    people.hear(active: ["d"], away: [])
    XCTAssertEqual(people.active, ["d"])
  }
}

final class APITests: XCTestCase {
  func testProblemsKeepTheirFields() {
    let body = Data(#"{"error":"That email address has an account already","redirect":"/session/new?email_address=a%40x","field":"emailAddress"}"#.utf8)
    XCTAssertEqual(
      EmberAPI.problem(status: 409, data: body),
      .problem(EmberProblem(status: 409, message: EmberText.emailAddressTaken, field: "emailAddress", redirect: "/session/new?email_address=a%40x")))
    XCTAssertEqual(EmberAPI.problem(status: 429, data: Data()), .refused(429, "Request failed (429)"))
    XCTAssertEqual(EmberAPI.problem(status: 502, data: Data("<html>".utf8)), .refused(502, "Request failed (502)"))
    let app = EmberAPI.problem(status: 422, data: Data(#"{"error":"x","signIn":true}"#.utf8))
    XCTAssertEqual(app.problem?.signIn, true)
  }

  func testConnectElsewhereSaysWhere() {
    let error = EmberError.connectElsewhere(ElsewhereConnection(memberfulConnection: "https://m", ssoConnection: nil), ssoName: "SSO")
    XCTAssertEqual(error.errorDescription, "This workspace now uses Memberful. Connect your Memberful account to keep signing in.")
    let both = EmberError.connectElsewhere(ElsewhereConnection(memberfulConnection: "https://m", ssoConnection: "https://s"), ssoName: "Okta")
    XCTAssertEqual(both.errorDescription, "This workspace now uses Memberful and Okta. Connect your account at either to keep signing in.")
  }

  func testMentionPrompt() throws {
    let html = #"""
    <lexxy-prompt-item search="Ann &amp; Co" sgid="0000000000000ann">
      <template type="menu"><span class="autocomplete__item"><img class="avatar" aria-hidden="true" src="/users/t/avatar?v=1" width="48" height="48"><span class="autocompletable__name">Ann &amp; Co</span> <span class="autocompletable__username">@ann</span></span></template>
      <template type="editor"><span class="mention" sgid="0000000000000ann"></span></template>
    </lexxy-prompt-item>
    <lexxy-prompt-item search="Ember" sgid="ember">
      <template type="menu"><span class="autocomplete__item"><img class="avatar" aria-hidden="true" src="/e" width="48" height="48"><span class="autocompletable__name">Ember</span> <span class="autocompletable__badge">Agent</span></span></template>
      <template type="editor"></template>
    </lexxy-prompt-item>
    """#
    let items = try MentionPrompt.items(in: html)
    XCTAssertEqual(items.map(\.name), ["Ann & Co", "Ember"])
    XCTAssertEqual(items[0].username, "ann")
    XCTAssertEqual(items[0].avatarUrl, "/users/t/avatar?v=1")
    XCTAssertTrue(items[1].agent)
    XCTAssertEqual(try MentionPrompt.items(in: ""), [])
  }

  func testMultipartForm() throws {
    let photo = ChosenPhoto(data: Data("img".utf8), fileName: "me.jpg", contentType: "image/jpeg", variant: Data("v".utf8), variantContentType: "image/jpeg")
    let form = try MultipartForm.photo(photo, user: SignUp(name: "Ann", emailAddress: "a@x", password: "p"))
    let body = String(decoding: form.body, as: UTF8.self)
    XCTAssertTrue(body.contains(#"name="user""#))
    XCTAssertTrue(body.contains(#"name="avatar"; filename="me.jpg""#))
    XCTAssertTrue(body.contains(#"name="variant"; filename="variant""#))
    XCTAssertTrue(body.hasSuffix("--\(form.boundary)--\r\n"))
  }
}

final class RulesTests: XCTestCase {
  func testAvatars() {
    // packages/protocol's avatars.test.ts.
    XCTAssertEqual(Avatars.crc32("1"), 0x83DC_EFB7)
    XCTAssertEqual(["1", "2", "42", "1000"].map(Avatars.color(for:)), ["#BF7C2A", "#698F9C", "#D07B53", "#BFA07A"])
    XCTAssertEqual(Avatars.crc32("\u{E9}"), 0x0E04_8D3E)
    XCTAssertEqual(Avatars.crc32("\u{20AC}"), 0x83F2_C8D6)
    XCTAssertEqual(Avatars.crc32("\u{1F600}"), 0x054D_B544)
    XCTAssertEqual(Avatars.initials("David Heinemeier Hansson"), "DHH")
    XCTAssertEqual(Avatars.initials("\u{C9}lodie \u{DC}nal-Smith o'Brien 3po _x \u{F1}"), "SoB3_")
    XCTAssertEqual(Avatars.initials("grace"), "g")
    XCTAssertEqual(Avatars.initials("\u{C9}lodie"), "")
    XCTAssertEqual(Avatars.initials("Ada Byron King Lovelace Countess"), "ABKLC")
  }

  func testUsernamesAndNames() {
    // packages/protocol's index.test.ts.
    XCTAssertEqual(EmberRules.username(of: "@Grace Hopper"), "gracehopper")
    XCTAssertEqual(EmberRules.username(of: "GRACE\t\n"), "grace")
    XCTAssertEqual(EmberRules.username(of: "grace@navy"), "grace@navy")
    XCTAssertEqual(EmberRules.username(from: "Katherine Johnson"), "katherinejohnson")
    XCTAssertEqual(EmberRules.username(from: "Ada Lovelace (1815)"), "adalovelace1815")
    XCTAssertEqual(EmberRules.username(from: "\u{C9}milie du Ch\u{E2}telet"), "emilieduchatelet")
    XCTAssertEqual(EmberRules.username(from: "Maximiliana Wolfeschlegelsteinhausen"), "maximilianawolfes")
    XCTAssertEqual(EmberRules.username(from: "\u{674E}\u{767D}"), "member")
    XCTAssertEqual(EmberRules.username(from: " "), "member")
    XCTAssertTrue(EmberRules.isUsername("grace.h-1_"))
    XCTAssertFalse(EmberRules.isUsername("_grace"))
    XCTAssertFalse(EmberRules.isUsername(String(repeating: "a", count: 22)))
    for name in ["Recap", "recap", " RECAP ", "@Recap", "\u{FF32}\u{FF45}\u{FF43}\u{FF41}\u{FF50}", "Re\u{200B}cap"] {
      XCTAssertTrue(EmberRules.sameName(name, "Recap"), name)
    }
    for name in ["Recaps", "Re cap", "Recap Bot", ""] { XCTAssertFalse(EmberRules.sameName(name, "Recap"), name) }
    XCTAssertTrue(EmberRules.isReservedName(" ember"))
  }

  func testPasswordsAndCodes() {
    XCTAssertTrue(EmberRules.isPasswordTooShort("1234567"))
    XCTAssertFalse(EmberRules.isPasswordTooShort("\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}"), "eight characters, counted as characters")
    XCTAssertTrue(EmberRules.isPasswordTooLong(String(repeating: "\u{1F600}", count: 37)), "74 UTF-16 units")
    XCTAssertEqual(EmberRules.passwordResetCode(of: "1234 5678"), "12345678")
    XCTAssertEqual(EmberRules.passwordResetCode(of: "1234-567"), nil)
  }

  func testSearchQuery() {
    // packages/protocol's search.test.ts.
    let search = Search(q: "eel", in: "room1", from: "ada", withMe: true, hasLink: true, hasFile: true, inThread: true)
    XCTAssertEqual(Searches.query(search), "q=eel&in=room1&from=ada&with=me&has=link&has=file&is=thread")
    XCTAssertEqual(Searches.query(Search(q: "eel"), sort: .newest, cursor: 42), "q=eel&cursor=42")
    XCTAssertEqual(Searches.query(Search(q: "two words"), sort: .oldest), "q=two+words&sort=oldest")
    XCTAssertFalse(Search(q: "!!").isSearchable)
    XCTAssertTrue(Search(q: "", hasFile: true).isSearchable)
    XCTAssertEqual(Searches.words("eel, pie"), ["eel", "pie"])
  }

  func testEmailAddressesAndDomains() {
    let pasted = EmberRules.emailAddresses(in: #"Ann <ann@example.com>, "Bob, Jr" bob@example.com; ann@EXAMPLE.com nope"#)
    XCTAssertEqual(pasted.emailAddresses, ["ann@example.com", "bob@example.com"])
    XCTAssertEqual(pasted.refused, ["nope"])
    XCTAssertEqual(WorkspaceRules.emailDomain(of: "@Example.COM"), "example.com")
    XCTAssertNil(WorkspaceRules.emailDomain(of: "example"))
    XCTAssertEqual(EmberText.domainsInWords(["a.com", "b.com", "c.com"]), "a.com, b.com or c.com")
  }

  func testBlockedWords() {
    // packages/protocol's blocked-words.test.ts.
    XCTAssertEqual(BlockedWords.words(of: "Caf\u{E9} cr\u{E8}me, s'il vous pla\u{EE}t!"), ["cafe", "creme", "s", "il", "vous", "plait"])
    XCTAssertEqual(BlockedWords.words(of: "Vi\u{1EC7}t Nam 2026 \u{130}stanbul"), ["viet", "nam", "2026", "istanbul"])
    XCTAssertEqual(BlockedWords.words(of: "\u{4F60}\u{662F}"), ["\u{4F60}", "\u{662F}"])
    XCTAssertEqual(BlockedWords.typed("fudge\n  darn   it ,heck\n\n,,Fudge\nf\u{FA}dge\n"), ["fudge", "darn it", "heck"])
    XCTAssertEqual(BlockedWords.typed("  \n , "), [])
    XCTAssertNil(BlockedWords.refusal(["fudge"]))
    XCTAssertEqual(BlockedWords.refusal(["fudge", "!!!"]), BlockedWords.unmatchable("!!!"))
    XCTAssertEqual(BlockedWords.refusal([String(repeating: "x", count: 61)]), BlockedWords.tooLong(String(repeating: "x", count: 61)))
  }

  func testReleasesAndKeys() {
    XCTAssertTrue(WorkspaceRules.isNewer("2.4.1", than: "2.4.0"))
    XCTAssertTrue(WorkspaceRules.isNewer("2.5.0", than: "2.5.0-beta.3"))
    XCTAssertFalse(WorkspaceRules.isNewer("2.5.0-beta.3", than: "2.5.0"))
    XCTAssertFalse(WorkspaceRules.isNewer("2.4.0", than: "2.4.0"))
    XCTAssertEqual(Huddles.appId(of: String(repeating: "a", count: 32)), String(repeating: "a", count: 32))
    XCTAssertNil(Huddles.appId(of: "short"))
    XCTAssertNotNil(WorkspaceRules.turnstileKey(of: "0x4AAAAAAAAAAAAAAAAAA"))
    XCTAssertNotNil(WorkspaceRules.resendApiKey(of: "re_abc"))
    XCTAssertEqual(AssistantRules.model(of: " anthropic/claude-haiku-5.5 "), "anthropic/claude-haiku-5.5")
    XCTAssertEqual(AnswerLevels.top.within(.default), .default)
    XCTAssertEqual(AssistantRules.modelName("xai/grok-4.7"), "Grok 4.7")
  }

  func testPages() {
    XCTAssertEqual(Pages.page(of: "/rooms/general/@m1"), .room("general", messageId: "m1"))
    XCTAssertEqual(Pages.page(of: "/rooms/general/messages/m1"), .message("general", messageId: "m1"))
    XCTAssertEqual(Pages.page(of: "/rooms/general/threads/p1/@r1"), .room("general", threadId: "p1", replyId: "r1"))
    XCTAssertEqual(Pages.page(of: "/rooms/general/huddle"), .room("general", huddle: true))
    XCTAssertEqual(Pages.page(of: "/rooms/directs/d1"), .roomOfKind(.direct, "d1"))
    XCTAssertEqual(Pages.page(of: "/rooms/closeds/new"), .newRoom(.closed))
    XCTAssertEqual(Pages.page(of: "/users/me/profile"), .profile)
    XCTAssertEqual(Pages.page(of: "/users/abc"), .person("abc"))
    XCTAssertNil(Pages.page(of: "/nowhere"))
    XCTAssertEqual(Pages.page(ofLink: "https://irc.dxnd.ai/rooms/general/@m1", origin: "https://irc.dxnd.ai"), .room("general", messageId: "m1"))
    XCTAssertNil(Pages.page(ofLink: "https://example.com/rooms/general", origin: "https://irc.dxnd.ai"))
    XCTAssertEqual(Pages.messagePath("general", "m1"), "/rooms/general/@m1")
    XCTAssertEqual(Pages.threadPath("g", "p", replyId: "r"), "/rooms/g/threads/p/@r")
    XCTAssertEqual(BotsRules.messagesPath(room: "g", key: "k", threadId: "t"), "/rooms/g/k/messages?thread=t")
  }

  func testPromptTemplates() {
    XCTAssertNil(Prompts.refusal(Prompts.emberTemplate))
    XCTAssertEqual(Prompts.refusal("no place"), Prompts.instructionsPlaceNeeded)
    XCTAssertTrue(Prompts.refusal("{{nope}} {{instructions}}")?.hasPrefix("Ember has nothing to fill in for {{nope}}.") == true)
    let prompt = Prompts.around(
      answererId: Assistant.id, name: "Ember", askerName: "Ann", askedIn: AskedIn(community: "dxnd", roomName: "general", inThread: false), words: 400,
      web: "", now: Date(timeIntervalSince1970: 0))
    XCTAssertTrue(prompt.before.hasPrefix(#"You are Ember, the AI assistant in the team chat "dxnd"."#))
    XCTAssertTrue(prompt.after.contains(#"You're asked in the room "general"."#))
    XCTAssertTrue(prompt.after.contains("It's Thursday, January 1, 1970 at 00:00 in UTC."))
  }

  func testTablesPorted() {
    XCTAssertEqual(RoomIcons.names.count, 3540)
    XCTAssertTrue(EmberRules.isRoomIcon("coffee"))
    XCTAssertTrue(EmberRules.isRoomIcon("iconoir:regular:home"))
    XCTAssertEqual(Reactions.all.count, 8)
    XCTAssertEqual(Reactions.quick.map(\.name), ["Thumbs up", "Clapping", "Waving hand"])
    XCTAssertEqual(Translations.all.count, 13)
    XCTAssertEqual(Translations.of("email_address")?.first?.text, "Enter your email address")
  }
}
