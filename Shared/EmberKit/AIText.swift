import Foundation

// The AI assistant, chat bots and huddles admin screens' rules and words: packages/protocol/src/assistant.ts's
// pure functions the web app calls, and apps/web's assistant-settings, assistant-setup, model-picker,
// ember-settings, level-dials, prompt-preview, agent-list, agent-page, agent-tools, app-list, app-page,
// outside-ai-settings, bots-page, bot-settings-page, huddles-settings, huddles-steps, relay-setup and
// setup-huddles copy, so both themes say what the web says.

extension AssistantRules {
  /** `THINKING_TOKENS` */
  public static func thinkingTokens(_ level: ThinkingLevel) -> Int {
    switch level {
    case .off: 0
    case .low: 4_000
    case .medium: 16_000
    case .high: 32_000
    }
  }

  /** `ANSWER_TOKENS` */
  public static func answerTokens(_ length: AnswerLength) -> Int {
    switch length {
    case .short: 1_000
    case .medium: 2_000
    case .long: 6_000
    }
  }

  /** `UNTHINKING_TOKENS` */
  public static let unthinkingTokens = 2_000

  /** `thinkingTokensAt` */
  public static func thinkingTokens(at level: ThinkingLevel) -> Int { level == .off ? unthinkingTokens : thinkingTokens(level) }

  /** `maxTokensAt` */
  public static func maxTokens(at levels: AnswerLevels) -> Int { thinkingTokens(at: levels.thinking) + answerTokens(levels.length) }

  /** `thinkingTaken`: the level a model that takes `taken` is asked for in place of `level`, or nil for one that takes none. */
  public static func thinkingTaken(_ level: ThinkingLevel, _ taken: [ThinkingLevel]?) -> ThinkingLevel? {
    guard let taken, !taken.contains(level) else { return level }
    let all = ThinkingLevel.allCases
    guard let index = all.firstIndex(of: level) else { return nil }
    if let below = all[..<index].reversed().first(where: taken.contains) { return below }
    return all[(index + 1)...].first(where: taken.contains)
  }

  /** `offeredModelOf` */
  public static func offeredModel(_ model: String, in offered: [OfferedModel]) -> OfferedModel? { offered.first { $0.id == model } }

  /** `noLongerOffered` */
  public static func noLongerOffered(_ model: String, offered: [OfferedModel], workersAi: String?) -> Bool {
    offeredModel(model, in: offered) == nil && !(isWorkersAiModel(model) && workersAi != nil)
  }

  /** `isXaiModel` */
  public static func isXaiModel(_ model: String) -> Bool { model.hasPrefix("xai/") }

  /** `providerFormatOf` */
  public static func providerFormat(_ model: String) -> ModelFormat? {
    if model.hasPrefix("anthropic/") { return .anthropic }
    return model.hasPrefix("openai/") ? .openai : nil
  }

  /** `formatOf` */
  public static func format(of model: String, in models: [AssistantModel] = []) -> ModelFormat {
    if let listed = models.first(where: { $0.id == model }) { return listed.format }
    if let shipped = shippedModels.first(where: { $0.id == model }) { return shipped.format }
    if let provider = providerFormat(model) { return provider }
    return isWorkersAiModel(model) ? .workers : .chat
  }

  /** `searchFormatOf` */
  public static func searchFormat(_ model: String, _ format: ModelFormat) -> ModelFormat? {
    if isXaiModel(model) { return .chat }
    if format == .chat { return isWorkersAiModel(model) ? .workers : nil }
    return webTools(in: format).isEmpty ? nil : format
  }

  /** `webToolsOf` */
  public static func webTools(of model: String, format: ModelFormat, offered: [OfferedModel]) -> [WebTool] {
    guard let searchesIn = searchFormat(model, format), searchesIn == format || format == .xai else { return [] }
    if let listed = offered.first(where: { $0.id == model && searchFormat($0.id, $0.format) == searchesIn }), let tools = listed.webTools { return tools }
    return webTools(in: format)
  }

