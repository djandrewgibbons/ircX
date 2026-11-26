import EmberKit
import Foundation
import Observation

/**
 * Signing in to an instance, as the web's sign-in page does it, for both themes: a password, a sign-in
 * link, just a name where guests may, Memberful and single sign-on in a web view, and the ways to join,
 * reset a password or connect an account elsewhere that it links to.
 */
@MainActor
@Observable
public final class SignInModel {
  public enum Method: String, CaseIterable, Identifiable {
    case password, link, guest
    public var id: String { rawValue }

    var title: String {
      switch self {
      case .password: "Password"
      case .link: "Sign-In Link"
      case .guest: "Just a Name"
      }
    }
  }

  /** What opens over the sign-in screen. */
  enum Sheet: Identifiable {
    case join(JoinModel)
    case emailLink(EmailLinkModel)
    case reset(PasswordResetModel)
    case browser(BrowserFlowRequest)

    var id: String {
      switch self {
      case .join: "join"
      case .emailLink: "email-link"
      case .reset: "reset"
      case let .browser(request): request.id.uuidString
      }
    }
  }

  @ObservationIgnored unowned let session: InstanceSession
  var method = Method.password
  var email = ""
  var password = ""
  var name = ""
  var link = ""
  /** Why the last try didn't sign in, in the form's red box. */
  var problem: String?
  /** Ember couldn't be reached, said apart from the form (web's alert above the card). */
  var unreachable: String?
  /** What the screen says on arriving: an account deleted, a password reset. */
  var notice: String?
  var busy = false
  /** Where to connect an account elsewhere, after a right password, while that's the way in now. */
  var elsewhere: ElsewhereStart?
  /** Whether the password form shows while Memberful or SSO is the only way in, for administrators and invited people. */
  var showsPasswordForm = false
  var sheet: Sheet?

  init(session: InstanceSession) {
    self.session = session
  }

  var bootstrap: Bootstrap? { session.bootstrap }
  var account: Account? { session.bootstrap?.account }
  var workspace: String { session.name }
  var ssoName: String { bootstrap?.ssoName ?? SSO.defaultName }

  /** The ways to sign in offered here: a password and a sign-in link always, just a name where guests may. */
  var methods: [Method] { bootstrap?.guestSignIn == true ? Method.allCases : [.password, .link] }

  /** The provider whose button stands in for the password form while it's the only way in, if one is. */
  var onlyElsewhere: (name: String, memberful: Bool)? {
    guard let account, account.signsInElsewhereOnly, !showsPasswordForm else { return nil }
    return account.ssoSignIn ? (ssoName, false) : ("Memberful", true)
  }

  /** Whether both are the only ways in and Memberful can sign people in, so its link sits beside single sign-on's. */
  private var eitherOnly: Bool {
    guard let account, let bootstrap else { return false }
    return account.memberfulSignIn && account.ssoSignIn && bootstrap.signInWithMemberful
  }

  /**
   * The smaller links to sign in elsewhere, under the form or the only-way button (`sign-in-page.tsx`).
   * Once the password form shows while Memberful or SSO is the only way in, `backToElsewhere` stands in for them.
   */
  var otherElsewhere: [(title: String, memberful: Bool)] {
    guard let bootstrap, let account else { return [] }
    if account.signsInElsewhereOnly {
      return onlyElsewhere != nil && eitherOnly ? [("Member? Sign in with Memberful", true)] : []
    }
    var links: [(String, Bool)] = []
    if bootstrap.signInWithMemberful { links.append(("Member? Sign in with Memberful", true)) }
    if bootstrap.signInWithSso != nil { links.append(("Use single sign-on? Sign in with \(ssoName)", false)) }
    return links
  }

  /** The link back from the password form to the only-way button, while Memberful or SSO is the only way in. */
  var backToElsewhere: String? {
    guard let account, account.signsInElsewhereOnly, showsPasswordForm else { return nil }
    if eitherOnly { return "No password? Sign in with \(ssoName) or Memberful" }
    return account.ssoSignIn ? "Use single sign-on? Sign in with \(ssoName)" : "Member? Sign in with Memberful"
  }

  /** The "Have a password?" link, which swaps the only-way button for the password form. */
  var offersPasswordForm: Bool { onlyElsewhere != nil }

  var offersReset: Bool { bootstrap?.passwordResetCodes == true && onlyElsewhere == nil && method == .password }
  var offersSignUp: Bool { account?.signsUpOpenly == true }
  var offersEmailSignUp: Bool { account?.signsUpOpenly == false && account?.signsUpWithEmailDomain == true }
  var emailDomains: [String] { account?.emailDomains ?? [] }

