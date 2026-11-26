import Foundation

// Ember AI and its agents, connected apps and outside AI: packages/protocol/src/assistant.ts, agents.ts,
// apps.ts and outside.ts.

// MARK: - Ember AI (assistant.ts)

/** `MODEL_FORMATS` */
public enum ModelFormat: String, Codable, Sendable, CaseIterable {
  case messages, responses, chat, xai, anthropic, openai, workers
}

/** `THINKING_LEVELS`, in order. */
public enum ThinkingLevel: String, Codable, Sendable, CaseIterable {
  case off, low, medium, high

  /** `LEVEL_NAMES` */
  public var name: String {
    switch self {
    case .off: "Off"
    case .low: "Low"
    case .medium: "Medium"
    case .high: "High"
    }
  }

  var rank: Int {
    switch self {
    case .off: 0
    case .low: 1
    case .medium: 2
    case .high: 3
    }
  }
}

/** `ANSWER_LENGTHS`, in order. */
public enum AnswerLength: String, Codable, Sendable, CaseIterable {
  case short, medium, long

  /** `LEVEL_NAMES` */
  public var name: String {
    switch self {
    case .short: "Short"
    case .medium: "Medium"
    case .long: "Long"
    }
  }

  /** `ANSWER_WORDS` */
  public var words: Int {
    switch self {
    case .short: 150
    case .medium: 400
    case .long: 1_500
    }
  }

  var rank: Int {
    switch self {
    case .short: 0
    case .medium: 1
    case .long: 2
    }
  }
}

/** `WEB_TOOLS` */
public enum WebTool: String, Codable, Sendable, CaseIterable {
  case search, read
}

/** `AnswerLevels`: how hard a model thinks, and how long it answers. */
public struct AnswerLevels: Codable, Hashable, Sendable {
  public var thinking: ThinkingLevel
  public var length: AnswerLength

  public init(thinking: ThinkingLevel, length: AnswerLength) {
    self.thinking = thinking
    self.length = length
  }

  /** `DEFAULT_LEVELS` */
  public static let `default` = AnswerLevels(thinking: .low, length: .medium)
  /** `TOP_LEVELS` */
  public static let top = AnswerLevels(thinking: .high, length: .long)

  /** `withinMost`: these levels, each no higher than `most`'s. */
  public func within(_ most: AnswerLevels) -> AnswerLevels {
    AnswerLevels(
      thinking: ThinkingLevel.allCases[min(thinking.rank, most.thinking.rank)],
      length: AnswerLength.allCases[min(length.rank, most.length.rank)])
  }
}

/** `ModelPrice`: dollars per million tokens. */
public struct ModelPrice: Codable, Hashable, Sendable {
  public var input: Double
  public var output: Double
}

/** A model Ember AI answers with (`AssistantModel`). */
public struct AssistantModel: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var format: ModelFormat
  public var price: ModelPrice?
  public var thinkingLevels: [ThinkingLevel]?
  public init(id: String, name: String, format: ModelFormat, price: ModelPrice? = nil, thinkingLevels: [ThinkingLevel]? = nil) {
    self.id = id
    self.name = name
    self.format = format
    self.price = price
    self.thinkingLevels = thinkingLevels
  }
}

/** A model Ember offers (`OfferedModel`), with the web tools it may use, and the day it's offered until. */
public struct OfferedModel: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var format: ModelFormat
  public var price: ModelPrice?
  public var thinkingLevels: [ThinkingLevel]?
  public var webTools: [WebTool]?
  public var until: String?
}

/** `OfferedModels` */
public struct OfferedModels: Codable, Sendable {
  public var models: [OfferedModel]
  public var suggested: String
  public var workersAi: String?
}

/** Ember AI as the AI assistant tab shows administrators (`AssistantSettings`). */
public struct AssistantSettings: Codable, Hashable, Sendable {
  public var accountId: String
  public var model: String
  public var models: [AssistantModel]
  public var most: AnswerLevels
  public var webTools: [WebTool]?
  public var instructions: String
  public var promptTemplate: String?
  public var avatarUrl: String
  public var avatar: Bool
}

