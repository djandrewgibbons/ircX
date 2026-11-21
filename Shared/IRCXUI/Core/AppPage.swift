import AppCoreUI
import EmberKit
import SwiftUI

// Connect an app and an app's page (web `app-page.tsx`, `app-signed-in-page.tsx`): its name, its MCP
// server's address and token, or the sign-in to its server, which runs in a web view of ircX's own and
// finishes natively; the tools Ember read from it, Read its tools again, and Remove app.

@MainActor
@Observable
final class AppEditor {
  enum Busy { case saving, reading, signingIn }

  @ObservationIgnored unowned let session: InstanceSession
  let appId: AppID?
  var app: EmberKit.App?
  var name = ""
  var url = ""
  var token = ""
  var noToken = false
  var clientId = ""
  var clientSecret = ""
  var busy: Busy?
  var loadFailure: String?
  /** Why the form was refused, and whether the server wants a sign-in, or a client ID first. */
  var refusal: EmberProblem?
  var askedClient = false
  /** Why reading the tools again failed, and whether a sign-in would fix it. */
  var unread: String?
  var unreadOffersSignIn = false
  var notice: String?
  var browser: BrowserFlowRequest?

  init(session: InstanceSession, appId: AppID?) {
    self.session = session
    self.appId = appId
  }

  private var ai: AIAdmin { session.admin.ai }

  func load() async {
    guard let appId else { return }
    do {
      show(try await session.api.app(appId))
    } catch {
      logger.error("Loading an app failed: \(error.localizedDescription, privacy: .public)")
      if (error as? EmberError) == .signedOut { return session.sessionEnded() }
      loadFailure = error.localizedDescription
    }
  }

  private func show(_ app: EmberKit.App) {
    self.app = app
    name = app.name
    url = app.url
    token = ""
    noToken = false
    if let kept = app.signIn?.clientId { clientId = kept }
    clientSecret = ""
  }

  var signedIn: Bool { app?.signIn != nil }

  /** `changesOf`: only what's changed, so saving doesn't put back what another administrator saved since. */
  var changes: AppChanges {
    guard let app else { return AppChanges() }
    var changes = AppChanges()
    if name.trimmingCharacters(in: .whitespaces) != app.name { changes.name = name }
    if !signedIn, url.trimmingCharacters(in: .whitespaces) != app.url { changes.url = url }
    if noToken {
      changes.token = ""
    } else if !token.trimmingCharacters(in: .whitespaces).isEmpty {
      changes.token = token
    }
    return changes
  }

  var changed: Bool {
    guard busy == nil else { return false }
    guard app != nil else { return !name.trimmingCharacters(in: .whitespaces).isEmpty && !url.trimmingCharacters(in: .whitespaces).isEmpty }
    let changes = changes
    return changes.name != nil || changes.url != nil || changes.token != nil
  }

  /** Whether to ask for a client ID: the server asked for one, or the app signs in with one already. */
  var asksClient: Bool { askedClient || app?.signIn?.clientId != nil }

  /** Whether to offer a sign-in: the server asked for one, or the app signs in already. */
  var offersSignIn: Bool { refusal?.signIn == true || refusal?.client == true || asksClient || unreadOffersSignIn || signedIn }

  var redirectAddress: String { session.instance.origin + AppRules.signedInPath }

  func refused(_ field: String) -> String? { refusal?.field == field ? refusal?.message : nil }

  /** A refusal no field shows, which shows under the form. */
  var generalRefusal: String? {
    guard let refusal else { return nil }
    if let field = refusal.field, ["name", "url", "token", "clientId", "clientSecret"].contains(field) { return nil }
    return refusal.message
  }

