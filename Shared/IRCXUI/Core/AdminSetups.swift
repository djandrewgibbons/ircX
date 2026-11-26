import AppCoreUI
import EmberKit
import SwiftUI

// The setup dialogs Server Settings opens (web `email-setup.tsx`, `turnstile-setup.tsx`,
// `memberful-setup.tsx`, `sso-setup.tsx`). Each saves as it goes; secrets live in SecureFields only while
// the dialog is open, and never in the input line's history.

/** The setup dialog Server Settings has open, in either theme. */
struct AdminSetupSheet: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let setup: AdminSetup
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    Group {
      switch setup {
      case .email: EmailSetup(session: session, admin: admin)
      case .turnstile: TurnstileSetup(session: session, admin: admin)
      case .memberful: MemberfulSetup(admin: admin)
      case .sso: SsoSetupForm(admin: admin)
      }
    }
    .frame(minWidth: 560, minHeight: 520)
    .environment(\.adminNotices, admin)
    .suiteTheme(.ircX)
  }
}

/**
 * A setup dialog's frame: AppCoreUI's SheetFrame over the steps' Form, with an EditorFooter, in Suite; a
 * titled Form with its buttons in the toolbar in IRC Classic.
 */
struct SetupFrame<Content: View>: View {
  let title: String
  let systemImage: String
  let cancelTitle: String
  /** The step's main action, or nil when it has none. */
  let actionTitle: String?
  var canAct = true
  var busy = false
  /** Whether the page has changes a swipe down mustn't lose: Cancel asks about them instead (web `UnsavedChanges`). */
  var keepsOpen = false
  var submit: EditorSubmitShortcut = .return
  let onCancel: () -> Void
  var onAct: () -> Void = {}
  @ViewBuilder let content: () -> Content
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @Environment(\.adminNotices) private var notices

  var body: some View {
    switch look {
    case .suite:
      SheetFrame(title: title, systemImage: systemImage) {
        form
      } footer: {
        EditorFooter(
          canSave: actionTitle != nil && canAct && !busy, canCancel: !busy, saveHelp: actionTitle ?? title, cancelHelp: cancelTitle,
          saveTitle: actionTitle.map { EditorActionTitle($0) }, cancelTitle: EditorActionTitle(cancelTitle), bindsKeyboard: true, submitShortcut: submit,
          onCancel: onCancel, onSave: onAct)
      }
      .interactiveDismissDisabled(busy || keepsOpen)
    case .irc:
      NavigationStack {
        form
          .navigationTitle(title)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(cancelTitle, action: onCancel).disabled(busy) }
            if let actionTitle {
              ToolbarItem(placement: .confirmationAction) { Button(actionTitle, action: onAct).disabled(busy || !canAct) }
            }
          }
      }
      .interactiveDismissDisabled(busy || keepsOpen)
    }
  }

  @ViewBuilder
  private var form: some View {
    switch look {
    case .suite:
      #if os(macOS)
      Form { content() }.sheetFormStyle().modifier(SheetNotice(admin: notices))
      #else
      Form { content() }.formStyle(.grouped).modifier(SheetNotice(admin: notices))
      #endif
    case .irc:
      Form {
        if let notices, let message = notices.message {
          Text("-!- \(message)").foregroundStyle(notices.messageIsError ? irc.part : irc.join).onTapGesture { notices.message = nil }
        }
        content()
      }
      .themedForm(look, irc)
    }
  }
}

extension EnvironmentValues {
  /**
   * The Server Settings whose notices a dialog over it shows: a failure or "Changes saved." from a page
   * open over Server Settings shows on that page, where the administrator is looking, as the web flashes it.
   */
  @Entry var adminNotices: WorkspaceAdmin? = nil
}

/** Server Settings' notice at the bottom of a dialog open over it, in Suite. */
private struct SheetNotice: ViewModifier {
  let admin: WorkspaceAdmin?