/** `AssistantChanged`, `AssistantForgotten` */
public struct AssistantChanged: Codable, Sendable {
  public var assistant: AssistantSettings?
}

/** `AssistantSaved`: the settings, and @ember's greeting from the model. */
public struct AssistantSaved: Codable, Sendable {
  public var assistant: AssistantSettings
  public var greeting: String
}

/** `WebSearchChanged`: the settings, and what the model found, when it searched. */
public struct WebSearchChanged: Codable, Sendable {
  public var assistant: AssistantSettings
  public var found: String?
}

/** `AssistantKeys`, `AssistantSetup` (with `model`). */
public struct AssistantSetup: Codable, Sendable {
  public var accountId: String
  public var apiToken: String?
  public var model: String?

  public init(accountId: String, apiToken: String? = nil, model: String? = nil) {
    self.accountId = accountId
    self.apiToken = apiToken
    self.model = model
  }
}

/** `AssistantChanges` */
public struct AssistantChanges: Encodable, Sendable {
  public var thinking: ThinkingLevel?
  public var length: AnswerLength?
  public var model: String?
  public var instructions: String?
  /** `.some(nil)` goes back to Ember's own template. */
  public var promptTemplate: String??

  public init(thinking: ThinkingLevel? = nil, length: AnswerLength? = nil, model: String? = nil, instructions: String? = nil, promptTemplate: String?? = nil) {
    self.thinking = thinking
    self.length = length
    self.model = model
    self.instructions = instructions
    self.promptTemplate = promptTemplate
  }

  private enum Keys: String, CodingKey { case thinking, length, model, instructions, promptTemplate }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encodeIfPresent(thinking, forKey: .thinking)
    try c.encodeIfPresent(length, forKey: .length)
    try c.encodeIfPresent(model, forKey: .model)
    try c.encodeIfPresent(instructions, forKey: .instructions)
    if let promptTemplate { try c.encode(promptTemplate, forKey: .promptTemplate) }
  }
}

/** Your own levels and model for @ember's answers to you (`YourAssistant`). */
public struct YourAssistant: Codable, Hashable, Sendable {
  public var levels: AnswerLevels
  public var most: AnswerLevels
  public var model: String?
  public var defaultModel: String
  public var models: [AssistantModel]
}

/** `YourAssistantChanges`: `model` `.some(nil)` goes back to the workspace's. */
public struct YourAssistantChanges: Encodable, Sendable {
  public var thinking: ThinkingLevel?
  public var length: AnswerLength?
  public var model: String??

  public init(thinking: ThinkingLevel? = nil, length: AnswerLength? = nil, model: String?? = nil) {
    self.thinking = thinking
    self.length = length
    self.model = model
  }

  private enum Keys: String, CodingKey { case thinking, length, model }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encodeIfPresent(thinking, forKey: .thinking)
    try c.encodeIfPresent(length, forKey: .length)
    if let model { try c.encode(model, forKey: .model) }
  }
}

/** `YourAssistantChanged` */
public struct YourAssistantChanged: Codable, Sendable {
  public var assistant: YourAssistant?
}

public enum AssistantRules {
  public static let maxAssistantModels = 20
  public static let maxModelNameLength = 100
  public static let maxInstructionsLength = 10_000
  public static let maxModelLength = 200
  public static let maxConversationLength = 40_000
  public static let webSearchesPerAnswer = 5
  public static let pagesReadPerAnswer = 3
  public static let levelsRefused = "Choose a level the dial has."
  public static let modelNotListed = "Choose one of the models an administrator added."
  public static let instructionsTooLong = "Instructions can be at most 10,000 characters."
  public static let assistantOff = "Ember AI is off. Turn it on first."
  public static let webSearchRefused = "Say whether @ember searches the web."
  public static let webSearchChanged = "Ember AI changed while its model searched. Try again."
  public static let accountIdRefused = "An account ID is 32 letters and digits. Search the Cloudflare dashboard for Copy account ID to copy it."
  public static let apiTokenRefused = "Paste an API token from Account API tokens in the Cloudflare dashboard."
  public static let modelRefused = "Choose one of the models Ember offers."
  public static let defaultModelKept = "@ember answers everyone with this model. Choose another for that first."
  public static let modelsFull = "People can pick from at most 20 models. Remove one first."
  public static let forbidden = "Only administrators can set up Ember AI"
  public static func cannotSearchWith(_ name: String) -> String {
    "\(name) can't search the web through AI Gateway, but the models Ember offers can. Choose one under Models or Change."
  }