  /** `webPromptFor`: what an answerer is told it may do on the web. */
  public static func webPrompt(askerName: String, webTools: [WebTool], webSearchOn: Bool) -> String {
    if !webTools.contains(.search), webSearchOn {
      return "You can't search the web or open links with the model \(quoted(askerName)) picked for your answers to them. When they ask you to, say so, and that they can pick one that can under Ember AI on their profile."
    }
    if !webTools.contains(.search) {
      return "You can't search the web or open links. When someone asks you to, say so, and that an administrator can turn on Search the web under \(Prompts.aiSettings)."
    }
    let reading = webTools.contains(.read) ? ", and read the pages people link to or your searches find," : ""
    return "You can search the web\(reading) when a question needs what's current, or what you don't know. Only what you write after you last search or read is posted, so write all of your answer then. The chat lists the pages you cite after it, so don't list them yourself."
  }

  /** `quoted`, as the prompts write a name. */
  static func quoted(_ name: String) -> String {
    let spaced = name.replacing(#/[\s\p{Cc}]+/#, with: " ").trimmingCharacters(in: .whitespaces)
    let unquoted = spaced.replacing(#/["\u{201C}-\u{201F}\u{FF02}]/#, with: "'")
    return "\"" + unquoted + "\""
  }

  /** The makers the model menu groups by (`MAKERS`), then Workers AI's. */
  public static let makers: [(prefix: String, label: String)] = [("anthropic/", "Anthropic"), ("openai/", "OpenAI"), ("xai/", "xAI")]

  /** `makerOf`: who makes `model`, or nil for one Cloudflare runs on Workers AI. */
  public static func maker(of model: String) -> String? { makers.first { model.hasPrefix($0.prefix) }?.label }

  /** The menu's groups (web `ModelPicker`): each maker's models, then Workers AI's. */
  public static func grouped(_ models: [OfferedModel]) -> [(label: String, models: [OfferedModel])] {
    var groups = makers.map { maker in (label: maker.label, models: models.filter { $0.id.hasPrefix(maker.prefix) && $0.format != .workers }) }
    groups.append((label: "Workers AI", models: models.filter { $0.format == .workers }))
    return groups.filter { !$0.models.isEmpty }
  }

  /** `dollars`: US dollars, with cents or fractions of one when it has them. */
  public static func dollars(_ amount: Double) -> String {
    let whole = amount.rounded() == amount
    return amount.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(whole ? 0...0 : 2...3)))
  }

  /** `shortPrice`: a million tokens read, then written. */
  public static func shortPrice(_ price: ModelPrice) -> String { "\(dollars(price.input)) / \(dollars(price.output))" }

  /** A menu entry: the name, and its price when it's known. */
  public static func entry(_ model: OfferedModel) -> String {
    guard let price = model.price else { return model.name }
    return "\(model.name) · \(shortPrice(price))"
  }

