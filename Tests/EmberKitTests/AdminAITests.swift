import XCTest

@testable import EmberKit

/** The AI assistant, chat bots and huddles admin screens' rules, as packages/protocol/src/assistant.ts has them, and their commands. */
final class AdminAITests: XCTestCase {
  func testThinkingTaken() {
    XCTAssertEqual(AssistantRules.thinkingTaken(.medium, nil), .medium)
    XCTAssertEqual(AssistantRules.thinkingTaken(.medium, [.low, .high]), .low)
    XCTAssertEqual(AssistantRules.thinkingTaken(.off, [.low, .high]), .low)
    XCTAssertNil(AssistantRules.thinkingTaken(.high, []))
  }

  func testMaxTokens() {
    XCTAssertEqual(AssistantRules.maxTokens(at: AnswerLevels(thinking: .off, length: .short)), 3_000)
    XCTAssertEqual(AssistantRules.maxTokens(at: AnswerLevels(thinking: .high, length: .long)), 38_000)
  }

  func testSearchFormatsAndWebTools() {
    XCTAssertEqual(AssistantRules.searchFormat("xai/grok-4.7", .xai), .chat)
    XCTAssertEqual(AssistantRules.searchFormat("@cf/meta/llama", .chat), .workers)
    XCTAssertNil(AssistantRules.searchFormat("mistral/large", .chat))
    XCTAssertEqual(AssistantRules.webTools(of: "anthropic/claude-haiku-5.5", format: .anthropic, offered: []), [.search, .read])
    let offered = [OfferedModel(id: "@cf/x/y", name: "Y", format: .workers, price: nil, thinkingLevels: nil, webTools: [], until: nil)]
    XCTAssertEqual(AssistantRules.webTools(of: "@cf/x/y", format: .workers, offered: offered), [])
    XCTAssertEqual(AssistantRules.format(of: "@cf/x/y"), .workers)
    XCTAssertEqual(AssistantRules.format(of: "openai/gpt-9"), .openai)
  }

  func testNoLongerOffered() {
    XCTAssertTrue(AssistantRules.noLongerOffered("anthropic/old", offered: [], workersAi: nil))
    XCTAssertFalse(AssistantRules.noLongerOffered("@cf/x/y", offered: [], workersAi: "Workers AI's models aren't listed"))
    XCTAssertEqual(AssistantRules.cost(of: "anthropic/old", offered: [], workersAi: nil, accountId: nil).text, AIText.noLongerOfferedNote)
  }

  func testCostAndPrices() {
    XCTAssertEqual(AssistantRules.dollars(3), "$3")
    XCTAssertEqual(AssistantRules.dollars(0.1), "$0.10")
    XCTAssertEqual(AssistantRules.dollars(0.075), "$0.075")
    let model = OfferedModel(id: "anthropic/a", name: "A", format: .anthropic, price: ModelPrice(input: 2, output: 10), thinkingLevels: nil, webTools: nil, until: "2027-01-15")
    XCTAssertEqual(AssistantRules.entry(model), "A · $2 / $10")
    let cost = AssistantRules.cost(of: "anthropic/a", offered: [model], workersAi: nil, accountId: "abc")
    XCTAssertTrue(cost.text.hasPrefix("AI Gateway's credits pay for this model, $2 for each million tokens it reads"))
    XCTAssertTrue(cost.text.hasSuffix("Anthropic plans to stop running it on January 15, 2027."))
    XCTAssertEqual(cost.link, "https://dash.cloudflare.com/abc/ai/ai-gateway")
    XCTAssertEqual(AssistantRules.dashboard(nil, "api-tokens"), "https://dash.cloudflare.com/?to=/:account/api-tokens")
    XCTAssertEqual(AssistantRules.answerCost(0.004), "less than a cent")
    XCTAssertEqual(AssistantRules.answerCost(0.42), "42¢")
    XCTAssertEqual(AssistantRules.answerCost(1.5), "$1.50")
    XCTAssertEqual(AssistantRules.seconds(3_210), "3.2 seconds")
    XCTAssertEqual(AssistantRules.seconds(12_600), "13 seconds")
  }

