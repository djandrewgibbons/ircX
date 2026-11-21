import AppCoreUI
import EmberKit
import SwiftUI

// New agent and an agent's settings (web `agent-page.tsx`): its avatar, name and what it does, its
// instructions with what Ember adds around them, how it answers, Search the web, its rooms, admin access,
// Try it, then Create agent or Save changes, which ask its model a test question first when it's new or
// its model changed; a saved agent's page adds its tools and Delete agent.

/** An agent's page as it's filled in (web `Fields`). */
struct AgentFields: Equatable {
  var name = ""
  var description = ""
  var instructions = ""
  var promptTemplate = Prompts.agentTemplate
  var model: String
  var levels = AnswerLevels.default
  var webSearch = false
  var everyOpenRoom = true
  var chosenRooms: [RoomID] = []
  var adminsOnly = false
  var adminDms = false

  /** The fields a refusal can name (`AgentField`), which say it on themselves. */
  static let named: Set<String> = ["name", "description", "instructions", "promptTemplate", "model", "levels", "webSearch", "access", "rooms"]

  /** A new agent's page (web `newFields`): @ember's model, or Ember's suggestion if it's no longer offered. */
  static func new(_ assistant: AssistantSettings, offered: OfferedModels) -> AgentFields {
    AgentFields(model: AssistantRules.startingModel(assistant.model, offered: offered))
  }

  /** An agent's page as it's saved (web `fieldsOf`). */
  static func of(_ agent: AgentSettings) -> AgentFields {
    var fields = AgentFields(model: agent.model)
    fields.name = agent.name
    fields.description = agent.description
    fields.instructions = agent.instructions
    if let template = agent.promptTemplate { fields.promptTemplate = template }
    fields.levels = agent.levels
    fields.webSearch = agent.webTools.contains(.search)
    fields.everyOpenRoom = agent.rooms == nil
    fields.chosenRooms = (agent.rooms ?? []).map(\.id)
    fields.adminsOnly = agent.access != .everyone
    fields.adminDms = agent.access == .adminDms
    return fields
  }

  /** `accessOf` */
  var access: AgentAccess { adminDms ? .adminDms : adminsOnly ? .admins : .everyone }

  /** `roomsChosen`: none while only admin DMs reach it. */
  var rooms: PickedRooms { adminDms ? .these([]) : everyOpenRoom ? .everyOpenRoom : .these(chosenRooms) }

  /** `templateSent`: nil for Ember's own. */
  var templateSent: String? { promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines) == Prompts.agentTemplate ? nil : promptTemplate }

  /** `newAgentOf` */
  var newAgent: AgentChanges {
    AgentChanges(
      name: name, description: description, instructions: instructions, promptTemplate: templateSent.map { .some($0) }, model: model,
      thinking: levels.thinking, length: levels.length, webSearch: webSearch, access: access, rooms: rooms)
  }

  /** `changesOf`: only what changed, so saving doesn't put back what another administrator saved since. */
  func changes(of agent: AgentSettings) -> AgentChanges {
    var changes = AgentChanges()
    let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
    let savedTemplate = agent.promptTemplate ?? Prompts.agentTemplate
    if trimmed(name) != agent.name { changes.name = name }
    if trimmed(description) != agent.description { changes.description = description }
    if trimmed(instructions) != agent.instructions { changes.instructions = instructions }
    if trimmed(promptTemplate) != savedTemplate { changes.promptTemplate = .some(templateSent) }
    if model != agent.model { changes.model = model }
    if levels.thinking != agent.levels.thinking { changes.thinking = levels.thinking }
    if levels.length != agent.levels.length { changes.length = levels.length }
    if webSearch != agent.webTools.contains(.search) { changes.webSearch = webSearch }
    if access != agent.access { changes.access = access }
    if !Self.same(rooms, agent.rooms) { changes.rooms = rooms }
    return changes
  }

  private static func same(_ rooms: PickedRooms, _ kept: [NamedRoom]?) -> Bool {
    switch (rooms, kept) {
    case (.everyOpenRoom, nil): true
    case let (.these(ids), kept?): ids.count == kept.count && kept.allSatisfy { ids.contains($0.id) }
    default: false
    }
  }
}