  func body(content: Content) -> some View {
    content.safeAreaInset(edge: .bottom) {
      if let admin, let message = admin.message {
        Notice(
          message, systemImage: admin.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
          tint: admin.messageIsError ? SemanticColor.warning : SemanticColor.positive, onDismiss: { admin.message = nil }
        )
        .padding(.horizontal, Spacing.lg)
      }
    }
  }
}

/** A setup's field: its name over it in a filled well in Suite (AppCoreUI's LabeledField), the field alone in IRC Classic. */
struct SetupField<Control: View>: View {
  let title: String
  @ViewBuilder let control: () -> Control
  @Environment(\.appTheme) private var look

  init(_ title: String, @ViewBuilder control: @escaping () -> Control) {
    self.title = title
    self.control = control
  }

  var body: some View {
    switch look {
    case .suite: LabeledField(title) { control().textFieldStyle(.plain) }
    case .irc: control()
    }
  }
}

/** A refusal under the field it's about. */
private struct FieldRefusal: View {
  let refusal: String?

  var body: some View {
    if let refusal { Explanation(refusal, isWarning: true) }
  }
}

// MARK: - Email

/**
 * Set up email (web `EmailSetup`): the provider, its key or its steps, the From address, then a test
 * email, each saved as it goes on. Closing says whether Ember can send email now.
 */
private struct EmailSetup: View {
  enum Step { case provider, resend, cloudflare, from, test }

  let session: InstanceSession
  let admin: WorkspaceAdmin
  @State private var step: Step = .provider
  @State private var provider: EmailProvider = .resend
  @State private var apiKey = ""
  @State private var from = ""
  @State private var refusal: String?
  @State private var saving = false
  @State private var onboarding: (domain: String, onboarded: Bool?, checking: Bool)?
  @State private var tested = false

  private var email: EmailSettings? { admin.settings?.email }

  var body: some View {
    SetupFrame(
      title: title, systemImage: "envelope", cancelTitle: step == .test ? "Close" : "Cancel", actionTitle: step == .test ? "Done" : saving ? "Checking…" : "Continue",
      busy: saving, onCancel: { admin.setupClosed(saved: admin.sendsEmail) }, onAct: next
    ) {
      switch step {
      case .provider: providerStep
      case .resend: resendStep
      case .cloudflare: cloudflareStep
      case .from: fromStep
      case .test: testStep
      }
      FieldRefusal(refusal: refusal)
    }
    .onAppear(perform: start)
  }

  private var title: String {
    switch step {
    case .provider: "Set Up Email"
    case .resend: "Send with Resend"
    case .cloudflare: "Send with Cloudflare"
    case .from: "Choose the From Address"
    case .test: "Send a Test Email"
    }
  }

  private func start() {
    guard let email else { return }
    from = email.from ?? from
    if email.resendKey == .secret {
      provider = .resend
      step = .from
    } else if let current = email.provider {
      provider = current
    } else if email.cloudflare {
      provider = .cloudflare
    }
  }

  @ViewBuilder
  private var providerStep: some View {
    Section {
      Picker("Provider", selection: $provider) {
        Text("Resend").tag(EmailProvider.resend)
        Text("Cloudflare Email Service").tag(EmailProvider.cloudflare).disabled(email?.cloudflare != true)
      }
      .pickerStyle(.inline)
      .labelsHidden()
      Explanation(provider == .resend ? AdminText.resendExplained : AdminText.cloudflareExplained)
      if email?.cloudflare != true { Explanation(AdminText.noEmailBinding) }
    }
  }

  @ViewBuilder
  private var resendStep: some View {
    Section {
      Text("1. \(AdminText.resendDomainStep)")
      OpenLinkButton(title: "Open Resend Domains", url: AdminText.resendDomains)
      Text("2. \(AdminText.resendKeyStep)")
      OpenLinkButton(title: "Open Resend API Keys", url: AdminText.resendApiKeys)
      SetupField("API key") {
        SecureField("API key", text: $apiKey, prompt: Text("re_…"))
          .onChange(of: apiKey) { refusal = nil }
          .onSubmit(next)
      }
    }
  }