  // MARK: - Signing in

  func signIn() {
    guard !busy else { return }
    busy = true
    problem = nil
    unreachable = nil
    notice = nil
    elsewhere = nil
    let method = method
    let email = email.trimmingCharacters(in: .whitespaces)
    let password = password
    let name = name.trimmingCharacters(in: .whitespaces)
    let link = link
    Task {
      defer { busy = false }
      do {
        switch method {
        case .password:
          if let start = try await session.signIn(emailAddress: email, password: password) {
            elsewhere = start
            problem = EmberText.nowUses(start.connection.connections(ssoName: ssoName).map(\.name))
          }
        case .link:
          try await session.signIn(transferLink: link)
          self.link = ""
        case .guest:
          guard name.count <= EmberLimits.maxGuestNameLength else {
            problem = "Name must be 1 to \(EmberLimits.maxGuestNameLength) characters"
            return
          }
          try await session.signIn(name: name)
        }
      } catch {
        refused(error, method: method)
      }
      self.password = ""
    }
  }

  /** Says why sign-in didn't work, as the web words it. */
  private func refused(_ error: Error, method: Method) {
    logger.error("Signing in failed: \(error.localizedDescription, privacy: .public)")
    switch error {
    case let EmberError.problem(problem) where method == .password:
      switch problem.status {
      case 401: self.problem = EmberText.signInRejected
      case 429: self.problem = EmberText.signInLimited
      default: self.problem = problem.message
      }
    case EmberError.transport:
      unreachable = PeopleText.couldNotReach
    default:
      problem = error.localizedDescription
    }
  }

  /** Signs in with Memberful or single sign-on in a web view (`/auth/memberful`, `/auth/sso`). */
  func signInElsewhere(memberful: Bool) {
    let path = memberful ? Memberful.signInPath : SSO.signInPath
    sheet = .browser(BrowserFlowRequest(title: memberful ? "Memberful" : ssoName, start: session.api.url(path)))
  }

  /** Connects the account elsewhere a right password was told to, with the state cookie Ember set. */
  func connect(_ address: String, name: String) {
    guard let elsewhere, let url = URL(string: address) else { return }
    sheet = .browser(BrowserFlowRequest(title: name, start: url, cookies: elsewhere.cookies))
  }

  /** Finishes a web view's flow: signed in, signed in as someone new, or back at sign-in saying why. */
  func finish(_ outcome: BrowserFlowOutcome) {
    switch outcome {
    case .canceled:
      return
    case let .ended(end, token):
      switch end {
      case .signedIn, .welcome, .connected:
        guard let token else {
          logger.error("A sign-in elsewhere ended without a session")
          problem = BrowserFlow.failed
          return
        }
        elsewhere = nil
        session.adoptSession(token, welcome: end == .welcome)
      case let .problem(text, passwordForm):
        problem = text
        if passwordForm { showsPasswordForm = true }
      case .appSignIn:
        problem = BrowserFlow.failed
      }
    }
  }

  // MARK: - Joining and resetting

  func openSignUp() { sheet = .join(JoinModel(session: session, kind: .open)) }
  func openEmailSignUp() { sheet = .emailLink(EmailLinkModel(session: session)) }
  func openReset() { openReset(emailAddress: email.trimmingCharacters(in: .whitespaces)) }

  /** The password reset under way, kept so that closing and opening it again stays on its code step. */
  @ObservationIgnored private var reset: PasswordResetModel?

  /**
   * Opens password reset (web `PasswordResetPage`, signed in or not): the one under way for the same address,
   * or else a new one for `emailAddress`.
   */
  func openReset(emailAddress: String) {
    if let reset, emailAddress.isEmpty || emailAddress == (reset.asked ?? reset.emailAddress) {
      sheet = .reset(reset)
      return
    }
    let started = PasswordResetModel(session: session, emailAddress: emailAddress)
    reset = started
    sheet = .reset(started)
  }

  /** The reset is done: the next one starts afresh. */
  func resetDone() { reset = nil }

