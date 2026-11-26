import EmberKit
import Foundation

// Server Settings' AI assistant, Chat bots and Huddles sections' state (web `workspace-settings-page.tsx`'s
// AI assistant and Huddles panels, `ember-settings.tsx`, `agent-list.tsx`, `app-list.tsx`,
// `outside-ai-settings.tsx`, `huddles-settings.tsx`): what they show, what's saving, and each change, which
// both themes' pages and IRC Classic's commands make alike.

/** A page or dialog the AI assistant, Chat bots or Huddles sections open over Server Settings. */
enum AIEditor: Identifiable, Hashable {
  /** Set up Ember AI (web `AssistantSetup`). */
  case assistantSetup
  /** @ember's page (web `EmberPage`). */
  case ember
  /** New agent, for nil, or an agent's page. */
  case agent(UserID?)
  /** Connect an app, for nil, or an app's page. */
  case app(AppID?)
  /** Add a chat bot, for nil, or a bot's page. */
  case bot(UserID?)
  /** Set up huddles, or change the SFU app's keys. */
  case huddlesSetup
  /** Set up the relay, or change its TURN key. */
  case relaySetup

  var id: String {
    switch self {
    case .assistantSetup: "assistant-setup"
    case .ember: "ember"
    case let .agent(id): "agent-\(id ?? "new")"
    case let .app(id): "app-\(id ?? "new")"
    case let .bot(id): "bot-\(id ?? "new")"
    case .huddlesSetup: "huddles-setup"
    case .relaySetup: "relay-setup"
    }
  }
}

/** Why a form's save was refused: on the field the Worker names, or under the form's button for none. */
struct FormRefusal: Equatable {
  var field: String?
  var error: String

  /**
   * The refusal `error` is, when it's one the form shows (the web's `isRefusal`s): 422, AI Gateway's 429 and
   * 502, and with `conflicts`, a 409 other than Ember AI being off. Anything else is the page's to say.
   */
  static func of(_ error: Error, conflicts: Bool = false) -> FormRefusal? {
    guard let problem = (error as? EmberError)?.problem else { return nil }
    let shown = [422, 429, 502].contains(problem.status) || (conflicts && problem.status == 409 && problem.message != AssistantRules.assistantOff)
    return shown ? FormRefusal(field: problem.field, error: problem.message) : nil
  }

  func on(_ field: String) -> String? { self.field == field ? error : nil }
}

@MainActor
@Observable
final class AIAdmin {
  @ObservationIgnored unowned let session: InstanceSession

  var editor: AIEditor?
  var stoppingAssistant = false
  /** The models Ember offers through Ember AI's account, once asked. */
  var offered: OfferedModels?
  var agents: [Agent]?
  var agentsFailure: String?
  var apps: [AppSummary]?
  var appsFailure: String?
  var movingOutside: Bool?

  // @ember's page
  /** What @ember's page saves, while it does: everything else on it waits. */
  var savingEmber: String?
  /** Ember AI as @ember's page shows it while a change saves, which a refusal puts back. */
  var shownAssistant: AssistantSettings?
  /** Search the web's line: what the model found, or why it didn't turn on. */
  var webSearchLine: (text: String, isError: Bool)?
  var pickedAvatar: Data?

  // Huddles
  var stoppingHuddles = false
  var stoppingRelay = false
  var movedCameras: Bool?
  var movedScreens: Bool?

  init(session: InstanceSession) {
    self.session = session
  }

  private var admin: WorkspaceAdmin { session.admin }
  var assistant: AssistantSettings? { shownAssistant ?? admin.settings?.assistant }
  var huddles: HuddlesSettings? { admin.settings?.huddles }

  /** The Cloudflare account the dashboard links open in: Ember AI's, else the one Ember is deployed to. */
  var accountId: String? { admin.settings?.assistant?.accountId ?? admin.settings?.cloudflareAccountId }

  // MARK: Loading

  /** The agents, apps and offered models, while Ember AI is on (web `AgentList`, `AppList`, `useOfferedModels`). */
  func load() async {
    guard admin.isAdministrator, admin.settings?.assistant != nil else {
      agents = nil
      apps = nil
      return
    }
    async let agents: Void = loadAgents()
    async let apps: Void = loadApps()
    async let offered: Void = loadOffered()
    _ = await (agents, apps, offered)
  }

  func loadAgents() async {
    do {
      agents = try await session.api.agents()
      agentsFailure = nil
    } catch {
      agentsFailure = loadFailed("Loading the agents", error)
    }
  }

  func loadApps() async {
    do {
      apps = try await session.api.apps()
      appsFailure = nil
    } catch {
      appsFailure = loadFailed("Loading the apps", error)
    }
  }

