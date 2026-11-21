import EmberKit
import Foundation

/**
 * What the input line's workspace commands do (`AdminCommand`): each does what Server Settings' control
 * does, printing the result as `-!-` lines; what the web asks about first is asked here too, and what
 * needs a form opens Server Settings at it.
 */
@MainActor
enum AdminCommander {
  static func run(_ command: AdminCommand, app: AppModel, session: InstanceSession, room: RoomModel) {
    let admin = session.admin
    switch command {
    case let .open(section):
      session.openWorkspaceSettings(section.flatMap(AdminSection.init(rawValue:)))
      return
    case let .joinLink(regenerate) where !regenerate:
      perform(room) { try await printJoinLink(session: session, room: room) }
      return
    case let .version(check) where !check && session.me?.administrator != true:
      room.note(session.bootstrap.map { "Ember version \($0.version)" } ?? "Ember's version isn't known yet")
      return
    case .reload:
      session.reloadAfterUpdate()
      room.note("Reloading \(session.instance.host)")
      return
    case _ where AICommander.isAnyones(command):
      return AICommander.run(command, session: session, room: room)
    default:
      break
    }
    guard session.me?.administrator == true else { return room.note(command.forbidden, kind: .error) }
    if AICommander.handles(command) { return AICommander.run(command, session: session, room: room) }
    switch command {
    case .open, .reload, .ai, .outside, .agents, .agent, .app, .bots, .bot, .huddles:
      break
    case let .set(setting):
      set(setting, session: session, room: room)
    case .styles:
      perform(room) {
        let styles = try await session.api.customStyles()
        room.note("Custom CSS: \(styles.count) characters. Edit it in Server Settings (/admin styles).")
      }
    case let .order(order):
      self.order(order, session: session, room: room)
    case let .joinMode(way, on):
      perform(room) {
        _ = try await admin.loaded()
        guard let way else { return room.print(ways(admin)) }
        try await flip(way, on, admin: admin, session: session, room: room)
      }
    case .joinLink:
      perform(room) {
        let code = try await session.api.regenerateJoinCode()
        admin.settings?.joinCode = code
        session.adoptJoinCode(code)
        room.note("New join link: \(session.joinLink(code))")
      }
    case let .domains(change):
      domains(change, admin: admin, room: room)
    case let .inviteEmail(text):
      invite(text, admin: admin, session: session, room: room)
    case let .invites(action):
      invites(action, admin: admin, session: session, room: room)
    case let .mail(action):
      mail(action, admin: admin, session: session, room: room)
    case let .turnstile(action):
      perform(room) {
        let settings = try await admin.loaded()
        switch action {
        case .status: room.note(settings.turnstile == nil ? AdminText.turnstileOff : AdminText.turnstileOn(secret: settings.turnstile == .secret))
        case .off:
          guard settings.turnstile == .saved else { return room.note("Turnstile has no saved keys to forget", kind: .error) }
          session.confirmation = .admin(.stopTurnstile)
        case .setup: openSetup(.turnstile, session: session)
        }
      }
    case let .memberful(action):
      provider(action, memberful: true, admin: admin, session: session, room: room)
    case let .sso(action):
      provider(action, memberful: false, admin: admin, session: session, room: room)
    case let .blocked(action):
      blocked(action, admin: admin, room: room)
    case let .reports(n, outcome):
      reports(n, outcome, admin: admin, session: session, room: room)
    case let .role(nick, administrator):
      guard let person = person(nick, session: session, room: room) else { return }
      perform(room) {
        let changed = try await session.api.changeRole(person.id, to: administrator ? .administrator : .member)
        session.adoptPerson(changed)
        let me = session.me?.name ?? "you"
        room.note(administrator ? "\(me) gives operator status to \(changed.name)" : "\(me) removes operator status from \(changed.name)")
      }
    case let .remove(nick):
      guard let person = person(nick, session: session, room: room) else { return }
      session.confirmation = .admin(.remove(person))
    case let .domain(action):
      domain(action, app: app, admin: admin, session: session, room: room)
    case let .version(check):
      perform(room) {
        let release = check ? try await session.api.checkForReleaseAfresh() : try await session.api.releaseCheck()
        session.adoptRelease(release)
        guard let merged = session.releaseCheck else { return }
        var lines = [merged.heading, merged.note]
        if let update = merged.update { lines += [merged.updating.says, "\(merged.updating.label): \(merged.updating.url)", "What's new: \(update.notes)"] }
        if let beta = merged.betaToTry { lines += [AdminText.betaToTry(beta.release), "\(merged.trying.label): \(merged.trying.url)"] }
        room.print(lines)
      }
    }
  }

