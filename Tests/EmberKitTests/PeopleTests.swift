import CoreGraphics
@testable import EmberKit
import ImageIO
import XCTest

/** Every way in, read from pasted links, the pages a browser-held flow ends on, and the profile form's rules. */
final class PeopleTests: XCTestCase {
  func testLinksRouteToTheirFlows() throws {
    func route(_ text: String) -> EmberRoute? { EmberLink.parse(text)?.route }
    XCTAssertEqual(EmberLink.parse("irc.dxnd.ai")?.baseURL.absoluteString, "https://irc.dxnd.ai")
    XCTAssertEqual(route("irc.dxnd.ai"), .instance)
    XCTAssertEqual(route("https://chat.example.com/join/abc-123"), .join(code: "abc-123"))
    XCTAssertEqual(route("https://chat.example.com/join"), .signUp)
    XCTAssertEqual(route("https://chat.example.com/join/invitation#token=inv0"), .invitation(token: "inv0"))
    XCTAssertEqual(route("https://chat.example.com/join/email"), .emailSignUp(token: nil))
    XCTAssertEqual(route("https://chat.example.com/join/email#token=em1"), .emailSignUp(token: "em1"))
    XCTAssertEqual(route("https://chat.example.com/session/transfers#token=t42"), .transfer(id: "t42"))
    XCTAssertEqual(route("https://chat.example.com/passwords/new?email_address=ada%40example.com"), .passwordReset(emailAddress: "ada@example.com"))
    XCTAssertEqual(
      route("https://chat.example.com/session/new?joining=link_off"), .signIn(emailAddress: nil, problem: EmberText.joiningProblems["link_off"]))
    XCTAssertEqual(route("https://chat.example.com/session/new?sso=membership"), .signIn(emailAddress: nil, problem: SSO.signInProblems["membership"]))
    XCTAssertEqual(route("http://localhost:8787/first_run#token=s3t"), .firstRun(token: "s3t"))
    XCTAssertEqual(route("https://chat.example.com/rooms/r1/@m1"), .page("https://chat.example.com/rooms/r1/@m1"))
    guard case let .outsideConnect(ask) = route("https://chat.example.com/oauth/authorize?response_type=code&client_id=c1&scope=read%20write&state=xyz") else {
      return XCTFail("Not an AI app's request")
    }
    XCTAssertEqual(ask.clientId, "c1")
    XCTAssertEqual(ask.scope, "read write")
    XCTAssertEqual(ask.state, "xyz")
    // A link whose secret is missing is just the server.
    XCTAssertEqual(route("https://chat.example.com/session/transfers"), .instance)
  }

  func testBrowserFlowsEndAtEmberPages() throws {
    let hosts: Set<String> = ["chat.example.com", "chat.example.org"]
    func end(_ address: String) -> BrowserFlowEnd? { BrowserFlow.end(of: URL(string: address)!, hosts: hosts) }
    XCTAssertNil(end("https://accounts.google.com/o/oauth2/auth?x=1"))
    XCTAssertNil(end("https://chat.example.com/auth/sso/callback?code=1"))
    XCTAssertEqual(end("https://chat.example.com/"), .signedIn)
    XCTAssertEqual(end("https://chat.example.org/rooms/r1"), .signedIn)
    XCTAssertEqual(end("https://chat.example.com/welcome?return_to=%2F"), .welcome)
    XCTAssertEqual(end("https://chat.example.com/session/new?memberful=taken"), .problem(Memberful.signInProblems["taken"]!, passwordForm: true))
    XCTAssertEqual(end("https://chat.example.com/session/new"), .problem(BrowserFlow.failed, passwordForm: false))
    XCTAssertEqual(end("https://chat.example.com/users/me/profile?sso=connected"), .connected(SSO.connectedNotice))
    XCTAssertEqual(end("https://chat.example.com/users/me/profile?memberful=another"), .problem(Memberful.signInProblems["another"]!, passwordForm: false))
    XCTAssertEqual(
      end("https://chat.example.com/account/apps/signed-in?state=s&code=c&iss=https%3A%2F%2Fauth"),
      .appSignIn(state: "s", code: "c", iss: "https://auth", error: nil))
    XCTAssertEqual(end("https://chat.example.com/account/apps/signed-in?error=access_denied"), .appSignIn(state: nil, code: nil, iss: nil, error: "access_denied"))
  }

