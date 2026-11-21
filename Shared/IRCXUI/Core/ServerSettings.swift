import AppCoreUI
import EmberKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/**
 * Server Settings' sections (web community settings' navigation, `settings-navigation.tsx`): General,
 * Rooms and permissions and Membership for everyone; Domain settings, Chat bots, AI assistant, Huddles and
 * Custom styles for administrators.
 */
public enum AdminSection: String, CaseIterable, Identifiable, Hashable, Sendable {
  case general, rooms, membership, domain, bots, assistant = "ai", huddles, styles

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .general: "General"
    case .rooms: "Rooms"
    case .membership: "Membership"
    case .domain: "Domain"
    case .bots: "Bots"
    case .assistant: "AI"
    case .huddles: "Huddles"
    case .styles: "Styles"
    }
  }

  /** The web's label, which the short one's help gives. */
  public var webTitle: String {
    switch self {
    case .general: "Basic community settings"
    case .rooms: "Rooms and permissions"
    case .membership: "Membership"
    case .domain: "Domain settings"
    case .bots: "Chat bots"
    case .assistant: "AI assistant"
    case .huddles: "Huddles"
    case .styles: "Custom styles"
    }
  }

  public var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .rooms: "number"
    case .membership: "person.2"
    case .domain: "globe"
    case .bots: "cpu"
    case .assistant: "sparkles"
    case .huddles: "headphones"
    case .styles: "paintbrush"
    }
  }

  /** Whether only administrators see it in the navigation. */
  public var administratorsOnly: Bool { ![.general, .rooms, .membership].contains(self) }

  /** The sections someone sees: all of them for administrators (web `settings-navigation.tsx:87-101`). */
  static func shown(administrator: Bool) -> [AdminSection] { allCases.filter { administrator || !$0.administratorsOnly } }
}

#if os(macOS)
extension AdminSection: SettingsPage {}
#endif

/** A setup dialog Server Settings opens over itself. */
enum AdminSetup: String, Identifiable {
  case email, turnstile, memberful, sso

  var id: String { rawValue }
}

/** Something Server Settings asks about before doing it, in the web's words. */
public enum AdminConfirmation: Identifiable, Equatable, Sendable {
  case turnOn(JoinWay, question: String)
  case stopEmail
  case stopTurnstile
  case forgetSso
  case revoke(EmailInvitation)
  case handle(Report, ReportOutcome, name: String)
  case remove(DirectoryUser)
  case stopAssistant
  case stopOutsideAi
  case stopHuddles
  case stopRelay
  case deleteAgent(UserID, name: String)
  case removeApp(AppID, name: String, url: String)
  case deleteBot(UserID, name: String)
  case newBotKey(UserID, name: String)

  public var id: String {
    switch self {
    case let .turnOn(way, _): "on-\(way.rawValue)"
    case .stopEmail: "stop-email"
    case .stopTurnstile: "stop-turnstile"
    case .forgetSso: "forget-sso"
    case let .revoke(invitation): "revoke-\(invitation.id)"
    case let .handle(report, outcome, _): "report-\(report.id)-\(outcome.rawValue)"
    case let .remove(person): "remove-\(person.id)"
    case .stopAssistant: "stop-assistant"
    case .stopOutsideAi: "stop-outside-ai"
    case .stopHuddles: "stop-huddles"
    case .stopRelay: "stop-relay"
    case let .deleteAgent(id, _): "delete-agent-\(id)"
    case let .removeApp(id, _, _): "remove-app-\(id)"
    case let .deleteBot(id, _): "delete-bot-\(id)"
    case let .newBotKey(id, _): "new-bot-key-\(id)"
    }
  }

  var title: String {
    switch self {
    case let .turnOn(way, _): "Turn On \(way.name)"
    case .stopEmail: "Stop Sending Email"
    case .stopTurnstile: "Turn Off Turnstile"
    case .forgetSso: "Remove"
    case .revoke: "Revoke"
    case let .handle(_, outcome, name):
      switch outcome {
      case .deleted: "Delete Message"
      case .removed: "Remove \(name)"
      case .banned: "Ban \(name)"
      case .dismissed: "Dismiss"
      }
    case let .remove(person): "Remove \(person.name)"
    case .stopAssistant: "Turn Off Ember AI"
    case .stopOutsideAi: "Disconnect AI Apps"
    case .stopHuddles: "Turn Off Huddles"
    case .stopRelay: "Turn Off Relay"
    case let .deleteAgent(_, name): "Delete \(name)"
    case let .removeApp(_, name, _): "Remove \(name)"
    case let .deleteBot(_, name): "Delete \(name)"
    case .newBotKey: "Generate New Key"
    }
  }

  var message: String {
    switch self {
    case let .turnOn(_, question): question
    case .stopEmail: AdminText.confirmStopEmail
    case .stopTurnstile: AdminText.confirmStopTurnstile
    case .forgetSso: AdminText.confirmForgetSso
    case .revoke: AdminText.confirmRevoke
    case let .handle(_, outcome, _):
      switch outcome {
      case .deleted: AdminText.confirmDeleteMessage
      case .removed: NavigationText.removePersonConfirm
      case .banned: NavigationText.banConfirm
      case .dismissed: ""
      }
    case .remove: NavigationText.removePersonConfirm
    case .stopAssistant: AIText.confirmStopAssistant
    case .stopOutsideAi: AIText.confirmStopOutsideAi
    case .stopHuddles: AIText.confirmStopHuddles
    case .stopRelay: AIText.confirmStopRelay
    case .deleteAgent: AIText.confirmDeleteAgent
    case .removeApp: AIText.confirmRemoveApp
    case .deleteBot: AIText.confirmDeleteBot
    case .newBotKey: AIText.confirmNewKey
    }
  }

  var isDestructive: Bool {
    if case .turnOn = self { return false }
    return true
  }
}

/**
 * Server Settings' state (web `WorkspaceSettingsPage`'s): the settings `GET /api/account` answers, what's
 * typed and moved while it saves, and each section's saves. A save answers with the workspace, which the
 * whole app takes first (web `answered`), and what's been typed since stays.
 */
