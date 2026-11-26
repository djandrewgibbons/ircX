import EmberKit
import Foundation

/**
 * What IRC Classic's AI assistant, agents, apps, outside AI, chat bots and huddles commands do: each does what
 * Server Settings' control does, printing the result as `-!-` lines, and what needs a form opens it.
 */
@MainActor
enum AICommander {
  static func run(_ command: AdminCommand, session: InstanceSession, room: RoomModel) {
    switch command {
    case let .ai(action): ai(action, session: session, room: room)
    case let .outside(on): outside(on, session: session, room: room)
    case .agents: agents(session: session, room: room)
    case let .agent(action): agent(action, session: session, room: room)
    case let .app(action): app(action, session: session, room: room)
    case .bots: bots(session: session, room: room)
    case let .bot(action): bot(action, session: session, room: room)
    case let .huddles(action): huddles(action, session: session, room: room)
    default: break
    }
  }

  /** Whether `command` is one of these. */
  static func handles(_ command: AdminCommand) -> Bool {
    switch command {
    case .ai, .outside, .agents, .agent, .app, .bots, .bot, .huddles: true
    default: false
    }
  }

  /** Whether `command` is anyone's, rather than an administrator's: your own answer levels, and Available Agents. */
  static func isAnyones(_ command: AdminCommand) -> Bool {
    switch command {
    case .ai(.mine), .agents: true
    default: false
    }
  }