  @ViewBuilder
  private var cloudflareStep: some View {
    Section {
      Text("1. \(AdminText.workersPaidStep)")
      OpenLinkButton(title: "Open Workers Plans", url: AdminText.workersPlans)
      Text("2. \(AdminText.onboardStep)")
      OpenLinkButton(title: "Open Email Sending", url: AdminText.emailSendingDashboard)
      if email?.resendKey == .saved { Explanation(AdminText.stopsResend, isWarning: true) }
    }
  }

  @ViewBuilder
  private var fromStep: some View {
    Section {
      SetupField("From") {
        TextField("From", text: $from, prompt: Text("Ember <ember@example.com>"))
          .autocorrectionDisabled()
          #if os(iOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.emailAddress)
          #endif
          .onSubmit(next)
          .onChange(of: from) { refusal = nil }
      }
      Explanation(AdminText.fromExplained(cloudflare: provider == .cloudflare))
      if provider == .cloudflare, let onboarding {
        if onboarding.checking {
          Explanation(AdminText.checkingOnboarded(onboarding.domain))
        } else if let onboarded = onboarding.onboarded {
          if onboarded {
            Explanation(AdminText.onboarded(onboarding.domain))
          } else {
            Explanation(AdminText.notOnboarded(onboarding.domain), isWarning: true)
            OpenLinkButton(title: "Open Email Sending", url: AdminText.emailSendingDashboard)
          }
        } else {
          Explanation(AdminText.onboardingUnknown(onboarding.domain))
        }
      }
    }
    .task(id: from) { await checkOnboarding() }
  }

  @ViewBuilder
  private var testStep: some View {
    Section {
      if let test = admin.testEmail { Explanation(test.text, isWarning: test.isError) }
      Button("Back") { step = .from }
    }
    .onAppear {
      // Once, however often the step shows.
      guard !tested else { return }
      tested = true
      admin.sendTestEmail()
    }
  }

  /**
   * Whether the From address's domain is onboarded to Cloudflare Email Sending, asked 500 ms after typing
   * stops, once a domain (web `useOnboarding`): advice only, which never holds the step up.
   */
  private func checkOnboarding() async {
    guard provider == .cloudflare, let mailbox = Mailbox(from) else { return onboarding = nil }
    let domain = mailbox.domain
    guard onboarding?.domain != domain else { return }
    try? await Task.sleep(for: .milliseconds(500))
    guard !Task.isCancelled else { return }
    onboarding = (domain, nil, true)
    do {
      let onboarded = try await session.api.checkSendingDomain(domain)
      onboarding = (domain, onboarded, false)
    } catch {
      logger.error("Checking \(domain, privacy: .public)'s onboarding failed: \(error.localizedDescription, privacy: .public)")
      onboarding = (domain, nil, false)
    }
  }

  private func next() {
    refusal = nil
    switch step {
    case .provider:
      step = provider == .resend ? .resend : .cloudflare
    case .resend:
      if apiKey.trimmingCharacters(in: .whitespaces).isEmpty, email?.resendKey == .saved { return step = .from }
      guard let key = WorkspaceRules.resendApiKey(of: apiKey) else { return refusal = WorkspaceRules.resendApiKeyRefused }
      save {
        admin.settings?.email = try await session.api.saveResendApiKey(key)
        apiKey = ""
        step = .from
      }
    case .cloudflare:
      save {
        if email?.resendKey == .saved { admin.settings?.email = try await session.api.forgetResendApiKey() }
        step = .from
      }
    case .from:
      guard let mailbox = Mailbox(from) else { return refusal = WorkspaceRules.emailFromRefused }
      if mailbox.text == email?.from { return step = .test }
      save {
        try await admin.saveFrom(mailbox)
        step = .test
      }
    case .test:
      admin.setupClosed(saved: admin.sendsEmail)
    }
  }

  /** Saves a step, saying why it was refused under it, or as the page's alerts do. */
  private func save(_ work: @escaping @MainActor () async throws -> Void) {
    saving = true
    Task {
      do {
        try await work()
      } catch let error as EmberError where [422, 502].contains(error.problem?.status) {
        refusal = error.localizedDescription
      } catch {
        logger.error("Setting up email failed: \(error.localizedDescription, privacy: .public)")
        refusal = error.localizedDescription
      }
      saving = false
    }
  }
}

