import AppCoreUI
import EmberKit
import SwiftUI
import UniformTypeIdentifiers

// Server Settings' General and Membership pages (web `workspace-settings-page.tsx` and its cards).

// MARK: - General

/** General (web `General`): the release card, the icon, the name and tagline, and Hide translation buttons; members read them. */
struct GeneralSettings: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  @Environment(\.appTheme) private var look

  var body: some View {
    if let account = admin.account {
      if admin.isAdministrator {
        if let check = session.releaseCheck { ReleaseCard(admin: admin, check: check) }
        Section("Icon") { LogoPicker(session: session, admin: admin, account: account) }
        Section("Community") {
          TextField(
            "Name", text: Binding(get: { admin.shownName(account) }, set: { admin.typedName = String($0.prefix(EmberLimits.maxAccountNameLength)) }),
            prompt: Text("Name this account")
          )
          .help("Community name, up to \(EmberLimits.maxAccountNameLength) characters")
          TextField(
            "Tagline", text: Binding(get: { admin.shownTagline(account) }, set: { admin.typedTagline = String($0.prefix(EmberLimits.maxTaglineLength)) }),
            prompt: Text("Sum it up in a few words")
          )
          .help("\(AdminText.taglineHelp) \(EmberLimits.maxTaglineLength - admin.shownTagline(account).count) left.")
          Toggle("Hide Translations", isOn: Binding(get: { admin.hideTranslations(account) }, set: { admin.movedHideTranslations = $0 }))
            .help("Hide translation buttons: \(AdminText.hideTranslationsHelp)")
          Button(admin.savingGeneral ? "Saving…" : "Save Changes", action: admin.saveGeneral)
            .disabled(!admin.generalChanged || admin.savingGeneral)
            .keyboardShortcut("s", modifiers: .command)
        }
      } else {
        Section {
          HStack(spacing: Spacing.lg) {
            WorkspaceLogo(session: session, account: account, size: 96)
            VStack(alignment: .leading, spacing: Spacing.xs) {
              Text(account.name).font(look == .irc ? Theme.font(16, weight: .bold) : DesignFont.title)
              if !account.tagline.isEmpty { Text(account.tagline).foregroundStyle(.secondary) }
            }
          }
        }
      }
    }
  }
}

/** The workspace's icon: its logo, public at `/account/logo`, or Ember's flame. */
struct WorkspaceLogo: View {
  let session: InstanceSession
  let account: Account
  var picked: Data?
  var size: CGFloat = 72
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    ZStack {
      Circle().fill(look == .irc ? irc.bar : SemanticColor.secondaryFill)
      if let picked, let image = PlatformImage(data: picked) {
        #if os(macOS)
        Image(nsImage: image).resizable().scaledToFill()
        #else
        Image(uiImage: image).resizable().scaledToFill()
        #endif
      } else if let logo = account.logo {
        AuthImage(api: session.api, path: logo).scaledToFill()
      } else {
        Image(systemName: "flame.fill").font(.system(size: size * 0.4)).foregroundStyle(look == .irc ? irc.ember : SuiteTheme.ircX.accent)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityLabel("\(account.name) icon")
  }
}

/** Upload icon and Remove icon (web `PicturePicker`), saved as they're picked. */
private struct LogoPicker: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let account: Account
  @Environment(\.appTheme) private var look

  var body: some View {
    HStack(spacing: Spacing.lg) {
      WorkspaceLogo(session: session, account: account, picked: admin.pickedLogo, size: 96)
        .opacity(admin.savingLogo ? 0.5 : 1)
        #if os(macOS)
        // An image dropped on the circle is chosen as Upload icon would choose it.
        .dropDestination(for: URL.self) { urls, _ in
          guard let url = urls.first, !admin.savingLogo else { return false }
          dropped(url)
          return true
        }
        .help("Choose a community icon, or drop an image here")
        #endif
      VStack(alignment: .leading, spacing: Spacing.sm) {
        PhotoPickerButton(onPick: admin.changeLogo, onRefused: { admin.say($0, error: true) }) {
          Label(look == .irc ? "[upload icon]" : "Upload Icon", systemImage: "camera")
        }
        .help("Choose a community icon")
        .disabled(admin.savingLogo)
        if account.logo != nil {
          Button(look == .irc ? "[remove icon]" : "Remove Icon", systemImage: "trash", role: .destructive, action: admin.removeLogo)
            .disabled(admin.savingLogo)
        }
      }
    }
  }

