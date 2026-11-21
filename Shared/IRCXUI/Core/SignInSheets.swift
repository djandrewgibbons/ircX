import AppCoreUI
import EmberKit
import SwiftUI

// The ways in that open over sign-in, in either theme: joining (the join link, open sign-up, an invitation
// or email link), asking for an email domain's link, resetting a password, and a web view for Memberful
// and single sign-on. Then the welcome page for someone new, an AI app's consent, and first run.

extension View {
  /** The sheets the sign-in screen opens. */
  func signInSheets(_ form: SignInModel) -> some View {
    modifier(SignInSheets(form: form))
  }
}

private struct SignInSheets: ViewModifier {
  @Bindable var form: SignInModel
  @Environment(\.appTheme) private var look

  func body(content: Content) -> some View {
    content.sheet(item: $form.sheet) { sheet in
      Group {
        switch sheet {
        case let .join(model): JoinSheet(model: model)
        case let .emailLink(model): EmailLinkSheet(model: model)
        case let .reset(model): PasswordResetSheet(model: model)
        case let .browser(request):
          BrowserFlowSheet(request: request, instance: form.session.instance, customDomain: form.account?.customDomain) { form.finish($0) }
        }
      }
      .environment(\.appTheme, look)
    }
  }
}

/** A field's problem under it, as the web's forms put one. */
struct FieldProblem: View {
  let text: String?
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    if let text {
      Text(look == .irc ? "-!- \(text)" : text)
        .font(look == .irc ? Theme.font(11) : DesignFont.detail)
        .foregroundStyle(look == .irc ? irc.part : SemanticColor.warning)
    }
  }
}

/** Create your account (web `JoinPage`, invitation and email-link forms), or the first administrator's (`SetupPage`). */
struct JoinSheet: View {
  @Bindable var model: JoinModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    NavigationStack {
      JoinFields(model: model)
        .themedForm(look, irc)
        .navigationTitle(look == .irc ? "/register" : model.title)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button(model.busy ? "Creating…" : "Create Account", action: model.send).disabled(!model.canSend)
          }
        }
    }
    .frame(minWidth: 440, minHeight: 520)
    .task { await model.lookUp() }
  }
}

/** The join form's fields, which first run's form shares. */
struct JoinFields: View {
  @Bindable var model: JoinModel
  @Environment(\.appTheme) private var look

  var body: some View {
    Form {
      Section {
        Text(model.title).font(look == .irc ? Theme.font(16, weight: .bold) : DesignFont.title)
        Text(model.linkGone ?? model.explained).foregroundStyle(model.linkGone == nil ? Color.secondary : SemanticColor.warning)
      }
      if model.linkGone == nil {
        Section {
          PhotoField(photo: $model.photo, refusal: $model.photoRefusal)
          TextField("Name", text: $model.name, prompt: model.placeholders.map { Text($0.name) })
            .textContentType(.name)
            .onChange(of: model.name) { _, name in
              if name.count > EmberLimits.maxUserNameLength { model.name = String(name.prefix(EmberLimits.maxUserNameLength)) }
            }
          FieldProblem(text: model.problems["name"])
          if model.asksEmailAddress {
            TextField("Email", text: $model.emailAddress, prompt: model.placeholders.map { Text($0.emailAddress) }).textContentTypeEmail()
            FieldProblem(text: model.problems["emailAddress"])
          } else {
            LabeledContent("Email", value: model.emailAddress)
          }
          SecureField("Password", text: $model.password)
            .textContentType(.newPassword)
            .help(PeopleText.setupPasswordRule)
            .onSubmit(model.send)
          FieldProblem(text: model.problems["password"])
        }
        if let key = model.turnstileSiteKey {
          Section { TurnstileCheck(instance: model.session.instance, siteKey: key, token: $model.turnstileToken, attempt: model.turnstileTries) }
        }
      }
      if let problem = model.problem {
        Section { FieldProblem(text: problem) }
      }
    }
  }
}