  /** `dayOf`: YYYY-MM-DD written out. */
  public static func day(_ day: String) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = .gmt
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: day) else { return day }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: .gmt))
  }

  /** `dashboard`: a page of the Cloudflare dashboard, in the account `accountId` names, or the one it asks for. */
  public static func dashboard(_ accountId: String?, _ path: String) -> String {
    guard let accountId else { return "https://dash.cloudflare.com/?to=/:account/\(path)" }
    return "https://dash.cloudflare.com/\(accountId)/\(path)"
  }

  /** What a model costs, and where that's paid (web `Cost`). */
  public struct CostNote: Sendable, Equatable {
    public var text: String
    public var linkTitle: String?
    public var link: String?
  }

  /** What the model picker's cost note says of `model`: what it costs and who pays, or that Ember no longer offers it. */
  public static func cost(of model: String, offered: [OfferedModel], workersAi: String?, accountId: String?) -> CostNote {
    let costed: (id: String, format: ModelFormat, price: ModelPrice?, until: String?)
    if let listed = offeredModel(model, in: offered) {
      costed = (listed.id, listed.format, listed.price, listed.until)
    } else if noLongerOffered(model, offered: offered, workersAi: workersAi) {
      return CostNote(text: AIText.noLongerOfferedNote)
    } else {
      costed = (model, .workers, nil, nil)
    }
    var stops = ""
    if let until = costed.until {
      let runner = maker(of: costed.id) ?? "Cloudflare"
      stops = " \(runner) plans to stop running it on \(day(until))."
    }
    var price = ""
    if costed.format == .workers {
      if let known = costed.price {
        price = ", at \(dollars(known.input)) for each million tokens it reads, and \(dollars(known.output)) for each million it writes"
      }
      return CostNote(
        text:
          "Cloudflare runs this model on Workers AI, free for the account's first 10,000 Neurons each day, and beyond that on Workers Paid\(price). AI Gateway's credits pay for its searches of the web, and for the model too once the default gateway's Workers AI Billing is Unified billing.\(stops)",
        linkTitle: "Open Workers AI", link: dashboard(accountId, "ai/workers-ai"))
    }
    if let known = costed.price { price = ", \(dollars(known.input)) for each million tokens it reads, and \(dollars(known.output)) for each million it writes" }
    return CostNote(
      text: "AI Gateway's credits pay for this model\(price). Top them up under Credits Available in AI Gateway.\(stops)", linkTitle: "Open AI Gateway",
      link: dashboard(accountId, "ai/ai-gateway"))
  }

  /** `startingModelOf`: `model` while it's offered, else Ember's suggestion. */
  public static func startingModel(_ model: String?, offered: OfferedModels) -> String {
    guard let model, offeredModel(model, in: offered.models) != nil else { return offered.suggested }
    return model
  }

  /** `SHIPPED_MODELS`, with why Workers AI's aren't listed (`offeredModelsThrough`'s fallback). */
  public static func shipped(workersAi: String) -> OfferedModels { OfferedModels(models: shippedModels, suggested: suggestedModel, workersAi: workersAi) }

  /** `modelsToAddTo`: the offered models people can't pick yet. */
  public static func modelsToAdd(_ assistant: AssistantSettings, offered: [OfferedModel]) -> [OfferedModel] {
    offered.filter { model in !assistant.models.contains { $0.id == model.id } }
  }

  /** The most an answer costs at `price` (web `mostCostOf`), having been `told` the prompt around the conversation. */
  public static func mostCost(told: String, levels: AnswerLevels, price: ModelPrice) -> Double {
    let read = ((Double(maxConversationLength + told.utf16.count)) / 4).rounded(.up)
    return (read * price.input + Double(maxTokens(at: levels)) * price.output) / 1_000_000
  }

  /** `costOf`: an answer's cost in cents under a dollar, else dollars. */
  public static func answerCost(_ amount: Double) -> String {
    let cents = Int((amount * 100).rounded())
    if cents < 1 { return "less than a cent" }
    return cents < 100 ? "\(cents)¢" : dollars(Double(cents) / 100)
  }

  /** `secondsOf`: how long Try it's answer took, to a tenth under ten seconds. */
  public static func seconds(_ ms: Double) -> String {
    let seconds = max(ms, 100) / 1000
    return seconds < 10 ? "\(String(format: "%.1f", seconds)) seconds" : "\(Int(seconds.rounded())) seconds"
  }

  /** `lengthOf`: how many of the 10,000 characters `text` has. */
  public static func length(of text: String) -> String {
    let format = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "en_US"))
    return "\(text.utf16.count.formatted(format)) of \(maxInstructionsLength.formatted(format)) characters"
  }

  /** What the Thinking dial says under it (web `thinkingNoteOf`), for a model called `name` that takes `takes`. */
  public static func thinkingNote(_ level: ThinkingLevel, modelName name: String?, takes: [ThinkingLevel]?) -> String {
    let format = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "en_US"))
    let note: String
    switch level {
    case .off: note = "Answers at once, without thinking first."
    case .low: note = "Thinks a little first, up to about \(thinkingTokens(.low).formatted(format)) tokens."
    case .medium: note = "Thinks more first, up to about \(thinkingTokens(.medium).formatted(format)) tokens."
    case .high: note = "Thinks the most first, up to about \(thinkingTokens(.high).formatted(format)) tokens, which takes longest."
    }
    guard let name, let takes, takes.count != ThinkingLevel.allCases.count else { return note }
    if takes.isEmpty { return "\(name) can't be told how much to think, so it decides for itself, up to about \(thinkingTokens(at: level).formatted(format)) tokens." }
    guard let asked = thinkingTaken(level, takes) else { return note }
    if asked != level { return "\(name) can't be set to \(level.name), so it thinks at \(asked.name) instead." }
    let refused = ThinkingLevel.allCases.filter { !takes.contains($0) }.map(\.name)
    return "\(note) \(name) can't be set to \(refused.formatted(.list(type: .or).locale(Locale(identifier: "en_US"))))."
  }

  /** What the Answer length dial says under it (`LENGTH_NOTES`). */
  public static func lengthNote(_ length: AnswerLength) -> String {
    switch length {
    case .short: "About 150 words."
    case .medium: "About 400 words."
    case .long: "About 1,500 words, nearly all one message holds."
    }
  }
}

