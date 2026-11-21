import AppCoreUI
import EmberKit
import SwiftUI

// The pages and dialogs the AI assistant, Chat bots and Huddles sections open over Server Settings: Set up
// Ember AI (web `assistant-setup.tsx`), Add a model (`add-assistant-model.tsx`) and @ember's page
// (`ember-settings.tsx`) here; agents, apps, bots and the huddle keys in their own files.

/** The page or dialog `editor` names, in either theme. */
struct AIEditorSheet: View {
  let app: AppModel
  let session: InstanceSession
  let editor: AIEditor

  private var ai: AIAdmin { session.admin.ai }

  var body: some View {
    Group {
      switch editor {
      case .assistantSetup: AssistantSetupSheet(session: session) { ai.editor = nil }
      case .ember: EmberPage(session: session) { ai.editor = nil }
      case let .agent(id): AgentPage(session: session, agentId: id) { ai.editor = nil }
      case let .app(id): AppPage(session: session, appId: id) { ai.editor = nil }
      case let .bot(id): BotPage(session: session, botId: id) { ai.editor = nil }
      case .huddlesSetup: CloudflareKeysSheet(session: session, kind: .huddles) { ai.editor = nil }
      case .relaySetup: CloudflareKeysSheet(session: session, kind: .relay) { ai.editor = nil }
      }
    }
    .frame(minWidth: 600, minHeight: 640)
    .environment(\.adminNotices, session.admin)
    .suiteTheme(.ircX)
  }
}

// MARK: - Set up Ember AI

/**
 * Set up Ember AI's steps (web `AssistantSetup`): the Cloudflare account and its API token, then the model,
 * which the Worker asks a test question before keeping all three, then what it said.
 */
@MainActor
@Observable
final class AssistantSetupModel {
  enum Step { case keys, model, done }

  @ObservationIgnored unowned let session: InstanceSession
  /** Ember AI as it was when the setup opened. */
  let opened: AssistantSettings?
  /** Whether the account's ID was filled in, so the steps needn't say where to copy it from. */
  let filledIn: Bool
  let deployedAccountId: String?
  var step: Step = .keys
  var accountId: String
  var apiToken = ""
  var offered: OfferedModels?
  var model = ""
  var refusal: FormRefusal?
  var saving = false
  var saved: AssistantSaved?

  init(session: InstanceSession) {
    self.session = session
    let settings = session.admin.settings
    opened = settings?.assistant
    deployedAccountId = settings?.cloudflareAccountId
    let start: String
    if let kept = settings?.assistant?.accountId {
      start = kept
    } else if let deployed = settings?.cloudflareAccountId {
      start = deployed
    } else {
      start = ""
    }
    accountId = start
    filledIn = !start.isEmpty
  }

  var hasToken: Bool { opened != nil }

  var canContinue: Bool {
    !accountId.trimmingCharacters(in: .whitespaces).isEmpty && (hasToken || !apiToken.trimmingCharacters(in: .whitespaces).isEmpty)
  }

  var title: String {
    switch step {
    case .keys: "Set Up Ember AI"
    case .model: "Choose a Model"
    case .done: "Ember AI Is Set Up"
    }
  }

  /** The account's ID as typed, when it's one. */
  var typedAccountId: String? { AssistantRules.accountId(of: accountId) }

  private var keys: AssistantSetup? {
    guard let id = typedAccountId else { return nil }
    let token = apiToken.trimmingCharacters(in: .whitespaces)
    return AssistantSetup(accountId: id, apiToken: token.isEmpty ? nil : token)
  }

  /** Continue: the account and token checked as the Worker would, then the models offered through them. */
  func next() {
    refusal = nil
    guard let keys else { return refusal = FormRefusal(field: "accountId", error: AssistantRules.accountIdRefused) }
    if let token = keys.apiToken, AssistantRules.apiToken(of: token) == nil { return refusal = FormRefusal(field: "apiToken", error: AssistantRules.apiTokenRefused) }
    step = .model
    offered = nil
    Task {
      do {
        let offered = try await session.admin.ai.offeredModels(keys)
        self.offered = offered
        model = AssistantRules.startingModel(model.isEmpty ? opened?.model : model, offered: offered)
      } catch {
        session.admin.failed("Listing the models Ember offers", error)
      }
    }
  }

