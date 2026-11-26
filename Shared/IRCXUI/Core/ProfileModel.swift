import EmberKit
import Foundation
import Observation

/**
 * Your profile (web `ProfilePage`), for both themes and the input line's commands: the form, your photo,
 * accounts elsewhere, Ember AI, your apps and AI apps, huddle sounds, your sign-in link, and deleting your
 * account. Each answer shows as the web shows it: a photo's answer that arrives late keeps the newer photo.
 */
@MainActor
@Observable
final class ProfileModel {
  @ObservationIgnored unowned let session: InstanceSession
  var loaded = false
  var failure: String?
  /** The profile as the page last loaded or saved it. */
  private(set) var saved: ProfileFields?
  /** The form as typed. */
  var fields = ProfileFields(name: "", username: "", emailAddress: "", bio: "")
  var password = ""
  var currentPassword = ""
  private(set) var avatarUrl: String?
  private(set) var hasAvatar = false
  private(set) var hasPassword = false
  private(set) var hasEmailAddress = false
  private(set) var memberful: MemberfulStatus?
  private(set) var sso: SsoStatus?
  private(set) var membershipNeeded = true
  private(set) var assistant: YourAssistant?
  private(set) var apps: [YourApp] = []
  private(set) var outsideAi: [OutsideConnection]?
  private(set) var transferId: String?
  /** Your name as the profile last had it, which deleting an account without a password asks for. */
  private(set) var savedName = ""
  var saving = false
  var savingPicture = false
  /** Which connection or app is being worked on, whose buttons wait meanwhile. */
  var busy: String?
  /** The page's result or failure, one line at its foot. */
  var message: String?
  var messageIsError = false
  /** A flow elsewhere under way: connecting Memberful or SSO, or signing in to an app. */
  var browser: BrowserFlowRequest?
  @ObservationIgnored private var disconnectedMemberful = false
  @ObservationIgnored private var disconnectedSso = false

  init(session: InstanceSession) {
    self.session = session
    if let me = session.me { savedName = me.name }
  }

  /** Whether Memberful or single sign-on alone signs you in, with no password (`signsInElsewhereAlone`). */
  var signsInElsewhereAlone: Bool { !hasPassword && (memberful?.connected != nil || sso?.connected != nil) }
  var changed: Bool { saved.map { fields != $0 } == true || !password.isEmpty }
  var ssoName: String { sso?.name ?? "single sign-on" }
  var memberfulClosed: String? {
    guard let account = session.account, account.ssoSignIn, !account.memberfulSignIn else { return nil }
    return PeopleText.memberfulClosed(ssoName)
  }
  var ssoClosed: String? {
    guard let account = session.account, account.memberfulSignIn, !account.ssoSignIn else { return nil }
    return PeopleText.ssoClosed(ssoName)
  }
  var signInLink: String? { transferId.map { session.instance.origin + Pages.transferLink($0) } }
  var mcpAddress: String { session.instance.origin + Outside.mcpPath }

  func say(_ text: String, error: Bool = false) {
    message = text
    messageIsError = error
  }