  /** `WEB_TOOLS_IN` */
  public static func webTools(in format: ModelFormat) -> [WebTool] {
    switch format {
    case .messages, .anthropic: [.search, .read]
    case .responses, .chat, .xai, .openai, .workers: [.search]
    }
  }

  /** `accountIdOf` */
  public static func accountId(of text: String) -> String? {
    let id = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return id.wholeMatch(of: #/[0-9a-f]{32}/#) != nil ? id : nil
  }

  /** `apiTokenOf` */
  public static func apiToken(of text: String) -> String? {
    let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return (20...200).contains(token.utf16.count) && token.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) ? token : nil
  }

  /** `modelOf` */
  public static func model(of text: String) -> String? {
    let model = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return model.utf16.count <= maxModelLength && model.wholeMatch(of: #/@?[\w.-]+(?:\/[\w.:@-]+)+/#) != nil ? model : nil
  }

  /** `isWorkersAiModel` */
  public static func isWorkersAiModel(_ model: String) -> Bool { model.hasPrefix("@cf/") }

  /** `ASSISTANT_MODELS`: the models Ember ships offering (models.json). */
  public static let shippedModels: [OfferedModel] = [
    shipped("anthropic/claude-fable-5.2", "Claude Fable 5.2", .anthropic, 8, 40),
    shipped("anthropic/claude-opus-5.5", "Claude Opus 5.5", .anthropic, 4, 20),
    shipped("anthropic/claude-sonnet-5.5", "Claude Sonnet 5.5", .anthropic, 2, 10),
    shipped("anthropic/claude-haiku-5.5", "Claude Haiku 5.5", .anthropic, 0.1, 0.5),
    shipped("openai/gpt-6-astra", "GPT-6 Astra", .openai, 10, 50),
    shipped("openai/gpt-6.1-sol", "GPT-6.1 Sol", .openai, 2, 10),
    shipped("openai/gpt-6.1-terra", "GPT-6.1 Terra", .openai, 1, 5),
    shipped("openai/gpt-6-luna", "GPT-6 Luna", .openai, 0.1, 0.5),
    shipped("xai/grok-4.7", "Grok 4.7", .chat, 2, 6),
  ]
  /** `SUGGESTED_MODEL` */
  public static let suggestedModel = "anthropic/claude-haiku-5.5"

  private static func shipped(_ id: String, _ name: String, _ format: ModelFormat, _ input: Double, _ output: Double) -> OfferedModel {
    OfferedModel(id: id, name: name, format: format, price: ModelPrice(input: input, output: output), thinkingLevels: nil, webTools: nil, until: nil)
  }

  /** `modelName`: a model's name, from `models` or what Ember ships, else its id. */
  public static func modelName(_ model: String, in models: [AssistantModel] = []) -> String {
    if let listed = models.first(where: { $0.id == model }) { return listed.name }
    if let shipped = shippedModels.first(where: { $0.id == model }) { return shipped.name }
    return model
  }

  /** A model's name among the models Ember offers (web `modelName(model, offered?.models)`), else as `modelName(_:in:)`. */
  public static func modelName(_ model: String, offered: [OfferedModel]?) -> String {
    if let listed = offered?.first(where: { $0.id == model }) { return listed.name }
    return modelName(model)
  }
}

// MARK: - Agents (agents.ts)

/** `AGENT_ACCESS`: who can ask an agent. */
public enum AgentAccess: String, Codable, Sendable, CaseIterable {
  case everyone, admins
  case adminDms = "admin-dms"
}

/** An agent, as Agents lists them (`Agent`). `rooms` nil for every open room. */
public struct Agent: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  public var username: String?
  public var bio: String?
  public var role: Role
  public var status: UserStatus
  public var avatarUrl: String
  public var agent: Bool?
  public var adminsOnly: Bool?
  public var description: String
  public var model: String
  public var modelName: String
  public var webTools: [WebTool]
  public var access: AgentAccess
  public var rooms: [NamedRoom]?
}