  /** Save: the Worker asks the model a test question, then keeps the account, token and model. */
  func save() {
    guard var keys, !saving else { return }
    keys.model = model
    refusal = nil
    saving = true
    Task {
      defer { saving = false }
      do {
        let saved = try await session.api.saveAssistant(keys)
        self.saved = saved
        apiToken = ""
        session.admin.ai.assistantSaved(saved.assistant)
        step = .done
      } catch {
        guard let refused = FormRefusal.of(error) else { return session.admin.failed("Setting up Ember AI", error) }
        logger.error("Setting up Ember AI was refused: \(refused.error, privacy: .public)")
        refusal = refused
        if refused.field == "accountId" || refused.field == "apiToken" { step = .keys }
      }
    }
  }

  /** What the last step says once the change turned Search the web off. */
  var searchNote: String? {
    guard let opened, let saved, opened.webTools?.contains(.search) == true, saved.assistant.webTools?.contains(.search) != true else { return nil }
    let account = opened.accountId != saved.assistant.accountId && opened.model == saved.assistant.model
    return AIText.searchTurnedOff(saved.assistant.webTools, changed: account ? "account" : "model")
  }
}

struct AssistantSetupSheet: View {
  let session: InstanceSession
  let onClose: () -> Void
  @State private var model: AssistantSetupModel

  init(session: InstanceSession, onClose: @escaping () -> Void) {
    self.session = session
    self.onClose = onClose
    _model = State(initialValue: AssistantSetupModel(session: session))
  }

  var body: some View {
    @Bindable var model = model
    SetupFrame(
      title: model.title, systemImage: "sparkles", cancelTitle: cancelTitle, actionTitle: actionTitle, canAct: canAct, busy: model.saving,
      onCancel: cancel, onAct: act
    ) {
      switch model.step {
      case .keys: keys
      case .model: choose
      case .done: done
      }
    }
  }

  private var cancelTitle: String {
    switch model.step {
    case .keys: "Cancel"
    case .model: "Back"
    case .done: "Close"
    }
  }

  private var actionTitle: String {
    switch model.step {
    case .keys: "Continue"
    case .model: model.saving ? "Asking…" : "Save"
    case .done: "Done"
    }
  }

  private var canAct: Bool {
    switch model.step {
    case .keys: model.canContinue
    case .model: model.offered != nil
    case .done: true
    }
  }

  private func cancel() {
    if model.step == .model { model.step = .keys } else { onClose() }
  }

  private func act() {
    switch model.step {
    case .keys: model.next()
    case .model: model.save()
    case .done: onClose()
    }
  }

  @ViewBuilder
  private var keys: some View {
    @Bindable var model = model
    Section {
      Explanation(AIText.setupExplained)
      ForEach(Array(AIText.tokenSteps.enumerated()), id: \.offset) { index, step in Text("\(index + 1). \(step)") }
      OpenLinkButton(title: "Open Account API Tokens", url: AssistantRules.dashboard(model.typedAccountId, "api-tokens"))
      if !model.filledIn { Text("4. \(AIText.accountIdStep)") }
    }
    Section {
      SetupField("Account ID") {
        TextField("Account ID", text: $model.accountId)
          .autocorrectionDisabled()
          #if os(iOS)
          .textInputAutocapitalization(.never)
          #endif
          .onChange(of: model.accountId) { model.refusal = nil }
          .onSubmit(act)
      }
      if let refused = model.refusal?.on("accountId") {
        StatusLine(refused, tone: .warning)
      } else if let deployed = model.deployedAccountId, model.typedAccountId == deployed {
        Explanation(AIText.deployedAccount)
      }
      SetupField("API token") {
        SecureField("API token", text: $model.apiToken)
          .onChange(of: model.apiToken) { model.refusal = nil }
          .onSubmit(act)
      }
      if let refused = model.refusal?.on("apiToken") {
        StatusLine(refused, tone: .warning)
      } else if model.hasToken {
        Explanation(AIText.tokenKept)
      }
    }
  }