  func loadOffered() async {
    do {
      offered = try await offeredModels(nil)
    } catch {
      _ = loadFailed("Listing the models Ember offers", error)
    }
  }

  /**
   * The models Ember offers through `keys`, or Ember AI's account for nil, or else, but for a session
   * that's ended, the ones this Ember shipped with, saying why Workers AI's aren't listed (web
   * `offeredModelsThrough`).
   */
  func offeredModels(_ keys: AssistantSetup?) async throws -> OfferedModels {
    do {
      return try await session.api.offeredModels(keys)
    } catch EmberError.signedOut {
      throw EmberError.signedOut
    } catch {
      logger.error("Listing the offered models failed: \(error.localizedDescription, privacy: .public)")
      let problem = (error as? EmberError)?.problem
      return AssistantRules.shipped(workersAi: problem?.status == 422 ? error.localizedDescription : AIText.offeredUnread)
    }
  }

  private func loadFailed(_ doing: String, _ error: Error) -> String? {
    logger.error("\(doing, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    if (error as? EmberError) == .signedOut {
      session.sessionEnded()
      return nil
    }
    // Ember AI turned off meanwhile: the section shows it off.
    if (error as? EmberError)?.problem?.message == AssistantRules.assistantOff { Task { await admin.load() } }
    return error.localizedDescription
  }