  #if os(macOS)
  /** Reads a dropped file as a picked one, refusing what isn't an image. */
  private func dropped(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image), let mime = type.preferredMIMEType else {
      return admin.say("That file isn't an image.", error: true)
    }
    do {
      let data = try Data(contentsOf: url)
      admin.changeLogo(Avatars.chosenPhoto(data, fileName: url.lastPathComponent, contentType: mime))
    } catch {
      admin.failed("Reading the dropped image", error)
    }
  }
  #endif
}

/** The release card (web `EmberVersion`): this Ember's release, a newer one to update to and how, and a beta to try. */
private struct ReleaseCard: View {
  let admin: WorkspaceAdmin
  let check: ReleaseCheck
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    Section(check.heading) {
      Explanation(check.note)
      if let update = check.update {
        Explanation(check.updating.says)
        HStack {
          OpenLinkButton(title: "What's New", url: update.notes, systemImage: "doc.text")
          OpenLinkButton(title: check.updating.label, url: check.updating.url)
        }
      }
      HStack {
        Button("Check for Updates", systemImage: "arrow.clockwise", action: admin.checkForUpdates)
          .disabled(admin.checkingForUpdates)
          .help("Ask GitHub again for Ember's newest release")
        if admin.checkingForUpdates {
          Explanation(AdminText.checkingForUpdates)
        } else if let failed = admin.updateCheckFailed {
          Explanation(failed, isWarning: true)
        } else if let checked = check.checkedAt.flatMap(EmberDate.parse) {
          Explanation("Last checked \(checked.formatted(.relative(presentation: .named))).")
        }
      }
    }
    if let beta = check.betaToTry {
      Section(AdminText.betaToTry(beta.release)) {
        Explanation(check.trying.says)
        HStack {
          OpenLinkButton(title: "What's in It", url: beta.notes, systemImage: "doc.text")
          OpenLinkButton(title: check.trying.label, url: check.trying.url)
        }
      }
      .tint(look == .irc ? irc.part : SemanticColor.destructive)
    }
  }
}

// MARK: - Membership

/**
 * Membership (web `Membership`): for administrators, reports, blocked words, the ways to join, invite by
 * email, email and Turnstile; for members, how people join; then the people for everyone.
 */
struct MembershipSettings: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin

  var body: some View {
    if let settings = admin.settings, let account = admin.account {
      if admin.isAdministrator {
        ReportsSection(session: session, admin: admin)
        BlockedWordsSection(admin: admin)
        if let ways = admin.ways { WaysToJoinSections(session: session, admin: admin, settings: settings, account: account, ways: ways) }
        InviteByEmailSection(session: session, admin: admin, settings: settings)
        EmailSection(admin: admin, email: settings.email)
        TurnstileSection(admin: admin, turnstile: settings.turnstile)
      } else {
        HowPeopleJoin(session: session, settings: settings, account: account)
      }
      PeopleListSection(session: session, admin: admin)
    }
  }
}

/** A way to join's switch row: its title and switch, and why it's set aside, or what it does. */
private struct WayRow: View {
  let title: String
  let description: String
  let setAside: String?
  let isOn: Bool
  var saving = false
  var isWarning = false
  let flip: (Bool) -> Void

  var body: some View {
    Toggle(isOn: Binding(get: { isOn }, set: flip)) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(title).foregroundStyle(setAside == nil ? Color.primary : Color.secondary)
        Explanation(setAside ?? description, isWarning: setAside == nil && isWarning)
      }
    }
    .disabled(setAside != nil || saving)
  }
}