  func testStateCookiesSurviveFoundationsJoinedHeader() {
    let header =
      "__Host-sso_state=abc.def; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=600, other=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/x"
    let cookies = StateCookie.parse(header)
    XCTAssertEqual(cookies.count, 2)
    XCTAssertEqual(cookies[0], StateCookie(name: "__Host-sso_state", value: "abc.def", path: "/", secure: true, httpOnly: true, maxAge: 600))
    XCTAssertEqual(cookies[1].name, "other")
    XCTAssertEqual(cookies[1].path, "/x")
  }

  func testProfileChangesSendOnlyWhatChanged() throws {
    let saved = ProfileFields(name: "Ada", username: "ada", emailAddress: "ada@example.com", bio: "")
    var typed = saved
    typed.bio = "Analyst"
    let changes = typed.changes(from: saved, password: "", currentPassword: "")
    XCTAssertEqual(changes.bio, "Analyst")
    XCTAssertNil(changes.name)
    XCTAssertNil(changes.password)
    XCTAssertTrue(saved.changes(from: saved, password: "", currentPassword: "").isEmpty)
    XCTAssertEqual(saved.changes(from: saved, password: "new secret", currentPassword: "old").password, "new secret")
    // What's typed while a save is under way stays; the rest shows what Ember saved.
    var meanwhile = typed
    meanwhile.name = "Ada L."
    let now = ProfileFields(name: "Ada", username: "ada", emailAddress: "ada@example.com", bio: "Analyst.")
    let settled = meanwhile.settled(sent: typed, saved: now)
    XCTAssertEqual(settled.name, "Ada L.")
    XCTAssertEqual(settled.bio, "Analyst.")
  }

  func testProfileDecodes() throws {
    let json = """
      {"profile":{"name":"Ada","username":null,"emailAddress":"ada@example.com","bio":null,"avatarUrl":"/users/a/avatar?v=3","avatar":true,
      "password":true,"membershipNeeded":false,"memberful":{"membersOnly":true,"connected":{"name":"Ada","emailAddress":null}},
      "sso":null,"assistant":null,"apps":[{"id":"gh","name":"GitHub","signedInAt":null,"ended":false,"wantsMore":false}],
      "outsideAi":[{"id":"o1","name":"Claude","comesBackTo":"claude.ai","scopes":["read","write"],"connectedAt":"2026-11-19T14:00:00.000Z","usedAt":null}]},
      "transferId":"t1"}
      """
    let answer = try JSONDecoder().decode(ProfileAnswer.self, from: Data(json.utf8))
    let fields = ProfileFields(answer.profile)
    XCTAssertEqual(fields.username, "")
    XCTAssertEqual(answer.profile.memberful?.connected?.described, "Ada")
    XCTAssertEqual(PeopleText.connectedAs(ElsewhereAccount(name: "Grace", emailAddress: "g@example.com"), name: "Memberful"), "Connected as Grace (g@example.com).")
    let connection = try XCTUnwrap(answer.profile.outsideAi?.first)
    XCTAssertEqual(
      PeopleText.status(of: connection, at: { _ in "today" }),
      "From claude.ai, connected today. It can send messages as you. It hasn't asked Ember anything yet.")
    XCTAssertEqual(PeopleText.status(of: answer.profile.apps[0], at: { $0 }), PeopleText.notSignedIn)
  }

  func testAdministratorsAreNamedInASentence() {
    XCTAssertNil(PeopleText.administratorsNamed([]))
    XCTAssertEqual(PeopleText.administratorsNamed(["Ada"]), "Ada is this community's administrator.")
    XCTAssertEqual(PeopleText.administratorsNamed(["Ada", "Grace", "Alan"]), "Ada, Grace and Alan are this community's administrators.")
  }