extension AgentChanges {
  var isEmpty: Bool {
    name == nil && description == nil && instructions == nil && promptTemplate == nil && model == nil && thinking == nil && length == nil && webSearch == nil
      && access == nil && rooms == nil
  }
}

@MainActor
@Observable
final class AgentEditor {
  @ObservationIgnored unowned let session: InstanceSession
  let agentId: UserID?
  var saved: AgentSettings?
  var fields: AgentFields?
  var touched = false
  var avatar: ChosenPhoto?
  var avatarRefusal: String?
  var removingAvatar = false
  var refusal: FormRefusal?
  var busy: String?
  var loadFailure: String?
  var question = ""
  var trial: AgentTrialAnswer?
  var asking = false
  var trialRefusal: String?

  init(session: InstanceSession, agentId: UserID?) {
    self.session = session
    self.agentId = agentId
    // A new agent's page fills in at once when Ember AI and its models are known already.
    if agentId == nil, let assistant = session.admin.ai.assistant, let offered = session.admin.ai.offered {
      fields = AgentFields.new(assistant, offered: offered)
    }
  }

  private var ai: AIAdmin { session.admin.ai }
  var offered: OfferedModels? { ai.offered }

  func load() async {
    do {
      if ai.offered == nil { await ai.loadOffered() }
      if let agentId {
        let agent = try await session.api.agent(agentId)
        saved = agent
        fields = AgentFields.of(agent)
      } else if fields != nil {
        return
      } else if let assistant = ai.assistant, let offered = ai.offered {
        fields = AgentFields.new(assistant, offered: offered)
      } else {
        loadFailure = AssistantRules.assistantOff
      }
    } catch {
      logger.error("Loading an agent failed: \(error.localizedDescription, privacy: .public)")
      if (error as? EmberError) == .signedOut { return session.sessionEnded() }
      loadFailure = error.localizedDescription
    }
  }

  /** Changes the page, forgetting a refusal it may have answered (web `change`). */
  func change(_ field: String, _ edit: (inout AgentFields) -> Void) {
    guard var fields else { return }
    edit(&fields)
    self.fields = fields
    touched = true
    if refusal?.field == field || refusal?.field == nil || (field == "model" && refusal?.field == "webSearch") { refusal = nil }
  }

  var called: String {
    guard let fields, !fields.name.trimmingCharacters(in: .whitespaces).isEmpty else { return "the agent" }
    return fields.name.trimmingCharacters(in: .whitespaces)
  }

  var sameModel: Bool { saved?.model == fields?.model }

  var offeredModel: OfferedModel? {
    guard let fields, let offered else { return nil }
    return AssistantRules.offeredModel(fields.model, in: offered.models)
  }

  var modelName: String {
    guard let fields else { return "" }
    if let saved, sameModel { return saved.modelName }
    if let offeredModel { return offeredModel.name }
    return AssistantRules.modelName(fields.model)
  }

  var format: ModelFormat {
    guard let fields else { return .chat }
    if let saved, sameModel { return saved.format }
    if let offeredModel { return offeredModel.format }
    return AssistantRules.format(of: fields.model)
  }

  /** What it may do on the web with this model (web `mayOnTheWeb`). */
  var mayOnTheWeb: [WebTool] {
    guard let fields, let offered, let searchFormat = AssistantRules.searchFormat(fields.model, format) else { return [] }
    if searchFormat == .workers, offeredModel?.format != .workers { return [] }
    return AssistantRules.webTools(of: fields.model, format: searchFormat, offered: offered.models)
  }

  var canSearch: Bool {
    if !mayOnTheWeb.isEmpty { return true }
    guard let saved, sameModel else { return false }
    return !saved.webTools.isEmpty
  }

  var webTools: [WebTool] {
    guard let fields, fields.webSearch, canSearch else { return [] }
    if let saved, sameModel, !saved.webTools.isEmpty { return saved.webTools }
    return mayOnTheWeb
  }