/** The AI assistant, agents, apps, outside AI, chat bots and huddles screens' words, as the web app has them. */
public enum AIText {
  // Ember AI (assistant-settings.tsx, assistant-setup.tsx)
  public static let whatAgentsSend =
    "Mention an agent, or write to it directly, and it answers, sending the thread, or the room's latest messages, through Cloudflare to its model."
  public static let confirmStopAssistant =
    "Are you sure you want to turn off Ember AI? @ember and the agents will leave every room, and Ember will forget the API token and the models people can pick. It keeps each agent for when Ember AI is on again."
  public static let setupExplained =
    "Ember AI asks Claude, GPT or Grok through your Cloudflare account's AI Gateway, paid for with AI Gateway's credits, or a model Cloudflare runs on Workers AI. Ember keeps the API token encrypted."
  public static let tokenSteps = [
    "In the Cloudflare dashboard, open Account API tokens and choose Create Token.",
    "Under Custom Token, choose Get started, name the token, and under Permissions choose Account, AI Gateway and Run. Then Add more: Account, AI Gateway and Read, and Account, Workers AI and Read.",
    "Choose Continue to summary, then Create Token, and copy the token here.",
  ]
  public static let accountIdStep = "Copy the account's ID too: search the dashboard for Copy account ID."
  public static let deployedAccount = "Ember is deployed to this account. To ask through another, paste that account's ID."
  public static let tokenKept =
    "Ember has an API token already. Leave this blank to keep it, or paste another to ask with it instead. Either needs the AI Gateway Run and Read and the Workers AI Read permissions."
  public static let chooseModel =
    "Choose the model @ember answers everyone with. Ember asks it a test question through AI Gateway before keeping it. You can let people pick other models later."
  public static func askingTestQuestion(_ name: String) -> String { "Asking \(name) a test question…" }
  public static func setUp(_ name: String) -> String { "@ember is in every room open to everyone, running on \(name). Asked to say hello, it said:" }
  public static func searchTurnedOff(_ webTools: [WebTool]?, changed: String = "model") -> String {
    webTools == nil ? "Search the web is off, as this model can't search the web through AI Gateway." : "Search the web is off for the new \(changed). Turn it on again to try it."
  }

  // The model picker (model-picker.tsx, use-offered-models.ts)
  public static let noLongerOffered = "no longer offered"
  public static let listingModels = "Listing the models Ember offers…"
  public static let offeredUnread = "Workers AI's models aren't listed, as Ember couldn't list them. Try again in a moment."
  public static let noLongerOfferedNote = "Ember no longer offers this model. It answers as it did until you choose one that Ember offers."

  // @ember's page (ember-settings.tsx, add-assistant-model.tsx)
  public static let emberExplained = "Ember's own agent, @ember, which answers anything people ask in every room open to everyone."
  public static let emberInstructionsExplained =
    "@ember follows Ember's own instructions. Add yours to them, such as how your team likes answers written, or what to leave to people."
  public static let instructionsUnsaved = "You’ve changed @ember’s instructions. Save them before you leave, or discard them to keep things as they were."
  public static let instructionsPlaceholder = "Answer in British English, and send billing questions to the Support room."
  public static let modelsExplained = "People can pick any of these on their profile for @ember to answer them with. The one chosen here answers everyone else."
  public static let everyModelAdded = "People can pick every model Ember offers."
  public static let limitsExplained =
    "The most @ember may think and write for anyone's question. Each person picks their own levels on their profile, up to these. AI Gateway's spend limits can cap what each person's questions cost, as every request says who asked."
  public static let webSearchOff =
    "@ember answers from what its model learned in training. Turn this on to let it search the web when a question needs what's current, at most 5 times an answer, and list the pages it used under its answer."
  public static func webSearchOn(_ webTools: [WebTool], models: Int) -> String {
    let reads = webTools.contains(.read) ? ", and reads the pages people link to or its searches find, at most 3" : ""
    let picked = models > 1 ? " A model someone picks searches too, if it can." : ""
    return "@ember searches the web when a question needs it, at most 5 times an answer\(reads), and lists the pages it used under its answer.\(picked) AI Gateway's credits pay for each search."
  }
  public static func searchingWith(_ name: String) -> String { "Asking \(name) something it has to search the web for…" }
  public static func searched(_ found: String) -> String { "It searched the web and said: \(found)" }
  public static let avatarExplained = "Everyone sees it beside @ember's answers. Choose a picture of your own in place of Ember's flame."
  public static let uploadedAvatarExplained = "Everyone sees it beside @ember's answers. Choose another picture, or go back to Ember's flame."
  public static let addModelExplained =
    "Choose a model people can pick for @ember to answer them with. Ember asks it a test question through AI Gateway before adding it."
  public static func modelAdded(_ name: String) -> String { "People can pick \(name) on their profile now. Asked to say hello, it said:" }