// MARK: - Turnstile

/**
 * Set up Turnstile (web `TurnstileSetup`): the widget's keys, then Turnstile's own check drawn with them,
 * whose token Ember checks the keys with, then done.
 */
private struct TurnstileSetup: View {
  enum Step { case keys, check, done }

  let session: InstanceSession
  let admin: WorkspaceAdmin
  @State private var step: Step = .keys
  @State private var siteKey = ""
  @State private var secretKey = ""
  @State private var siteRefusal: String?
  @State private var secretRefusal: String?
  @State private var checkRefusal: String?
  @State private var token: String?
  @State private var attempt = 0
  @State private var saving = false

  var body: some View {
    SetupFrame(
      title: "Set Up Turnstile", systemImage: "checkmark.shield", cancelTitle: step == .done ? "Close" : "Cancel",
      actionTitle: step == .keys ? "Continue" : step == .check ? (saving ? "Checking…" : "Waiting for the check…") : "Done", canAct: step != .check,
      busy: saving, onCancel: { admin.setupClosed(saved: step == .done) }, onAct: act
    ) {
      switch step {
      case .keys:
        Section {
          Text(AdminText.turnstileKeysStep(session.instance.host))
          OpenLinkButton(title: "Open Turnstile", url: AdminText.turnstileDashboard)
          if admin.settings?.turnstile != nil { Explanation(AdminText.turnstileKeysKept) }
          SetupField("Site key") {
            TextField("Site key", text: $siteKey, prompt: Text("0x4AAAAAAA…")).autocorrectionDisabled().onChange(of: siteKey) { siteRefusal = nil }
          }
          FieldRefusal(refusal: siteRefusal)
          SetupField("Secret key") {
            SecureField("Secret key", text: $secretKey, prompt: Text("0x4AAAAAAA…")).onChange(of: secretKey) { secretRefusal = nil }
          }
          FieldRefusal(refusal: secretRefusal)
        }
      case .check:
        Section {
          TurnstileCheck(instance: session.instance, siteKey: siteKey, token: $token, attempt: attempt) { code, unavailable in
            let problem = AdminText.turnstileProblem(code: code, unavailable: unavailable, host: session.instance.host)
            if problem.siteKey {
              siteRefusal = problem.message
              step = .keys
            } else {
              checkRefusal = problem.message
            }
          }
          if saving { Explanation(AdminText.turnstileChecking) }
          FieldRefusal(refusal: checkRefusal)
          if checkRefusal != nil {
            Button("Try Again") {
              checkRefusal = nil
              token = nil
              attempt += 1
            }
          }
        }
        .onChange(of: token) { _, token in if let token { check(token) } }
      case .done:
        Section { Text(AdminText.turnstileDone) }
      }
    }
  }

  /** The footer's main action: Continue with the keys, or Done once Ember has them. */
  private func act() {
    switch step {
    case .keys: keysGiven()
    case .check: break
    case .done: admin.setupClosed(saved: true)
    }
  }

  private func keysGiven() {
    guard let site = WorkspaceRules.turnstileKey(of: siteKey) else { return siteRefusal = WorkspaceRules.turnstileSiteKeyRefused }
    guard let secret = WorkspaceRules.turnstileKey(of: secretKey), secret != site else { return secretRefusal = WorkspaceRules.turnstileSecretKeyRefused }
    siteKey = site
    secretKey = secret
    token = nil
    checkRefusal = nil
    attempt += 1
    step = .check
  }

  /** Has Ember check the keys with the token the widget made with them (`PUT /api/account/turnstile_keys`). */
  private func check(_ token: String) {
    saving = true
    Task {
      do {
        admin.settings?.turnstile = try await session.api.saveTurnstileKeys(TurnstileKeysChange(siteKey: siteKey, secretKey: secretKey, turnstileToken: token))
        secretKey = ""
        step = .done
      } catch let error as EmberError where error.problem?.field == "siteKey" || error.problem?.field == "secretKey" {
        if error.problem?.field == "siteKey" { siteRefusal = error.localizedDescription } else { secretRefusal = error.localizedDescription }
        step = .keys
      } catch {
        logger.error("Saving Turnstile's keys failed: \(error.localizedDescription, privacy: .public)")
        checkRefusal = error.localizedDescription
      }
      saving = false
    }
  }
}