@MainActor
@Observable
public final class WorkspaceAdmin {
  @ObservationIgnored unowned let session: InstanceSession

  public internal(set) var settings: WorkspaceSettings?
  var loadFailure: String?
  /** The latest result or failure to show, until it's dismissed or replaced. */
  var message: String?
  var messageIsError = false
  var setup: AdminSetup?
  /** What to do once a setup closes having saved: turn on the way that opened it. */
  @ObservationIgnored var afterSetup: (() -> Void)?
  var confirming: AdminConfirmation?
  /** Which section the IRC tab strip, or the Mac's page column, shows. */
  var section: AdminSection = .general

  // General
  var typedName: String?
  var typedTagline: String?
  var movedHideTranslations: Bool?
  var savingGeneral = false
  var savingLogo = false
  var pickedLogo: Data?
  var checkingForUpdates = false
  var updateCheckFailed: String?

  // Rooms
  let order = RoomOrderModel()
  var restricting = false
  /** Where Server Settings was going when a staged room order held it, asked about until it's saved or discarded. */
  var leavingOrder: (() -> Void)?

  // Chat bots
  var bots: [Bot]?
  var botsFailure: String?

  // Membership
  var moved: [JoinWay: Bool] = [:]
  var regeneratingJoinCode = false
  var addingDomains = false
  var domainsDraft: [String]?
  var typedDomain = ""
  var domainRefusal: String?
  var savingDomains = false
  var inviteText = ""
  var inviteOutcome: String?
  var inviteRefused = false
  var sendingInvites = false
  /** The links of the invitations Ember didn't email, by id, since only now are they known. */
  var inviteLinks: [String: String] = [:]
  var testEmail: (text: String, isError: Bool)?
  var typedBlockedWords: String?
  var blockedRefusal: String?
  var savingBlockedWords = false
  var reports: Reports?
  var reportsFailure: String?
  var handling: Set<String> = []
  var changingPeople: Set<UserID> = []

  // Domain
  /** A domain `/domain setup <host>` typed into Set up's field. */
  var domainToSetUp: String?
  var changingDomain = false
  var domainCheck: (address: String, reaches: CustomDomainReach?)?
  var useRefusal: String?

  // Styles
  var customStyles: String?
  var typedStyles: String?
  var savingStyles = false
  var stylesRefusal: String?
  var iconDraft: [NavigationSlot: String] = [:]
  var savingIcons = false

  /** The AI assistant, Chat bots and Huddles sections' state. */
  let ai: AIAdmin

  init(session: InstanceSession) {
    self.session = session
    self.ai = AIAdmin(session: session)
  }

  var account: Account? { session.account ?? settings?.account }

  /** Whether the controls show: the Worker's own answer, once it's given, else the session's. */
  var isAdministrator: Bool {
    if let settings { return settings.canAdminister }
    return session.me?.administrator == true
  }

  var sections: [AdminSection] { AdminSection.shown(administrator: isAdministrator) }

  var ways: WaysToJoin? {
    guard let account, let settings else { return nil }
    return WaysToJoin(account: account, moved: moved, memberfulSetUp: settings.memberfulSite != nil, ssoSetUp: settings.sso != nil)
  }

  var sendsEmail: Bool { settings.map { WorkspaceRules.sendsEmail($0.email) } == true }

  /** The address Memberful and the provider send people back to, and shared links lead to: the custom domain, or this server's. */
  var publicOrigin: String { session.publicOrigin }

  /** The count Membership's entry shows administrators: the open reports, none at 0 (web `SettingsNavigation`'s count). */
  func badge(_ section: AdminSection) -> Int {
    guard section == .membership, isAdministrator, let open = session.openReports else { return 0 }
    return open
  }

  // MARK: Loading and notices

  /** Loads the settings and the people (web `workspace-settings-page.tsx:198-213`), and for administrators, the reports. */
  func load() async {
    loadFailure = nil
    do {
      let loaded = try await session.api.workspaceSettings()
      settings = loaded
      // What was typed is for the settings as they were: loaded again, they show as Ember has them.
      typedName = nil
      typedTagline = nil
      session.adoptAccount(loaded.account)
      // Only administrators have the welcome card, and they're always given the code (web `onJoinCodeChanged`).
      if let code = loaded.joinCode { session.adoptJoinCode(code) }
      if loaded.canAdminister { await loadReports() }
    } catch EmberError.signedOut {
      logger.error("Loading workspace settings found the session ended")
      session.sessionEnded()
      return
    } catch {
      logger.error("Loading workspace settings failed: \(error.localizedDescription, privacy: .public)")
      loadFailure = error.localizedDescription
    }
    await session.refreshDirectory()
  }

  func say(_ text: String, error: Bool = false) {
    message = text
    messageIsError = error
  }