  private static func perform(_ room: RoomModel, _ work: @escaping @MainActor () async throws -> Void) {
    Task {
      do {
        try await work()
      } catch {
        logger.error("An AI command failed: \(error.localizedDescription, privacy: .public)")
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }

  /** Opens Server Settings at `section`, with `editor` over it. */
  private static func open(_ editor: AIEditor?, at section: AdminSection, session: InstanceSession) {
    session.openWorkspaceSettings(section)
    session.admin.ai.editor = editor
  }

  /** Ember AI's settings, or a refusal saying it's off. */
  private static func assistant(_ session: InstanceSession) async throws -> AssistantSettings {
    guard let assistant = try await session.admin.loaded().assistant else { throw EmberError.refused(409, AssistantRules.assistantOff) }
    return assistant
  }

  // MARK: /ai

  private static func ai(_ action: AdminCommand.AI, session: InstanceSession, room: RoomModel) {
    let admin = session.admin
    let ai = admin.ai
    switch action {
    case .open: open(nil, at: .assistant, session: session)
    case .setup: open(.assistantSetup, at: .assistant, session: session)
    case .ember: open(.ember, at: .assistant, session: session)
    case .status:
      perform(room) {
        guard let assistant = try await admin.loaded().assistant else { return room.note("Ember AI: off (/ai setup)") }
        room.print([
          "Ember AI: on, model \(AssistantRules.modelName(assistant.model, in: assistant.models)) [\(assistant.model)]",
          "Account: \(assistant.accountId) · \(assistant.models.count) pickable · search \(assistant.webTools?.contains(.search) == true ? "on" : "off")",
          "Limits: thinking \(assistant.most.thinking.name.lowercased()), length \(assistant.most.length.name.lowercased())",
        ])
      }
    case .off:
      perform(room) {
        _ = try await assistant(session)
        session.confirmation = .admin(.stopAssistant)
      }
    case .models:
      perform(room) {
        let assistant = try await assistant(session)
        if ai.offered == nil { await ai.loadOffered() }
        var lines = assistant.models.map { "\($0.id == assistant.model ? "*" : " ") \($0.name) [\($0.id)]" }
        if let offered = ai.offered {
          lines.append("Offered:")
          for group in AssistantRules.grouped(offered.models) {
            lines += group.models.map { "  [\(group.label)] \(AssistantRules.entry($0)) [\($0.id)]" }
          }
          if let workersAi = offered.workersAi { lines.append(workersAi) }
        }
        room.print(lines)
      }
    case let .defaultModel(model):
      perform(room) {
        let assistant = try await assistant(session)
        guard assistant.models.contains(where: { $0.id == model }) else { throw EmberError.refused(422, AssistantRules.modelNotListed) }
        admin.settings?.assistant = try await session.api.changeAssistantSettings(AssistantChanges(model: model))
        room.note("@ember answers everyone with \(AssistantRules.modelName(model, in: assistant.models)) now")
      }
    case let .add(model):
      perform(room) {
        _ = try await assistant(session)
        room.note(AIText.askingTestQuestion(AssistantRules.modelName(model)))
        let saved = try await session.api.addAssistantModel(model)
        admin.settings?.assistant = saved.assistant
        room.print([AIText.modelAdded(AssistantRules.modelName(model, in: saved.assistant.models)), saved.greeting])
      }
    case let .remove(model):
      perform(room) {
        _ = try await assistant(session)
        admin.settings?.assistant = try await session.api.removeAssistantModel(model)
        room.note("People can't pick \(model) any more")
      }
    case let .search(on):
      perform(room) {
        let assistant = try await assistant(session)
        let name = AssistantRules.modelName(assistant.model, in: assistant.models)
        if on {
          guard assistant.webTools != nil else { throw EmberError.refused(422, AssistantRules.cannotSearchWith(name)) }
          room.note(AIText.searchingWith(name))
        }
        let changed = try await session.api.changeWebSearch(on)
        admin.settings?.assistant = changed.assistant
        if let found = changed.found { room.note(AIText.searched(found)) } else { room.note("Search the web is \(on ? "on" : "off")") }
      }
    case let .think(level):
      perform(room) {
        _ = try await assistant(session)
        admin.settings?.assistant = try await session.api.changeAssistantSettings(AssistantChanges(thinking: level))
        room.note("@ember thinks at most at \(level.name)")
      }
    case let .length(length):
      perform(room) {
        _ = try await assistant(session)
        admin.settings?.assistant = try await session.api.changeAssistantSettings(AssistantChanges(length: length))
        room.note("@ember answers at most \(length.name.lowercased())")
      }
    case .prompt:
      perform(room) {
        let assistant = try await assistant(session)
        guard let prompt = ai.emberPrompt(template: assistant.promptTemplate) else { return }
        let instructions = assistant.instructions.isEmpty ? "-!- [\(AIText.yourInstructions)]" : assistant.instructions
        room.print((prompt.before + instructions + prompt.after).components(separatedBy: "\n"))
      }
    case let .mine(thinking, length, model):
      perform(room) {
        if thinking == nil, length == nil, model == nil {
          guard let mine = try await session.api.profile().profile.assistant else { return room.note(AssistantRules.assistantOff, kind: .error) }
          let fallback = "Default (\(AssistantRules.modelName(mine.defaultModel, in: mine.models)))"
          let answering = mine.model.map { AssistantRules.modelName($0, in: mine.models) } ?? fallback
          return room.print([
            "Your @ember: \(answering) · thinking \(mine.levels.thinking.name.lowercased()) · length \(mine.levels.length.name.lowercased())",
            "Up to thinking \(mine.most.thinking.name.lowercased()), length \(mine.most.length.name.lowercased()) · models: \(mine.models.map(\.id).joined(separator: ", "))",
          ])
        }
        guard try await session.api.changeYourAssistant(YourAssistantChanges(thinking: thinking, length: length, model: model)) != nil else {
          return room.note(AssistantRules.assistantOff, kind: .error)
        }
        room.note("Your @ember levels are saved")
      }
    }
  }

  // MARK: /outside

  private static func outside(_ on: Bool?, session: InstanceSession, room: RoomModel) {
    let admin = session.admin
    perform(room) {
      let settings = try await admin.loaded()
      switch on {
      case nil:
        room.note(settings.outsideAi ? AIText.outsideAiAddress(admin.ai.outsideAddress) : "Outside AI: off (/outside on)")
      case true?:
        admin.settings?.outsideAi = try await session.api.changeOutsideAi(true)
        room.note(AIText.outsideAiAddress(admin.ai.outsideAddress))
      case false?:
        guard settings.outsideAi else { return room.note("Outside AI is off already", kind: .error) }
        session.confirmation = .admin(.stopOutsideAi)
      }
    }
  }

  // MARK: /agents, /agent

  private static func agents(session: InstanceSession, room: RoomModel) {
    guard session.me?.administrator == true else {
      session.showingAgents = true
      return
    }
    let ai = session.admin.ai
    perform(room) {
      let assistant = try await assistant(session)
      await ai.loadAgents()
      var lines = ["@ember  \(ai.emberDetails(assistant).joined(separator: "  "))  [\(AIText.builtIn)]"]
      lines += ai.listedAgents.map { "\($0.name)  \(ai.agentDetails($0).joined(separator: "  "))  — \($0.description)" }
      if ai.listedAgents.isEmpty { lines.append("No agents yet (/agent new)") }
      room.print(lines)
    }
  }

  /** The agent `text` starts with, by its name, the longest that matches, and what follows it. */
  private static func agent(named text: String, session: InstanceSession) async throws -> (agent: Agent, rest: String) {
    let ai = session.admin.ai
    if ai.agents == nil { await ai.loadAgents() }
    let lowered = text.lowercased()
    let found = ai.listedAgents.filter { lowered == $0.name.lowercased() || lowered.hasPrefix($0.name.lowercased() + " ") }.max { $0.name.count < $1.name.count }
    guard let found else { throw EmberError.refused(404, "\(text): No such agent (/agents lists them)") }
    return (found, String(text.dropFirst(found.name.count)).trimmingCharacters(in: .whitespaces))
  }

  /** What an answer says, as lines of text. */
  private static func lines(of body: String, session: InstanceSession) throws -> [String] {
    try Display.body(body, plainText: "", host: session.instance.host).map { node in
      node.plainText { id in session.people[id].map(\.name) ?? id }
    }
    .flatMap { $0.components(separatedBy: "\n") }
  }

  private static func agent(_ action: AdminCommand.AgentAction, session: InstanceSession, room: RoomModel) {
    switch action {
    case .new: open(.agent(nil), at: .assistant, session: session)
    case let .open(name):
      if ["ember", "@ember"].contains(name.lowercased()) { return open(.ember, at: .assistant, session: session) }
      perform(room) { open(.agent(try await agent(named: name, session: session).agent.id), at: .assistant, session: session) }
    case let .remove(name):
      perform(room) {
        let found = try await agent(named: name, session: session).agent
        session.confirmation = .admin(.deleteAgent(found.id, name: found.name))
      }
    case let .trial(text):
      perform(room) {
        let (found, question) = try await agent(named: text, session: session)
        guard !question.isEmpty else { throw EmberError.refused(422, AgentRules.questionNeeded) }
        let settings = try await session.api.agent(found.id)
        room.note(AIText.askingYourQuestion(settings.modelName))
        let trial = AgentTrial(
          name: settings.name, instructions: settings.instructions, promptTemplate: settings.promptTemplate, model: settings.model,
          thinking: settings.levels.thinking, length: settings.levels.length, webSearch: settings.webTools.contains(.search), question: question)
        let answer = try await session.api.tryAgent(trial, agent: found.id)
        room.print(try lines(of: answer.body, session: session).map { "<\(settings.name)> \($0)" })
        room.note(AIText.answeredIn(answer.ms))
      }
    case let .tools(name):
      perform(room) {
        let (id, called) = try await toolsOwner(name, session: session)
        let apps = try await session.api.agentTools(id)
        guard !apps.isEmpty else { return room.note(AIText.noAppsToPick) }
        var lines = ["\(called): \(AIText.picked(ToolsModel.picks(apps).count))"]
        for app in apps {
          lines += app.tools.map { "[\($0.picked ? "x" : " ")] \(app.name):\($0.name)\($0.alwaysAllowed ? "  (always)" : "")\($0.changed ? "  (changed)" : "")" }
        }
        room.print(lines)
      }
    case let .tool(text):
      perform(room) { try await tool(text, session: session, room: room) }
    }
  }

  /** `/agent tool name +app:tool|-app:tool|always app:tool|ask app:tool`: picks one tool, saving every pick. */
  private static func tool(_ text: String, session: InstanceSession, room: RoomModel) async throws {
    let pieces = text.split(separator: " ").map(String.init)
    guard pieces.count >= 2, let last = pieces.last else {
      throw EmberError.refused(422, "/agent tool takes an agent's name, then +app:tool, -app:tool, always app:tool or ask app:tool")
    }
    var verb = "+"
    var target = last
    var nameWords = Array(pieces.dropLast())
    if let first = target.first, first == "+" || first == "-" {
      verb = String(first)
      target = String(target.dropFirst())
    } else if let word = nameWords.last?.lowercased(), word == "always" || word == "ask" {
      verb = word
      nameWords.removeLast()
    }
    let pair = target.split(separator: ":", maxSplits: 1).map(String.init)
    guard pair.count == 2 else { throw EmberError.refused(422, "Name the tool as app:tool") }
    let (id, called) = try await toolsOwner(nameWords.joined(separator: " "), session: session)
    let model = ToolsModel(session: session, agent: id)
    await model.load()
    if let failure = model.failure { throw EmberError.refused(422, failure) }
    guard let app = (model.apps ?? []).first(where: { $0.name.caseInsensitiveCompare(pair[0]) == .orderedSame }) else {
      throw EmberError.refused(404, "\(pair[0]): No such app (/agent tools \(called))")
    }
    switch verb {
    case "+": try await model.set(app.id, pair[1], picked: true)
    case "-": try await model.set(app.id, pair[1], picked: false)
    default: try await model.set(app.id, pair[1], picked: true, alwaysAllowed: verb == "always")
    }
    room.note("\(called): \(AIText.picked(model.picked))")
  }

  /** @ember, or the agent named, whose tools these are. */
  private static func toolsOwner(_ name: String, session: InstanceSession) async throws -> (UserID, String) {
    if ["ember", "@ember"].contains(name.lowercased()) { return (Assistant.id, "@ember") }
    let found = try await agent(named: name, session: session).agent
    return (found.id, found.name)
  }

  // MARK: /apps

  private static func app(named name: String, session: InstanceSession) async throws -> AppSummary {
    let ai = session.admin.ai
    if ai.apps == nil { await ai.loadApps() }
    guard let found = (ai.apps ?? []).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
      throw EmberError.refused(404, "\(name): No such app (/apps admin lists them)")
    }
    return found
  }

  private static func app(_ action: AdminCommand.AppAction, session: InstanceSession, room: RoomModel) {
    let ai = session.admin.ai
    switch action {
    case .connect: open(.app(nil), at: .assistant, session: session)
    case .list:
      perform(room) {
        _ = try await assistant(session)
        await ai.loadApps()
        let apps = ai.apps ?? []
        guard !apps.isEmpty else { return room.note(AIText.noApps) }
        room.print(
          apps.map { app in
            var line = "\(app.name)  \(app.url)  \(AIText.tools(app.toolCount))"
            if app.signInEnded { line += "  [\(AIText.signInEnded)]" } else if app.wantsAccess { line += "  [\(AIText.wantsAccess)]" }
            if app.setAside > 0 { line += "  [\(AIText.setAside(app.setAside))]" }
            return line
          })
      }
    case let .open(name), let .signIn(name):
      perform(room) { open(.app(try await app(named: name, session: session).id), at: .assistant, session: session) }
    case let .reread(name):
      perform(room) {
        let found = try await app(named: name, session: session)
        room.note(AIText.readingTools)
        let read = try await session.api.readAppTools(found.id)
        await ai.loadApps()
        room.note("Ember read \(AIText.tools(read.tools.count)) from \(read.name)")
      }
    case let .remove(name):
      perform(room) {
        let found = try await app(named: name, session: session)
        session.confirmation = .admin(.removeApp(found.id, name: found.name, url: found.url))
      }
    }
  }

  // MARK: /bots, /bot

  private static func bot(named name: String, session: InstanceSession) async throws -> Bot {
    let admin = session.admin
    if admin.bots == nil { await admin.loadBots() }
    guard let found = admin.listedBots.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
      throw EmberError.refused(404, "\(name): No such bot (/bots lists them)")
    }
    return found
  }