  /** Follows a pasted link's route while signed out. */
  func follow(_ route: EmberRoute) {
    switch route {
    case let .join(code):
      sheet = .join(JoinModel(session: session, kind: .code(code)))
    case .signUp:
      guard account?.signsUpOpenly == true else {
        problem = EmberText.joiningProblems["closed"]
        return
      }
      sheet = .join(JoinModel(session: session, kind: .open))
    case let .invitation(token):
      sheet = .join(JoinModel(session: session, kind: .emailLink(token, .invitation)))
    case let .emailSignUp(token):
      if let token {
        sheet = .join(JoinModel(session: session, kind: .emailLink(token, .emailDomain)))
      } else if account?.signsUpWithEmailDomain == true {
        sheet = .emailLink(EmailLinkModel(session: session))
      } else {
        problem = EmberText.joiningProblems["email_off"]
      }
    case let .transfer(id):
      method = .link
      link = id
      signIn()
    case let .passwordReset(emailAddress):
      openReset(emailAddress: emailAddress ?? email.trimmingCharacters(in: .whitespaces))
    case let .signIn(emailAddress, problem):
      if let emailAddress { email = emailAddress }
      method = .password
      self.problem = problem
    case .instance, .page, .firstRun, .outsideConnect:
      return
    }
  }

  /** Where a form's `redirect` sends someone: sign-in, with an address and why, or home. */
  func redirected(to path: String, saying message: String) {
    sheet = nil
    if let link = EmberLink.parse(session.instance.origin + path), case let .signIn(emailAddress, problem) = link.route {
      follow(.signIn(emailAddress: emailAddress, problem: problem ?? message))
    } else {
      Task { await session.start() }
    }
  }
}

/** Joining a workspace (web `JoinPage`, `InvitationPage`, the email link's form) or setting a new one up (`SetupPage`'s form). */
@MainActor
@Observable
final class JoinModel {
  enum Kind: Equatable {
    /** The join link's code. */
    case code(String)
    /** Open sign-up. */
    case open
    /** An emailed link's token and the kind of link the page it opened is for: an invitation, or an email domain's link. */
    case emailLink(String, EmailLinkKind)
    /** First run, with the setup password or link token where it needs one. */
    case setup(String?)

    var isSetup: Bool {
      if case .setup = self { return true }
      return false
    }
  }

  @ObservationIgnored unowned let session: InstanceSession
  let kind: Kind
  var name = ""
  var emailAddress = ""
  var password = ""
  var photo: ChosenPhoto?
  var photoRefusal: String?
  var turnstileToken: String?
  var turnstileTries = 0
  var busy = false
  /** Why the form wasn't taken, by the field it's about (`name`, `emailAddress`, `password`). */
  var problems: [String: String] = [:]
  /** Why the form wasn't taken, about none of its fields. */
  var problem: String?
  /** An emailed link, once looked up: whom it's for and what kind it is. */
  var linkFor: EmailLinkFor?
  /** Why an emailed link no longer works. */
  var linkGone: String?
  /** First run's answer: the first room, which opens once the huddles question is answered. */
  var newWorkspace: NewWorkspace?

  init(session: InstanceSession, kind: Kind) {
    self.session = session
    self.kind = kind
  }

  var workspace: String { session.name }

  /** Turnstile's site key, where the form takes its check: open sign-up only (web `JoinPage`). */
  var turnstileSiteKey: String? {
    guard kind == .open else { return nil }
    return session.bootstrap?.turnstileSiteKey
  }

  var title: String { kind.isSetup ? "Set up Ember" : PeopleText.joinTitle(workspace) }

  /** First run's examples for the name and email address (`Bootstrap.setupPlaceholders`). */
  var placeholders: SetupPlaceholders? { kind.isSetup ? session.bootstrap?.setupPlaceholders : nil }

  var explained: String {
    switch kind {
    case .setup: PeopleText.setupExplained
    case .emailLink: linkFor?.kind == .invitation ? PeopleText.invitationForAddress : PeopleText.linkForAddress
    default: PeopleText.joinExplained
    }
  }

  var asksEmailAddress: Bool {
    if case .emailLink = kind { return false }
    return true
  }

  var canSend: Bool {
    !busy && !name.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
      && (!asksEmailAddress || !emailAddress.trimmingCharacters(in: .whitespaces).isEmpty)
      && (turnstileSiteKey == nil || turnstileToken != nil) && linkGone == nil
  }

  /** Looks an emailed link up first, which spends nothing (`useEmailLink`). */
  func lookUp() async {
    guard case let .emailLink(token, expected) = kind, linkFor == nil, linkGone == nil else { return }
    do {
      let found = try await session.api.lookUpEmailLink(token: token)
      // A link of the other kind doesn't work on this page (`useEmailLink`).
      guard found.kind == expected else {
        gone(EmberText.invitationGone)
        return
      }
      linkFor = found
      emailAddress = found.emailAddress
    } catch let EmberError.problem(answer) where (400..<500).contains(answer.status) {
      gone(EmberText.invitationGone)
    } catch {
      logger.error("Looking up an emailed link failed: \(error.localizedDescription, privacy: .public)")
      problem = error.localizedDescription
    }
  }