  private func failed(_ doing: String, _ error: Error) {
    logger.error("\(doing, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    say(error.localizedDescription, error: true)
  }

  // MARK: - Loading and saving

  func load() async {
    guard !loaded else { return }
    do {
      adopt(try await session.api.profile())
    } catch {
      logger.error("Loading the profile failed: \(error.localizedDescription, privacy: .public)")
      failure = error.localizedDescription
    }
  }

  /** Takes a loaded profile, as loading does, and as render tests give one. */
  func adopt(_ answer: ProfileAnswer) {
    saved = ProfileFields(answer.profile)
    fields = ProfileFields(answer.profile)
    savedName = answer.profile.name
    hasEmailAddress = answer.profile.emailAddress != nil
    show(answer)
    assistant = answer.profile.assistant
    apps = answer.profile.apps
    outsideAi = answer.profile.outsideAi
    loaded = true
    failure = nil
  }

  /** Loads the profile again, after an account elsewhere or an app came back. */
  func reload() async {
    do {
      adopt(try await session.api.profile())
    } catch {
      failed("Loading the profile", error)
    }
  }

  /** Shows what an answer says of your photo, password, accounts elsewhere and sign-in link (`showAnswer`). */
  private func show(_ answer: ProfileAnswer) {
    let profile = answer.profile
    // A later answer's photo stays.
    if avatarUrl.map({ Self.version($0) > Self.version(profile.avatarUrl) }) != true {
      avatarUrl = profile.avatarUrl
      hasAvatar = profile.avatar
    }
    hasPassword = hasPassword || profile.password
    if disconnectedMemberful, var status = profile.memberful, status.connected != nil {
      status.connected = nil
      memberful = status.membersOnly ? status : nil
    } else {
      memberful = profile.memberful
    }
    if disconnectedSso, var status = profile.sso, status.connected != nil {
      status.connected = nil
      sso = status.ssoOnly ? status : nil
    } else {
      sso = profile.sso
    }
    membershipNeeded = profile.membershipNeeded
    transferId = answer.transferId
  }

  /** An avatar address's `v`, which rises with each change (`avatarVersionOf`). */
  static func version(_ address: String) -> Int {
    guard let query = URLComponents(string: address)?.queryItems, let v = query.first(where: { $0.name == "v" })?.value, let version = Int(v) else {
      return -1
    }
    return version
  }

  /** Save changes: only the fields that changed, and the passwords if typed, with the web's tick. */
  func save() {
    guard let saved, !saving else { return }
    let sent = fields
    let password = password
    let currentPassword = currentPassword
    let changes = sent.changes(from: saved, password: password, currentPassword: currentPassword)
    guard !changes.isEmpty else { return }
    if let username = changes.username, !username.isEmpty, !EmberRules.isUsername(EmberRules.username(of: username)) {
      return say(EmberText.usernameRefused, error: true)
    }
    if !password.isEmpty, EmberRules.isPasswordTooShort(password) { return say(EmberText.passwordTooShort, error: true) }
    if EmberRules.isPasswordTooLong(password) { return say(EmberText.passwordTooLong, error: true) }
    var sending = changes
    if let username = changes.username { sending.username = EmberRules.username(of: username) }
    saving = true
    Task {
      defer { saving = false }
      do {
        let answer = try await session.api.changeProfile(sending)
        let now = ProfileFields(answer.profile)
        self.saved = now
        savedName = answer.profile.name
        fields = fields.settled(sent: sent, saved: now)
        hasEmailAddress = answer.profile.emailAddress != nil
        if self.password == password { self.password = "" }
        if self.currentPassword == currentPassword { self.currentPassword = "" }
        if !password.isEmpty {
          if answer.profile.memberful?.connected == nil { disconnectedMemberful = true }
          if answer.profile.sso?.connected == nil { disconnectedSso = true }
        }
        show(answer)
        session.adoptName(answer.profile.name)
        say(PeopleText.saved)
      } catch {
        failed("Saving the profile", error)
      }
    }
  }

  /** Saves a photo as your avatar at once, with the notice that it takes a while everywhere. */
  func changeAvatar(_ photo: ChosenPhoto) {
    savingPicture = true
    Task {
      defer { savingPicture = false }
      do {
        show(try await session.api.changeAvatar(photo))
        say(PeopleText.avatarChanged)
      } catch {
        failed("Saving a photo", error)
      }
    }
  }

  func removeAvatar() {
    savingPicture = true
    Task {
      defer { savingPicture = false }
      do {
        let answer = try await session.api.removeAvatar()
        avatarUrl = answer.profile.avatarUrl
        hasAvatar = answer.profile.avatar
        show(answer)
      } catch {
        failed("Removing the photo", error)
      }
    }
  }

  // MARK: - Accounts elsewhere

  /** Connect Memberful or single sign-on: the provider's sign-in in a web view, with your session and its state cookie. */
  func connect(memberful: Bool, currentPassword: String) {
    busy = memberful ? "memberful" : "sso"
    let typed = hasPassword ? currentPassword : nil
    Task {
      defer { busy = nil }
      do {
        let start = memberful ? try await session.api.connectMemberful(currentPassword: typed) : try await session.api.connectSso(currentPassword: typed)
        guard let address = memberful ? start.connection.memberfulConnection : start.connection.ssoConnection, let url = URL(string: address) else {
          throw EmberError.notEmber
        }
        browser = BrowserFlowRequest(title: memberful ? "Memberful" : ssoName, start: url, cookies: start.cookies, sessionToken: session.api.token)
      } catch {
        failed("Connecting an account elsewhere", error)
      }
    }
  }

  func disconnect(memberful: Bool, currentPassword: String) {
    busy = memberful ? "memberful" : "sso"
    Task {
      defer { busy = nil }
      do {
        let disconnection = Disconnection(currentPassword: currentPassword)
        let answer = memberful ? try await session.api.disconnectMemberful(disconnection) : try await session.api.disconnectSso(disconnection)
        if memberful { disconnectedMemberful = true } else { disconnectedSso = true }
        show(answer)
        say(memberful ? Memberful.disconnectedNotice : SSO.disconnectedNotice)
      } catch {
        failed("Disconnecting an account elsewhere", error)
      }
    }
  }

  // MARK: - Apps

  /** Sign in to an app yourself: its authorization server in a web view, finished here when it comes back. */
  func signIn(to app: YourApp) {
    busy = app.id
    Task {
      defer { busy = nil }
      do {
        let address = try await session.api.beginOwnAppSignIn(app.id)
        guard let url = URL(string: address) else { throw EmberError.notEmber }
        browser = BrowserFlowRequest(title: app.name, start: url)
      } catch {
        failed("Signing in to an app", error)
      }
    }
  }

  func signOut(of app: YourApp) {
    busy = app.id
    Task {
      defer { busy = nil }
      do {
        let answer = try await session.api.signOutOfApp(app.id)
        apps = answer.apps
        say(PeopleText.signedOut(app.name, revoked: answer.revoked), error: !answer.revoked)
      } catch {
        failed("Signing out of an app", error)
      }
    }
  }

  /** Finishes a web view's flow: an account connected, an app signed in to, or why not. */
  func finish(_ outcome: BrowserFlowOutcome) {
    guard case let .ended(end, _) = outcome else { return }
    switch end {
    case let .connected(notice):
      say(notice)
      Task { await reload() }
    case let .problem(text, _):
      say(text, error: true)
    case let .appSignIn(state, code, iss, error):
      if error == "access_denied" { return say(PeopleText.signInTurnedDown, error: true) }
      guard error == nil, let state, let code else { return say(PeopleText.signInNotFinished, error: true) }
      say(PeopleText.finishingOwnSignIn)
      Task {
        do {
          switch try await session.api.finishAppSignIn(AppSignInReturn(state: state, code: code, iss: iss)) {
          case let .yours(app):
            if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index] = app } else { apps.append(app) }
            say(PeopleText.signedInYourself(app.name))
          case .app:
            await reload()
          }
        } catch {
          failed("Finishing an app's sign-in", error)
        }
      }
    case .signedIn, .welcome:
      Task { await reload() }
    }
  }

  // MARK: - AI

  func disconnect(_ connection: OutsideConnection) {
    busy = connection.id
    Task {
      defer { busy = nil }
      do {
        outsideAi = try await session.api.disconnectOutside(connection.id).connections
        say(PeopleText.disconnected(connection.name))
      } catch {
        failed("Disconnecting an AI app", error)
      }
    }
  }

  /** Changes how @ember answers you, shown at once and put back if it doesn't save (web `AnswerLevels`). */
  func changeAssistant(_ changes: YourAssistantChanges) {
    guard let before = assistant else { return }
    var shown = before
    if let thinking = changes.thinking { shown.levels.thinking = thinking }
    if let length = changes.length { shown.levels.length = length }
    if let model = changes.model { shown.model = model }
    assistant = shown
    Task {
      do {
        assistant = try await session.api.changeYourAssistant(changes)
      } catch {
        assistant = before
        failed("Saving Ember AI's levels", error)
      }
    }
  }

  // MARK: - Deleting

  func deleteAccount(currentPassword: String, name: String) async -> Bool {
    let deletion = hasPassword ? AccountDeletion(currentPassword: currentPassword) : AccountDeletion(name: name)
    do {
      try await session.deleteAccount(deletion)
      return true
    } catch {
      failed("Deleting the account", error)
      return false
    }
  }
}

extension ThinkingLevel {
  /** The levels up to `most`, as the dials offer them (`withinMost`). */
  static func upTo(_ most: ThinkingLevel) -> [ThinkingLevel] {
    guard let end = allCases.firstIndex(of: most) else { return [] }
    return Array(allCases[...end])
  }
}

extension AnswerLength {
  static func upTo(_ most: AnswerLength) -> [AnswerLength] {
    guard let end = allCases.firstIndex(of: most) else { return [] }
    return Array(allCases[...end])
  }
}