// MARK: - Memberful

/**
 * Set up Memberful (web `MemberfulSetup`): the site, the custom app's keys and the webhook's secret, all
 * given again each time, which Ember checks with Memberful before it keeps them.
 */
private struct MemberfulSetup: View {
  let admin: WorkspaceAdmin
  @State private var site = ""
  @State private var apiKey = ""
  @State private var clientId = ""
  @State private var clientSecret = ""
  @State private var webhookSecret = ""
  @State private var refusals: [String: String] = [:]
  @State private var saving = false
  @State private var savedSite: String?

  private var kept: String? { admin.settings?.memberfulSiteKept }
  private var origin: String { admin.publicOrigin }
  private var typedSite: String? { Memberful.site(of: kept ?? site) }

  var body: some View {
    SetupFrame(
      title: "Set Up Memberful", systemImage: "person.badge.key", cancelTitle: savedSite != nil ? "Close" : "Cancel",
      actionTitle: savedSite != nil ? "Done" : saving ? "Checking…" : "Save", canAct: savedSite != nil || filled, busy: saving,
      onCancel: { admin.setupClosed(saved: savedSite != nil) }, onAct: { savedSite != nil ? admin.setupClosed(saved: true) : save() }
    ) {
      if let savedSite {
        Section { Text(AdminText.memberfulTook(savedSite)) }
      } else {
        Section("1. Your Memberful site") {
          if let kept {
            LabeledContent("Address", value: kept)
            Explanation(Memberful.siteKept(kept))
          } else {
            SetupField("Address") { TextField("Address", text: $site, prompt: Text("yoursite.memberful.com")).autocorrectionDisabled() }
            Explanation(AdminText.memberfulSiteHint)
          }
          FieldRefusal(refusal: refusals["site"])
        }
        Section("2. Add a custom app") {
          if let site = typedSite, let page = Memberful.newAppPage(site) { OpenLinkButton(title: "Open Memberful", url: page) }
          Explanation(AdminText.memberfulAppSteps)
          CopyRow(title: "OAuth Redirect URL", value: origin + Memberful.callbackPath)
          SetupField("API Key") { SecureField("API Key", text: $apiKey) }
          FieldRefusal(refusal: refusals["apiKey"])
          SetupField("OAuth Identifier") { TextField("OAuth Identifier", text: $clientId).autocorrectionDisabled() }
          FieldRefusal(refusal: refusals["clientId"])
          SetupField("OAuth Secret") { SecureField("OAuth Secret", text: $clientSecret) }
          FieldRefusal(refusal: refusals["clientSecret"])
        }
        Section("3. Add a webhook") {
          if let site = typedSite, let page = Memberful.newWebhookPage(site) { OpenLinkButton(title: "Open Memberful", url: page) }
          CopyRow(title: "Endpoint URL", value: origin + Memberful.webhookPath)
          Explanation(AdminText.memberfulWebhookSteps)
          SetupField("Secret key") { SecureField("Secret key", text: $webhookSecret) }
          FieldRefusal(refusal: refusals["webhookSecret"])
        }
        Section {
          Explanation(admin.settings?.memberfulKeys == .saved ? AdminText.memberfulKeysKept : AdminText.memberfulKeysChecked)
          if saving { Explanation(AdminText.memberfulAsking) }
          FieldRefusal(refusal: refusals["form"])
        }
      }
    }
  }

  private var filled: Bool {
    [kept ?? site, apiKey, clientId, clientSecret, webhookSecret].allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }

  private func save() {
    let given = kept ?? site
    refusals = [:]
    if let refused = Memberful.refusal(site: given, apiKey: apiKey, clientId: clientId, clientSecret: clientSecret, webhookSecret: webhookSecret) {
      refusals[refused.field] = refused.message
      return
    }
    guard let origin = Memberful.site(of: given), let apiKey = Memberful.key(of: apiKey), let clientId = Memberful.key(of: clientId),
          let clientSecret = Memberful.key(of: clientSecret), let webhookSecret = Memberful.key(of: webhookSecret)
    else { return }
    saving = true
    Task {
      do {
        let saved = try await admin.session.api.saveMemberfulKeys(
          MemberfulKeysChange(site: origin, apiKey: apiKey, clientId: clientId, clientSecret: clientSecret, webhookSecret: webhookSecret))
        admin.settings?.memberfulSite = saved.memberfulSite
        admin.settings?.memberfulWebhooks = saved.memberfulWebhooks
        admin.settings?.memberfulKeys = saved.memberfulKeys
        admin.settings?.memberfulSiteKept = saved.memberfulSiteKept
        self.apiKey = ""
        self.clientSecret = ""
        self.webhookSecret = ""
        savedSite = saved.memberfulSite ?? origin
      } catch let error as EmberError where error.problem?.field != nil {
        refusals[error.problem?.field ?? "form"] = error.localizedDescription
      } catch {
        logger.error("Saving Memberful's keys failed: \(error.localizedDescription, privacy: .public)")
        refusals["form"] = error.localizedDescription
      }
      saving = false
    }
  }
}

/** An address to paste elsewhere, with a button that copies it. */
private struct CopyRow: View {
  let title: String
  let value: String

  var body: some View {
    LabeledContent(title) {
      HStack {
        Text(value).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(value) }.labelStyle(.iconOnly).buttonStyle(.borderless).help("Copy \(title)")
      }
    }
  }
}

// MARK: - Single sign-on

/**
 * Set up single sign-on (web `SsoSetup`): the provider's app, its button name, its scopes and who may
 * sign in, which Ember checks with the provider before it keeps them.
 */
private struct SsoSetupForm: View {
  let admin: WorkspaceAdmin
  @Environment(\.appTheme) private var look
  @State private var issuer = ""
  @State private var clientId = ""
  @State private var clientSecret = ""
  @State private var name = SSO.defaultName
  @State private var scopes = ""
  @State private var groupsClaim = SSO.defaultGroupsClaim
  @State private var allowedGroups = ""
  @State private var linksVerifiedEmails = false
  @State private var refusal: SsoRefusal?
  @State private var saving = false
  @State private var done = false

  private var sso: SsoSettings? { admin.settings?.sso }
  private var fromSecrets: Bool { sso?.source == .secret }
  private var origin: String { admin.publicOrigin }

  /** The saved secret stays only while the issuer and client ID are as saved. */
  private var keepsSecret: Bool {
    guard let sso, sso.source == .saved else { return fromSecrets }
    return sso.issuer == issuer.trimmingCharacters(in: .whitespaces) && sso.clientId == clientId.trimmingCharacters(in: .whitespaces)
  }

  private var filled: Bool {
    fromSecrets || (!issuer.trimmingCharacters(in: .whitespaces).isEmpty && !clientId.trimmingCharacters(in: .whitespaces).isEmpty
      && (keepsSecret || !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty))
  }