  /** The agents as the people directory has them now: by their names now, without those it says are gone (web `listedNow`). */
  var listedAgents: [Agent] {
    guard let agents else { return [] }
    return agents.filter { session.people[$0.id]?.status != .deactivated }
      .map { agent in
        var named = agent
        if let person = session.people[agent.id] { named.name = person.name }
        return named
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /** @ember's row's details (web `emberRow`). */
  func emberDetails(_ assistant: AssistantSettings) -> [String] {
    let model = AssistantRules.modelName(assistant.model, in: assistant.models) + (assistant.models.count > 1 ? ", or the model each person picks" : "")
    return [model] + (assistant.webTools?.contains(.search) == true ? [AIText.searchesTheWeb] : []) + [AIText.everyRoom]
  }

  func agentDetails(_ agent: Agent) -> [String] {
    [agent.modelName] + (agent.webTools.contains(.search) ? [AIText.searchesTheWeb] : []) + AgentReach.reach(agent.access, agent.rooms)
  }

  /** The open rooms an agent or bot can be kept to, by name (web `roomsToPick`): the sidebar's, and those it's in already. */
  func roomsToPick(kept: [NamedRoom]) -> [NamedRoom] {
    let open = session.rooms.filter { $0.room.kind == .open }.compactMap { room in room.room.name.map { NamedRoom(id: room.id, name: $0) } }
    var byId: [RoomID: NamedRoom] = [:]
    for room in kept + open { byId[room.id] = room }
    return byId.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  // MARK: Ember AI

  /** Ember AI's switch (web `AssistantSettings`): on opens Set up Ember AI, off asks first. */
  func flipAssistant(_ on: Bool) {
    if on {
      editor = .assistantSetup
    } else {
      admin.confirming = .stopAssistant
    }
  }

  /** Turns Ember AI off: @ember and the agents leave every room, and Ember forgets the token and the pickable models. */
  func stopAssistant() {
    stoppingAssistant = true
    admin.run("Turning Ember AI off") {
      defer { self.stoppingAssistant = false }
      try await self.session.api.forgetAssistant()
      self.admin.settings?.assistant = nil
      self.agents = nil
      self.apps = nil
      self.offered = nil
    }
  }

  /**
   * Whether the people directory has a newer @ember avatar than Ember AI's, from another window or
   * administrator, while nothing on @ember's page saves (web `changedElsewhere`).
   */
  var avatarChangedElsewhere: Bool {
    guard savingEmber == nil, let listed = session.people[Assistant.id]?.avatarUrl, let assistant = admin.settings?.assistant else { return false }
    return ProfileModel.version(listed) > ProfileModel.version(assistant.avatarUrl)
  }

  /** Reads Ember AI again after @ember's avatar changed elsewhere, for the avatar and whether an administrator uploaded it. */
  func rereadAssistant() async {
    do {
      let read = try await session.api.workspaceSettings()
      // A read a save of the page's own began after, or that outlived the change, isn't shown.
      guard !Task.isCancelled, savingEmber == nil else { return }
      admin.settings?.assistant = read.assistant
    } catch {
      if Task.isCancelled, (error as? EmberError) != .signedOut { return }
      admin.failed("Reading Ember AI again", error)
    }
  }

  /** Ember AI as Set up Ember AI saved it, with the models offered through its account read again. */
  func assistantSaved(_ saved: AssistantSettings) {
    admin.settings?.assistant = saved
    Task { await load() }
  }

  /**
   * Saves a change to Ember AI from @ember's page, showing `shown` meanwhile and putting it back if it's
   * refused (web `saveShown`); `doing` is what the page says it's busy with.
   */
  func changeAssistant(
    _ doing: String, shown: AssistantSettings? = nil, _ request: @escaping @MainActor () async throws -> AssistantSettings?,
    then: (@MainActor () -> Void)? = nil
  ) {
    guard savingEmber == nil else { return }
    savingEmber = doing
    shownAssistant = shown
    Task {
      defer {
        savingEmber = nil
        shownAssistant = nil
      }
      do {
        let saved = try await request()
        admin.settings?.assistant = saved
        then?()
      } catch {
        admin.failed(doing, error)
      }
    }
  }

  /** Chooses the model @ember answers everyone with, which turns Search the web off when it can't search with it. */
  func chooseDefault(_ model: String) {
    guard var shown = assistant, shown.model != model else { return }
    let searched = shown.webTools?.contains(.search) == true
    shown.model = model
    changeAssistant("Choosing @ember's model", shown: shown) {
      try await self.session.api.changeAssistantSettings(AssistantChanges(model: model))
    } then: {
      guard searched, let now = self.admin.settings?.assistant, now.webTools?.contains(.search) != true else { return }
      self.webSearchLine = (AIText.searchTurnedOff(now.webTools), false)
    }
  }

  func removeModel(_ model: String) {
    guard var shown = assistant else { return }
    shown.models.removeAll { $0.id == model }
    changeAssistant("Removing a model", shown: shown) { try await self.session.api.removeAssistantModel(model) }
  }

  /** The most @ember thinks, or writes, for anyone's question. */
  func setMost(thinking: ThinkingLevel? = nil, length: AnswerLength? = nil) {
    guard var shown = assistant else { return }
    if let thinking { shown.most.thinking = thinking }
    if let length { shown.most.length = length }
    changeAssistant("Changing @ember's limits", shown: shown) {
      try await self.session.api.changeAssistantSettings(AssistantChanges(thinking: thinking, length: length))
    }
  }

  /**
   * Search the web's switch (web `WebSearch`): a model that can't search opens Set up Ember AI; turning on
   * asks the model something it has to search the web for, and says what it found.
   */
  func flipWebSearch(_ on: Bool) {
    guard let assistant, savingEmber == nil else { return }
    guard assistant.webTools != nil else {
      editor = .assistantSetup
      return
    }
    var shown = assistant
    shown.webTools = on ? [.search] : []
    webSearchLine = nil
    savingEmber = on ? AIText.searchingWith(AssistantRules.modelName(assistant.model, in: assistant.models)) : "Turning Search the web off"
    shownAssistant = shown
    Task {
      defer {
        savingEmber = nil
        shownAssistant = nil
      }
      do {
        let changed = try await session.api.changeWebSearch(on)
        admin.settings?.assistant = changed.assistant
        if let found = changed.found { webSearchLine = (AIText.searched(found), false) }
      } catch {
        if let refusal = FormRefusal.of(error, conflicts: true) {
          logger.error("Turning Search the web on was refused: \(refusal.error, privacy: .public)")
          webSearchLine = (refusal.error, true)
        } else {
          admin.failed("Changing Search the web", error)
        }
      }
    }
  }

  /** @ember's instructions, and what Ember adds around them: nil for Ember's own. */
  func saveInstructions(_ instructions: String?, template: String??, then: @escaping @MainActor () -> Void) {
    changeAssistant("Saving @ember's instructions") {
      try await self.session.api.changeAssistantSettings(AssistantChanges(instructions: instructions, promptTemplate: template))
    } then: {
      self.admin.say(AdminText.saved)
      then()
    }
  }

  /** Uploads @ember's avatar, showing it at once (web `saveAvatar`). */
  func changeAvatar(_ photo: ChosenPhoto) {
    guard photo.data.count <= Avatars.maxAvatarSize else { return admin.say(Avatars.avatarTooLarge, error: true) }
    pickedAvatar = photo.variant ?? photo.data
    changeAssistant("Uploading @ember's avatar") {
      defer { self.pickedAvatar = nil }
      return try await self.session.api.changeAssistantAvatar(photo)
    } then: {
      self.admin.say(AdminText.saved)
    }
  }

  func removeAvatar() {
    changeAssistant("Going back to Ember's flame") { try await self.session.api.removeAssistantAvatar() }
  }

  /** The prompt @ember is told around its instructions, for a direct question from whoever's signed in (web `emberPrompt`). */
  func emberPrompt(template: String?) -> Prompt? {
    guard let assistant, let me = session.me else { return nil }
    let levels = AnswerLevels.default.within(assistant.most)
    let web = AssistantRules.webPrompt(askerName: me.name, webTools: assistant.webTools ?? [], webSearchOn: false)
    return Prompts.around(
      answererId: Assistant.id, name: Assistant.name, askerName: me.name, askedIn: AskedIn(community: session.name, roomName: nil, inThread: false),
      words: levels.length.words, web: web, now: Date(), template: template)
  }

  // MARK: Outside AI

  /** Let AI apps connect to Ember: off asks first (web `OutsideAiSettings`). */
  func flipOutside(_ on: Bool) {
    if on { return setOutside(true) }
    admin.confirming = .stopOutsideAi
  }

  func setOutside(_ on: Bool) {
    guard movingOutside == nil else { return }
    movingOutside = on
    admin.run(on ? "Letting AI apps connect" : "Stopping AI apps connecting") {
      defer { self.movingOutside = nil }
      self.admin.settings?.outsideAi = try await self.session.api.changeOutsideAi(on)
    }
  }

  var outsideAddress: String { session.publicOrigin + Outside.mcpPath }

  // MARK: Agents, apps and bots, removed

  func deleteAgent(_ id: UserID, then: (@MainActor () -> Void)? = nil) {
    admin.run("Deleting the agent") {
      try await self.session.api.deleteAgent(id)
      self.agents?.removeAll { $0.id == id }
      then?()
    }
  }

  func removeApp(_ id: AppID, name: String, url: String, then: (@MainActor () -> Void)? = nil) {
    admin.run("Removing the app") {
      let removed = try await self.session.api.disconnectApp(id)
      self.apps?.removeAll { $0.id == id }
      if let revoked = removed.revoked { self.admin.say(AIText.removedNotice(name, url: url, revoked: revoked), error: !revoked) }
      then?()
    }
  }

  func deleteBot(_ id: UserID, then: (@MainActor () -> Void)? = nil) {
    admin.run("Deleting the bot") {
      try await self.session.api.deleteBot(id)
      self.admin.bots?.removeAll { $0.id == id }
      then?()
    }
  }

  func newBotKey(_ id: UserID, then: (@MainActor () -> Void)? = nil) {
    admin.run("Generating a new key") {
      try await self.session.api.resetBotKey(id)
      await self.admin.loadBots()
      then?()
    }
  }

  // MARK: Huddles

  /** Huddles' switch (web `HuddlesSettings`): on opens setup, off asks first. */
  func flipHuddles(_ on: Bool) {
    if on {
      editor = .huddlesSetup
    } else {
      admin.confirming = .stopHuddles
    }
  }

  func stopHuddles() {
    stoppingHuddles = true
    admin.run("Turning huddles off") {
      defer { self.stoppingHuddles = false }
      try await self.session.api.forgetHuddles()
      self.admin.settings?.huddles = nil
      await self.refreshAccount()
    }
  }

  func flipRelay(_ on: Bool) {
    if on {
      editor = .relaySetup
    } else {
      admin.confirming = .stopRelay
    }
  }

  func stopRelay() {
    stoppingRelay = true
    admin.run("Turning the relay off") {
      defer { self.stoppingRelay = false }
      self.admin.settings?.huddles = try await self.session.api.forgetHuddleRelay()
    }
  }

  /** Cameras and Screen sharing (web `HuddleSwitches`): saved at once, showing where they were moved meanwhile. */
  func setCameras(_ on: Bool) {
    guard movedCameras == nil else { return }
    movedCameras = on
    admin.run("Changing cameras in huddles") {
      defer { self.movedCameras = nil }
      self.admin.answered(try await self.session.api.changeAccount(AccountChanges(settings: AccountSettings(huddleCameras: on))))
    }
  }

  func setScreens(_ on: Bool) {
    guard movedScreens == nil else { return }
    movedScreens = on
    admin.run("Changing screen sharing in huddles") {
      defer { self.movedScreens = nil }
      self.admin.answered(try await self.session.api.changeAccount(AccountChanges(settings: AccountSettings(huddleScreens: on))))
    }
  }

  /** Huddles saved: the settings, and the workspace, whose `huddles` the room headers follow. */
  func huddlesSaved(_ huddles: HuddlesSettings?) {
    admin.settings?.huddles = huddles
    Task { await refreshAccount() }
  }

  /** The workspace again, as turning huddles on or off changes `Account.huddles`, which `account.updated` brings too. */
  private func refreshAccount() async {
    do {
      let loaded = try await session.api.workspaceSettings()
      admin.answered(loaded.account)
    } catch {
      logger.error("Reading the workspace after a huddles change failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