/** Who can join (web `WaysToJoin`): Open, Join link, Email domain, Memberful and Single sign-on, each saved as it's flipped. */
private struct WaysToJoinSections: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let settings: WorkspaceSettings
  let account: Account
  let ways: WaysToJoin

  var body: some View {
    Section {
      WayRow(title: "Open", description: AdminText.openDescription, setAside: ways.openSetAside, isOn: ways.open, saving: admin.moved[.openSignUp] != nil) {
        admin.flip(.openSignUp, $0)
      }
      if ways.open, ways.openSetAside == nil {
        Explanation(AdminText.shareSignUp)
        LinkShare(link: session.publicOrigin + Pages.signUpPath, shareText: NavigationText.joinShareText, name: "sign-up link")
        if !account.restrictRoomCreation { Explanation(AdminText.roomCreationHint) }
        Explanation(settings.turnstile != nil ? AdminText.turnstileSignUps : AdminText.signUpLimits)
        if settings.turnstile == nil { Button("Set Up Turnstile") { admin.open(.turnstile) } }
      }
    } header: {
      Text("Who can join").help(AdminText.whoCanJoin)
    }
    Section {
      WayRow(title: "Join link", description: AdminText.joinLinkDescription, setAside: ways.linkSetAside, isOn: ways.link, saving: admin.moved[.joinLink] != nil) {
        admin.flip(.joinLink, $0)
      }
      if ways.link, ways.linkSetAside == nil, let code = settings.joinCode {
        Explanation(AdminText.shareJoinLink)
        LinkShare(link: session.joinLink(code), shareText: NavigationText.joinShareText, name: "join link")
        Button("Regenerate Join Link", systemImage: "arrow.triangle.2.circlepath", action: admin.regenerateJoinCode)
          .disabled(admin.regeneratingJoinCode)
          .help("Make a new join link, which the old one no longer joins with")
      }
    }
    EmailDomainSection(session: session, admin: admin, settings: settings, ways: ways)
    MemberfulSection(admin: admin, settings: settings, ways: ways)
    SingleSignOnSection(admin: admin, settings: settings, ways: ways)
  }
}

/** Email domain (web `EmailDomainSettings`): its switch, then its domains, link and limits while it's on. */
private struct EmailDomainSection: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let settings: WorkspaceSettings
  let ways: WaysToJoin

  var body: some View {
    @Bindable var admin = admin
    let emails = admin.sendsEmail
    let checked = ways.emailDomain
    let on = checked || admin.addingDomains
    let setAside = ways.emailDomainSetAside
    Section {
      WayRow(
        title: "Email domain",
        description: emails ? AdminText.emailDomainDescription : checked ? AdminText.emailDomainOnWithoutEmail : AdminText.emailDomainOffWithoutEmail,
        setAside: setAside, isOn: on, saving: admin.savingDomains || admin.moved[.emailDomainSignUp] != nil, isWarning: checked && !emails,
        flip: admin.flipEmailDomain)
      if checked, !emails, setAside == nil {
        Button("Set Up Email") { admin.open(.email) }
      }
      if on, setAside == nil {
        HStack {
          TextField("Add a domain", text: $admin.typedDomain, prompt: Text("example.com"))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .onSubmit(admin.addDomains)
            .onChange(of: admin.typedDomain) { admin.domainRefusal = nil }
          Button("Add", action: admin.addDomains).disabled(admin.typedDomain.trimmingCharacters(in: .whitespaces).isEmpty || admin.savingDomains)
        }
        if let refusal = admin.domainRefusal { Explanation(refusal, isWarning: true) }
        domains
        if admin.addingDomains || admin.domainsDraft != nil {
          Button(admin.addingDomains ? "Save and Turn On" : "Save Domains", action: admin.saveDomains)
            .disabled(admin.savingDomains || admin.listedDomains.isEmpty)
        }
        if checked {
          Explanation(AdminText.shareEmailSignUp)
          LinkShare(link: session.publicOrigin + Pages.emailSignUpPath, shareText: NavigationText.joinShareText, name: "email sign-up link")
        }
        Explanation("\(AdminText.emailLinkLimit) \(settings.turnstile != nil ? AdminText.turnstileEmailLinks : AdminText.emailLinksPerNetwork)")
        if settings.turnstile == nil { Button("Set Up Turnstile") { admin.open(.turnstile) } }
      }
    }
  }

  /** The domains listed, each a chip that removes it, and a warning for any anyone can have an address at. */
  @ViewBuilder
  private var domains: some View {
    let listed = admin.listedDomains
    if listed.isEmpty {
      Explanation(WorkspaceRules.noEmailDomains)
    } else {
      FlowLayout(hSpacing: Spacing.xs, vSpacing: Spacing.xs) {
        ForEach(listed, id: \.self) { domain in
          Button {
            admin.removeDomain(domain)
          } label: {
            Label(domain, systemImage: "xmark").labelStyle(TrailingIconLabelStyle())
          }
          .buttonStyle(.bordered)
          .disabled(admin.savingDomains)
          .accessibilityLabel("Remove \(domain)")
        }
      }
    }
    let free = listed.filter(WorkspaceRules.freeEmailDomains.contains)
    if !free.isEmpty { Explanation(AdminText.freeDomains(free), isWarning: true) }
  }
}