  // What Ember adds around the instructions (prompt-preview.tsx)
  public static func aroundExplained(_ name: String) -> String {
    "Ember tells \(name) who it is, how the chat shows an answer and the cards it can show under one, and where it's asked, then gives it the conversation, each message after its writer's name. Your instructions go after who it is. For a question you write to it directly, it reads:"
  }
  public static func cautionFor(_ name: String) -> String {
    "Every answer \(name) gives starts from these words. A change here can leave it unsure who it is, where it's asked or what the chat can show, so change only what you need to."
  }
  public static func placeholdersExplained(_ name: String) -> String { "Ember fills in each of these whenever \(name) is asked:" }
  /** `PLACEHOLDER_MEANINGS`, in `Prompts.placeholders`' order. */
  public static let placeholderMeanings: [(name: String, meaning: String)] = [
    ("name", "its name"), ("community", "the community's name"), ("where", "the room, thread or direct message it's asked in"),
    ("asker", "the name of whoever asked"), ("words", "about how many words it may answer in"),
    ("cards", "how it can show cards under its answer, with what they can hold and how to write them"), ("web", "what it may do on the web"),
    ("today", "today's date and the time, in UTC"), ("instructions", "your instructions, which it needs once"),
  ]
  public static let yourInstructions = "Your instructions"