  /** Runs a command's request, printing why it failed. */
  private static func perform(_ room: RoomModel, _ work: @escaping @MainActor () async throws -> Void) {
    Task {
      do {
        try await work()
      } catch {
        logger.error("An admin command failed: \(error.localizedDescription, privacy: .public)")
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }

  private static func person(_ nick: String, session: InstanceSession, room: RoomModel) -> DirectoryUser? {
    guard let person = session.people.values.first(where: { $0.name.caseInsensitiveCompare(nick) == .orderedSame || $0.username == nick })
      ?? session.person(named: nick)
    else {
      room.note("\(nick): No such nick", kind: .error)
      return nil
    }
    guard person.id != session.me?.id else {
      room.note("Administrators can't change their own role or remove themselves", kind: .error)
      return nil
    }
    return person
  }

  /** Opens Server Settings with a setup dialog over it. */
  private static func openSetup(_ setup: AdminSetup, session: InstanceSession, then: (() -> Void)? = nil) {
    session.openWorkspaceSettings(.membership)
    session.admin.open(setup, then: then)
  }

  // MARK: General

  private static func set(_ setting: AdminCommand.Setting, session: InstanceSession, room: RoomModel) {
    let changes: AccountChanges
    let said: (Account) -> String
    switch setting {
    case let .name(name):
      guard name.count <= EmberLimits.maxAccountNameLength else { return room.note(EmberText.nameTooLong, kind: .error) }
      changes = AccountChanges(name: name)
      said = { "name set to \"\($0.name)\"" }
    case let .tagline(tagline):
      guard tagline.count <= EmberLimits.maxTaglineLength else { return room.note(EmberText.taglineTooLong, kind: .error) }
      changes = AccountChanges(tagline: tagline)
      said = { $0.tagline.isEmpty ? "tagline cleared" : "tagline set to \"\($0.tagline)\"" }
    case let .restrictRooms(on):
      changes = AccountSettings(restrictRoomCreation: on).changes
      said = { $0.restrictRoomCreation ? "only administrators create rooms" : "anyone can create rooms" }
    case let .hideTranslations(on):
      changes = AccountSettings(hideTranslationButtons: on).changes
      said = { $0.hideTranslationButtons ? "translation buttons hidden" : "translation buttons shown" }
    case let .icon(slot, name):
      var value = ""
      if let name {
        guard EmberRules.isRoomIcon(name) else { return room.note("\(name): no such icon", kind: .error) }
        if name != slot.defaultIcon { value = name }
      }
      changes = AccountChanges(navigationIcons: [slot.rawValue: value])
      said = { "\(slot.label) icon set to \($0.icon(for: slot))" }
    }
    perform(room) {
      let saved = try await session.api.changeAccount(changes)
      session.admin.answered(saved)
      room.note(said(saved))
    }
  }

  // MARK: Rooms

  private static func order(_ order: AdminCommand.Order, session: InstanceSession, room: RoomModel) {
    let model = session.admin.order
    switch order {
    case .list:
      let rooms = model.rooms(session)
      guard !rooms.isEmpty else { return room.note(NavigationText.noRoomsToArrange) }
      var lines = rooms.enumerated().map { index, item in
        "[\(String(format: "%2d", index + 1))] \(item.room.kind == .closed ? "&" : "#")\(session.title(of: item.room))  (\(item.room.kind == .open ? "everyone" : "selected people"))"
      }
      if model.staged != nil { lines.append(NavigationText.sharedOrderUnsaved + " /order save or /order cancel") }
      room.print(lines)
    case let .move(name, position):
      var ids = model.rooms(session).map(\.id)
      guard let found = session.room(named: name), let from = ids.firstIndex(of: found.id) else { return room.note("#\(name): No such channel", kind: .error) }
      ids.remove(at: from)
      ids.insert(found.id, at: min(position - 1, ids.count))
      model.staged = ids
      model.status = NavigationText.sharedOrderUnsaved
      room.note("#\(name) moved to \(min(position, ids.count)). \(NavigationText.sharedOrderUnsaved) /order save")
    case .save:
      guard model.staged != nil else { return room.note("The room order has no changes to save", kind: .error) }
      model.save(session: session) { room.note(NavigationText.sharedOrderSaved) }
    case .cancel:
      model.cancel()
      room.note("Room move canceled.")
    }
  }

  // MARK: Membership

  /** The ways to join as the cards show them. */
  private static func ways(_ admin: WorkspaceAdmin) -> [String] {
    guard let ways = admin.ways else { return [] }
    func line(_ name: String, _ on: Bool, _ setAside: String?) -> String {
      guard let setAside else { return "\(name) [\(on ? "x" : " ")]" }
      return "\(name) [\(on ? "x" : " ")]  \(setAside)"
    }
    return [
      line("open", ways.open, ways.openSetAside),
      line("link", ways.link, ways.linkSetAside),
      line("domain", ways.emailDomain, ways.emailDomainSetAside),
      line("memberful", ways.memberful, ways.memberfulSetAside) + "  members-only [\(ways.membersOnly ? "x" : " ")]",
      line("sso", ways.sso, ways.ssoSetAside) + "  sso-only [\(ways.ssoOnly ? "x" : " ")]",
      "/join-mode open|link|domain|memberful|members-only|sso|sso-only on|off",
    ]
  }

  /** `/join-mode way on|off`: as the card's switch does, asking first or setting up first where it does. */
  private static func flip(_ way: JoinWay, _ on: Bool, admin: WorkspaceAdmin, session: InstanceSession, room: RoomModel) async throws {
    guard let ways = admin.ways else { return }
    var saving = way
    var asks = true
    switch way {
    case .memberfulJoin:
      guard let flip = ways.memberfulFlip(on) else { return room.note("Memberful is saving; try again in a moment", kind: .error) }
      if on, flip.way == .memberfulJoin, admin.settings?.memberfulSite == nil {
        return openSetup(.memberful, session: session) { [weak admin] in admin?.flip(.memberfulJoin, true) }
      }
      (saving, asks) = (flip.way, flip.asks)
    case .ssoJoin:
      guard let flip = ways.ssoFlip(on) else { return room.note("Single sign-on is saving; try again in a moment", kind: .error) }
      if on, flip.way == .ssoJoin, admin.settings?.sso == nil {
        return openSetup(.sso, session: session) { [weak admin] in admin?.flip(.ssoJoin, true) }
      }
      (saving, asks) = (flip.way, flip.asks)
    case .emailDomainSignUp where on && (!admin.sendsEmail || admin.keptDomains.isEmpty):
      session.openWorkspaceSettings(.membership)
      return admin.flipEmailDomain(true)
    case .openSignUp, .joinLink, .emailDomainSignUp, .memberfulSignIn, .ssoSignIn:
      let setAside: String?
      switch way {
      case .openSignUp: setAside = ways.openSetAside
      case .joinLink: setAside = ways.linkSetAside
      case .emailDomainSignUp: setAside = ways.emailDomainSetAside
      default: setAside = nil
      }
      if let setAside { return room.note(setAside, kind: .error) }
    }
    if on, asks, let question = ways.question(turningOn: saving) {
      session.confirmation = .admin(.turnOn(saving, question: question))
      return
    }
    let saved = try await session.api.changeAccount(AccountChanges(settings: saving.settings(on)))
    admin.answered(saved)
    room.note("\(saving.name) is now \(on ? "on" : "off")")
  }

  private static func printJoinLink(session: InstanceSession, room: RoomModel) async throws {
    let settings = try await session.admin.loaded()
    let administrator = session.me?.administrator == true
    guard let code = settings.joinCode, administrator || session.account?.joinsWithLink == true else {
      return room.note("This workspace has no join link", kind: .error)
    }
    var lines = ["Join link: \(session.joinLink(code))", NavigationText.joinShareText]
    if administrator { lines.append("/joinlink new makes another, which the old one no longer joins with") }
    room.print(lines)
  }

  private static func domains(_ change: AdminCommand.Domains, admin: WorkspaceAdmin, room: RoomModel) {
    perform(room) {
      let settings = try await admin.reloaded()
      let kept = admin.keptDomains
      let typed = { (words: [String]) throws -> [String] in
        let (domains, refused) = WorkspaceRules.emailDomainsTyped(words.joined(separator: " "))
        if let first = refused.first { throw EmberError.refused(422, AdminText.notADomain(first)) }
        return domains
      }
      var domains: [String]
      switch change {
      case .list:
        let on = settings.account.emailDomainSignUp ? "on" : "off"
        return room.print(["Email domain is \(on): \(kept.isEmpty ? "no domains" : kept.joined(separator: ", "))", "/domains add|del|set example.com"])
      case let .add(words):
        domains = kept
        for domain in try typed(words) where !domains.contains(domain) { domains.append(domain) }
      case let .remove(words):
        let removed = Set(try typed(words))
        domains = kept.filter { !removed.contains($0) }
      case let .set(words):
        domains = try typed(words)
      }
      guard domains.count <= EmberLimits.maxEmailDomains else { throw EmberError.refused(422, AdminText.tooManyDomains) }
      admin.answered(try await admin.session.api.changeAccount(AccountChanges(emailDomains: domains)))
      admin.settings?.emailDomains = domains
      room.note("Email domain's domains: \(domains.isEmpty ? "none" : domains.joined(separator: ", "))")
      let free = domains.filter(WorkspaceRules.freeEmailDomains.contains)
      if !free.isEmpty { room.note(AdminText.freeDomains(free), kind: .error) }
    }
  }

  private static func invite(_ text: String, admin: WorkspaceAdmin, session: InstanceSession, room: RoomModel) {
    let (addresses, refused) = EmberRules.emailAddresses(in: text)
    guard refused.isEmpty, !addresses.isEmpty else { return room.note(Invitations.refusal(refused), kind: .error) }
    perform(room) {
      _ = try await admin.loaded()
      var outcomes: [InvitationOutcome] = []
      for batch in Invitations.batches(addresses) {
        let answered = try await session.api.invite(batch)
        outcomes += answered
        admin.settings?.invitations = Invitations.withSaved(admin.settings?.invitations ?? [], answered.compactMap(\.invitation))
        for outcome in answered {
          if outcome.member == true {
            room.note("\(outcome.emailAddress) has an account already")
          } else if let invitation = outcome.invitation {
            if let link = outcome.link {
              admin.inviteLinks[invitation.id] = link
              room.note("invited \(outcome.emailAddress) (link: \(link))")
            } else {
              room.note("invited \(outcome.emailAddress) (emailed)")
            }
          }
        }
      }
      room.note(Invitations.summary(outcomes))
    }
  }

  private static func invites(_ action: AdminCommand.Invites, admin: WorkspaceAdmin, session: InstanceSession, room: RoomModel) {
    perform(room) {
      let invitations = try await admin.reloaded().invitations
      switch action {
      case .list:
        guard !invitations.isEmpty else { return room.note("No pending invitations") }
        room.print(invitations.enumerated().map { index, invitation in
          let inviter = session.people[invitation.invitedBy]?.name ?? EmberText.deletedPersonName
          return "[\(index + 1)] \(invitation.emailAddress)  \(Invitations.status(invitation, inviter: inviter))"
        } + ["/invites resend n · /invites revoke n"])
      case let .resend(n):
        guard invitations.indices.contains(n - 1) else { return room.note("No invitation \(n)", kind: .error) }
        let resent = try await session.api.resendInvitation(invitations[n - 1].id)
        admin.settings?.invitations = Invitations.withSaved(admin.settings?.invitations ?? [], [resent.invitation])
        if let link = resent.link {
          room.note("\(resent.invitation.emailAddress): new link: \(link)")
        } else {
          room.note("\(resent.invitation.emailAddress): emailed again")
        }
      case let .revoke(n):
        guard invitations.indices.contains(n - 1) else { return room.note("No invitation \(n)", kind: .error) }
        session.confirmation = .admin(.revoke(invitations[n - 1]))
      }
    }
  }

  private static func mail(_ action: AdminCommand.Mail, admin: WorkspaceAdmin, session: InstanceSession, room: RoomModel) {
    perform(room) {
      let settings = try await admin.loaded()
      switch action {
      case .status:
        room.note(AdminText.sentWith(settings.email))
      case .test:
        room.note(AdminText.sendingTest)
        room.note(AdminText.testSent(try await session.api.sendTestEmail()))
      case let .from(text):
        guard let mailbox = Mailbox(text) else { return room.note(WorkspaceRules.emailFromRefused, kind: .error) }
        try await admin.saveFrom(mailbox)
        room.note("Email comes from \(mailbox.text)")
      case .stop:
        guard WorkspaceRules.sendsEmail(settings.email) else { return room.note(AdminText.cantSendEmail, kind: .error) }
        session.confirmation = .admin(.stopEmail)
      case .setup:
        openSetup(.email, session: session)
      }
    }
  }

  private static func provider(_ action: AdminCommand.Provider, memberful: Bool, admin: WorkspaceAdmin, session: InstanceSession, room: RoomModel) {
    perform(room) {
      let settings = try await admin.loaded()
      switch action {
      case .status:
        guard let ways = admin.ways else { return }
        if memberful {
          let site = settings.memberfulSite.map { AdminText.memberfulOn($0, webhooks: settings.memberfulWebhooks) } ?? AdminText.memberfulOff
          room.print(["Memberful [\(ways.memberful ? "x" : " ")] members-only [\(ways.membersOnly ? "x" : " ")]", site])
        } else {
          let provider = settings.sso.map { AdminText.ssoSetUp($0, besideMembersOnly: false) } ?? AdminText.ssoOff
          room.print(["Single sign-on [\(ways.sso ? "x" : " ")] sso-only [\(ways.ssoOnly ? "x" : " ")]", provider])
        }
      case let .on(on):
        try await flip(memberful ? .memberfulJoin : .ssoJoin, on, admin: admin, session: session, room: room)
      case let .only(on):
        try await flip(memberful ? .memberfulSignIn : .ssoSignIn, on, admin: admin, session: session, room: room)
      case .setup:
        openSetup(memberful ? .memberful : .sso, session: session)
      case .remove:
        guard settings.sso?.source == .saved else { return room.note("Single sign-on has no saved provider to remove", kind: .error) }
        session.confirmation = .admin(.forgetSso)
      }
    }
  }

  private static func blocked(_ action: AdminCommand.Blocked, admin: WorkspaceAdmin, room: RoomModel) {
    perform(room) {
      switch action {
      case .list:
        let words = try await admin.reloaded().blockedWords
        room.note(words.isEmpty ? "No blocked words" : "Blocked words: \(words.joined(separator: ", "))")
      case let .add(word):
        let words = try await admin.changeBlockedWords { $0 + [word] }
        room.note("Blocked words: \(words.joined(separator: ", "))")
      case let .remove(word):
        let key = BlockedWords.words(of: word).joined(separator: " ")
        let words = try await admin.changeBlockedWords { $0.filter { BlockedWords.words(of: $0).joined(separator: " ") != key } }
        room.note(words.isEmpty ? "No blocked words" : "Blocked words: \(words.joined(separator: ", "))")
      }
    }
  }

  private static func reports(_ n: Int?, _ outcome: ReportOutcome?, admin: WorkspaceAdmin, session: InstanceSession, room: RoomModel) {
    perform(room) {
      await admin.loadReports()
      if let failure = admin.reportsFailure { throw EmberError.refused(500, failure) }
      let open = admin.reports?.open ?? []
      guard let n else {
        guard !open.isEmpty else { return room.note(AdminText.noOpenReports) }
        return room.print(open.enumerated().map { index, report in "[\(index + 1)] \(line(report, admin: admin, session: session))" } + ["/reports n dismiss|delete|remove|ban"])
      }
      guard open.indices.contains(n - 1) else { return room.note("No report \(n)", kind: .error) }
      let report = open[n - 1]
      guard let outcome else { return room.note(line(report, admin: admin, session: session)) }
      guard admin.handlings(for: report).contains(outcome) else { return room.note("Report \(n) can't be handled that way", kind: .error) }
      if outcome == .dismissed {
        admin.handle(report, .dismissed)
        room.note("Report \(n) dismissed")
      } else {
        session.confirmation = .admin(.handle(report, outcome, name: admin.subject(of: report).name))
      }
    }
  }

  /** A report on one line: why, who reported whom, and what. */
  private static func line(_ report: Report, admin: WorkspaceAdmin, session: InstanceSession) -> String {
    let reporter = session.people[report.reporterId]?.name ?? EmberText.deletedPersonName
    var text = "\(report.reason.label.lowercased())  \(reporter) reported \(admin.subject(of: report).name)"
    if case let .message(_, place, message) = report.subject {
      if place.kind == .direct {
        text += " (DM)"
      } else if let name = place.name {
        text += " (\(place.kind == .closed ? "&" : "#")\(name))"
      }
      text += ": \"\(message.plainText.prefix(120))\""
    }
    if !report.note.isEmpty { text += "  note: \"\(report.note)\"" }
    return text
  }

  // MARK: Domain

  private static func domain(_ action: AdminCommand.Domain, app: AppModel, admin: WorkspaceAdmin, session: InstanceSession, room: RoomModel) {
    perform(room) {
      let settings = try await admin.reloaded()
      let here = admin.here
      switch action {
      case .status:
        var lines = ["Ember's address is \(settings.account.customDomain ?? settings.addresses.deployed ?? here)."]
        if let deployed = settings.addresses.deployed { lines.append("Deployed at \(deployed)") }
        lines += admin.otherAddresses(settings).map(admin.otherSays)
        lines.append("/domain check host · /domain use [host] · /domain reset · /domain setup [host]")
        room.print(lines)
      case let .check(typed):
        switch WorkspaceRules.domainTyped(typed) {
        case let .failure(refused): room.note(refused.message, kind: .error)
        case let .success(host):
          let reaches = try await session.api.checkCustomDomain(host)
          if reaches != .ember { admin.settings?.addresses.others.removeAll { $0 == host } }
          switch reaches {
          case .ember: room.note("\(host) still reaches Ember.")
          case .elsewhere: room.note("Something else answers at \(host), not Ember.")
          case .nothing: room.note("\(host) no longer reaches Ember.")
          }
        }
      case let .use(typed):
        guard let typed else { return try await use(here, app: app, admin: admin, session: session, room: room) }
        switch WorkspaceRules.domainTyped(typed) {
        case let .failure(refused): room.note(refused.message, kind: .error)
        case let .success(host): try await use(host, app: app, admin: admin, session: session, room: room)
        }
      case .reset:
        guard let deployed = settings.addresses.deployed else {
          admin.answered(try await session.api.changeAccount(AccountChanges(customDomain: .some(nil))))
          return room.note("Ember no longer has a custom domain")
        }
        try await use(deployed, app: app, admin: admin, session: session, room: room)
      case let .setup(typed):
        if let typed {
          switch WorkspaceRules.domainTyped(typed) {
          case let .failure(refused): return room.note(refused.message, kind: .error)
          case let .success(host): admin.domainToSetUp = host
          }
        }
        session.openWorkspaceSettings(.domain)
      }
    }
  }

  private static func use(_ address: String, app: AppModel, admin: WorkspaceAdmin, session: InstanceSession, room: RoomModel) async throws {
    admin.answered(try await session.api.changeAccount(AccountChanges(customDomain: .some(address))))
    room.note("Ember's address is now \(address). \(AdminText.signsInAgain)")
    if address != admin.here { app.move(session, to: address) }
  }
}

extension AccountSettings {
  /** `{settings}` alone. */
  var changes: AccountChanges { AccountChanges(settings: self) }
}

extension WorkspaceAdmin {
  /** The settings as loaded, loading them first if they aren't yet. */
  func loaded() async throws -> WorkspaceSettings {
    if let settings { return settings }
    return try await reloaded()
  }

  /** The settings as Ember has them now. */
  func reloaded() async throws -> WorkspaceSettings {
    let loaded = try await session.api.workspaceSettings()
    settings = loaded
    session.adoptAccount(loaded.account)
    return loaded
  }
}