/** A chip's symbol after its title, as a chip that removes what it names shows it. */
private struct TrailingIconLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: Spacing.xs) {
      configuration.title
      configuration.icon
    }
  }
}

/** Memberful (web `MemberfulSettings`): its switch, Members only, and its addresses and keys while it's on. */
private struct MemberfulSection: View {
  let admin: WorkspaceAdmin
  let settings: WorkspaceSettings
  let ways: WaysToJoin

  private var description: String {
    if let closed = ways.memberfulClosed { return closed }
    guard let site = settings.memberfulSite else { return ways.memberful ? AdminText.memberfulKeysGone : AdminText.memberfulOff }
    return AdminText.memberfulOn(site, webhooks: settings.memberfulWebhooks)
  }

  var body: some View {
    Section {
      WayRow(
        title: "Memberful", description: description, setAside: ways.memberfulSetAside, isOn: ways.memberfulChecked, saving: ways.memberfulSaving,
        isWarning: ways.memberful && settings.memberfulSite == nil, flip: admin.flipMemberful)
      if ways.memberful, ways.memberfulSetAside == nil {
        if let beside = ways.memberfulBeside {
          Explanation(beside)
        } else {
          Toggle(isOn: Binding(get: { ways.membersOnly }, set: { admin.flip(.memberfulSignIn, $0) })) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
              Text("Members only")
              Explanation(AdminText.membersOnlyDescription)
            }
          }
          .disabled(admin.moved[.memberfulSignIn] != nil)
        }
        Explanation(AdminText.memberfulAddresses(admin.publicOrigin))
        if settings.memberfulKeys == .secret, !settings.memberfulWebhooks { Explanation(AdminText.memberfulWebhookSecrets) }
        if settings.memberfulKeys == .saved { Button("Change Keys") { admin.open(.memberful) } }
      }
    }
  }
}

/** Single sign-on (web `SingleSignOnSettings`): its switch, SSO only, and Change settings and Remove while it's set up. */
private struct SingleSignOnSection: View {
  let admin: WorkspaceAdmin
  let settings: WorkspaceSettings
  let ways: WaysToJoin

  private var description: String {
    if let closed = ways.ssoClosed { return closed }
    guard let sso = settings.sso else { return ways.sso ? AdminText.ssoOnWithoutProvider : AdminText.ssoOff }
    return AdminText.ssoSetUp(sso, besideMembersOnly: ways.membersOnly && !ways.ssoOnly)
  }

  var body: some View {
    Section {
      WayRow(
        title: "Single sign-on", description: description, setAside: ways.ssoSetAside, isOn: ways.ssoChecked, saving: ways.ssoSaving,
        isWarning: ways.sso && settings.sso == nil, flip: admin.flipSso)
      if ways.sso, ways.ssoSetAside == nil {
        if let beside = ways.ssoBeside {
          Explanation(beside)
        } else {
          Toggle(isOn: Binding(get: { ways.ssoOnly }, set: { admin.flip(.ssoSignIn, $0) })) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
              Text("SSO only")
              Explanation(AdminText.ssoOnlyDescription)
            }
          }
          .disabled(admin.moved[.ssoSignIn] != nil)
        }
      }
      if let sso = settings.sso {
        HStack {
          Button("Change Settings") { admin.open(.sso) }
          if sso.source == .saved {
            Button("Remove", role: .destructive) { admin.confirming = .forgetSso }
              .help(AdminText.confirmForgetSso)
          }
        }
      }
    }
  }
}