  // Agents (agent-list.tsx, agent-page.tsx, agent-tools.tsx, lib/agents.ts)
  public static let agentsExplained =
    "People mention an agent by name, and it answers following the instructions you gave it, on the model you chose for it. You can make up to 20."
  public static let searchesTheWeb = "Searches the web"
  public static let everyRoom = "Every room"
  public static let dmsOnly = "Direct messages only"
  public static func keptFor(_ access: AgentAccess) -> String? {
    switch access {
    case .everyone: nil
    case .admins: "Admins only"
    case .adminDms: "Admin DMs only"
    }
  }
  public static let builtIn = "Built in"
  public static let agentExplained = "An AI agent people mention by name. It follows your instructions, on the model you choose, through Cloudflare AI Gateway."
  public static let agentInstructionsExplained =
    "The agent's system prompt: its task, how to go about it, and what to leave alone. Anyone who can ask it could get it to repeat these, so leave out anything secret."
  public static let agentChanges = "You’ve made changes to this agent. Save them before you leave, or discard them to keep things as they were."
  public static let confirmDeleteAgent = "Are you sure you want to delete this agent? It leaves every room for good, though its answers stay. This can’t be undone."
  public static let agentNameExplained = "People mention it as @name. Nobody else here can have its name."
  public static let agentDescriptionExplained = "Shown in the list of agents, so people know when to ask it."
  public static let agentAvatarExplained = "Everyone sees it beside the agent's answers."
  public static func tryExplained(_ name: String) -> String { "Ask \(name) something, as it's set up above, before you save. Nobody else sees what it says." }
  public static func askingYourQuestion(_ name: String) -> String { "Asking \(name) your question…" }
  public static func answeredIn(_ ms: Double) -> String { "Answered in \(AssistantRules.seconds(ms))." }
  public static let unshowableAnswer = "Ember couldn't show this answer."
  public static func cannotSearch(_ name: String) -> String { "\(name) can't search the web through AI Gateway, but the other models Ember offers can." }
  public static let agentWebSearchOff =
    "It answers from what its model learned in training. Turn this on to let it search the web when a question needs what's current, at most 5 times an answer, and list the pages it used under its answer."
  public static func agentWebSearchOn(_ webTools: [WebTool]) -> String {
    let reads = webTools.contains(.read) ? ", and reads the pages people link to or its searches find, at most 3" : ""
    return "It searches the web when a question needs it, at most 5 times an answer\(reads), and lists the pages it used under its answer. AI Gateway's credits pay for each search."
  }
  public static func roomsExplained(_ called: String, _ access: AgentAccess) -> String {
    switch access {
    case .adminDms: "Not in any room while it's only available in admin DMs."
    case .admins: "Where administrators can mention \(called). They can also write to it directly."
    case .everyone: "Where people can mention \(called). Anyone can also write to it directly."
    }
  }
  public static func adminsOnlyExplained(_ called: String, on: Bool, kept: Bool) -> String {
    if kept { return "On, since only administrators can write to it." }
    return on
      ? "Only administrators can ask \(called). Everyone else sees its answers in its rooms, but it doesn't answer them."
      : "Anyone in \(called)'s rooms can ask it. Turn this on so that only administrators can."
  }
  public static func adminDmsExplained(_ called: String, on: Bool) -> String {
    let it = called.prefix(1).uppercased() + called.dropFirst()
    return on
      ? "\(it) isn't in any room. Administrators write to it directly, and nobody else can see it or ask it anything."
      : "Turn this on to keep \(called) out of every room: administrators write to it directly, and nobody else can see it or ask it anything."
  }
  public static func mostCost(_ model: String, _ cost: String, searches: Bool) -> String {
    "At \(model)'s prices, an answer at these levels costs at most about \(cost), and most far less\(searches ? ", besides what searching the web costs" : "")."
  }
  public static func lastChanged(_ by: String, _ name: String, _ when: String) -> String { "\(by) last changed \(name) on \(when)." }
  public static func toolsExplained(_ name: String) -> String {
    "Pick what \(name) may use of the apps you've connected, up to 20 tools. Anyone who can ask \(name) could have it use them, with the token each app was connected with, and allows each call on a card first. A tool you always allow skips that in open rooms, never in DMs or private rooms."
  }
  public static func alwaysAllowExplained(_ name: String) -> String {
    "Always allow: in open rooms, \(name) calls it without asking first, and only its typing line says so"
  }
  public static let noAppsToPick = "No apps are connected yet."
  public static let noToolsToPick = "Its server has no tools Ember can use any more."
  public static let toolChanged = "Its app describes this tool another way than when it was picked, so it's set aside. Pick it again to keep it."
  public static func picked(_ count: Int) -> String { "\(count) of 20 picked" }