  /** Sends `request`, holding the form meanwhile, then `done`, or a 422 on the form, or else the page's alert. */
  private func send<T>(
    _ doing: Busy, _ request: @escaping @MainActor () async throws -> T, done: @escaping @MainActor (T) -> Void,
    refused: (@MainActor (EmberProblem) -> Void)? = nil
  ) {
    busy = doing
    refusal = nil
    unread = nil
    unreadOffersSignIn = false
    if doing != .signingIn { notice = nil }
    Task {
      defer { busy = nil }
      do {
        done(try await request())
      } catch {
        if let problem = (error as? EmberError)?.problem, problem.status == 422 {
          logger.error("The app was refused: \(problem.message, privacy: .public)")
          if let refused { refused(problem) } else { refusal = problem }
          if problem.client { askedClient = true }
        } else {
          session.admin.failed("Changing the app", error)
        }
      }
    }
  }

  /** Connect, or Save changes: the Worker reads the server's tools first, when its address or token is new. */
  func save() {
    if let app {
      let changes = changes
      let rereads = changes.url != nil || changes.token != nil
      send(.saving, { try await self.session.api.changeApp(app.id, changes) }) { saved in
        self.show(saved)
        self.notice = rereads ? AIText.savedRead(saved.name, tools: saved.tools.count) : AdminText.saved
        Task { await self.ai.loadApps() }
      }
    } else {
      let typed = token.trimmingCharacters(in: .whitespaces)
      let new = AppChanges(name: name, url: url, token: typed.isEmpty ? nil : token)
      send(.saving, { try await self.session.api.connectApp(new) }) { connected in
        self.show(connected)
        self.notice = AIText.connected(connected.name, tools: connected.tools.count)
        Task { await self.ai.loadApps() }
      }
    }
  }

  /** Read its tools again: what's typed stays, and a refusal says why, offering a sign-in when that would fix it. */
  func readAgain() {
    guard let app else { return }
    send(.reading, { try await self.session.api.readAppTools(app.id) }) { read in
      self.app = read
    } refused: { problem in
      self.unread = problem.message
      self.unreadOffersSignIn = problem.signIn
    }
  }

  /** Sign in to its server: Ember finds the sign-in, then the web view goes to it. */
  func signIn() {
    let secret = clientSecret.trimmingCharacters(in: .whitespaces)
    let client = AppClient(clientId: clientId.trimmingCharacters(in: .whitespaces), clientSecret: secret.isEmpty ? nil : clientSecret)
    let asksClient = asksClient
    let app = app
    let name = name
    let url = url
    send(.signingIn, {
      if let app { return try await self.session.api.beginAppSignIn(app.id, client: asksClient ? client : nil) }
      var new = client
      new.name = name
      new.url = url
      if !asksClient { new.clientId = nil }
      return try await self.session.api.beginNewAppSignIn(new)
    }) { address in
      guard let start = URL(string: address) else {
        logger.error("The sign-in's address isn't one: \(address, privacy: .public)")
        self.refusal = EmberProblem(status: 422, message: "Ember's sign-in address for this app didn't make sense.")
        return
      }
      self.browser = BrowserFlowRequest(title: AIText.signInTo(url), start: start)
    }
  }

  /** The web view came back to Ember's `/account/apps/signed-in`: the sign-in is finished here, as the web's return page does. */
  func finish(_ outcome: BrowserFlowOutcome) {
    guard case let .ended(end, _) = outcome, case let .appSignIn(state, code, iss, error) = end else { return }
    if error == "access_denied" { return notice = PeopleText.signInTurnedDown }
    guard error == nil, let state, let code else { return notice = PeopleText.signInNotFinished }
    notice = AIText.finishingSignIn
    send(.signingIn, { try await self.session.api.finishAppSignIn(AppSignInReturn(state: state, code: code, iss: iss)) }) { finished in
      guard case let .app(app, again) = finished else { return }
      self.show(app)
      self.notice = again ? AIText.signedInAgain(app.name) : AIText.connected(app.name, tools: app.tools.count)
      Task { await self.ai.loadApps() }
    }
  }
}

/** Connect an app, or an app's page, in either theme. */
struct AppPage: View {
  let session: InstanceSession
  let onClose: () -> Void
  @State private var editor: AppEditor
  @State private var removing = false
  @Environment(\.appTheme) private var look

  init(session: InstanceSession, appId: AppID?, onClose: @escaping () -> Void) {
    self.session = session
    self.onClose = onClose
    _editor = State(initialValue: AppEditor(session: session, appId: appId))
  }