/** Invite by email (web `InviteByEmail`): addresses to invite, and the invitations no one has accepted yet. */
private struct InviteByEmailSection: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let settings: WorkspaceSettings

  var body: some View {
    @Bindable var admin = admin
    let emails = admin.sendsEmail
    Section("Invite by email") {
      Explanation(emails ? AdminText.inviteEmails : AdminText.inviteWithoutEmail)
      if !emails { Button("Set Up Email") { admin.open(.email) } }
      TextField("Email addresses", text: $admin.inviteText, prompt: Text("ann@example.com, bob@example.com"), axis: .vertical)
        .lineLimit(3...6)
        .labelsHidden()
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
        #endif
        .disabled(admin.sendingInvites)
      Button(emails ? "Send Invitations" : "Create Invite Links", action: admin.sendInvitations)
        .disabled(admin.sendingInvites || admin.inviteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if let outcome = admin.inviteOutcome { Explanation(outcome, isWarning: admin.inviteRefused) }
    }
    if !settings.invitations.isEmpty {
      Section("Pending invitations") {
        ForEach(settings.invitations) { invitation in
          PendingInvitationRow(session: session, admin: admin, invitation: invitation, emails: emails)
        }
      }
    }
  }
}

private struct PendingInvitationRow: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let invitation: EmailInvitation
  let emails: Bool

  private var refused: Bool {
    if case .refused = invitation.delivery { return true }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(invitation.emailAddress)
      Explanation(Invitations.status(invitation, inviter: session.people[invitation.invitedBy]?.name ?? EmberText.deletedPersonName), isWarning: refused)
      HStack {
        if let link = admin.inviteLinks[invitation.id] {
          Button("Copy Link", systemImage: "doc.on.doc") { Pasteboard.copy(link) }.help("Copy invite link")
        }
        Button(emails ? "Send Again" : "New Link") { admin.resend(invitation) }.disabled(admin.sendingInvites)
        Button("Revoke", role: .destructive) { admin.confirming = .revoke(invitation) }.disabled(admin.sendingInvites)
      }
      .buttonStyle(.borderless)
    }
  }
}

/** Email (web `EmailSettings`): how Ember sends email, a test, Change and Stop, or Set up email. */
private struct EmailSection: View {
  let admin: WorkspaceAdmin
  let email: EmailSettings

  var body: some View {
    Section("Email") {
      Explanation(AdminText.sentWith(email))
      if WorkspaceRules.sendsEmail(email) {
        HStack {
          Button("Send Test Email", action: admin.sendTestEmail).help("Send me a test email")
          Button("Change") { admin.open(.email) }
          Button("Stop Sending", role: .destructive) { admin.confirming = .stopEmail }.help("Stop sending email")
        }
        if let test = admin.testEmail { Explanation(test.text, isWarning: test.isError) }
      } else {
        Button("Set Up Email") { admin.open(.email) }
      }
    }
  }
}

/** Turnstile (web `TurnstileSettings`): on while it has keys, which turning it on sets up and off forgets. */
private struct TurnstileSection: View {
  let admin: WorkspaceAdmin
  let turnstile: KeySource?

  var body: some View {
    Section("Turnstile") {
      Toggle(isOn: Binding(get: { turnstile != nil }, set: { on in if on { admin.open(.turnstile) } else { admin.confirming = .stopTurnstile } })) {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text("Turnstile")
          Explanation(turnstile == nil ? AdminText.turnstileOff : AdminText.turnstileOn(secret: turnstile == .secret))
        }
      }
      .disabled(turnstile == .secret)
      if turnstile == .saved { Button("Change Keys") { admin.open(.turnstile) } }
    }
  }
}

/** Blocked words (web `BlockedWordsSettings`): one a line, saved once they differ from what's kept. */
private struct BlockedWordsSection: View {
  let admin: WorkspaceAdmin