  @ViewBuilder
  private var choose: some View {
    @Bindable var model = model
    Section {
      Explanation(AIText.chooseModel)
      ModelPicker(
        models: model.offered?.models, chosen: $model.model, refusal: model.refusal?.on("model"), disabled: model.saving,
        accountId: model.typedAccountId, workersAi: model.offered?.workersAi)
      if model.saving {
        StatusLine(AIText.askingTestQuestion(AssistantRules.modelName(model.model, offered: model.offered?.models)))
      } else if let refusal = model.refusal, refusal.field == nil {
        StatusLine(refusal.error, tone: .warning)
      }
    }
  }

  @ViewBuilder
  private var done: some View {
    if let saved = model.saved {
      Section {
        Text(AIText.setUp(AssistantRules.modelName(saved.assistant.model, in: saved.assistant.models)))
        Text(saved.greeting).italic().textSelection(.enabled)
        if let note = model.searchNote { Explanation(note) }
      }
    }
  }
}

// MARK: - Add a model

/** Add a model (web `AddAssistantModel`): a model people can pick for @ember, which Ember asks a test question first. */
struct AddModelSheet: View {
  let session: InstanceSession
  let onClose: () -> Void
  @State private var chosen = ""
  @State private var adding = false
  @State private var refusal: FormRefusal?
  @State private var added: AssistantSaved?

  private var ai: AIAdmin { session.admin.ai }

  private var toAdd: [OfferedModel]? {
    guard let assistant = ai.assistant, let offered = ai.offered else { return nil }
    return AssistantRules.modelsToAdd(assistant, offered: offered.models)
  }

  var body: some View {
    SetupFrame(
      title: added == nil ? "Add a Model" : "Model Added", systemImage: "plus.circle", cancelTitle: added == nil ? "Cancel" : "Close",
      actionTitle: added == nil ? (adding ? "Asking…" : "Add") : "Done", canAct: !chosen.isEmpty, busy: adding, onCancel: onClose,
      onAct: { added == nil ? add() : onClose() }
    ) {
      if let added {
        Section {
          Text(AIText.modelAdded(AssistantRules.modelName(chosen, in: added.assistant.models)))
          Text(added.greeting).italic().textSelection(.enabled)
        }
      } else {
        Section {
          Explanation(AIText.addModelExplained)
          ModelPicker(
            models: toAdd, chosen: $chosen, refusal: refusal?.error, disabled: adding, accountId: ai.accountId, workersAi: ai.offered?.workersAi)
          if adding { StatusLine(AIText.askingTestQuestion(AssistantRules.modelName(chosen, offered: ai.offered?.models))) }
        }
      }
    }
    .task {
      if ai.offered == nil { await ai.loadOffered() }
      if chosen.isEmpty, let first = toAdd?.first { chosen = first.id }
    }
  }

  private func add() {
    adding = true
    refusal = nil
    Task {
      defer { adding = false }
      do {
        let saved = try await session.api.addAssistantModel(chosen)
        session.admin.settings?.assistant = saved.assistant
        added = saved
      } catch {
        guard let refused = FormRefusal.of(error) else { return session.admin.failed("Adding a model", error) }
        refusal = refused
      }
    }
  }
}

// MARK: - @ember's page

/**
 * @ember's page (web `EmberSettings`): its avatar, its instructions with what Ember adds around them, the
 * models people can pick, Search the web, the limits of its dials, and its tools. Each change saves at
 * once, but the instructions and template, which Save instructions saves.
 */
struct EmberPage: View {
  let session: InstanceSession
  let onClose: () -> Void
  @State private var instructions: String?
  @State private var template: String?
  @State private var refusal: String?
  @State private var addingModel = false
  @State private var asking = false
  @State private var tools: ToolsModel
  @Environment(\.appTheme) private var look