/** Join with an email domain's address (web `EmailSignUpPage`): ask for a link, then paste the one emailed. */
struct EmailLinkSheet: View {
  @Bindable var model: EmailLinkModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    NavigationStack {
      Form {
        if let sent = model.sent {
          Section("Check your email") {
            Text(PeopleText.checkEmailForLink(sent))
            TextField("Emailed Link", text: $model.link, prompt: Text(PeopleText.pasteEmailedLink))
              .autocorrectionDisabled()
              .onSubmit(model.openLink)
            Button("Open Link", action: model.openLink).disabled(model.link.isEmpty)
            #if os(iOS)
            if let mail = URL(string: "message://") { Button("Open Mail") { openURL(mail) } }
            #endif
            Button("Didn't get it? Ask again") { model.sent = nil }
          }
        } else {
          Section {
            Text(model.gone ? EmberText.emailLinkGone : PeopleText.emailLinkExplained)
              .foregroundStyle(model.gone ? SemanticColor.warning : Color.secondary)
            if model.on {
              TextField("Email", text: $model.emailAddress)
                .textContentTypeEmail()
                .help(PeopleText.addressesCanJoin(model.domains))
                .onSubmit(model.send)
              Text(PeopleText.addressesCanJoin(model.domains)).font(DesignFont.detail).foregroundStyle(.secondary)
            }
          }
          if model.on, let key = model.turnstileSiteKey {
            Section { TurnstileCheck(instance: model.session.instance, siteKey: key, token: $model.turnstileToken, attempt: model.turnstileTries) }
          }
        }
        if let problem = model.problem {
          Section { FieldProblem(text: problem) }
        }
      }
      .themedForm(look, irc)
      .navigationTitle(look == .irc ? "/join-email" : PeopleText.joinTitle(model.workspace))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        if model.sent == nil, model.on {
          ToolbarItem(placement: .confirmationAction) {
            Button(model.busy ? "Sending…" : "Email Me a Link", action: model.send).disabled(!model.canSend)
          }
        }
      }
    }
    .frame(minWidth: 440, minHeight: 360)
  }
}

/** Reset your password (web `PasswordResetPage`): an emailed code, then a new password. */
struct PasswordResetSheet: View {
  @Bindable var model: PasswordResetModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    NavigationStack {
      Form {
        if !model.available {
          Section { Text(EmberText.cantEmailCodes) }
        } else if let asked = model.asked {
          Section("Check your email") {
            Text(PeopleText.checkEmailForCode(asked))
            // The account the new password is for, for password managers (web's hidden username field).
            TextField("Email", text: .constant(asked))
              .textContentTypeEmail()
              .disabled(true)
            TextField("Code", text: $model.code, prompt: Text("8-digit code"))
              .textContentType(.oneTimeCode)
              #if os(iOS)
              .keyboardType(.numberPad)
              #endif
            if model.problemField == "code" { FieldProblem(text: model.problem) }
            SecureField("New Password", text: $model.password)
              .textContentType(.newPassword)
              .onSubmit(model.reset)
            if model.problemField == "password" { FieldProblem(text: model.problem) }
            Button("Didn't get it? Send another code") { model.asked = nil }
          }
        } else {
          Section {
            Text(PeopleText.resetExplained).foregroundStyle(.secondary)
            TextField("Email", text: $model.emailAddress)
              .textContentTypeEmail()
              .onSubmit(model.ask)
          }
          if let key = model.turnstileSiteKey {
            Section { TurnstileCheck(instance: model.session.instance, siteKey: key, token: $model.turnstileToken, attempt: model.turnstileTries) }
          }
        }
        if model.problemField != "code", model.problemField != "password", let problem = model.problem {
          Section { FieldProblem(text: problem) }
        }
      }
      .themedForm(look, irc)
      .navigationTitle(look == .irc ? "/reset" : "Reset your password")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        if model.available {
          ToolbarItem(placement: .confirmationAction) {
            if model.asked == nil {
              Button(model.busy ? "Sending…" : "Email Me a Code", action: model.ask).disabled(!model.canAsk)
            } else {
              Button(model.busy ? "Resetting…" : "Reset Password", action: model.reset).disabled(!model.canReset)
            }
          }
        }
      }
    }
    .frame(minWidth: 440, minHeight: 360)
  }
}

/**
 * The welcome page (web `WelcomePage`), for someone new who joined with Memberful or single sign-on: the
 * name and username people see, and a photo. Each saves in turn, and what saved stays if a later one fails.
 */