  private var ai: AIAdmin { session.admin.ai }

  var body: some View {
    @Bindable var editor = editor
    SetupFrame(
      title: editor.app == nil ? "Connect an App" : "Edit App", systemImage: "puzzlepiece.extension", cancelTitle: "Close",
      actionTitle: editor.busy == .saving ? AIText.readingTools : editor.app == nil ? "Connect" : "Save Changes", canAct: editor.changed, busy: editor.busy != nil,
      onCancel: onClose, onAct: editor.save
    ) {
      if let failure = editor.loadFailure {
        Section { StatusLine(failure, tone: .warning) }
      } else if editor.appId != nil, editor.app == nil {
        Section { Color.clear.frame(height: 40).loadingActivity(true) }
      } else {
        form
      }
    }
    .task { await editor.load() }
    .sheet(item: $editor.browser) { request in
      BrowserFlowSheet(request: request, instance: session.instance, customDomain: session.account?.customDomain) { editor.finish($0) }
        .environment(\.appTheme, look)
        .frame(minWidth: 520, minHeight: 640)
    }
    .confirmationDialog("Remove App", isPresented: $removing, titleVisibility: .visible) {
      Button("Remove \(editor.name)", role: .destructive) {
        guard let app = editor.app else { return }
        ai.removeApp(app.id, name: app.name, url: app.url, then: onClose)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(AIText.confirmRemoveApp)
    }
  }

  @ViewBuilder
  private var form: some View {
    @Bindable var editor = editor
    let busy = editor.busy != nil
    Section {
      Explanation(AIText.appExplained)
      SetupField("Name") { TextField("Name", text: $editor.name, prompt: Text("Linear")) }
      if let refused = editor.refused("name") { StatusLine(refused, tone: .warning) }
      SetupField("Server address") {
        TextField("Server address", text: $editor.url, prompt: Text("https://example.com/mcp"))
          .autocorrectionDisabled()
          #if os(iOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          #endif
      }
      .disabled(editor.signedIn)
      if let refused = editor.refused("url") { StatusLine(refused, tone: .warning) } else { Explanation(editor.signedIn ? AIText.addressKept : AIText.urlExplained) }
      if !editor.signedIn {
        SetupField("Token") {
          SecureField("Token", text: $editor.token, prompt: Text(editor.noToken ? "None" : editor.app?.hasToken == true ? "Unchanged" : "Optional"))
        }
        .disabled(editor.noToken)
        if editor.app?.hasToken == true { Toggle("Send No Token", isOn: $editor.noToken) }
        if let refused = editor.refused("token") {
          StatusLine(refused, tone: .warning)
        } else if let app = editor.app, app.hasToken, !editor.noToken, editor.token.isEmpty, editor.url.trimmingCharacters(in: .whitespaces) != app.url {
          StatusLine(AppRules.tokenStays, tone: .warning)
        } else {
          Explanation(editor.app?.hasToken == true ? AIText.appTokenKept : AIText.tokenExplained)
        }
      }
    }
    .disabled(busy)
    if let signIn = editor.app?.signIn { signedIn(signIn) }
    if editor.asksClient { client }
    if editor.offersSignIn, editor.app?.signIn == nil {
      Section {
        Button(AIText.signInTo(editor.url), systemImage: "person.badge.key", action: editor.signIn).disabled(busy || editor.url.isEmpty)
      }
    }
    Section {
      if editor.busy == .reading { StatusLine(AIText.readingTools) }
      if editor.busy == .signingIn { StatusLine(AIText.findingSignIn) }
      if let notice = editor.notice { StatusLine(notice, tone: .positive) }
      if let refusal = editor.generalRefusal { StatusLine(refusal, tone: .warning) }
    }
    if let app = editor.app {
      tools(app, busy: busy)
      Section {
        Button("Remove App", systemImage: "trash", role: .destructive) { removing = true }
          .disabled(busy)
          .help(AIText.confirmRemoveApp)
      }
    }
  }

  /** The Sign-in group (web `SignedIn`): ended, wanting more, who signed in, and Sign in again. */
  private func signedIn(_ signIn: AppSignIn) -> some View {
    Section {
      if signIn.ended { StatusLine(AIText.signInHasEnded, tone: .warning) }
      if let scope = signIn.wantsScope { StatusLine(AIText.wantsMore(scope), tone: .warning) }
      if let when = EmberDate.parse(signIn.at) {
        let date = when.formatted(date: .long, time: .shortened)
        Text(signIn.by.map { "Signed in by \($0.name), \(date)." } ?? "Signed in \(date).")
      }
      Explanation(AIText.signInExplained)
      Button("Sign In Again", systemImage: "person.badge.key", action: editor.signIn).disabled(editor.busy != nil)
    } header: {
      AIHeading("Sign-in")
    }
  }

  /** The Client group (web `Client`): the redirect address to register, and the client ID and secret the service gave. */
  @ViewBuilder
  private var client: some View {
    @Bindable var editor = editor
    Section {
      CopyLine(title: "Redirect address", text: editor.redirectAddress)
      Explanation(AIText.redirectExplained)
      SetupField("Client ID") { TextField("Client ID", text: $editor.clientId).onSubmit(editor.signIn) }
      if let refused = editor.refused("clientId") { StatusLine(refused, tone: .warning) } else { Explanation(AIText.clientIdExplained) }
      SetupField("Client secret") {
        SecureField("Client secret", text: $editor.clientSecret, prompt: Text(editor.app?.signIn?.clientId != nil ? "Unchanged" : "Optional"))
          .onSubmit(editor.signIn)
      }
      if let refused = editor.refused("clientSecret") {
        StatusLine(refused, tone: .warning)
      } else {
        Explanation(editor.app?.signIn?.clientId != nil ? AIText.clientSecretKept : AIText.clientSecretExplained)
      }
    } header: {
      AIHeading("Client")
    }
    .disabled(editor.busy != nil)
  }

  /** The Tools card (web `Tools`): what Ember read from the server, Read its tools again, and what's set aside. */
  private func tools(_ app: EmberKit.App, busy: Bool) -> some View {
    Section {
      Explanation(facts(app))
      Button(editor.busy == .reading ? AIText.readingTools : "Read Its Tools Again", systemImage: "arrow.clockwise", action: editor.readAgain)
        .disabled(busy)
      if let unread = editor.unread { StatusLine(unread, tone: .warning) }
      Explanation(AIText.toolsNote)
      if app.tools.isEmpty { Text(AIText.noToolsToPick).foregroundStyle(.secondary) }
      if !app.setAside.isEmpty {
        StatusLine(AIText.setAsideExplained, tone: .warning)
        ForEach(app.setAside, id: \.name) { tool in
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(tool.name).font(look == .irc ? Theme.font(12) : DesignFont.monoBody)
            Explanation((tool.gone ? "\(AIText.toolIsGone), " : "") + "picked for \(tool.agents.map(\.name).formatted(.list(type: .and)))")
          }
        }
      }
      ForEach(app.tools, id: \.name) { tool in
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          HStack {
            Text(tool.name).font(look == .irc ? Theme.font(12) : DesignFont.monoBody)
            if let title = tool.title { Text(title).foregroundStyle(.secondary) }
          }
          Text(tool.description).font(look == .irc ? Theme.font(11) : DesignFont.detail).foregroundStyle(.secondary).lineLimit(3).help(tool.description)
        }
      }
      if app.toolsLeftOut > 0 { Explanation(AIText.toolsLeftOut(app.toolsLeftOut)) }
    } header: {
      AIHeading("Tools (\(app.tools.count))")
    }
  }

  private func facts(_ app: EmberKit.App) -> String {
    var facts: [String] = []
    if let server = app.serverName { facts.append("Its server calls itself \(server)") }
    if let read = EmberDate.parse(app.toolsReadAt) { facts.append("Read \(read.formatted(date: .abbreviated, time: .shortened))") }
    if let by = app.connectedBy { facts.append("Connected by \(by.name)") }
    return facts.joined(separator: " · ")
  }
}