  init(session: InstanceSession, onClose: @escaping () -> Void) {
    self.session = session
    self.onClose = onClose
    _tools = State(initialValue: ToolsModel(session: session, agent: Assistant.id))
  }

  private var ai: AIAdmin { session.admin.ai }

  private func savedTemplate(_ assistant: AssistantSettings) -> String { assistant.promptTemplate ?? Prompts.emberTemplate }

  private func changed(_ assistant: AssistantSettings) -> Bool {
    (instructions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) != assistant.instructions } == true)
      || (template.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) != savedTemplate(assistant).trimmingCharacters(in: .whitespacesAndNewlines) } == true)
  }

  var body: some View {
    SetupFrame(
      title: "@ember", systemImage: "flame", cancelTitle: "Done", actionTitle: nil, keepsOpen: ai.assistant.map(changed) == true, onCancel: close
    ) {
      if let assistant = ai.assistant {
        content(assistant)
      } else {
        Section { Text(AssistantRules.assistantOff).foregroundStyle(.secondary) }
      }
    }
    .alert("Unsaved Changes", isPresented: $asking) {
      Button("Save") { save(then: onClose) }
      Button("Discard", role: .destructive, action: onClose)
      Button("Keep Editing", role: .cancel) {}
    } message: {
      Text(AIText.instructionsUnsaved)
    }
    .sheet(isPresented: $addingModel) {
      AddModelSheet(session: session) { addingModel = false }.environment(\.appTheme, look).frame(minWidth: 520, minHeight: 420)
    }
    .task(id: ai.avatarChangedElsewhere ? session.people[Assistant.id]?.avatarUrl : nil) {
      guard ai.avatarChangedElsewhere else { return }
      await ai.rereadAssistant()
    }
  }

  private func close() {
    if let assistant = ai.assistant, changed(assistant) { return asking = true }
    onClose()
  }

  @ViewBuilder
  private func content(_ assistant: AssistantSettings) -> some View {
    let busy = ai.savingEmber != nil
    Section {
      Explanation(AIText.emberExplained)
      if let saving = ai.savingEmber { StatusLine(saving) }
    }
    Section {
      HStack(spacing: Spacing.lg) {
        AgentAvatar(session: session, path: assistant.avatarUrl, picked: ai.pickedAvatar, size: 64, systemImage: "flame.fill")
        VStack(alignment: .leading, spacing: Spacing.sm) {
          PhotoPickerButton(onPick: ai.changeAvatar, onRefused: { session.admin.say($0, error: true) }) {
            Label(look == .irc ? "[choose picture]" : "Choose Picture", systemImage: "camera")
          }
          if assistant.avatar {
            Button(look == .irc ? "[use ember's flame]" : "Use Ember's Flame", systemImage: "flame", action: ai.removeAvatar)
          }
        }
      }
      .disabled(busy)
      Explanation(assistant.avatar ? AIText.uploadedAvatarExplained : AIText.avatarExplained)
    } header: {
      AIHeading("Avatar")
    }
    Section {
      PromptEditor(
        "Instructions",
        text: Binding(get: { instructions ?? assistant.instructions }, set: { instructions = $0; refusal = nil }),
        prompt: LocalizedStringKey(AIText.instructionsPlaceholder))
      .disabled(busy)
      StatusLine(AssistantRules.length(of: instructions ?? assistant.instructions))
      Explanation(AIText.emberInstructionsExplained)
      PromptPreview(
        name: "@ember", prompt: ai.emberPrompt(template: template ?? assistant.promptTemplate),
        template: Binding(get: { template ?? savedTemplate(assistant) }, set: { template = $0; refusal = nil }), ownTemplate: Prompts.emberTemplate,
        refusal: refusal, disabled: busy, save: { save(then: {}) }, canSave: changed(assistant))
      if let refusal { StatusLine(refusal, tone: .warning) }
      Button("Save Instructions") { save(then: {}) }
        .disabled(!changed(assistant) || busy)
    } header: {
      AIHeading("Instructions")
    }
    models(assistant, busy: busy)
    webSearch(assistant, busy: busy)
    Section {
      Explanation(AIText.limitsExplained)
      LevelDials(levels: assistant.most, disabled: busy) { levels in
        ai.setMost(
          thinking: levels.thinking == assistant.most.thinking ? nil : levels.thinking, length: levels.length == assistant.most.length ? nil : levels.length)
      }
    } header: {
      AIHeading("Limits")
    }
    ToolsSection(model: tools, name: "@ember") { ai.editor = .app(nil) }
  }

  @ViewBuilder
  private func models(_ assistant: AssistantSettings, busy: Bool) -> some View {
    let offered = ai.offered
    let full = assistant.models.count >= AssistantRules.maxAssistantModels
    let none = offered.map { AssistantRules.modelsToAdd(assistant, offered: $0.models).isEmpty } == true
    Section {
      Explanation(AIText.modelsExplained)
      Picker("Answers Everyone", selection: Binding(get: { assistant.model }, set: ai.chooseDefault)) {
        ForEach(assistant.models) { model in Text(name(model, offered)).tag(model.id) }
      }
      .pickerStyle(.inline)
      .disabled(busy)
      ForEach(assistant.models.filter { $0.id != assistant.model }) { model in
        Button(look == .irc ? "[remove \(model.name)]" : "Remove \(model.name)", systemImage: "minus.circle", role: .destructive) { ai.removeModel(model.id) }
          .disabled(busy)
      }
      Button("Add a Model", systemImage: "plus") { addingModel = true }
        .disabled(busy || full || none)
        .help(full ? AssistantRules.modelsFull : none ? AIText.everyModelAdded : AIText.addModelExplained)
      if full { Explanation(AssistantRules.modelsFull) } else if none { Explanation(AIText.everyModelAdded) }
    } header: {
      AIHeading("Models")
    }
  }

  private func name(_ model: AssistantModel, _ offered: OfferedModels?) -> String {
    guard let offered, AssistantRules.noLongerOffered(model.id, offered: offered.models, workersAi: offered.workersAi) else { return model.name }
    return "\(model.name) (\(AIText.noLongerOffered))"
  }

  @ViewBuilder
  private func webSearch(_ assistant: AssistantSettings, busy: Bool) -> some View {
    let searches = assistant.webTools?.contains(.search) == true
    Section {
      Toggle("Search the Web", isOn: Binding(get: { searches }, set: ai.flipWebSearch))
        .disabled(busy)
      if let webTools = assistant.webTools {
        Explanation(searches ? AIText.webSearchOn(webTools, models: assistant.models.count) : AIText.webSearchOff)
      } else {
        Explanation(AssistantRules.cannotSearchWith(AssistantRules.modelName(assistant.model, in: assistant.models)))
      }
      if let line = ai.webSearchLine { StatusLine(line.text, tone: line.isError ? .warning : .positive) }
    } header: {
      AIHeading("Search the Web")
    }
  }

  /** Save instructions: checked as the Worker checks them, sending only what changed, and Ember's own template as nil. */
  private func save(then: @escaping () -> Void) {
    guard let assistant = ai.assistant else { return }
    let typed = instructions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    if let typed, typed.utf16.count > AssistantRules.maxInstructionsLength { return refusal = AssistantRules.instructionsTooLong }
    var sentTemplate: String??
    if let template, template.trimmingCharacters(in: .whitespacesAndNewlines) != savedTemplate(assistant).trimmingCharacters(in: .whitespacesAndNewlines) {
      if let refused = Prompts.refusal(template) { return refusal = refused }
      sentTemplate = .some(template.trimmingCharacters(in: .whitespacesAndNewlines) == Prompts.emberTemplate ? nil : template)
    }
    let sentInstructions = typed == assistant.instructions ? nil : typed
    guard sentInstructions != nil || sentTemplate != nil else { return then() }
    ai.saveInstructions(sentInstructions, template: sentTemplate) {
      instructions = nil
      template = nil
      then()
    }
  }
}