  private static func bots(session: InstanceSession, room: RoomModel) {
    let admin = session.admin
    perform(room) {
      await admin.loadBots()
      if let failure = admin.botsFailure { return room.note(failure, kind: .error) }
      guard !admin.listedBots.isEmpty else { return room.note("No chat bots yet (/bot new)") }
      room.print(admin.listedBots.map { "\($0.name)  \($0.rooms.isEmpty ? AdminText.noRooms : AgentReach.names($0.rooms))" })
    }
  }

  private static func bot(_ action: AdminCommand.BotAction, session: InstanceSession, room: RoomModel) {
    switch action {
    case .new: open(.bot(nil), at: .bots, session: session)
    case let .open(name): perform(room) { open(.bot(try await bot(named: name, session: session).id), at: .bots, session: session) }
    case let .urls(name):
      perform(room) {
        let found = try await bot(named: name, session: session)
        guard !found.rooms.isEmpty else { return room.note(AIText.noAddresses) }
        var lines: [String] = []
        for place in found.rooms {
          let messages = session.publicOrigin + BotsRules.messagesPath(room: place.id, key: found.key)
          lines += ["#\(place.name):", AIText.curlText(messages), AIText.curlUpload(messages), session.publicOrigin + BotsRules.slackPath(room: place.id, key: found.key)]
        }
        room.print(lines)
      }
    case let .key(name):
      perform(room) {
        let found = try await bot(named: name, session: session)
        session.confirmation = .admin(.newBotKey(found.id, name: found.name))
      }
    case let .remove(name):
      perform(room) {
        let found = try await bot(named: name, session: session)
        session.confirmation = .admin(.deleteBot(found.id, name: found.name))
      }
    }
  }