/** An agent people can ask (`AvailableAgent`). */
public struct AvailableAgent: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  public var username: String?
  public var bio: String?
  public var role: Role
  public var status: UserStatus
  public var avatarUrl: String
  public var agent: Bool?
  public var adminsOnly: Bool?
  public var description: String
  public var access: AgentAccess
  public var rooms: [NamedRoom]?
}

/** `AvailableAgents` */
public struct AvailableAgents: Codable, Sendable {
  public var agents: [AvailableAgent]
}

/** An agent as its page shows it (`AgentSettings`). */
public struct AgentSettings: Codable, Hashable, Sendable, Identifiable {
  public var id: UserID
  public var name: String
  public var username: String?
  public var bio: String?
  public var role: Role
  public var status: UserStatus
  public var avatarUrl: String
  public var agent: Bool?
  public var adminsOnly: Bool?
  public var description: String
  public var model: String
  public var modelName: String
  public var webTools: [WebTool]
  public var access: AgentAccess
  public var rooms: [NamedRoom]?
  public var instructions: String
  public var promptTemplate: String?
  public var format: ModelFormat
  public var levels: AnswerLevels
  public var thinkingLevels: [ThinkingLevel]?
  public var avatar: Bool
  public var changedBy: User
  public var changedAt: String
}

/** What a person's page shows of an agent (`AgentProfile`). */
public struct AgentProfile: Codable, Hashable, Sendable {
  public var description: String
  public var model: String
  public var modelName: String
  public var setUpBy: User
}

extension AgentProfile {
  /** The makers AI Gateway sends a conversation to, by the model ID's first part (web `MAKERS`). */
  static let makers = ["anthropic": "Anthropic", "openai": "OpenAI", "google": "Google", "moonshotai": "Moonshot AI"]

  /** The model an agent answers with, and where it runs: on Cloudflare, or at the maker AI Gateway sends it to (web `runsOn`). */
  public var runsOn: String {
    if AssistantRules.isWorkersAiModel(model) { return "An AI agent running on \(modelName), on Cloudflare’s Workers AI." }
    let prefix = String(model.prefix { $0 != "/" })
    let maker = Self.makers[prefix] ?? "the model’s maker"
    return "An AI agent running on \(modelName) through Cloudflare AI Gateway, which sends the conversation you ask it in to \(maker)."
  }

  /** `runsOn`, then who set it up: "You" for the person asking, else `setUpByName`, the directory's name for them now. */
  public func about(me: UserID?, setUpByName: String) -> String {
    "\(runsOn) \(setUpBy.id == me ? "You" : setUpByName) set it up."
  }
}

/** `Agents` */
public struct Agents: Codable, Sendable {
  public var agents: [Agent]
}

/** `AgentAnswer` */
public struct AgentAnswer: Codable, Sendable {
  public var agent: AgentSettings
}

/** An agent to make, or what changes in one (`NewAgent`, `AgentChanges`). */
public struct AgentChanges: Encodable, Sendable {
  public var name: String?
  public var description: String?
  public var instructions: String?
  /** `.some(nil)` goes back to Ember's own template. */
  public var promptTemplate: String??
  public var model: String?
  public var thinking: ThinkingLevel?
  public var length: AnswerLength?
  public var webSearch: Bool?
  public var access: AgentAccess?
  public var rooms: PickedRooms?