  var body: some View {
    Section {
      TextField(
        AdminText.blockedWordsField,
        text: Binding(get: { admin.shownBlockedWords }, set: { admin.typedBlockedWords = $0; admin.blockedRefusal = nil }), axis: .vertical
      )
      .lineLimit(4...10)
      .labelsHidden()
      .help(AdminText.blockedWordsExplained)
      if let refusal = admin.blockedRefusal { Explanation(refusal, isWarning: true) }
      if admin.blockedWordsChanged {
        Button(admin.savingBlockedWords ? "Saving…" : "Save Blocked Words", action: admin.saveBlockedWords).disabled(admin.savingBlockedWords)
      }
    } header: {
      Text("Blocked words").help(AdminText.blockedWordsExplained)
    }
  }
}

/** Reports (web `ReportsList`): the open ones, newest first, each to handle, and the handled ones. */
private struct ReportsSection: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  private var openCount: Int {
    guard let open = admin.reports?.open.count else { return 0 }
    guard open >= Reporting.openReportsListed, let counted = session.openReports else { return open }
    return max(counted, open)
  }

  var body: some View {
    let open = admin.reports?.open ?? []
    Section {
      if let failure = admin.reportsFailure { Explanation(failure, isWarning: true) }
      if admin.reports != nil, open.isEmpty { Explanation(AdminText.noOpenReports) }
      if open.count >= Reporting.openReportsListed { Explanation(AdminText.showingNewest) }
      ForEach(open) { report in ReportRow(session: session, admin: admin, report: report) }
      if let handled = admin.reports?.handled, !handled.isEmpty {
        DisclosureGroup("Handled (\(handled.count))") {
          ForEach(handled) { report in ReportRow(session: session, admin: admin, report: report) }
        }
      }
    } header: {
      HStack {
        Label("Reports", systemImage: "flag")
        if openCount > 0 { Text("\(openCount) open").foregroundStyle(look == .irc ? irc.ember : SemanticColor.warning) }
      }
      .help(AdminText.reportsExplained)
    }
    .task(id: session.reportsHeard) { await admin.loadReports() }
  }
}