  var body: some View {
    SetupFrame(
      title: "Set Up Single Sign-On", systemImage: "person.badge.shield.checkmark", cancelTitle: done ? "Close" : "Cancel",
      actionTitle: done ? "Done" : saving ? "Checking…" : "Save", canAct: done || filled, busy: saving, submit: .commandReturn,
      onCancel: { admin.setupClosed(saved: done) }, onAct: { done ? admin.setupClosed(saved: true) : save() }
    ) {
      if done {
        Section { Text(AdminText.ssoDone) }
      } else {
        Section {
          Text("1. \(AdminText.ssoAppStep)")
          Text("2. \(AdminText.ssoRedirectStep(origin))").textSelection(.enabled)
          Button("Copy Redirect URI", systemImage: "doc.on.doc") { Pasteboard.copy(origin + SSO.callbackPath) }
          Text("3. \(AdminText.ssoLogoutStep(origin))").textSelection(.enabled)
          Text("4. \(fromSecrets ? AdminText.ssoSecretsStep : AdminText.ssoDetailsStep)")
        }
        Section {
          if fromSecrets, let sso {
            LabeledContent("Issuer URL", value: sso.issuer)
            LabeledContent("Client ID", value: sso.clientId)
            Explanation(AdminText.ssoSecretsSet)
          } else {
            SetupField("Issuer URL") { TextField("Issuer URL", text: $issuer, prompt: Text("https://auth.example.com")).autocorrectionDisabled() }
            refused("issuer")
            SetupField("Client ID") { TextField("Client ID", text: $clientId).autocorrectionDisabled() }
            refused("clientId")
            SetupField("Client Secret") { SecureField("Client Secret", text: $clientSecret) }.help(keepsSecret ? AdminText.ssoSecretKept : AdminText.ssoSecretStored)
            Explanation(keepsSecret ? AdminText.ssoSecretKept : AdminText.ssoSecretStored)
            refused("clientSecret")
          }
          SetupField("Button name") { TextField("Button name", text: $name, prompt: Text(SSO.defaultName)) }.help(AdminText.ssoNameHelp)
          refused("name")
          SetupField("Extra scopes") { TextField("Extra scopes", text: $scopes).autocorrectionDisabled() }.help(AdminText.ssoScopesHelp)
          refused("scopes")
          SetupField("Groups claim") {
            TextField("Groups claim", text: $groupsClaim, prompt: Text(SSO.defaultGroupsClaim)).autocorrectionDisabled()
          }
          .help(AdminText.ssoGroupsClaimHelp)
          refused("groupsClaim")
          Group {
            switch look {
            case .suite: PromptEditor("Allowed groups", text: $allowedGroups, minHeight: 60, maxHeight: 160)
            case .irc: TextField("Allowed groups", text: $allowedGroups, axis: .vertical).lineLimit(3...8)
            }
          }
          .autocorrectionDisabled()
          .help(AdminText.ssoGroupsHelp)
          refused("allowedGroups")
          Toggle("Link by Email", isOn: $linksVerifiedEmails).help("Link accounts by verified email. \(AdminText.ssoLinkHelp)")
          #if os(iOS)
          Explanation(AdminText.ssoLinkHelp, isWarning: true)
          #endif
        }
        Section {
          if saving { Explanation(AdminText.ssoContacting) }
          refused("form")
        }
      }
    }
    .onAppear(perform: fill)
  }

  @ViewBuilder
  private func refused(_ field: String) -> some View {
    if let refusal, refusal.field == field { Explanation(refusal.message, isWarning: true) }
  }

  private func fill() {
    guard let sso else { return }
    issuer = sso.issuer
    clientId = sso.clientId
    name = sso.name
    scopes = sso.scopes.joined(separator: " ")
    groupsClaim = sso.groupsClaim
    allowedGroups = sso.allowedGroups.joined(separator: "\n")
    linksVerifiedEmails = sso.linksVerifiedEmails
  }

  private func save() {
    refusal = nil
    let parsed = SSO.setup(
      issuer: fromSecrets ? nil : issuer, clientId: fromSecrets ? nil : clientId, clientSecret: fromSecrets ? nil : clientSecret, name: name, scopes: scopes,
      groupsClaim: groupsClaim, allowedGroups: allowedGroups, linksVerifiedEmails: linksVerifiedEmails)
    let setup: SsoSetup
    switch parsed {
    case let .failure(refused): return refusal = refused
    case let .success(given): setup = given
    }
    saving = true
    Task {
      do {
        admin.settings?.sso = try await admin.session.api.saveSso(setup)
        clientSecret = ""
        done = true
      } catch let error as EmberError where error.problem?.field != nil {
        refusal = SsoRefusal(field: error.problem?.field ?? "form", message: error.localizedDescription)
      } catch {
        logger.error("Saving single sign-on failed: \(error.localizedDescription, privacy: .public)")
        refusal = SsoRefusal(field: "form", message: error.localizedDescription)
      }
      saving = false
    }
  }
}