  func testGroupedModels() {
    let models = [
      OfferedModel(id: "@cf/a/b", name: "B", format: .workers, price: nil, thinkingLevels: nil, webTools: nil, until: nil),
      OfferedModel(id: "openai/x", name: "X", format: .openai, price: nil, thinkingLevels: nil, webTools: nil, until: nil),
      OfferedModel(id: "anthropic/y", name: "Y", format: .anthropic, price: nil, thinkingLevels: nil, webTools: nil, until: nil),
    ]
    XCTAssertEqual(AssistantRules.grouped(models).map(\.label), ["Anthropic", "OpenAI", "Workers AI"])
  }

  func testThinkingNotes() {
    XCTAssertEqual(AssistantRules.thinkingNote(.low, modelName: nil, takes: nil), "Thinks a little first, up to about 4,000 tokens.")
    XCTAssertEqual(AssistantRules.thinkingNote(.medium, modelName: "M", takes: [.off, .low, .high]), "M can't be set to Medium, so it thinks at Low instead.")
    XCTAssertEqual(
      AssistantRules.thinkingNote(.high, modelName: "M", takes: [.off, .high]),
      "Thinks the most first, up to about 32,000 tokens, which takes longest. M can't be set to Low or Medium.")
    XCTAssertEqual(AssistantRules.thinkingNote(.off, modelName: "M", takes: []), "M can't be told how much to think, so it decides for itself, up to about 2,000 tokens.")
  }

  func testWebPrompt() {
    XCTAssertTrue(AssistantRules.webPrompt(askerName: "Ada", webTools: [], webSearchOn: false).hasPrefix("You can't search the web or open links. When someone"))
    XCTAssertTrue(AssistantRules.webPrompt(askerName: "Ada", webTools: [.search, .read], webSearchOn: true).contains(", and read the pages"))
  }

  func testAgentReach() {
    let rooms = ["a", "b", "c", "d", "e"].map { NamedRoom(id: $0, name: $0) }
    XCTAssertEqual(AgentReach.rooms(nil), "Every room")
    XCTAssertEqual(AgentReach.rooms([]), "Direct messages only")
    XCTAssertEqual(AgentReach.names(rooms), "a, b, c and 2 more")
    XCTAssertEqual(AgentReach.reach(.admins, nil), ["Admins only", "Every room"])
    XCTAssertEqual(AgentReach.reach(.adminDms, []), ["Admin DMs only"])
  }

  func testInstructionsLength() {
    XCTAssertEqual(AssistantRules.length(of: "hello"), "5 of 10,000 characters")
  }

  func testCommands() {
    XCTAssertEqual(InputCommand.parse("/ai status"), .admin(.ai(.status)))
    XCTAssertEqual(InputCommand.parse("/ai"), .ai(disconnect: nil))
    XCTAssertEqual(InputCommand.parse("/ai disconnect Claude"), .ai(disconnect: "Claude"))
    XCTAssertEqual(InputCommand.parse("/ai think medium"), .admin(.ai(.think(.medium))))
    XCTAssertEqual(InputCommand.parse("/ai me model default"), .admin(.ai(.mine(nil, nil, model: .some(nil)))))
    XCTAssertEqual(InputCommand.parse("/ai add anthropic/claude-haiku-5.5"), .admin(.ai(.add("anthropic/claude-haiku-5.5"))))
    XCTAssertEqual(InputCommand.parse("/agent try Helper what's new?"), .admin(.agent(.trial("Helper what's new?"))))
    XCTAssertEqual(InputCommand.parse("/agent Helper"), .admin(.agent(.open("Helper"))))
    XCTAssertEqual(InputCommand.parse("/apps"), .apps(.list))
    XCTAssertEqual(InputCommand.parse("/apps admin"), .admin(.app(.list)))
    XCTAssertEqual(InputCommand.parse("/apps signin Linear"), .apps(.signIn("Linear")))
    XCTAssertEqual(InputCommand.parse("/apps reread Linear"), .admin(.app(.reread("Linear"))))
    XCTAssertEqual(InputCommand.parse("/bot urls Deploys"), .admin(.bot(.urls("Deploys"))))
    XCTAssertEqual(InputCommand.parse("/huddles relay off"), .admin(.huddles(.relay(false))))
    XCTAssertEqual(InputCommand.parse("/huddles cameras on"), .admin(.huddles(.cameras(true))))
    XCTAssertEqual(InputCommand.parse("/outside"), .admin(.outside(nil)))
  }