  // MARK: /huddles

  private static func huddles(_ action: AdminCommand.HuddlesAction, session: InstanceSession, room: RoomModel) {
    let admin = session.admin
    switch action {
    case .on, .keys: open(.huddlesSetup, at: .huddles, session: session)
    case .status:
      perform(room) {
        let settings = try await admin.loaded()
        guard let huddles = settings.huddles else { return room.note("Huddles: off (/huddles on)") }
        let account = settings.account
        room.note(
          "Huddles: on (SFU app \(huddles.appId)) relay: \(huddles.relayKeyId ?? "none") cameras: \(account.huddleCameras ? "on" : "off") screens: \(account.huddleScreens ? "on" : "off")"
        )
      }
    case .off:
      perform(room) {
        guard try await admin.loaded().huddles != nil else { return room.note("Huddles are off already", kind: .error) }
        session.confirmation = .admin(.stopHuddles)
      }
    case let .cameras(on):
      perform(room) {
        admin.answered(try await session.api.changeAccount(AccountChanges(settings: AccountSettings(huddleCameras: on))))
        room.note("Cameras in huddles: \(on ? "on" : "off")")
      }
    case let .screens(on):
      perform(room) {
        admin.answered(try await session.api.changeAccount(AccountChanges(settings: AccountSettings(huddleScreens: on))))
        room.note("Screen sharing in huddles: \(on ? "on" : "off")")
      }
    case let .relay(on):
      perform(room) {
        guard let huddles = try await admin.loaded().huddles else { throw EmberError.refused(409, Huddles.relayWithoutHuddles) }
        if on { return open(.relaySetup, at: .huddles, session: session) }
        guard huddles.relayKeyId != nil else { return room.note("The relay is off already", kind: .error) }
        session.confirmation = .admin(.stopRelay)
      }
    }
  }
}