  /**
   * Logs a failure and shows it on the page. A session that's ended goes to sign in; a 403 means this
   * person no longer administers the workspace, so the settings load again, showing what they can do now.
   */
  func failed(_ doing: String, _ error: Error) {
    logger.error("\(doing, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    if (error as? EmberError) == .signedOut { return session.sessionEnded() }
    say(error.localizedDescription, error: true)
    if (error as? EmberError)?.problem?.status == 403 { Task { await load() } }
  }

  /**
   * Memberful turned on elsewhere, by an administrator who gave Set up Memberful the keys there: its
   * settings load again, rather than the card saying Ember has no keys (web `memberfulOn`'s effect).
   */
  func memberfulTurnedOn() {
    guard let settings, settings.memberfulSite == nil else { return }
    Task {
      do {
        let loaded = try await session.api.workspaceSettings()
        self.settings?.memberfulSite = loaded.memberfulSite
        self.settings?.memberfulWebhooks = loaded.memberfulWebhooks
        self.settings?.memberfulKeys = loaded.memberfulKeys
        self.settings?.memberfulSiteKept = loaded.memberfulSiteKept
      } catch {
        failed("Loading Memberful's settings", error)
      }
    }
  }

  /** Single sign-on turned on elsewhere, likewise: the provider loads again, for administrators, whom alone the settings tell of it. */
  func ssoTurnedOn() {
    guard let settings, settings.canAdminister, settings.sso == nil else { return }
    Task {
      do {
        self.settings?.sso = try await session.api.workspaceSettings().sso
      } catch {
        failed("Loading single sign-on's provider", error)
      }
    }
  }

  /** Runs a change, showing why it failed. */
  func run(_ doing: String, _ work: @escaping @MainActor () async throws -> Void) {
    Task {
      do {
        try await work()
      } catch {
        failed(doing, error)
      }
    }
  }

  /** Takes the workspace a change answered with, everywhere, and here. */
  func answered(_ account: Account) {
    session.adoptAccount(account)
    settings?.account = account
  }

  /** Asks before doing something that can't be undone, or does it. */
  func confirm(_ confirmation: AdminConfirmation) {
    switch confirmation {
    case let .turnOn(way, _): save(way, true)
    case .stopEmail: stopEmail()
    case .stopTurnstile: forgetTurnstile()
    case .forgetSso: forgetSso()
    case let .revoke(invitation): revoke(invitation)
    case let .handle(report, outcome, _): handle(report, outcome)
    case let .remove(person): remove(person)
    case .stopAssistant: ai.stopAssistant()
    case .stopOutsideAi: ai.setOutside(false)
    case .stopHuddles: ai.stopHuddles()
    case .stopRelay: ai.stopRelay()
    case let .deleteAgent(id, name): ai.deleteAgent(id) { self.say("\(name) is deleted.") }
    case let .removeApp(id, name, url): ai.removeApp(id, name: name, url: url)
    case let .deleteBot(id, name): ai.deleteBot(id) { self.say("\(name) is deleted.") }
    case let .newBotKey(id, name): ai.newBotKey(id) { self.say("\(name) has a new key.") }
    }
  }

  /** Opens a setup, doing `then` once it closes having saved. */
  func open(_ setup: AdminSetup, then: (() -> Void)? = nil) {
    afterSetup = then
    self.setup = setup
  }

  /** A setup closed: having saved, it goes on with what opened it. */
  func setupClosed(saved: Bool) {
    let then = afterSetup
    afterSetup = nil
    setup = nil
    if saved { then?() }
  }

  // MARK: General

  func shownName(_ account: Account) -> String { typedName ?? account.name }
  func shownTagline(_ account: Account) -> String { typedTagline ?? account.tagline }
  func hideTranslations(_ account: Account) -> Bool { movedHideTranslations ?? account.hideTranslationButtons }
  var generalChanged: Bool {
    guard let account else { return false }
    return (typedName.map { $0 != account.name } == true) || (typedTagline.map { $0 != account.tagline } == true)
      || (movedHideTranslations.map { $0 != account.hideTranslationButtons } == true)
  }

  /** Save changes (web General's form): name, tagline, and Hide translation buttons if it was moved. */
  func saveGeneral() {
    guard let account, !savingGeneral else { return }
    let name = shownName(account).trimmingCharacters(in: .whitespacesAndNewlines)
    let tagline = shownTagline(account)
    guard name.count <= EmberLimits.maxAccountNameLength else { return say(EmberText.nameTooLong, error: true) }
    guard tagline.count <= EmberLimits.maxTaglineLength else { return say(EmberText.taglineTooLong, error: true) }
    let hide = movedHideTranslations
    savingGeneral = true
    run("Saving the community's name") {
      defer { self.savingGeneral = false }
      let saved = try await self.session.api.changeAccount(AccountChanges(
        name: name, tagline: tagline, settings: hide.flatMap { $0 == account.hideTranslationButtons ? nil : AccountSettings(hideTranslationButtons: $0) }))
      self.answered(saved)
      // What's been typed since stays.
      if self.typedName == name || self.typedName == saved.name { self.typedName = nil }
      if self.typedTagline == tagline || self.typedTagline == saved.tagline { self.typedTagline = nil }
      if self.movedHideTranslations == hide { self.movedHideTranslations = nil }
      self.say(AdminText.saved)
    }
  }

  /** Sets one General setting from the input line, as Save changes would. */
  func change(_ changes: AccountChanges, _ doing: String, then: @escaping @MainActor (Account) -> Void) {
    run(doing) {
      let saved = try await self.session.api.changeAccount(changes)
      self.answered(saved)
      then(saved)
    }
  }

  /** Upload icon: saved at once, the picked image showing meanwhile (web `PicturePicker`). */
  func changeLogo(_ photo: ChosenPhoto) {
    guard photo.data.count <= Avatars.maxLogoSize else { return say(Avatars.logoTooLarge, error: true) }
    let logo = Avatars.chosenLogo(photo.data, fileName: photo.fileName, contentType: photo.contentType)
    pickedLogo = logo.large ?? photo.data
    savingLogo = true
    run("Uploading the community's icon") {
      defer {
        self.savingLogo = false
        self.pickedLogo = nil
      }
      self.answered(try await self.session.api.changeLogo(logo))
      self.say(AdminText.saved)
    }
  }

  func removeLogo() {
    savingLogo = true
    run("Removing the community's icon") {
      defer { self.savingLogo = false }
      self.answered(try await self.session.api.removeLogo())
    }
  }

  /** Check for updates: the Worker asks GitHub again (`POST /api/account/release_checks`). */
  func checkForUpdates() {
    checkingForUpdates = true
    updateCheckFailed = nil
    Task {
      do {
        session.adoptRelease(try await session.api.checkForReleaseAfresh())
      } catch {
        logger.error("Checking for updates failed: \(error.localizedDescription, privacy: .public)")
        updateCheckFailed = error.localizedDescription
      }
      checkingForUpdates = false
    }
  }

  // MARK: Rooms

  /** Must be admin to create new rooms: saved at once, showing where it was moved meanwhile. */
  func restrict(_ on: Bool) {
    guard !restricting else { return }
    restricting = true
    run("Changing who can make rooms") {
      defer { self.restricting = false }
      self.answered(try await self.session.api.changeAccount(AccountChanges(settings: AccountSettings(restrictRoomCreation: on))))
    }
  }

  /** Goes where `go` goes once a staged room order is saved or discarded, asking first (web `UnsavedChanges` with `ORDER_CHANGES`). */
  func leaveOrder(_ go: @escaping () -> Void) {
    guard order.changed else { return go() }
    leavingOrder = go
  }

  /** Save, in the Unsaved Changes dialog: saves the order, then goes on; a failure stays, saying why. */
  func saveOrderAndLeave() {
    guard let go = leavingOrder else { return }
    leavingOrder = nil
    order.save(session: session, then: go)
  }

  /** Discard: drops the staged order, then goes on. */
  func discardOrderAndLeave() {
    let go = leavingOrder
    leavingOrder = nil
    order.cancel()
    go?()
  }

  // MARK: Chat bots

  /** The chat bots (`GET /api/account/bots`), by their names now, without those the directory says are gone (web `listedNow`). */
  func loadBots() async {
    do {
      let loaded = try await session.api.bots()
      bots = loaded
      botsFailure = nil
    } catch EmberError.signedOut {
      session.sessionEnded()
    } catch {
      logger.error("Loading chat bots failed: \(error.localizedDescription, privacy: .public)")
      botsFailure = error.localizedDescription
    }
  }

  var listedBots: [Bot] {
    guard let bots else { return [] }
    let now = bots.filter { session.people[$0.id]?.status != .deactivated }.map { bot in
      var named = bot
      if let person = session.people[bot.id] { named.name = person.name }
      return named
    }
    return now.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  // MARK: Ways to join

  /** A way's switch moved (web `switchTo`): asks first where the web does, then saves. */
  func flip(_ way: JoinWay, _ on: Bool, asking: Bool = true) {
    guard moved[way] == nil, let ways else { return }
    if on, asking, let question = ways.question(turningOn: way) {
      confirming = .turnOn(way, question: question)
      return
    }
    save(way, on)
  }

  /** Saves a switch, showing it where it was moved until the answer comes. */
  func save(_ way: JoinWay, _ on: Bool) {
    guard moved[way] == nil else { return }
    moved[way] = on
    Task {
      do {
        answered(try await session.api.changeAccount(AccountChanges(settings: way.settings(on))))
      } catch {
        failed("Changing \(way.name)", error)
      }
      moved[way] = nil
    }
  }

  /** Memberful's switch: setting it up first, and beside SSO only, Members only's. */
  func flipMemberful(_ on: Bool) {
    guard let ways, let flip = ways.memberfulFlip(on) else { return }
    if on, flip.way == .memberfulJoin, settings?.memberfulSite == nil {
      return open(.memberful) { [weak self] in self?.flip(.memberfulJoin, true) }
    }
    self.flip(flip.way, on, asking: flip.asks)
  }

  func flipSso(_ on: Bool) {
    guard let ways, let flip = ways.ssoFlip(on) else { return }
    if on, flip.way == .ssoJoin, settings?.sso == nil {
      return open(.sso) { [weak self] in self?.flip(.ssoJoin, true) }
    }
    self.flip(flip.way, on, asking: flip.asks)
  }

  /**
   * Email domain's switch (web `EmailDomainSettings.switchTo`): it can't be on without a domain, so the
   * first Save turns it on, nor before Ember can send email, so that's set up first.
   */
  func flipEmailDomain(_ on: Bool) {
    guard on else {
      if addingDomains {
        addingDomains = false
      } else {
        flip(.emailDomainSignUp, false)
      }
      return
    }
    let turnOn = { [weak self] in
      guard let self else { return }
      if self.keptDomains.isEmpty { self.addingDomains = true } else { self.flip(.emailDomainSignUp, true) }
    }
    if sendsEmail { turnOn() } else { open(.email, then: turnOn) }
  }

  /** The domains Email domain keeps: as the workspace shows them while it's on, else as settings kept them. */
  var keptDomains: [String] {
    if let account, account.emailDomainSignUp { return account.emailDomains }
    return settings?.emailDomains ?? []
  }

  var listedDomains: [String] { domainsDraft ?? keptDomains }

  /** Add (web `add`): each domain typed, keeping in the field any that isn't one. */
  func addDomains() {
    let (domains, refused) = WorkspaceRules.emailDomainsTyped(typedDomain)
    var added = listedDomains
    for domain in domains where !added.contains(domain) { added.append(domain) }
    guard added.count <= EmberLimits.maxEmailDomains else { return domainRefusal = AdminText.tooManyDomains }
    domainsDraft = added == keptDomains ? nil : added
    typedDomain = refused.joined(separator: " ")
    domainRefusal = refused.first.map(AdminText.notADomain)
  }

  func removeDomain(_ domain: String) {
    let kept = listedDomains.filter { $0 != domain }
    domainsDraft = kept == keptDomains ? nil : kept
  }

  /** Save domains, or Save and turn on (web `saveEmailDomains`). */
  func saveDomains() {
    let sent = listedDomains
    let turnOn = addingDomains
    savingDomains = true
    run("Saving Email domain's domains") {
      defer { self.savingDomains = false }
      let saved = try await self.session.api.changeAccount(AccountChanges(
        settings: turnOn ? AccountSettings(emailDomainSignUp: true) : nil, emailDomains: sent))
      self.answered(saved)
      self.settings?.emailDomains = sent
      self.addingDomains = false
      // Unless they've been changed again since.
      if self.domainsDraft == sent { self.domainsDraft = nil }
      self.say(AdminText.saved)
    }
  }

  /** Regenerate join link (`POST /api/account/join_code`), which the old one no longer joins with. */
  func regenerateJoinCode() {
    regeneratingJoinCode = true
    run("Making a new join link") {
      defer { self.regeneratingJoinCode = false }
      let code = try await self.session.api.regenerateJoinCode()
      self.settings?.joinCode = code
      self.session.adoptJoinCode(code)
    }
  }

  // MARK: Invite by email

  /** Send invitations, `INVITATIONS_AT_ONCE` at a time, leaving those not yet invited in the box if one fails. */
  func sendInvitations() {
    let (addresses, refused) = EmberRules.emailAddresses(in: inviteText)
    guard refused.isEmpty, !addresses.isEmpty else {
      inviteOutcome = Invitations.refusal(refused)
      inviteRefused = true
      return
    }
    sendingInvites = true
    inviteRefused = false
    inviteOutcome = sendsEmail ? "Sending invitations…" : "Making invite links…"
    Task {
      var outcomes: [InvitationOutcome] = []
      do {
        for batch in Invitations.batches(addresses) {
          let answered = try await session.api.invite(batch)
          outcomes += answered
          let invited = answered.compactMap { outcome in outcome.invitation.map { ($0, outcome.link) } }
          settings?.invitations = Invitations.withSaved(settings?.invitations ?? [], invited.map(\.0))
          for (invitation, link) in invited { keepLink(link, for: invitation) }
        }
        inviteText = ""
        inviteOutcome = Invitations.summary(outcomes)
      } catch {
        inviteText = addresses.filter { address in !outcomes.contains { $0.emailAddress == address } }.joined(separator: "\n")
        inviteOutcome = outcomes.isEmpty ? nil : Invitations.summary(outcomes)
        failed("Inviting by email", error)
      }
      sendingInvites = false
    }
  }

  private func keepLink(_ link: String?, for invitation: EmailInvitation) {
    inviteLinks[invitation.id] = link
  }

  /** Send again, or New link: a 404 means it was accepted or revoked already, and it goes. */
  func resend(_ invitation: EmailInvitation) {
    Task {
      do {
        let resent = try await session.api.resendInvitation(invitation.id)
        settings?.invitations = Invitations.withSaved(settings?.invitations ?? [], [resent.invitation])
        keepLink(resent.link, for: resent.invitation)
      } catch let error as EmberError where error.problem?.status == 404 {
        gone(invitation.id)
      } catch {
        failed("Sending an invitation again", error)
      }
    }
  }

  func revoke(_ invitation: EmailInvitation) {
    Task {
      do {
        try await session.api.revokeInvitation(invitation.id)
        gone(invitation.id)
      } catch let error as EmberError where error.problem?.status == 404 {
        gone(invitation.id)
      } catch {
        failed("Revoking an invitation", error)
      }
    }
  }

  private func gone(_ id: String) {
    settings?.invitations.removeAll { $0.id == id }
    inviteLinks[id] = nil
  }

  // MARK: Email, Turnstile, single sign-on

  /** Send me a test email (`POST /api/account/test_email`). */
  func sendTestEmail() {
    testEmail = (AdminText.sendingTest, false)
    Task {
      do {
        testEmail = (AdminText.testSent(try await session.api.sendTestEmail()), false)
      } catch let error as EmberError where [422, 502, 503].contains(error.problem?.status) {
        testEmail = (error.localizedDescription, true)
      } catch {
        testEmail = nil
        failed("Sending a test email", error)
      }
    }
  }

  /** Stop sending email: forgets the From address, keeping a Resend key. */
  func stopEmail() {
    run("Stopping email") {
      self.answered(try await self.session.api.changeAccount(AccountChanges(emailFrom: .some(nil))))
      self.settings?.email.from = nil
    }
  }

  /** Saves a From address (`PATCH {emailFrom}`), which the answer doesn't carry, so it's kept as sent. */
  func saveFrom(_ mailbox: Mailbox) async throws {
    answered(try await session.api.changeAccount(AccountChanges(emailFrom: .some(mailbox.text))))
    settings?.email.from = mailbox.text
  }

  func forgetTurnstile() {
    run("Turning off Turnstile") { self.settings?.turnstile = try await self.session.api.forgetTurnstileKeys() }
  }

  func forgetSso() {
    run("Removing single sign-on") {
      self.settings?.sso = try await self.session.api.forgetSso()
      // Removing it turns single sign-on off, unless the deployment's secrets give a provider.
      self.answered(try await self.session.api.workspaceSettings().account)
    }
  }

  // MARK: Blocked words

  var shownBlockedWords: String { typedBlockedWords ?? (settings?.blockedWords ?? []).joined(separator: "\n") }
  var blockedWordsChanged: Bool { BlockedWords.typed(shownBlockedWords) != settings?.blockedWords }

  /** Save blocked words: checked as the Worker checks them first. */
  func saveBlockedWords() {
    let words = BlockedWords.typed(shownBlockedWords)
    if let refusal = BlockedWords.refusal(words) { return blockedRefusal = refusal }
    blockedRefusal = nil
    savingBlockedWords = true
    run("Saving blocked words") {
      defer { self.savingBlockedWords = false }
      self.answered(try await self.session.api.changeAccount(AccountChanges(blockedWords: words)))
      // The answer doesn't carry the list: what was sent is what's kept.
      self.settings?.blockedWords = words
      self.typedBlockedWords = nil
      self.say(AdminText.saved)
    }
  }

  /** `/blocked add` and `/blocked del`: the list as Ember has it now, changed, so another administrator's edit stays. */
  func changeBlockedWords(_ change: @escaping @MainActor ([String]) -> [String]) async throws -> [String] {
    let current = try await session.api.workspaceSettings()
    settings = current
    let words = BlockedWords.typed(change(current.blockedWords).joined(separator: "\n"))
    if let refusal = BlockedWords.refusal(words) { throw EmberError.refused(422, refusal) }
    answered(try await session.api.changeAccount(AccountChanges(blockedWords: words)))
    settings?.blockedWords = words
    return words
  }

  // MARK: Reports

  func loadReports() async {
    do {
      reports = try await session.api.reports()
      reportsFailure = nil
    } catch {
      logger.error("Loading reports failed: \(error.localizedDescription, privacy: .public)")
      reportsFailure = error.localizedDescription
    }
  }

  /** Handles a report, which closes the others of the same message or person; 409 means another administrator did. */
  func handle(_ report: Report, _ outcome: ReportOutcome) {
    handling.insert(report.id)
    Task {
      do {
        let closed = try await session.api.handleReport(report.id, outcome: outcome)
        let ids = Set(closed.map(\.id))
        if var reports {
          reports.open.removeAll { ids.contains($0.id) }
          reports.handled = Array((closed + reports.handled.filter { !ids.contains($0.id) }).prefix(Reporting.handledReportsListed))
          self.reports = reports
        }
      } catch let error as EmberError where error.problem?.status == 409 {
        say(error.localizedDescription, error: true)
        await loadReports()
      } catch {
        failed("Handling a report", error)
      }
      handling.remove(report.id)
    }
  }

  /** The person a report is of, or wrote the message. */
  func subject(of report: Report) -> (id: UserID, name: String) {
    switch report.subject {
    case let .message(_, _, message): (message.creator.id, message.creator.name)
    case let .person(person): (person.id, person.name)
    }
  }

  /** What can be done with an open report (`handlingsFor`). */
  func handlings(for report: Report) -> [ReportOutcome] {
    var outcomes: [ReportOutcome] = []
    if case .message = report.subject, !report.isOfDeletedAccount { outcomes.append(.deleted) }
    if !report.isOfDeletedAccount, let person = session.people[subject(of: report).id], person.agent != true, person.role != .bot {
      if person.status == .active || person.status == .suspended { outcomes.append(.removed) }
      if person.status != .banned { outcomes.append(.banned) }
    }
    outcomes.append(.dismissed)
    return outcomes
  }

  /** Asks first, as the web does for all but Dismiss. */
  func ask(_ report: Report, _ outcome: ReportOutcome) {
    guard outcome != .dismissed else { return handle(report, outcome) }
    confirming = .handle(report, outcome, name: subject(of: report).name)
  }

  // MARK: People

  /** The crown: administrator or member, taking the answer only while the person is as they were (web `changeRoleOf`). */
  func setRole(_ person: DirectoryUser, administrator: Bool) {
    changingPeople.insert(person.id)
    Task {
      do {
        let changed = try await session.api.changeRole(person.id, to: administrator ? .administrator : .member)
        if session.people[person.id] == person { session.adoptPerson(changed) } else { await session.refreshDirectory() }
      } catch {
        failed("Changing \(person.name)'s role", error)
      }
      changingPeople.remove(person.id)
    }
  }

  /** Delete: deactivates them (`DELETE /api/account/users/<id>`). */
  func remove(_ person: DirectoryUser) {
    changingPeople.insert(person.id)
    Task {
      do {
        let removed = try await session.api.removePerson(person.id)
        if session.people[person.id] == person { session.adoptPerson(removed) } else { await session.refreshDirectory() }
      } catch {
        failed("Removing \(person.name)", error)
      }
      changingPeople.remove(person.id)
    }
  }

  // MARK: Custom domain

  /** This server's host, the page's own address on the web. */
  var here: String { session.instance.host }

  /**
   * Makes `address` Ember's (`PATCH {customDomain}`), or none, then, when it isn't this server's, moves this
   * server there; a 422 says why under the button.
   */
  func useDomain(_ address: String?, move: @escaping (String) -> Void) {
    changingDomain = true
    useRefusal = nil
    let before = account?.customDomain
    Task {
      do {
        let saved = try await session.api.changeAccount(AccountChanges(customDomain: .some(address)))
        answered(saved)
        if saved.customDomain != before, let settings {
          self.settings?.addresses.others = WorkspaceRules.othersAfterMove(settings.addresses.others, left: [before, here], to: saved.customDomain)
        }
        say(AdminText.saved)
        domainToSetUp = nil
        if let address, address != here { move(address) }
      } catch let error as EmberError where error.problem?.status == 422 {
        useRefusal = error.localizedDescription
      } catch {
        failed("Changing Ember's address", error)
      }
      changingDomain = false
    }
  }

  /** The addresses Ember moved away from that the page lists: this one, if it moved away, then the others (web `listed`). */
  func otherAddresses(_ settings: WorkspaceSettings) -> [String] {
    let custom = settings.account.customDomain
    let left = WorkspaceRules.isCustomDomainHost(here) && custom != nil && custom != here ? here : nil
    return (left.map { [$0] } ?? []) + settings.addresses.others.filter { $0 != here && $0 != custom }
  }

  /** What an address Ember moved away from does: reaches Ember while it has no custom domain, or forwards (web `sendsPeople`). */
  func otherSays(_ other: String) -> String {
    guard let custom = account?.customDomain else { return "\(other) still reaches Ember." }
    return custom == here ? "\(other) still forwards here." : "\(other) still forwards to \(custom)."
  }

  /** Check: whether an address Ember moved away from still reaches it, forgetting it once it doesn't. */
  func checkOther(_ address: String) {
    domainCheck = (address, nil)
    Task {
      do {
        let reaches = try await session.api.checkCustomDomain(address)
        if reaches != .ember { settings?.addresses.others.removeAll { $0 == address } }
        domainCheck = (address, reaches)
      } catch {
        domainCheck = nil
        failed("Checking \(address)", error)
      }
    }
  }

  // MARK: Styles

  func loadStyles() async {
    guard customStyles == nil else { return }
    do {
      customStyles = try await session.api.customStyles()
    } catch {
      failed("Loading custom CSS", error)
    }
  }

  func shownStyles(_ account: Account) -> String { typedStyles ?? customStyles ?? account.customStyles }

  /** Save changes (`PATCH /api/account/custom_styles`). */
  func saveStyles() {
    guard let account else { return }
    let styles = shownStyles(account)
    guard styles.count <= EmberLimits.maxCustomStylesLength else { return stylesRefusal = AdminText.customStylesTooLong }
    stylesRefusal = nil
    savingStyles = true
    run("Saving custom CSS") {
      defer { self.savingStyles = false }
      let saved = try await self.session.api.changeCustomStyles(styles)
      self.answered(saved)
      self.customStyles = saved.customStyles
      if self.typedStyles == styles { self.typedStyles = nil }
      self.say(AdminText.saved)
    }
  }

  /** The icon a slot shows here: as chosen, unsaved, or as the workspace has it. */
  func icon(_ slot: NavigationSlot) -> String {
    if let chosen = iconDraft[slot] { return chosen.isEmpty ? slot.defaultIcon : chosen }
    guard let account else { return slot.defaultIcon }
    return account.icon(for: slot)
  }

  /** Chooses a slot's icon, staged; its default is saved as "" (`navigationIconsOf`). */
  func choose(_ icon: String?, for slot: NavigationSlot) {
    var value = ""
    if let icon, icon != slot.defaultIcon { value = icon }
    var saved = ""
    if let kept = account?.navigationIcons[slot.rawValue], kept != slot.defaultIcon { saved = kept }
    iconDraft[slot] = value == saved ? nil : value
  }

  /** Save changes: only the slots changed, so saving never undoes another administrator's change. */
  func saveIcons() {
    let sent = Dictionary(uniqueKeysWithValues: iconDraft.map { ($0.key.rawValue, $0.value) })
    guard !sent.isEmpty else { return }
    savingIcons = true
    run("Saving navigation icons") {
      defer { self.savingIcons = false }
      self.answered(try await self.session.api.changeAccount(AccountChanges(navigationIcons: sent)))
      for (key, value) in sent {
        if let slot = NavigationSlot(rawValue: key), self.iconDraft[slot] == value { self.iconDraft[slot] = nil }
      }
      self.say(AdminText.saved)
    }
  }
}

extension Avatars {
  /** The image types Ember resizes, whose logo gets variants (`VARIABLE_TYPES`). */
  static let variableTypes: Set<String> = ["image/png", "image/gif", "image/jpeg", "image/tiff", "image/webp", "image/avif", "image/heic", "image/heif"]

  /** A logo to send: the file, and its PNG variants within 512 and 192 pixels (web `logoVariantsOf`). */
  static func chosenLogo(_ data: Data, fileName: String, contentType: String) -> ChosenLogo {
    guard variableTypes.contains(contentType.lowercased()) else {
      return ChosenLogo(data: data, fileName: fileName, contentType: contentType, large: nil, small: nil, variantContentType: "image/png")
    }
    return ChosenLogo(
      data: data, fileName: fileName, contentType: contentType, large: pngVariant(of: data, box: logoBoxes.large),
      small: pngVariant(of: data, box: logoBoxes.small), variantContentType: "image/png")
  }
}

extension Avatars {
  /** A PNG within `box` pixels on its longest side, as a logo's variants are. */
  static func pngVariant(of data: Data, box: Int) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: box,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? output as Data : nil
  }
}

// MARK: - The window

/**
 * Server Settings (web community settings) for one server: a window on the Mac, a sheet on iOS, in either
 * theme. Suite lays its sections out as AppCoreUI's settings canvas on the Mac and a list on iOS; IRC
 * Classic as a tab strip in its status bar's blue.
 */
struct ServerSettingsView: View {
  let app: AppModel
  let session: InstanceSession
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @Environment(\.dismiss) private var dismiss