struct WelcomeSheet: View {
  let session: InstanceSession
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var profile: Profile?
  @State private var name = ""
  @State private var username = ""
  @State private var photo: ChosenPhoto?
  @State private var refusal: String?
  @State private var problem: String?
  @State private var saving = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(PeopleText.welcomeTo(session.name)).font(look == .irc ? Theme.font(16, weight: .bold) : DesignFont.title)
          Text(PeopleText.welcomeExplained).foregroundStyle(.secondary)
        }
        if profile != nil {
          Section {
            PhotoField(photo: $photo, refusal: $refusal, current: currentAvatar)
            TextField("Name", text: $name).textContentType(.name)
            TextField("Username", text: $username, prompt: Text("@username"))
              .autocorrectionDisabled()
              #if os(iOS)
              .textInputAutocapitalization(.never)
              #endif
              .onChange(of: username) { _, typed in
                let kept = EmberRules.username(of: typed)
                if kept != typed { username = String(kept.prefix(EmberLimits.maxUsernameLength)) }
              }
              .help(PeopleText.usernameHelp)
          }
        }
        if let problem { Section { FieldProblem(text: problem) } }
      }
      .themedForm(look, irc)
      .loadingActivity(profile == nil && problem == nil)
      .navigationTitle(look == .irc ? "/nick" : "Welcome")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(saving ? "Saving…" : "Continue", action: save)
            .disabled(saving || profile == nil || name.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty)
        }
      }
    }
    .interactiveDismissDisabled(saving)
    .frame(minWidth: 420, minHeight: 380)
    .task { await load() }
  }

  private var currentAvatar: AnyView? {
    guard let path = profile?.avatarUrl, profile?.avatar == true else { return nil }
    return AnyView(AuthImage(api: session.api, path: path).scaledToFill())
  }

  private func load() async {
    do {
      let loaded = try await session.api.profile().profile
      profile = loaded
      name = loaded.name
      if let saved = loaded.username { username = saved } else { username = EmberRules.username(from: loaded.name) }
    } catch {
      logger.error("Loading the profile failed: \(error.localizedDescription, privacy: .public)")
      problem = error.localizedDescription
    }
  }

  private func save() {
    guard let profile else { return }
    saving = true
    problem = nil
    let changes = ProfileChanges(
      name: name != profile.name ? name.trimmingCharacters(in: .whitespaces) : nil, username: username != profile.username ? username : nil)
    let photo = photo
    Task {
      defer { saving = false }
      do {
        if !changes.isEmpty {
          let answer = try await session.api.changeProfile(changes)
          self.profile = answer.profile
          session.adoptName(answer.profile.name)
        }
      } catch {
        logger.error("Saving the welcome page failed: \(error.localizedDescription, privacy: .public)")
        problem = error.localizedDescription
        return
      }
      if let photo {
        do {
          _ = try await session.api.changeAvatar(photo)
        } catch {
          logger.error("Saving a photo failed: \(error.localizedDescription, privacy: .public)")
          self.photo = nil
          refusal = error.localizedDescription
          return
        }
      }
      dismiss()
    }
  }
}

/** An AI app's request, as a sheet's item. */
struct OutsideAskItem: Identifiable {
  let ask: OutsideAsk
  var id: String { [ask.clientId, ask.state, ask.redirectUri].compactMap { $0 }.joined(separator: "|") }
}

/**
 * Connect an AI app (web `OutsideConnectPage`): what it asked to do as you, the optional parts, and where
 * it goes back to. Allow and Don't allow send the browser back to the app with its answer.
 */
struct OutsideConnectSheet: View {
  let session: InstanceSession
  let ask: OutsideAsk
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var asked: OutsideAsked?
  @State private var with: Set<OutsideScope> = []
  @State private var problem: String?
  @State private var answering = false

  var body: some View {
    NavigationStack {
      Form {
        if let asked {
          let optional = Outside.optionalScopes(asked.scopes)
          Section {
            Text(PeopleText.connectTo(asked.name, workspace: asked.workspace)).font(look == .irc ? Theme.font(16, weight: .bold) : DesignFont.title)
            if let me = session.me { Text(PeopleText.actsAs(me.name)) }
          }
          Section(PeopleText.itWillBeAbleTo) {
            ForEach(asked.scopes.filter { !optional.contains($0) }, id: \.self) { Label($0.explained, systemImage: "checkmark") }
          }
          if !optional.isEmpty {
            Section(PeopleText.andIfYouLetIt) {
              ForEach(optional, id: \.self) { scope in
                Toggle(scope.explained, isOn: Binding(get: { with.contains(scope) }, set: { on in if on { with.insert(scope) } else { with.remove(scope) } }))
              }
            }
          }
          Section {
            Text(PeopleText.goesBackTo(asked.comesBackTo)).foregroundStyle(.secondary)
            Text(PeopleText.disconnectAnyTime).foregroundStyle(.secondary)
          }
        }
        if let problem {
          Section(PeopleText.cantConnect) { FieldProblem(text: problem) }
        }
      }
      .themedForm(look, irc)
      .loadingActivity(asked == nil && problem == nil)
      .navigationTitle(look == .irc ? "/connect" : "Connect an AI App")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(asked == nil ? "Close" : "Don't Allow") { asked == nil ? dismiss() : answer(false) }.disabled(answering)
        }
        if asked != nil {
          ToolbarItem(placement: .confirmationAction) { Button("Allow") { answer(true) }.disabled(answering) }
        }
      }
    }
    .frame(minWidth: 440, minHeight: 420)
    .task { await describe() }
  }

  private func describe() async {
    do {
      let described = try await session.api.describeOutsideAsk(ask)
      asked = described
      with = Set(Outside.optionalScopes(described.scopes).filter { !Outside.untickedScopes.contains($0) })
    } catch {
      logger.error("Reading an AI app's request failed: \(error.localizedDescription, privacy: .public)")
      problem = error.localizedDescription
    }
  }

  private func answer(_ allow: Bool) {
    guard let asked else { return }
    answering = true
    let optional = Outside.optionalScopes(asked.scopes)
    let answer = OutsideAnswer(
      ask: ask, allow: allow, without: allow ? optional.filter { !with.contains($0) } : [], with: allow ? optional.filter { with.contains($0) } : [])
    Task {
      defer { answering = false }
      do {
        let address = try await session.api.answerOutsideAsk(answer)
        guard let url = URL(string: address) else { throw EmberError.notEmber }
        openURL(url)
        dismiss()
      } catch {
        logger.error("Answering an AI app failed: \(error.localizedDescription, privacy: .public)")
        problem = error.localizedDescription
      }
    }
  }
}