/** One report: why, who reported it and when, what it's of as it was, and what can be done. */
private struct ReportRow: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let report: Report
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  private func name(_ id: UserID) -> String {
    guard id != session.me?.id else { return "you" }
    return session.people[id]?.name ?? EmberText.deletedPersonName
  }

  private func when(_ text: String) -> String {
    guard let date = EmberDate.parse(text) else { return text }
    return date.formatted(date: .abbreviated, time: .shortened)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        switch look {
        case .suite: StatusCapsule(text: report.reason.label, tint: SemanticColor.warning, help: "Reason")
        case .irc: Text("[\(report.reason.label.lowercased())]").foregroundStyle(irc.ember)
        }
        Explanation("Reported by \(name(report.reporterId)), \(when(report.reportedAt))")
      }
      if !report.note.isEmpty { Text("\u{201C}\(report.note)\u{201D}") }
      subject
      if let handled = report.handled {
        Explanation("\(handledAs(handled.outcome)) by \(name(handled.by)), \(when(handled.at))")
      } else {
        HStack {
          ForEach(admin.handlings(for: report), id: \.self) { outcome in
            Button(title(outcome), role: outcome == .dismissed ? nil : .destructive) { admin.ask(report, outcome) }
          }
        }
        .buttonStyle(.borderless)
        .disabled(admin.handling.contains(report.id))
      }
    }
    .padding(.vertical, Spacing.xs)
  }

  @ViewBuilder
  private var subject: some View {
    switch report.subject {
    case let .message(_, room, message):
      if message.accountDeleted == true {
        Explanation("Deleted with their account")
      } else {
        HStack(spacing: Spacing.xs) {
          Button(message.creator.name) { showPerson(message.creator.id) }
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(look == .irc ? irc.link : Color.accentColor)
            .help("Open \(message.creator.name)'s page")
          Text(place(room)).fontWeight(.semibold)
        }
        said(message)
        if let file = message.attachment { Explanation("File: \(file.name)") }
        Explanation("Written \(when(message.createdAt))\(message.editedAt != nil ? ", edited before it was reported" : "")")
      }
    case let .person(person):
      if person.accountDeleted == true {
        Explanation("Name and bio deleted with their account")
      } else {
        Text(personName(person)).fontWeight(.semibold)
        if let bio = person.bio, !bio.isEmpty { Text(bio) } else { Explanation("No bio") }
      }
    }
  }

  /**
   * What the message said, as the room shows it in Suite (its markup, mentions and bot cards, whose buttons
   * do nothing here), and as its plain text in IRC Classic.
   */
  @ViewBuilder
  private func said(_ message: ReportedMessage) -> some View {
    switch look {
    case .suite:
      if message.attachment == nil, !message.body.isEmpty, let blocks = RichLayout.blocks(message.body, plainText: message.plainText, host: session.instance.host) {
        SuiteMessageBody(session: session, blocks: blocks, mentions: message.mentions)
      } else if !message.plainText.isEmpty {
        Text(message.plainText).textSelection(.enabled)
      }
      if let cards = message.cards, !cards.isEmpty {
        SuiteBotCards(session: session, cards: cards, onAction: nil).disabled(true)
      }
    case .irc:
      if !message.plainText.isEmpty { Text(message.plainText).lineLimit(6).textSelection(.enabled) }
    }
  }

  /** Their page, in the server's window, the sheet closing first on iOS. */
  private func showPerson(_ id: UserID) {
    #if os(iOS)
    session.showingWorkspaceSettings = false
    #endif
    session.show(.person(id))
  }

  private func place(_ room: ReportSubject.RoomOf) -> String {
    guard room.kind != .direct else { return "in a direct message" }
    guard let name = room.name else { return "in a room" }
    return "in \(room.kind == .closed ? "&" : "#")\(name)"
  }

  /** Their name as reported, and as it is now if it's changed. */
  private func personName(_ person: ReportedPerson) -> String {
    guard let now = session.people[person.id]?.name, now != person.name else { return person.name }
    return "\(person.name) (now \(now))"
  }

  private func title(_ outcome: ReportOutcome) -> String {
    let person = admin.subject(of: report).name
    switch outcome {
    case .deleted: return "Delete Message"
    case .removed: return "Remove \(person)"
    case .banned: return "Ban \(person)"
    case .dismissed: return "Dismiss"
    }
  }

  /** `HANDLED_AS` */
  private func handledAs(_ outcome: ReportOutcome) -> String {
    switch outcome {
    case .deleted: "Message deleted"
    case .removed: "Removed"
    case .banned: "Banned"
    case .dismissed: "Dismissed"
    }
  }
}

/** How new people join, for members (web `HowPeopleJoin`): the links that let people in, or how they join. */
private struct HowPeopleJoin: View {
  let session: InstanceSession
  let settings: WorkspaceSettings
  let account: Account

  var body: some View {
    let open = account.signsUpOpenly
    let linkCode = account.joinsWithLink ? settings.joinCode : nil
    let emailDomain = !open && account.signsUpWithEmailDomain
    Section("How people join") {
      if !open, linkCode == nil, !emailDomain {
        Text(sentence)
      }
      if open {
        Explanation(AdminText.shareSignUp)
        LinkShare(link: session.publicOrigin + Pages.signUpPath, shareText: NavigationText.joinShareText, name: "sign-up link")
      }
      if emailDomain {
        Explanation(AdminText.shareWithPeopleAt(account.emailDomains))
        LinkShare(link: session.publicOrigin + Pages.emailSignUpPath, shareText: NavigationText.joinShareText, name: "email sign-up link")
      }
      if let linkCode {
        Explanation(AdminText.shareJoinLink)
        LinkShare(link: session.joinLink(linkCode), shareText: NavigationText.joinShareText, name: "join link")
      }
    }
  }

  private var sentence: String {
    if account.memberfulSignIn && account.ssoSignIn { return AdminText.membersSignInElsewhere }
    if account.memberfulSignIn { return AdminText.membersSignInWithMemberful }
    if account.ssoSignIn { return AdminText.workspaceUsesSso }
    if account.memberfulJoin, let site = settings.memberfulSite { return AdminText.membersOf(site, sso: account.ssoJoin) }
    return account.ssoJoin ? AdminText.newPeopleJoinWithSso : AdminText.onlyInvited
  }
}