  /** What Ember tells the agent around its instructions, for a direct question from whoever's signed in. */
  var prompt: Prompt? {
    guard let fields, let me = session.me else { return nil }
    let name = fields.name.trimmingCharacters(in: .whitespaces)
    let web = AssistantRules.webPrompt(askerName: me.name, webTools: webTools, webSearchOn: !webTools.isEmpty)
    return Prompts.around(
      answererId: saved?.id, name: name.isEmpty ? "Agent" : name, askerName: me.name, askedIn: AskedIn(community: session.name, roomName: nil, inThread: false),
      words: fields.levels.length.words, web: web, now: Date(), template: fields.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  var changes: AgentChanges? {
    guard let saved, let fields else { return nil }
    return fields.changes(of: saved)
  }

  var asksModel: Bool {
    guard let saved, let changes else { return true }
    return changes.model != nil || (changes.webSearch == true && saved.webTools.isEmpty)
  }

  var changed: Bool {
    guard busy == nil else { return false }
    if avatar != nil { return true }
    guard saved != nil else { return touched }
    if removingAvatar { return true }
    guard let changes else { return false }
    return !changes.isEmpty
  }

  /** What the line under Create agent or Save changes says while it saves (web `savingNote`). */
  var savingNote: String? {
    guard asksModel else { return nil }
    return saved == nil || changes?.model != nil ? AIText.askingTestQuestion(modelName) : AIText.searchingWith(modelName)
  }

  /** A refusal no field shows, which shows under the button. */
  var generalRefusal: String? {
    guard let refusal else { return nil }
    if let field = refusal.field, AgentFields.named.contains(field) { return nil }
    return refusal.error
  }

  /** `refusalBefore`: a template Ember doesn't take, or Search the web on for a model that can't search. */
  func refusalBefore() -> FormRefusal? {
    guard let fields else { return nil }
    if let template = Prompts.refusal(fields.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)) { return FormRefusal(field: "promptTemplate", error: template) }
    if fields.webSearch, !canSearch { return FormRefusal(field: "webSearch", error: AgentRules.cannotSearchWith(modelName)) }
    return nil
  }

  /** Create agent or Save changes: the agent saved, then its avatar taken away if Remove avatar was pressed. */
  func save(then: @escaping @MainActor () -> Void) {
    guard let fields, busy == nil else { return }
    refusal = nil
    if let refused = refusalBefore() { return refusal = refused }
    busy = "saving"
    let photo = avatar
    Task {
      defer { busy = nil }
      do {
        var agent: AgentSettings
        if let saved {
          agent = saved
          if let changes, !changes.isEmpty || photo != nil { agent = try await session.api.changeAgent(saved.id, changes, avatar: photo) }
          if removingAvatar, photo == nil { agent = try await session.api.removeAgentAvatar(saved.id) }
        } else {
          agent = try await session.api.createAgent(fields.newAgent, avatar: photo)
        }
        self.saved = agent
        avatar = nil
        removingAvatar = false
        await ai.loadAgents()
        session.admin.say(AdminText.saved)
        then()
      } catch {
        refuse(error)
      }
    }
  }

  /** Says why saving failed: on the avatar, on the field it's about, under the button, or as the page's alerts do. */
  private func refuse(_ error: Error) {
    if let problem = (error as? EmberError)?.problem, problem.field == "avatar" { return avatarRefusal = problem.message }
    guard let refused = FormRefusal.of(error, conflicts: true) else { return session.admin.failed("Saving the agent", error) }
    logger.error("Saving the agent was refused: \(refused.error, privacy: .public)")
    refusal = refused
  }

  /** Try it: asks the agent as the page sets it up, saving nothing (web `TryIt`). */
  func ask() {
    guard let fields, !asking else { return }
    let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty else { return trialRefusal = AgentRules.questionNeeded }
    if let refused = refusalBefore() { return trialRefusal = refused.error }
    trialRefusal = nil
    trial = nil
    asking = true
    let trial = AgentTrial(
      name: fields.name, instructions: fields.instructions, promptTemplate: fields.templateSent, model: fields.model, thinking: fields.levels.thinking,
      length: fields.levels.length, webSearch: fields.webSearch, question: question)
    Task {
      defer { asking = false }
      do {
        self.trial = try await session.api.tryAgent(trial, agent: saved?.id)
      } catch {
        guard let refused = FormRefusal.of(error, conflicts: true) else { return session.admin.failed("Trying the agent", error) }
        trialRefusal = refused.error
      }
    }
  }
}

/** New agent, or an agent's page, in either theme. */
struct AgentPage: View {
  let session: InstanceSession
  let onClose: () -> Void
  @State private var editor: AgentEditor
  @State private var tools: ToolsModel?
  @State private var leaving = false
  @State private var deleting = false
  @Environment(\.appTheme) private var look