  private var admin: WorkspaceAdmin { session.admin }

  var body: some View {
    @Bindable var admin = admin
    shell
      // The task holds the session: the admin model only borrows it (unowned).
      .task(id: session.me?.administrator) { [session] in await session.admin.load() }
      .onAppear { admin.section = admin.sections.contains(session.adminSection) ? session.adminSection : .general }
      .onChange(of: session.adminSection) { _, section in if admin.sections.contains(section) { admin.section = section } }
      // Memberful or single sign-on turned on in another window or by another administrator.
      .onChange(of: session.account?.memberfulJoin) { was, now in if now == true, was == false { admin.memberfulTurnedOn() } }
      .onChange(of: session.account?.ssoJoin) { was, now in if now == true, was == false { admin.ssoTurnedOn() } }
      .alert(
        "Unsaved Changes", isPresented: Binding(get: { admin.leavingOrder != nil }, set: { if !$0 { admin.leavingOrder = nil } })
      ) {
        Button("Save") { admin.saveOrderAndLeave() }
        Button("Discard", role: .destructive) { admin.discardOrderAndLeave() }
        Button("Keep Editing", role: .cancel) { admin.leavingOrder = nil }
      } message: {
        Text(NavigationText.sharedOrderLeaving)
      }
      .modifier(OrderDismissGuard(session: session, order: admin.order))
      .sheet(item: $admin.setup) { setup in
        AdminSetupSheet(session: session, admin: admin, setup: setup).environment(\.appTheme, look)
      }
      .sheet(item: Binding(get: { admin.ai.editor }, set: { admin.ai.editor = $0 })) { editor in
        AIEditorSheet(app: app, session: session, editor: editor).environment(\.appTheme, look)
      }
      .confirmationDialog(
        admin.confirming?.title ?? "Are you sure?", isPresented: Binding(get: { admin.confirming != nil }, set: { if !$0 { admin.confirming = nil } }),
        titleVisibility: .visible, presenting: admin.confirming
      ) { confirmation in
        Button(confirmation.title, role: confirmation.isDestructive ? .destructive : nil) { admin.confirm(confirmation) }
        Button("Cancel", role: .cancel) {}
      } message: { confirmation in
        Text(confirmation.message)
      }
  }