  /** What the client checks before sending, as the server would refuse it. */
  private func checked() -> Bool {
    problems = [:]
    let name = name.trimmingCharacters(in: .whitespaces)
    if name.utf16.count > EmberLimits.maxUserNameLength { problems["name"] = EmberText.nameTooLong }
    if EmberRules.isReservedName(name) { problems["name"] = EmberText.nameReserved }
    if asksEmailAddress, emailAddress.utf16.count > EmberLimits.maxEmailAddressLength { problems["emailAddress"] = EmberText.emailAddressTooLong }
    if EmberRules.isPasswordTooShort(password) { problems["password"] = EmberText.passwordTooShort }
    if EmberRules.isPasswordTooLong(password) { problems["password"] = EmberText.passwordTooLong }
    return problems.isEmpty
  }

  func send() {
    guard canSend, checked() else { return }
    busy = true
    problem = nil
    let person = SignUp(
      name: name.trimmingCharacters(in: .whitespaces), emailAddress: emailAddress.trimmingCharacters(in: .whitespaces), password: password,
      turnstileToken: turnstileToken)
    let photo = photo
    let session = session
    Task {
      defer {
        busy = false
        // A Turnstile token is good once: draw a new check.
        turnstileToken = nil
        turnstileTries += 1
      }
      do {
        switch kind {
        case let .code(code): _ = try await session.api.join(code: code, person, photo: photo)
        case .open: _ = try await session.api.signUp(person, photo: photo)
        case let .emailLink(token, _):
          guard let linkFor else { return }
          _ = try await session.api.join(with: linkFor.kind, EmailLinkSignUp(token: token, name: person.name, password: person.password), photo: photo)
        case let .setup(secret):
          newWorkspace = try await session.api.setUpWorkspace(person, photo: photo, setupSecret: secret)
          password = ""
          return
        }
        password = ""
        session.signInForm.sheet = nil
        await session.start()
      } catch {
        refused(error)
      }
    }
  }

  private func refused(_ error: Error) {
    logger.error("Joining failed: \(error.localizedDescription, privacy: .public)")
    guard case let EmberError.problem(answer) = error else {
      problem = error.localizedDescription
      return
    }
    if let redirect = answer.redirect {
      if kind.isSetup {
        Task { await session.start() }
      } else {
        session.signInForm.redirected(to: redirect, saying: answer.message)
      }
      return
    }
    switch answer.field {
    case "avatar":
      photo = nil
      photoRefusal = answer.message
    case "turnstile":
      problem = answer.message
    case let field?:
      problems[field] = answer.message
    case nil:
      if case .emailLink = kind, answer.status == 404 {
        gone(answer.message)
      } else {
        problem = answer.message
      }
    }
  }

  /**
   * An emailed link that doesn't work: an invitation says so with `text`; an email domain's link opens the
   * form asking for another, saying the link is gone (web `EmailSignUpPage`'s `LinkRequest`).
   */
  private func gone(_ text: String) {
    guard case .emailLink(_, .emailDomain) = kind else {
      linkGone = text
      return
    }
    session.signInForm.sheet = .emailLink(EmailLinkModel(session: session, gone: true))
  }

  /** First run's huddles question, answered: Not now opens the new room, Set up huddles opens Admin too. */
  func openWorkspace(settingUpHuddles: Bool) {
    guard let room = newWorkspace?.room.id else { return }
    let session = session
    Task {
      await session.start()
      session.open(room: room)
      if settingUpHuddles { session.openWorkspaceSettings() }
    }
  }
}

/** Asking for a link to join with an email domain's address (web `EmailSignUpPage` without a token). */
@MainActor
@Observable
final class EmailLinkModel {
  @ObservationIgnored unowned let session: InstanceSession
  var emailAddress = ""
  var turnstileToken: String?
  var turnstileTries = 0
  var busy = false
  var problem: String?
  /** The address a link was emailed to. */
  var sent: String?
  /** The emailed link, pasted. */
  var link = ""
  /** Whether a link that no longer works opened this form, which then says so in its heading line. */
  let gone: Bool

  init(session: InstanceSession, gone: Bool = false) {
    self.session = session
    self.gone = gone
  }

  /** Whether the form asks for a link: Email domain is on (a gone link shows the form's heading even while off). */
  var on: Bool { session.bootstrap?.account.signsUpWithEmailDomain == true }

  var workspace: String { session.name }
  var domains: [String] { session.bootstrap?.account.emailDomains ?? [] }
  var turnstileSiteKey: String? { session.bootstrap?.turnstileSiteKey }
  var canSend: Bool { on && !busy && !emailAddress.trimmingCharacters(in: .whitespaces).isEmpty && (turnstileSiteKey == nil || turnstileToken != nil) }