  public init(
    name: String? = nil, description: String? = nil, instructions: String? = nil, promptTemplate: String?? = nil, model: String? = nil,
    thinking: ThinkingLevel? = nil, length: AnswerLength? = nil, webSearch: Bool? = nil, access: AgentAccess? = nil, rooms: PickedRooms? = nil
  ) {
    self.name = name
    self.description = description
    self.instructions = instructions
    self.promptTemplate = promptTemplate
    self.model = model
    self.thinking = thinking
    self.length = length
    self.webSearch = webSearch
    self.access = access
    self.rooms = rooms
  }

  private enum Keys: String, CodingKey { case name, description, instructions, promptTemplate, model, thinking, length, webSearch, access, rooms }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encodeIfPresent(name, forKey: .name)
    try c.encodeIfPresent(description, forKey: .description)
    try c.encodeIfPresent(instructions, forKey: .instructions)
    if let promptTemplate { try c.encode(promptTemplate, forKey: .promptTemplate) }
    try c.encodeIfPresent(model, forKey: .model)
    try c.encodeIfPresent(thinking, forKey: .thinking)
    try c.encodeIfPresent(length, forKey: .length)
    try c.encodeIfPresent(webSearch, forKey: .webSearch)
    try c.encodeIfPresent(access, forKey: .access)
    switch rooms {
    case .everyOpenRoom: try c.encodeNil(forKey: .rooms)
    case let .these(ids): try c.encode(ids, forKey: .rooms)
    case nil: break
    }
  }
}

/** A question to try an agent's setup with (`AgentTrial`). */
public struct AgentTrial: Encodable, Sendable {
  public var name: String
  public var instructions: String
  public var promptTemplate: String?
  public var model: String
  public var thinking: ThinkingLevel
  public var length: AnswerLength
  public var webSearch: Bool
  public var question: String

  public init(name: String, instructions: String, promptTemplate: String?, model: String, thinking: ThinkingLevel, length: AnswerLength, webSearch: Bool, question: String) {
    self.name = name
    self.instructions = instructions
    self.promptTemplate = promptTemplate
    self.model = model
    self.thinking = thinking
    self.length = length
    self.webSearch = webSearch
    self.question = question
  }

  private enum Keys: String, CodingKey { case name, instructions, promptTemplate, model, thinking, length, webSearch, question }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encode(name, forKey: .name)
    try c.encode(instructions, forKey: .instructions)
    try c.encode(promptTemplate, forKey: .promptTemplate)
    try c.encode(model, forKey: .model)
    try c.encode(thinking, forKey: .thinking)
    try c.encode(length, forKey: .length)
    try c.encode(webSearch, forKey: .webSearch)
    try c.encode(question, forKey: .question)
  }
}

/** `AgentTrialAnswer`: the answer's markup and cards, and how long it took. */
public struct AgentTrialAnswer: Codable, Sendable {
  public var body: String
  public var cards: [Card]
  public var ms: Double
}

public enum AgentRules {
  public static let maxAgents = 20
  public static let maxDescriptionLength = 100
  public static let emberDoes = "Answers anything people ask."
  public static let forbidden = "Only administrators can set up agents"
  public static let full = "Ember can have at most 20 agents. Delete one first."
  public static let nameTaken = "Someone is called that already. Choose another name."
  public static func agentsName(_ name: String) -> String { "\(name.trimmingCharacters(in: .whitespacesAndNewlines)) is an AI agent's name. Choose another." }
  public static let changed = "The agent was changed while its model answered. Try again."
  public static let setUpAgain = "Ember AI was set up again while the model answered, so nothing was saved. Try again."
  public static func cannotSearchWith(_ name: String) -> String {
    "\(name) can't search the web through AI Gateway, but the other models Ember offers can. Choose one of those, or leave Search the web off."
  }
  public static let nameRefused = "Give it a name of one line, at most 100 characters, which people mention it by."
  public static let descriptionRefused = "Say what it does in one line of at most 100 characters, so people know when to ask it."
  public static let instructionsNeeded = "Give it instructions: its task, how to go about it, and what to leave alone."
  public static let webSearchUnsaid = "Say whether it searches the web."
  public static let accessRefused = "Say who can ask it: everyone, administrators, or administrators in their direct messages with it."
  public static let roomsRefused = "Choose rooms open to everyone, or every one."
  public static let questionNeeded = "Ask it something."
}