  @ViewBuilder
  private var shell: some View {
    switch look {
    case .suite:
      #if os(macOS)
      SettingsCanvas(selection: Binding(get: { admin.section }, set: { admin.section = $0 }), pages: admin.sections) { section in
        page(section)
      }
      .frame(minWidth: 760, minHeight: 560)
      .background(SemanticColor.background)
      .suiteTheme(.ircX)
      #else
      NavigationStack {
        List(admin.sections) { section in
          NavigationLink {
            page(section).navigationTitle(section.title)
          } label: {
            Label(section.title, systemImage: section.systemImage)
          }
          .badge(admin.badge(section))
          .accessibilityHint(admin.badge(section) > 0 ? NavigationText.openReports(admin.badge(section)) : "")
        }
        .navigationTitle(session.me?.administrator == true ? "Admin" : "Workspace")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Done") { admin.leaveOrder { dismiss() } } }
        }
      }
      .suiteTheme(.ircX)
      #endif
    case .irc:
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Text("[\(session.name)(admin)]").foregroundStyle(irc.text)
          ForEach(admin.sections) { section in
            let count = admin.badge(section)
            Button(count > 0 ? "[\(section.title) \(count)]" : "[\(section.title)]") { admin.section = section }
              .buttonStyle(.plain)
              .foregroundStyle(admin.section == section ? irc.ember : irc.statusBracket)
              .help(count > 0 ? "\(section.webTitle): \(NavigationText.openReports(count)) (/admin \(section.rawValue))" : "\(section.webTitle) (/admin \(section.rawValue))")
          }
          Spacer()
          #if os(iOS)
          Button("[done]") { admin.leaveOrder { dismiss() } }.buttonStyle(.plain).foregroundStyle(irc.ember)
          #endif
        }
        .font(Theme.font(12, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(irc.statusBar)
        page(admin.section)
      }
      .background(irc.buffer)
      .frame(minWidth: 620, minHeight: 520)
      .preferredColorScheme(.dark)
      .tint(irc.ember)
    }
  }