/**
 * Set up a new Ember (web `SetupPage`), until whoever deployed it has: the setup password or link it asks
 * for, the first administrator's account, then whether to turn huddles on.
 */
struct SetupView: View {
  let session: InstanceSession
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var secret = ""
  @State private var link = ""
  @State private var checked = false
  @State private var checking = false
  @State private var problem: String?
  @State private var form: JoinModel?

  private var access: SetupAccess { session.bootstrap?.setupAccess ?? .closed }

  var body: some View {
    Group {
      if let form, form.newWorkspace != nil {
        FirstRunHuddles(session: session) { form.openWorkspace(settingUpHuddles: false) }
      } else if let form, checked || access == .open {
        VStack(spacing: 0) {
          JoinFields(model: form).themedForm(look, irc)
          HStack {
            Spacer()
            Button(form.busy ? "Creating…" : "Continue", action: form.send).buttonStyle(.borderedProminent).disabled(!form.canSend)
          }
          .padding()
        }
      } else {
        steps
      }
    }
    .frame(maxWidth: 560)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(look == .irc ? irc.buffer : Color.clear)
    .task(id: session.setupToken) { await checkLinkToken() }
    .onAppear { if access == .open { form = JoinModel(session: session, kind: .setup(nil)) } }
  }

  private var steps: some View {
    Form {
      Section {
        Text(look == .irc ? "*** Set up \(session.instance.host)" : "Set up \(session.instance.host)")
          .font(look == .irc ? Theme.font(16, weight: .bold) : DesignFont.title)
        switch access {
        case .closed:
          Text(PeopleText.setupClosed)
          Button("Copy \(PeopleText.setupEnvironmentVariable)", systemImage: "doc.on.doc") { Pasteboard.copy(PeopleText.setupEnvironmentVariable) }
          Button("Try Again", systemImage: "arrow.clockwise") { Task { await session.start() } }
        case .link:
          Text(PeopleText.setupLinkNeeded)
          TextField("Setup Link", text: $link)
            .autocorrectionDisabled()
            .onSubmit(useLink)
          Button("Continue", action: useLink).disabled(link.isEmpty || checking)
        case .password:
          if session.setupToken != nil, problem == PeopleText.setupLinkStale { Text(PeopleText.setupLinkStale) }
          SecureField("Setup Password", text: $secret)
            .textContentType(.password)
            .help(PeopleText.setupPasswordHelp)
            .onSubmit(check)
          Text(PeopleText.setupPasswordHelp).font(look == .irc ? Theme.font(11) : DesignFont.detail).foregroundStyle(.secondary)
          Button(checking ? "Checking…" : "Continue", action: check).disabled(secret.isEmpty || checking)
        case .open:
          EmptyView()
        }
      }
      if let problem, problem != PeopleText.setupLinkStale { Section { FieldProblem(text: problem) } }
    }
    .themedForm(look, irc)
  }

  private func useLink() {
    guard let parsed = EmberLink.parse(link), case let .firstRun(token?) = parsed.route else {
      problem = "That isn't a setup link."
      return
    }
    session.setupToken = token
  }

  /** A pasted or followed setup link's token is checked first; a stale one asks for the password instead. */
  private func checkLinkToken() async {
    guard let token = session.setupToken, !checked else { return }
    checking = true
    defer { checking = false }
    do {
      try await session.api.checkSetupPassword(token)
      form = JoinModel(session: session, kind: .setup(token))
      checked = true
    } catch {
      refused(error)
      if access == .password { problem = PeopleText.setupLinkStale }
    }
  }

  private func check() {
    checking = true
    problem = nil
    let secret = secret
    Task {
      defer { checking = false }
      do {
        try await session.api.checkSetupPassword(secret)
        form = JoinModel(session: session, kind: .setup(secret))
        checked = true
      } catch {
        refused(error)
      }
    }
  }

  private func refused(_ error: Error) {
    logger.error("Checking the setup secret failed: \(error.localizedDescription, privacy: .public)")
    if case let EmberError.problem(answer) = error, answer.status == 409 {
      // Someone else set it up meanwhile.
      Task { await session.start() }
      return
    }
    problem = error.localizedDescription
  }
}