  // Apps (app-list.tsx, app-page.tsx, app-signed-in-page.tsx)
  public static let appsExplained =
    "Connect another service by the address of its MCP server, and Ember reads the tools it offers, which you pick for @ember and for each agent on its page. Each call an agent makes waits on a card in its room until whoever asked, or an administrator, allows it, unless you always allow that agent the tool, which counts in open rooms alone. You can connect up to 10."
  public static let noApps = "No apps are connected yet."
  public static func setAside(_ count: Int) -> String {
    count == 1 ? "1 picked tool is set aside: its app changed it" : "\(count) picked tools are set aside: their app changed them"
  }
  public static let signInEnded = "Its sign-in has ended: sign in to it again on its page"
  public static let wantsAccess = "Its server asks for more than its sign-in allows: sign in to it again on its page"
  public static func tools(_ count: Int) -> String { count == 1 ? "1 tool" : "\(count) tools" }
  public static let appExplained =
    "An app is another service's MCP server. Ember reads the tools it offers when you connect it, and again whenever you ask."
  public static let confirmRemoveApp = "Are you sure you want to remove this app? Ember forgets its token or sign-in, and the tools it read."
  public static let readingTools = "Reading its tools…"
  public static let findingSignIn = "Finding its sign-in…"
  public static let urlExplained = "Where its MCP server is, which the app's documentation gives. It often ends in /mcp."
  public static let tokenExplained = "Optional. Ember sends it to the server with every request, keeps it encrypted, and never shows it again."
  public static let appTokenKept = "It has a token. Leave this blank to keep it, or type another."
  public static let addressKept = "This app signs in to its server there, so its address stays as it is. To move it, remove it and connect it again."
  public static let signInExplained = "Ember keeps the sign-in encrypted, and gets itself a new token from it as each one ends."
  public static let signInHasEnded = "Its sign-in has ended, so Ember doesn't ask its server, and no agent can use its tools. Sign in to it again."
  public static func wantsMore(_ scopes: String) -> String {
    "Its server has asked for more than this sign-in allows (\(scopes.split(separator: " ").joined(separator: ", "))). Sign in again to allow it."
  }
  public static func removedNotice(_ name: String, url: String, revoked: Bool) -> String {
    let host = URL(string: url)?.host(percentEncoded: false) ?? "its service"
    return revoked ? "\(name) is removed, and \(host) took back Ember's sign-in." : "\(name) is removed. Ember couldn't take back its sign-in at \(host), so remove Ember's access there."
  }
  public static let signInStays = "Ember signs in to an app at the address it's connected at. To sign in at another, remove this app and connect it there."
  public static let redirectExplained =
    "Register Ember with the service as an OAuth app, and give it this as the address it sends people back to, which it may call a redirect or callback URL."
  public static let clientIdExplained = "The client ID the service gave Ember when you registered it there."
  public static let clientSecretExplained = "Optional: only if the service gave one with the client ID. Ember keeps it encrypted, and never shows it again."
  public static let clientSecretKept = "Leave this blank to keep the secret Ember has, if the service gave one, or type another."
  public static func signInTo(_ url: String) -> String {
    guard let host = URL(string: url.trimmingCharacters(in: .whitespaces))?.host(percentEncoded: false) else { return "Sign in to its server" }
    return "Sign in to \(host)"
  }
  public static func connected(_ name: String, tools count: Int) -> String { "\(name) is connected. Ember read \(tools(count)) from it." }
  public static func savedRead(_ name: String, tools count: Int) -> String { "Changes saved. Ember read \(tools(count)) from \(name)." }
  public static func signedInAgain(_ name: String) -> String { "Ember is signed in to \(name) again." }
  public static func toolsLeftOut(_ count: Int) -> String {
    "It has \(count) more that Ember leaves out: it keeps 100 at most, and none whose name or inputs it can't give a model."
  }
  public static let setAsideExplained =
    "Set aside, as this app changed them after they were picked. No agent is given one until you pick it again on the agent's page, as it's described now:"
  public static let toolIsGone = "the app no longer has it"
  public static let toolsNote = "Each description is the app's own. Pick the tools an agent may use on the agent's page."
  public static let finishingSignIn = "Ember is finishing the sign-in and reading the app's tools."

  // Outside AI (outside-ai-settings.tsx)
  public static let outsideAiSettingExplained =
    "Let people connect AI apps, such as Claude and ChatGPT, to Ember as themselves. Each person allows an app on a page here first, and it can then see the open rooms they're in, read their messages and search them, and send messages as them if they let it, and their direct messages and private rooms only if they let it into those too. People who signed in with just a name can't. Turning this off disconnects every app."
  public static let confirmStopOutsideAi = "Are you sure you want to stop AI apps connecting to Ember? Every app people have connected will be disconnected."
  public static func outsideAiAddress(_ address: String) -> String { "People give an AI app this address, which their profile shows them: \(address)" }

  // Chat bots (bots-page.tsx, bot-settings-page.tsx)
  public static func curlText(_ url: String) -> String { "curl -d 'Hello!' \(url)" }
  public static func curlUpload(_ url: String) -> String { "curl -F \"attachment=@/path/to/file\" \(url)" }
  public static let confirmDeleteBot = "Are you sure you want to permanently remove this bot from the account? This can’t be undone."
  public static let confirmNewKey = "Are you sure you want to change the bot key? All usage of this bot must be updated."
  public static let botRoomsExplained = "Where apps can post as the bot, and people can mention it. To put it in a private room, use that room's settings."
  public static let botSetupExplained = "Connect another app or service to your workspace as a bot."
  public static let addressesAfterSave = "Each room's addresses appear once you save the bot, which puts it in its rooms."
  public static let noAddresses = "It isn't in any rooms, so it has no addresses yet."
  public static let webhookExplained =
    "Optional. Ember sends every message that @mentions the bot or is sent to it in a DM to this webhook URL, then posts whatever it answers within 30 seconds."