  @ViewBuilder
  private func page(_ section: AdminSection) -> some View {
    if admin.settings == nil, let failure = admin.loadFailure {
      VStack(spacing: Spacing.md) {
        Text(failure).foregroundStyle(look == .irc ? irc.part : SemanticColor.warning)
        Button("Try Again") { Task { await admin.load() } }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if admin.settings == nil {
      Color.clear.loadingActivity(true)
    } else {
      AdminPage(app: app, session: session, admin: admin, section: section)
    }
  }
}

/** A section's page: its Form, and the page's notice under it. */
struct AdminPage: View {
  let app: AppModel
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let section: AdminSection
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    let form = Form {
      if look == .irc, let message = admin.message {
        Text("-!- \(message)").foregroundStyle(admin.messageIsError ? irc.part : irc.join).onTapGesture { admin.message = nil }
      }
      switch section {
      case .general: GeneralSettings(session: session, admin: admin)
      case .rooms:
        RoomsAndPermissionsSection(session: session, admin: admin, order: admin.order, newRoom: { session.showingNewRoom = true }, leave: leaveForRoom)
      case .membership: MembershipSettings(session: session, admin: admin)
      case .domain: DomainSettings(app: app, session: session, admin: admin)
      case .bots: ChatBotsSettings(session: session, admin: admin)
      case .assistant: AssistantSettingsSection(session: session, admin: admin)
      case .huddles: HuddlesSettingsSection(session: session, admin: admin)
      case .styles: StylesSettings(session: session, admin: admin)
      }
    }
    .themedForm(look, irc)
    switch look {
    case .suite:
      #if os(macOS)
      form.settingsNotice(admin.message, isError: admin.messageIsError)
      #else
      form.safeAreaInset(edge: .bottom) {
        if let message = admin.message {
          Notice(
            message, systemImage: admin.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            tint: admin.messageIsError ? SemanticColor.warning : SemanticColor.positive, onDismiss: { admin.message = nil }
          )
          .padding(.horizontal, Spacing.lg)
        }
      }
      #endif
    case .irc: form
    }
  }
}

extension AdminPage {
  /**
   * A room's row leaves for its settings: once a staged order is saved or discarded, and on iOS, with the
   * sheet closed first, so the room's page doesn't open hidden behind it.
   */
  func leaveForRoom(_ go: @escaping () -> Void) {
    admin.leaveOrder {
      #if os(iOS)
      session.showingWorkspaceSettings = false
      #endif
      go()
    }
  }
}

/**
 * Closing the window, or swiping the sheet away, with a staged room order asks first, as leaving does
 * (web `UnsavedChanges`); iOS before 27 can only hold the sheet.
 */
private struct OrderDismissGuard: ViewModifier {
  let session: InstanceSession
  let order: RoomOrderModel