// MARK: - Connected apps (apps.ts)

public typealias AppID = String

/** `AppTool` */
public struct AppTool: Codable, Hashable, Sendable {
  public var name: String
  public var title: String?
  public var description: String
}

/** Someone, by id and name, as apps name who connected or signed in. */
public struct NamedUser: Codable, Hashable, Sendable {
  public var id: UserID
  public var name: String
}

/** A tool an app no longer offers, or that changed, and the agents that used it (`SetAsideTool`). */
public struct SetAsideTool: Codable, Hashable, Sendable {
  public var name: String
  public var gone: Bool
  public var agents: [NamedUser]
}

/** `AppSignIn` */
public struct AppSignIn: Codable, Hashable, Sendable {
  public var by: NamedUser?
  public var at: String
  public var ended: Bool
  public var clientId: String?
  public var wantsScope: String?
}

/** A connected app (MCP server), as its page shows it (`App`). */
public struct App: Codable, Hashable, Sendable, Identifiable {
  public var id: AppID
  public var name: String
  public var url: String
  public var hasToken: Bool
  public var serverName: String?
  public var tools: [AppTool]
  public var toolsLeftOut: Int
  public var toolsReadAt: String
  public var connectedBy: NamedUser?
  public var setAside: [SetAsideTool]
  public var signIn: AppSignIn?
}

/** An app, as Apps lists them (`AppSummary`). */
public struct AppSummary: Codable, Hashable, Sendable, Identifiable {
  public var id: AppID
  public var name: String
  public var url: String
  public var toolCount: Int
  public var setAside: Int
  public var signInEnded: Bool
  public var wantsAccess: Bool
}

/** `Apps` */
public struct Apps: Codable, Sendable {
  public var apps: [AppSummary]
}

/** `AppAnswer` */
public struct AppAnswer: Codable, Sendable {
  public var app: App
}

/** What removing an app answers (`Partial<AppRemoved>`): whether its server revoked the sign-in. */
public struct AppRemoved: Codable, Sendable {
  public var revoked: Bool?
}

/** An app to connect, or what changes in one (`NewApp`, `AppChanges`). */
public struct AppChanges: Codable, Sendable {
  public var name: String?
  public var url: String?
  public var token: String?

  public init(name: String? = nil, url: String? = nil, token: String? = nil) {
    self.name = name
    self.url = url
    self.token = token
  }
}

/** `AppClient`, and with `name` and `url`, `NewAppSignIn`. */
public struct AppClient: Codable, Sendable {
  public var name: String?
  public var url: String?
  public var clientId: String?
  public var clientSecret: String?

  public init(name: String? = nil, url: String? = nil, clientId: String? = nil, clientSecret: String? = nil) {
    self.name = name
    self.url = url
    self.clientId = clientId
    self.clientSecret = clientSecret
  }
}

/** `AppSignInBegun` */
public struct AppSignInBegun: Codable, Sendable {
  public var authorizationUrl: String
}

/** What an app's sign-in comes back with (`AppSignInReturn`). */
public struct AppSignInReturn: Codable, Sendable {
  public var state: String
  public var code: String
  public var iss: String?

  public init(state: String, code: String, iss: String? = nil) {
    self.state = state
    self.code = code
    self.iss = iss
  }
}

/** Your sign-in to a connected app (`YourApp`). */
public struct YourApp: Codable, Hashable, Sendable, Identifiable {
  public var id: AppID
  public var name: String
  public var signedInAt: String?
  public var ended: Bool
  public var wantsMore: Bool
}

/** What finishing an app sign-in answers: an administrator's (`AppSignedIn`) or your own (`YourAppSignedIn`). */
public enum AppSignInFinished: Decodable, Sendable {
  case app(App, again: Bool)
  case yours(YourApp)

  private enum Keys: String, CodingKey { case app, again, yours }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    if let yours = try c.decodeIfPresent(YourApp.self, forKey: .yours) {
      self = .yours(yours)
    } else {
      self = .app(try c.decode(App.self, forKey: .app), again: try c.decode(Bool.self, forKey: .again))
    }
  }
}