  func testDecodesAgentTools() throws {
    let json = #"""
      {"apps":[{"id":"app1","name":"Linear","tools":[{"name":"list_issues","title":null,"description":"Lists issues","fingerprint":"f1","picked":true,"changed":false,"alwaysAllowed":true}]}]}
      """#
    let tools = try JSONDecoder().decode(AgentTools.self, from: Data(json.utf8))
    XCTAssertEqual(tools.apps.first?.tools.first?.alwaysAllowed, true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let picks = try encoder.encode(AgentToolPicks(tools: [ToolPick(appId: "app1", name: "list_issues", fingerprint: "f1", alwaysAllowed: false)]))
    XCTAssertEqual(String(decoding: picks, as: UTF8.self), #"{"tools":[{"appId":"app1","fingerprint":"f1","name":"list_issues"}]}"#)
  }
  func testAgentRunsOn() {
    let workers = AgentProfile(description: "Helps", model: "@cf/meta/llama", modelName: "Llama", setUpBy: User(id: "u1", name: "Ann"))
    XCTAssertEqual(workers.about(me: "u1", setUpByName: "Ann"), "An AI agent running on Llama, on Cloudflare’s Workers AI. You set it up.")
    let claude = AgentProfile(description: "Helps", model: "anthropic/claude", modelName: "Claude", setUpBy: User(id: "u1", name: "Ann"))
    XCTAssertEqual(
      claude.about(me: "u2", setUpByName: "Annie"),
      "An AI agent running on Claude through Cloudflare AI Gateway, which sends the conversation you ask it in to Anthropic. Annie set it up.")
    let other = AgentProfile(description: "Helps", model: "xai/grok", modelName: "Grok", setUpBy: User(id: "u1", name: "Ann"))
    XCTAssertTrue(other.runsOn.hasSuffix("to the model’s maker."))
  }

  func testModelNameFromOffered() {
    let offered = [OfferedModel(id: "@cf/x/y", name: "Y", format: .workers, price: nil, thinkingLevels: nil, webTools: [], until: nil)]
    XCTAssertEqual(AssistantRules.modelName("@cf/x/y", offered: offered), "Y")
    XCTAssertEqual(AssistantRules.modelName("@cf/x/z", offered: offered), "@cf/x/z")
  }

  func testAiOnAndForbidden() {
    XCTAssertEqual(InputCommand.parse("/ai on"), .admin(.ai(.setup)))
    XCTAssertEqual(AdminCommand.ai(.off).forbidden, "Only administrators can set up Ember AI")
    XCTAssertEqual(AdminCommand.bots.forbidden, "Only administrators can manage bots")
    XCTAssertEqual(AdminCommand.outside(true).forbidden, "Only administrators can change whether AI apps connect")
  }

  func testAppRemovedDecodes() throws {
    XCTAssertEqual(try JSONDecoder().decode(AppRemoved.self, from: Data(#"{"revoked":true}"#.utf8)).revoked, true)
    XCTAssertNil(try JSONDecoder().decode(AppRemoved.self, from: Data("{}".utf8)).revoked)
  }
}