  // Huddles (huddles-settings.tsx, huddles-steps.tsx, huddles-setup.tsx, relay-setup.tsx, setup-huddles.tsx)
  public static let huddleChatTitle = "Audio and video chat"
  public static let confirmStopHuddles = "Are you sure you want to turn off huddles? Any huddle going on will end, and Ember will forget the SFU app's keys."
  public static let relayTitle = "Relay for strict networks"
  public static let relayExplained =
    "Some networks, like an office's or a hotel's, block the way huddles connect. With a relay, people on them connect through Cloudflare's TURN service, with a TURN key in your Cloudflare account."
  public static func relayOnExplained(_ keyId: String) -> String {
    "People whose network blocks huddles connect through Cloudflare's TURN service, by the TURN key \(keyId) in your Cloudflare account."
  }
  public static let confirmStopRelay =
    "Are you sure you want to turn off the relay? People whose network blocks huddles won't be able to connect to one, and Ember will forget the TURN key."
  public static let huddlesSetupExplained = "Huddles run through Cloudflare's Realtime SFU. It's free up to a monthly allowance, then billed to your Cloudflare account."
  public static let huddlesOn =
    "Cloudflare started a session with the app's keys, so huddles can run through it. Anyone can start one with the headphones at the top of a room."
  public static let sfuStepTitle = "Create an SFU app in Cloudflare"
  public static let sfuStep = "Open Realtime, choose Serverless SFU, and create an app. Any name will do."
  public static let keysStepTitle = "Copy the app's keys here"
  public static let secretKept = "Ember keeps it encrypted."
  public static let keysKept = "Ember has an app's keys already. Give another app's to run huddles through it instead."
  public static let checkingKeys = "Asking Cloudflare to start a session with the app's keys…"
  public static let relaySetupExplained = "The relay is Cloudflare's TURN service. Cloudflare doesn't charge for it when it's used with the Realtime SFU, as huddles use it."
  public static let relayOn =
    "Cloudflare made the relay's servers with the key. Whoever joins a huddle from now on connects through the relay where their network blocks the way."
  public static let turnStepTitle = "Create a TURN key in Cloudflare"
  public static let turnStep = "Open Realtime, find TURN, and create a key. Any name will do."
  public static let turnKeysStepTitle = "Copy the key's ID and token here"
  public static let turnKeyKept = "Ember has a TURN key already. Give another's to relay through it instead."
  public static let checkingRelay = "Asking Cloudflare for the relay's servers with the key…"
  public static func sfuDashboard(_ accountId: String?) -> String { AssistantRules.dashboard(accountId, "realtime/sfu") }
  public static func turnDashboard(_ accountId: String?) -> String { AssistantRules.dashboard(accountId, "calls") }
  public static let firstRunQuestion = "Would you like to enable audio and video chat?"
  public static let firstRunSubtitle = "Huddles let people in a room talk to each other live."
  public static let firstRunFacts: [(label: String, text: String)] = [
    ("What it is", "Live audio and video chat in any room, for up to \(Huddles.maxPeople) people in a huddle."),
    ("What it needs", "A Realtime SFU app in your Cloudflare account. Creating one takes a couple of minutes."),
    ("What it costs", "Cloudflare gives a free monthly allowance, then bills your account for what's sent past it."),
  ]
  public static let firstRunLater = "You can also turn it on later, in Admin under Huddles."
  public static let firstRunSteps = "Two steps: one in Cloudflare, one here."
  public static let firstRunOn = "Cloudflare accepted the app's keys."
  public static let firstRunStart = "Start a huddle with the headphones at the top of any room."
  public static let firstRunChange = "You can turn huddles off, or change the app, in Admin under Huddles."
  public static let unreachable = "Couldn't reach Ember. Check your connection and try again."
}

/** What the agents list says of an agent's rooms and reach (web `roomsOf`, `roomNames`, `reachOf`). */
public enum AgentReach {
  public static func rooms(_ rooms: [NamedRoom]?) -> String {
    guard let rooms else { return AIText.everyRoom }
    return rooms.isEmpty ? AIText.dmsOnly : names(rooms)
  }

  /** The first three names, then how many more. */
  public static func names(_ rooms: [NamedRoom]) -> String {
    let names = rooms.map(\.name)
    return names.count > 3 ? "\(names.prefix(3).joined(separator: ", ")) and \(names.count - 3) more" : names.joined(separator: ", ")
  }

  public static func reach(_ access: AgentAccess, _ rooms: [NamedRoom]?) -> [String] {
    switch access {
    case .adminDms: ["Admin DMs only"]
    case .admins: ["Admins only", self.rooms(rooms)]
    case .everyone: [self.rooms(rooms)]
    }
  }
}