  func body(content: Content) -> some View {
    #if os(macOS)
    guarded(content)
    #else
    if #available(iOS 27, *) {
      guarded(content)
    } else {
      content.interactiveDismissDisabled(order.changed)
    }
    #endif
  }

  @available(iOS 27, *)
  private func guarded(_ content: Content) -> some View {
    content.dismissalConfirmationDialog("Unsaved Changes", shouldPresent: order.changed) {
      Button("Save") { order.save(session: session) }
      Button("Discard", role: .destructive) { order.cancel() }
      Button("Keep Editing", role: .cancel) {}
    } message: {
      Text(NavigationText.sharedOrderLeaving)
    }
  }
}

/** A line of explanation under a setting: in its help on the Mac where it's long, whole on iOS, which has no help. */
struct Explanation: View {
  let text: String
  var isWarning = false
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  init(_ text: String, isWarning: Bool = false) {
    self.text = text
    self.isWarning = isWarning
  }

  var body: some View {
    Text(text)
      .font(look == .irc ? Theme.font(11) : DesignFont.detail)
      .foregroundStyle(isWarning ? (look == .irc ? irc.part : SemanticColor.warning) : Color.secondary)
      #if os(macOS)
      .lineLimit(3)
      .help(text)
      #endif
  }
}

/** Opens a link in the browser, as a button. */
struct OpenLinkButton: View {
  let title: String
  let url: String
  var systemImage = "arrow.up.right.square"
  var copying: String?
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button(title, systemImage: systemImage) {
      if let copying { Pasteboard.copy(copying) }
      guard let link = URL(string: url) else {
        logger.error("Not a link: \(url, privacy: .public)")
        return
      }
      openURL(link)
    }
    .help(copying.map { "Opens \(url), copying \($0)" } ?? url)
  }
}

#if os(macOS)
/** Server Settings' window on the Mac: one for each server, in the theme Settings picked. */
struct ServerSettingsWindow: View {
  static let id = "server-settings"

  let app: AppModel
  let id: UUID?
  @AppStorage(Preferences.theme) private var theme: AppTheme = .suite
  @AppStorage(Preferences.appearance) private var appearance: Appearance = .system

  var body: some View {
    Group {
      if let session = app.sessions.first(where: { $0.id == id }), session.phase == .ready {
        ServerSettingsView(app: app, session: session)
          .navigationTitle("\(session.name) Settings")
      } else {
        ContentUnavailableView("Server Settings", systemImage: "gearshape", description: Text("Sign in to the server to change its settings."))
      }
    }
    .environment(\.appTheme, theme)
    .preferredColorScheme(theme == .suite ? appearance.colorScheme : .dark)
  }
}
#endif