  func send() {
    guard canSend else { return }
    busy = true
    problem = nil
    let address = emailAddress.trimmingCharacters(in: .whitespaces)
    let asked = EmailRequest(emailAddress: address, turnstileToken: turnstileToken)
    let session = session
    Task {
      defer {
        busy = false
        turnstileToken = nil
        turnstileTries += 1
      }
      do {
        try await session.api.askForEmailLink(asked)
        sent = address
      } catch let EmberError.problem(answer) {
        logger.error("Asking for an email link failed: \(answer.message, privacy: .public)")
        if let redirect = answer.redirect {
          session.signInForm.redirected(to: redirect, saying: answer.message)
        } else {
          problem = answer.message
        }
      } catch {
        logger.error("Asking for an email link failed: \(error.localizedDescription, privacy: .public)")
        problem = PeopleText.couldNotReach
      }
    }
  }

  /** Opens the emailed link, pasted here: its join form. */
  func openLink() {
    guard let parsed = EmberLink.parse(link), case let .emailSignUp(token?) = parsed.route else {
      problem = EmberText.emailLinkGone
      return
    }
    session.signInForm.sheet = .join(JoinModel(session: session, kind: .emailLink(token, .emailDomain)))
  }
}

/** Resetting a password with an emailed code (web `PasswordResetPage`): the address, then the code and a new password. */
@MainActor
@Observable
final class PasswordResetModel {
  @ObservationIgnored unowned let session: InstanceSession
  var emailAddress: String
  /** The address a code was asked for, which step 2 is about. */
  var asked: String?
  var code = ""
  var password = ""
  var turnstileToken: String?
  var turnstileTries = 0
  var busy = false
  var problem: String?
  /** Which field the problem is about: `code` or `password`. */
  var problemField: String?

  init(session: InstanceSession, emailAddress: String) {
    self.session = session
    self.emailAddress = emailAddress
  }

  var available: Bool { session.bootstrap?.passwordResetCodes == true }
  var turnstileSiteKey: String? { asked == nil ? session.bootstrap?.turnstileSiteKey : nil }
  var canAsk: Bool { !busy && !emailAddress.trimmingCharacters(in: .whitespaces).isEmpty && (turnstileSiteKey == nil || turnstileToken != nil) }
  var canReset: Bool { !busy && !code.isEmpty && !password.isEmpty }

  func ask() {
    guard canAsk else { return }
    busy = true
    problem = nil
    let address = emailAddress.trimmingCharacters(in: .whitespaces)
    let request = EmailRequest(emailAddress: address, turnstileToken: turnstileToken)
    let session = session
    Task {
      defer {
        busy = false
        turnstileToken = nil
        turnstileTries += 1
      }
      do {
        try await session.api.askForPasswordResetCode(request)
        asked = address
      } catch {
        refused(error)
      }
    }
  }

  func reset() {
    guard let asked, canReset else { return }
    guard let digits = EmberRules.passwordResetCode(of: code) else {
      problem = EmberText.passwordResetCodeNeeded
      problemField = "code"
      return
    }
    if EmberRules.isPasswordTooShort(password) || EmberRules.isPasswordTooLong(password) {
      problem = EmberRules.isPasswordTooShort(password) ? EmberText.passwordTooShort : EmberText.passwordTooLong
      problemField = "password"
      return
    }
    busy = true
    problem = nil
    let reset = PasswordResetWithCode(emailAddress: asked, code: digits, password: password)
    let session = session
    Task {
      defer { busy = false }
      do {
        let user = try await session.api.resetPassword(reset)
        password = ""
        let form = session.signInForm
        form.sheet = nil
        form.resetDone()
        if let user {
          await session.signedIn(afterReset: user)
          session.notice = EmberText.passwordResetDone
        } else {
          // Someone who signs in elsewhere signs in themselves; a session here may have ended with the reset.
          if session.phase == .ready { await session.checkSession() }
          form.email = asked
          form.method = .password
          form.notice = EmberText.passwordResetSignIn
          if session.phase == .ready { session.notice = EmberText.passwordResetSignIn }
        }
      } catch {
        refused(error)
      }
    }
  }

  private func refused(_ error: Error) {
    logger.error("Resetting a password failed: \(error.localizedDescription, privacy: .public)")
    guard case let EmberError.problem(answer) = error else {
      problem = PeopleText.couldNotReach
      return
    }
    problem = answer.message
    problemField = answer.field
  }
}