/** `YourAppSignedOut` */
public struct YourAppSignedOut: Codable, Sendable {
  public var apps: [YourApp]
  public var revoked: Bool
}

/** `ToolPick`: a tool an agent may use. */
public struct ToolPick: Codable, Hashable, Sendable {
  public var appId: AppID
  public var name: String
  public var fingerprint: String
  public var alwaysAllowed: Bool?

  public init(appId: AppID, name: String, fingerprint: String, alwaysAllowed: Bool) {
    self.appId = appId
    self.name = name
    self.fingerprint = fingerprint
    self.alwaysAllowed = alwaysAllowed ? true : nil
  }
}

/** `OfferedTool` */
public struct OfferedTool: Codable, Hashable, Sendable {
  public var name: String
  public var title: String?
  public var description: String
  public var fingerprint: String
  public var picked: Bool
  public var changed: Bool
  public var alwaysAllowed: Bool
}

/** `OfferedApp` */
public struct OfferedApp: Codable, Hashable, Sendable, Identifiable {
  public var id: AppID
  public var name: String
  public var tools: [OfferedTool]
}

/** `AgentTools` */
public struct AgentTools: Codable, Sendable {
  public var apps: [OfferedApp]
}

/** `AgentToolPicks` */
public struct AgentToolPicks: Codable, Sendable {
  public var tools: [ToolPick]
}

public enum AppRules {
  public static let maxApps = 10
  public static let maxNameLength = 60
  public static let maxUrlLength = 2048
  public static let maxTokenLength = 4096
  public static let maxClientIdLength = 512
  public static let maxClientSecretLength = 1024
  public static let maxScopeLength = 1000
  public static let maxTools = 100
  public static let maxToolDescriptionLength = 1500
  public static let maxAgentTools = 20
  public static let forbidden = "Only administrators can connect apps"
  public static let full = "Ember connects at most 10 apps. Remove one first."
  public static let changed = "Someone else changed this app while Ember read its tools. Load the page again."
  public static let urlRefused = "The address must be an https URL, or an http one on localhost"
  public static let signedIn = "This app signs in to its server, so its address and token can't be changed here. Remove it and connect it again to move it."
  public static let tokenStays = "Ember sends a token only to the address it was given for. Type it again for the new address, or check Send no token."
  public static let signInEnded = "That sign-in has ended, or isn't one you started. Start it again."
  public static let isEmber = "That's this Ember's own address. Connected to itself, Ember would let its agents read your DMs and private rooms for anyone who asks them."
  public static let yourAppGone = "That app isn't one you can sign in to here any more."
  public static let yourAppsForbidden = "Guests can't sign in to apps"
  public static let agentToolsFull = "An agent uses at most 20 tools. Pick fewer."
  public static let toolGone = "One of those tools is gone from its app, or described another way than when this page loaded. Here they are as they are now."
  /** `CALL_ACTIONS`: the action ids of an approval card's buttons. */
  public static let allowAction = "ember.call.allow"
  public static let denyAction = "ember.call.deny"
  /** Where an app's sign-in comes back to (`APP_SIGNED_IN_PATH`). */
  public static let signedInPath = "/account/apps/signed-in"

  /** `isLoopback` */
  public static func isLoopback(_ hostname: String) -> Bool {
    hostname == "::1" || hostname.wholeMatch(of: #/(?:(?:.+\.)?localhost|127(?:\.\d{1,3}){3}|\[::1\])/#) != nil
  }

  /** `isAppUrl`: https, or http on this computer. */
  public static func isAppUrl(_ address: String) -> Bool {
    guard let url = URL(string: address), let host = url.host(percentEncoded: false), !host.isEmpty, url.user == nil, url.password == nil else { return false }
    return url.scheme == "https" || (url.scheme == "http" && isLoopback(host))
  }
}

// MARK: - Outside AI (outside.ts)

/** `OUTSIDE_SCOPES` */
public enum OutsideScope: String, Codable, Sendable, CaseIterable {
  case read, write, `private`