  func testConversationNotificationsOrder() {
    let ada = User(id: "a", name: "Ada")
    let bob = User(id: "b", name: "Bob")
    let rooms = [
      SidebarRoom(room: Room(id: "r2", kind: .open, name: "zeta"), unread: false, involvement: .mentions),
      SidebarRoom(room: Room(id: "r1", kind: .open, name: "Alpha"), unread: false, involvement: .invisible),
      SidebarRoom(room: Room(id: "d1", kind: .direct, members: [ada, bob], activeAt: "2026-11-19T15:00:00.000Z"), unread: false, involvement: .everything),
    ]
    let order = RoomList.profileOrder(rooms, me: "a")
    XCTAssertEqual(order.shared.map(\.id), ["r1", "r2"])
    XCTAssertEqual(order.directs.map(\.id), ["d1"])
  }

  func testAvatarVariantFitsTheBox() throws {
    // A 1200 by 600 opaque picture, as JPEG, comes out within 512 by 512 as JPEG.
    let width = 1200, height = 600
    let context = try XCTUnwrap(CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try XCTUnwrap(context.makeImage())
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let photo = Avatars.chosenPhoto(data as Data, fileName: "photo.png", contentType: "image/png")
    let variant = try XCTUnwrap(photo.variant)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(variant as CFData, nil))
    let made = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(made.width, 512)
    XCTAssertEqual(made.height, 256)
    XCTAssertEqual(photo.variantContentType, "image/jpeg")
    XCTAssertNil(Avatars.chosenPhoto(Data("not a photo".utf8), fileName: "x.svg", contentType: "image/svg+xml").variant)
  }

  func testPasswordCapCountsUTF16() {
    XCTAssertEqual(EmberRules.capped(password: String(repeating: "a", count: 80)).utf16.count, EmberLimits.maxPasswordLength)
    let emoji = String(repeating: "a", count: 71) + "🔥"
    XCTAssertEqual(EmberRules.capped(password: emoji), String(repeating: "a", count: 71))
    XCTAssertEqual(EmberRules.capped(password: "short"), "short")
  }

  func testPeopleCommandsParse() {
    XCTAssertEqual(InputCommand.parse("/ignore"), .ignored)
    XCTAssertEqual(InputCommand.parse("/nick Ada L."), .setProfile(.name, "Ada L."))
    XCTAssertEqual(InputCommand.parse("/username"), .setProfile(.username, ""))
    XCTAssertEqual(InputCommand.parse("/profile link"), .profile(link: true))
    XCTAssertEqual(InputCommand.parse("/profile connect sso"), .profileElsewhere(connect: true, memberful: false))
    XCTAssertEqual(InputCommand.parse("/profile disconnect Memberful"), .profileElsewhere(connect: false, memberful: true))
    XCTAssertEqual(InputCommand.parse("/profile connect okta"), .unknown("/profile connect takes sso or memberful"))
    XCTAssertEqual(InputCommand.parse("/avatar remove"), .avatar(remove: true))
    XCTAssertEqual(InputCommand.parse("/apps signin GitHub"), .apps(.signIn("GitHub")))
    XCTAssertEqual(InputCommand.parse("/apps"), .apps(.list))
    XCTAssertEqual(InputCommand.parse("/ai disconnect Claude"), .ai(disconnect: "Claude"))
    XCTAssertEqual(InputCommand.parse("/sounds ring off"), .sounds(.ring, false))
    XCTAssertEqual(InputCommand.parse("/notify #design all"), .notify(.everything, room: "design"))
    XCTAssertEqual(InputCommand.parse("/notify #design"), .notify(nil, room: "design"))
    XCTAssertEqual(InputCommand.parse("/quit"), .quit)
    XCTAssertEqual(InputCommand.parse("/delete-account"), .deleteAccount)
    XCTAssertEqual(InputCommand.parse("/appearance dark"), .appearance("dark"))
  }
}