  init(session: InstanceSession, agentId: UserID?, onClose: @escaping () -> Void) {
    self.session = session
    self.onClose = onClose
    _editor = State(initialValue: AgentEditor(session: session, agentId: agentId))
    _tools = State(initialValue: agentId.map { ToolsModel(session: session, agent: $0) })
  }

  private var ai: AIAdmin { session.admin.ai }

  var body: some View {
    SetupFrame(
      title: editor.saved.map { "Edit \($0.name)" } ?? "New Agent", systemImage: "cpu", cancelTitle: "Cancel",
      actionTitle: editor.busy == "saving" ? "Saving…" : editor.saved == nil ? "Create Agent" : "Save Changes", canAct: editor.changed, busy: editor.busy != nil,
      keepsOpen: editor.changed, submit: .commandReturn, onCancel: close, onAct: { editor.save(then: onClose) }
    ) {
      if let failure = editor.loadFailure {
        Section { StatusLine(failure, tone: .warning) }
      } else if let fields = editor.fields {
        form(fields)
      } else {
        Section { Color.clear.frame(height: 40).loadingActivity(true) }
      }
    }
    .task { await editor.load() }
    .alert("Unsaved Changes", isPresented: $leaving) {
      Button("Save") { editor.save(then: onClose) }
      Button("Discard", role: .destructive, action: onClose)
      Button("Keep Editing", role: .cancel) {}
    } message: {
      Text(AIText.agentChanges)
    }
    .confirmationDialog("Delete Agent", isPresented: $deleting, titleVisibility: .visible) {
      Button("Delete \(editor.called)", role: .destructive) {
        guard let saved = editor.saved else { return }
        editor.busy = "deleting"
        ai.deleteAgent(saved.id, then: onClose)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(AIText.confirmDeleteAgent)
    }
  }

  private func close() {
    if editor.changed { return leaving = true }
    onClose()
  }

  private func refused(_ field: String) -> String? { editor.refusal?.on(field) }

  @ViewBuilder
  private func form(_ fields: AgentFields) -> some View {
    let busy = editor.busy != nil
    identity(fields, busy: busy)
    Section {
      PromptEditor("Instructions", text: binding(fields, "instructions", \.instructions), minHeight: 160).disabled(busy)
      StatusLine(AssistantRules.length(of: fields.instructions))
      if let refusal = refused("instructions") { StatusLine(refusal, tone: .warning) }
      Explanation(AIText.agentInstructionsExplained)
      PromptPreview(
        name: editor.called, prompt: editor.prompt, template: binding(fields, "promptTemplate", \.promptTemplate), ownTemplate: Prompts.agentTemplate,
        refusal: refused("promptTemplate"), disabled: busy)
    } header: {
      AIHeading("Instructions")
    }
    answering(fields, busy: busy)
    Section {
      Toggle("Search the Web", isOn: binding(fields, "webSearch", \.webSearch)).disabled(busy)
      if !editor.canSearch {
        Explanation(AIText.cannotSearch(editor.modelName))
      } else {
        Explanation(fields.webSearch ? AIText.agentWebSearchOn(editor.webTools) : AIText.agentWebSearchOff)
      }
      if let refusal = refused("webSearch") { StatusLine(refusal, tone: .warning) }
    } header: {
      AIHeading("Search the Web")
    }
    Section {
      Explanation(AIText.roomsExplained(editor.called, fields.access))
      RoomsPicker(
        everyOpenRoom: binding(fields, "rooms", \.everyOpenRoom), chosen: binding(fields, "rooms", \.chosenRooms), rooms: ai.roomsToPick(kept: editor.saved?.rooms ?? []),
        disabled: busy || fields.adminDms)
      if let refusal = refused("rooms") { StatusLine(refusal, tone: .warning) }
    } header: {
      AIHeading("Rooms")
    }
    access(fields, busy: busy)
    tryIt(busy: busy)
    Section {
      if editor.busy == "saving", let note = editor.savingNote { StatusLine(note) }
      if let refusal = editor.generalRefusal { StatusLine(refusal, tone: .warning) }
      if let saved = editor.saved, let when = EmberDate.parse(saved.changedAt) {
        Explanation(AIText.lastChanged(saved.changedBy.id == session.me?.id ? "You" : saved.changedBy.name, saved.name, when.formatted(date: .long, time: .omitted)))
      }
    }
    if let saved = editor.saved {
      if let tools { ToolsSection(model: tools, name: saved.name) { ai.editor = .app(nil) } }
      Section {
        Button("Delete Agent", systemImage: "trash", role: .destructive) { deleting = true }
          .disabled(busy)
          .help(AIText.confirmDeleteAgent)
      }
    }
  }

  @ViewBuilder
  private func identity(_ fields: AgentFields, busy: Bool) -> some View {
    Section {
      Explanation(AIText.agentExplained)
      HStack(spacing: Spacing.lg) {
        AgentAvatar(session: session, path: editor.removingAvatar ? nil : editor.saved?.avatarUrl, picked: editor.avatar.map { $0.variant ?? $0.data }, size: 64)
        VStack(alignment: .leading, spacing: Spacing.sm) {
          PhotoPickerButton(
            onPick: { photo in
              editor.avatar = photo
              editor.avatarRefusal = nil
              editor.removingAvatar = false
            },
            onRefused: { editor.avatarRefusal = $0 }
          ) {
            Label(look == .irc ? "[upload avatar]" : "Upload Avatar", systemImage: "camera")
          }
          if editor.avatar != nil || (editor.saved?.avatar == true && !editor.removingAvatar) {
            Button(look == .irc ? "[remove avatar]" : "Remove Avatar", systemImage: "trash", role: .destructive) {
              editor.avatar = nil
              editor.removingAvatar = editor.saved?.avatar == true
            }
          }
        }
      }
      .disabled(busy)
      if let refusal = editor.avatarRefusal { StatusLine(refusal, tone: .warning) } else { Explanation(AIText.agentAvatarExplained) }
      SetupField("Name") {
        TextField("Name", text: binding(fields, "name", \.name), prompt: Text("Helper"))
      }
      .disabled(busy)
      if let refusal = refused("name") {
        StatusLine(refusal, tone: .warning)
      } else {
        Explanation(AIText.agentNameExplained.replacingOccurrences(of: "@name", with: "@\(editor.called)"))
      }
      SetupField("What it does") {
        TextField("What it does", text: binding(fields, "description", \.description), prompt: Text("Answers questions about the product"))
      }
      .disabled(busy)
      if let refusal = refused("description") { StatusLine(refusal, tone: .warning) } else { Explanation(AIText.agentDescriptionExplained) }
    }
  }

  @ViewBuilder
  private func answering(_ fields: AgentFields, busy: Bool) -> some View {
    Section {
      ModelPicker(
        models: editor.offered?.models,
        kept: editor.saved.map { AssistantModel(id: $0.model, name: $0.modelName, format: $0.format, price: nil, thinkingLevels: $0.thinkingLevels) },
        chosen: binding(fields, "model", \.model), refusal: refused("model"), disabled: busy, accountId: ai.accountId, workersAi: editor.offered?.workersAi)
      LevelDials(
        levels: fields.levels, modelName: editor.modelName, takes: editor.sameModel ? editor.saved?.thinkingLevels : editor.offeredModel?.thinkingLevels,
        disabled: busy
      ) { levels in editor.change("levels") { $0.levels = levels } }
      if let refusal = refused("levels") { StatusLine(refusal, tone: .warning) }
      if let price = editor.offeredModel?.price, let prompt = editor.prompt {
        let told = Prompts.withInstructions(prompt, fields.instructions.trimmingCharacters(in: .whitespacesAndNewlines))
        let cost = AssistantRules.answerCost(AssistantRules.mostCost(told: told, levels: fields.levels, price: price))
        Explanation(AIText.mostCost(editor.modelName, cost, searches: !editor.webTools.isEmpty))
      }
    } header: {
      AIHeading("How It Answers")
    }
  }

  @ViewBuilder
  private func access(_ fields: AgentFields, busy: Bool) -> some View {
    Section {
      Toggle(isOn: Binding(get: { fields.adminsOnly || fields.adminDms }, set: { on in editor.change("access") { $0.adminsOnly = on } })) {
        Label("Admins Only", systemImage: "crown")
      }
      .disabled(busy || fields.adminDms)
      .help(AIText.adminsOnlyExplained(editor.called, on: fields.adminsOnly, kept: fields.adminDms))
      Explanation(AIText.adminsOnlyExplained(editor.called, on: fields.adminsOnly, kept: fields.adminDms))
      Toggle(isOn: binding(fields, "access", \.adminDms)) {
        Label("Only Available in Admin DMs", systemImage: "eye.slash")
      }
      .disabled(busy)
      .help(AIText.adminDmsExplained(editor.called, on: fields.adminDms))
      Explanation(AIText.adminDmsExplained(editor.called, on: fields.adminDms))
      if let refusal = refused("access") { StatusLine(refusal, tone: .warning) }
    } header: {
      AIHeading("Admin Access")
    }
  }

  @ViewBuilder
  private func tryIt(busy: Bool) -> some View {
    @Bindable var editor = editor
    Section {
      Explanation(AIText.tryExplained(editor.called))
      HStack {
        TextField("Question", text: $editor.question, prompt: Text("Ask it something"))
          .onSubmit(editor.ask)
        Button(editor.asking ? "Asking…" : "Ask", action: editor.ask)
          .disabled(editor.question.trimmingCharacters(in: .whitespaces).isEmpty || editor.asking)
      }
      .disabled(busy)
      if editor.asking { StatusLine(AIText.askingYourQuestion(editor.modelName)) }
      if let refusal = editor.trialRefusal { StatusLine(refusal, tone: .warning) }
      if let trial = editor.trial { TrialAnswer(session: session, trial: trial) }
    } header: {
      AIHeading("Try It")
    }
  }

  /** A binding to one of the page's fields, which changing forgets a refusal it answered. */
  private func binding<Value>(_ shown: AgentFields, _ field: String, _ path: WritableKeyPath<AgentFields, Value>) -> Binding<Value> {
    Binding(
      get: { (editor.fields ?? shown)[keyPath: path] },
      set: { value in editor.change(field) { $0[keyPath: path] = value } })
  }
}

/** Try it's answer (web `TryIt`'s result): the answer as the room would show it, its cards, and how long it took. */
private struct TrialAnswer: View {
  let session: InstanceSession
  let trial: AgentTrialAnswer
  @Environment(\.appTheme) private var look

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      if let blocks = RichLayout.blocks(trial.body, plainText: "", host: session.instance.host) {
        switch look {
        case .suite: SuiteMessageBody(session: session, blocks: blocks)
        case .irc: IRCMessageBody(session: session, blocks: blocks)
        }
      } else {
        StatusLine(AIText.unshowableAnswer, tone: .warning)
      }
      if !trial.cards.isEmpty {
        switch look {
        case .suite: SuiteBotCards(session: session, cards: trial.cards, onAction: nil).disabled(true)
        case .irc: IRCBotCards(session: session, cards: trial.cards, onAction: nil).disabled(true)
        }
      }
      StatusLine(AIText.answeredIn(trial.ms))
    }
  }
}