  /** `OUTSIDE_SCOPE_EXPLAINED` */
  public var explained: String {
    switch self {
    case .read: "See the open rooms you're in, read their messages and search them, as you can"
    case .write: "Send messages as you, in the open rooms you're in"
    case .private: "Do the same in your direct messages and private rooms"
    }
  }
}

/** An AI app connected as you (`OutsideConnection`). */
public struct OutsideConnection: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var comesBackTo: String
  public var scopes: [OutsideScope]
  public var connectedAt: String
  public var usedAt: String?
}

/** `YourOutsideAi` */
public struct YourOutsideAi: Codable, Sendable {
  public var connections: [OutsideConnection]
}

/** `OutsideAiSettings`, and what turning outside AI on or off sends. */
public struct OutsideAiSettings: Codable, Sendable {
  public var on: Bool

  public init(on: Bool) {
    self.on = on
  }
}

/** An AI app's OAuth request, as `/oauth/authorize` was given it (`OutsideAsk`). */
public struct OutsideAsk: Codable, Hashable, Sendable {
  public var responseType: String?
  public var clientId: String?
  public var redirectUri: String?
  public var state: String?
  public var codeChallenge: String?
  public var codeChallengeMethod: String?
  public var scope: String?
  public var resource: String?

  /** `outsideAskOf`: from the consent page's query. */
  public init(query items: [URLQueryItem]) {
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    responseType = value("response_type")
    clientId = value("client_id")
    redirectUri = value("redirect_uri")
    state = value("state")
    codeChallenge = value("code_challenge")
    codeChallengeMethod = value("code_challenge_method")
    scope = value("scope")
    resource = value("resource")
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(responseType, forKey: .responseType)
    try c.encode(clientId, forKey: .clientId)
    try c.encode(redirectUri, forKey: .redirectUri)
    try c.encode(state, forKey: .state)
    try c.encode(codeChallenge, forKey: .codeChallenge)
    try c.encode(codeChallengeMethod, forKey: .codeChallengeMethod)
    try c.encode(scope, forKey: .scope)
    try c.encode(resource, forKey: .resource)
  }
}

/** What the consent page shows of an AI app's request (`OutsideAsked`). */
public struct OutsideAsked: Codable, Sendable {
  public var name: String
  public var comesBackTo: String
  public var workspace: String
  public var scopes: [OutsideScope]
}

/** `OutsideAnswer` */
public struct OutsideAnswer: Codable, Sendable {
  public var ask: OutsideAsk
  public var allow: Bool
  public var without: [OutsideScope]
  public var with: [OutsideScope]

  public init(ask: OutsideAsk, allow: Bool, without: [OutsideScope] = [], with: [OutsideScope] = []) {
    self.ask = ask
    self.allow = allow
    self.without = without
    self.with = with
  }
}

/** `OutsideAnswered` */
public struct OutsideAnswered: Codable, Sendable {
  public var redirectTo: String
}

public enum Outside {
  public static let mcpPath = "/mcp"
  public static let authorizePath = "/oauth/authorize"
  public static let defaultScopes: [OutsideScope] = [.read]
  public static let untickedScopes: [OutsideScope] = [.private]
  public static let maxConnections = 20
  public static let maxNameLength = 100
  public static let maxAddressLength = 2048
  public static let off = "Connecting AI apps to Ember is turned off"
  public static let forbidden = "Only administrators can change whether AI apps connect"
  public static let guest = "Someone who signed in with just a name can't connect an AI app"
  public static let full = "You have 20 AI apps connected already. Disconnect one on your profile first."
  public static let connectionGone = "That connection has ended already"
  public static let askRefused = "This isn't a request Ember can answer. Start connecting again from the AI app."

  /** `optionalOutsideScopes`: the scopes the person may leave out. */
  public static func optionalScopes(_ asked: [OutsideScope]) -> [OutsideScope] {
    asked.filter { untickedScopes.contains($0) || ($0 != .read && asked.contains(.read)) }
  }
}
