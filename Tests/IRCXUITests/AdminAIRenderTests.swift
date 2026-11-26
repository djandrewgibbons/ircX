import AppCoreUI
import AppCoreUITestSupport
@testable import EmberKit
@testable import IRCXUI
import SwiftUI
import XCTest

/**
 * The AI assistant, Chat bots and Huddles sections, and the pages and dialogs they open, as each theme draws
 * them, to .build/ui-renders/.
 */
@MainActor
final class AdminAIRenderTests: XCTestCase {
  let base = NavigationRenderTests()

  static let assistantJSON = #"""
    {"accountId":"0123456789abcdef0123456789abcdef","model":"anthropic/claude-haiku-5.5",
    "models":[{"id":"anthropic/claude-haiku-5.5","name":"Claude Haiku 5.5","format":"anthropic","price":{"input":0.1,"output":0.5},"thinkingLevels":["off","low","high"]},
    {"id":"openai/gpt-6-luna","name":"GPT-6 Luna","format":"openai"}],
    "most":{"thinking":"high","length":"long"},"webTools":["search","read"],"instructions":"Answer in British English.","promptTemplate":null,
    "avatarUrl":"/users/ember/avatar?v=1","avatar":false}
    """#

  static let agentsJSON = #"""
    {"agents":[{"id":"agt0000000000001","name":"Helper","role":"bot","status":"active","avatarUrl":"/h","agent":true,"description":"Answers product questions",
    "model":"openai/gpt-6-luna","modelName":"GPT-6 Luna","webTools":["search"],"access":"admins","rooms":[{"id":"r1","name":"general"},{"id":"r2","name":"design"}]}]}
    """#

  static let appsJSON = #"""
    {"apps":[{"id":"app1","name":"Linear","url":"https://mcp.linear.app/mcp","toolCount":12,"setAside":1,"signInEnded":false,"wantsAccess":true}]}
    """#

  static let botsJSON = #"""
    {"bots":[{"id":"bot0000000000001","name":"Deploys","role":"bot","status":"active","avatarUrl":"/d","key":"bot0000000000001-secret","rooms":[{"id":"r1","name":"general"}]}]}
    """#

  private func session(assistant: Bool = true, huddles: Bool = true) throws -> InstanceSession {
    let session = try base.session()
    let account = try XCTUnwrap(session.account)
    let encoded = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
    var settings = try JSONDecoder().decode(
      WorkspaceSettings.self, from: Data(AdminRenderTests.settingsJSON.replacingOccurrences(of: "ACCOUNT", with: encoded).utf8))
    if assistant { settings.assistant = try JSONDecoder().decode(AssistantSettings.self, from: Data(Self.assistantJSON.utf8)) }
    if huddles { settings.huddles = HuddlesSettings(appId: "0123456789abcdef0123456789abcdef", relayKeyId: "turnkey1") }
    settings.outsideAi = true
    session.admin.settings = settings
    session.admin.answered(account)
    session.admin.ai.offered = AssistantRules.shipped(workersAi: AIText.offeredUnread)
    session.admin.ai.agents = try JSONDecoder().decode(Agents.self, from: Data(Self.agentsJSON.utf8)).agents
    session.admin.ai.apps = try JSONDecoder().decode(Apps.self, from: Data(Self.appsJSON.utf8)).apps
    session.admin.bots = try JSONDecoder().decode(Bots.self, from: Data(Self.botsJSON.utf8)).bots
    return session
  }

  private func themed(_ view: some View, _ look: AppTheme) -> some View {
    view.environment(\.appTheme, look).environment(\.theme, .irc)
      .background(look == .irc ? Theme.irc.buffer : SemanticColor.background)
      .suiteTheme(.ircX)
  }

  func testSections() throws {
    let app = AppModel(tokens: MemoryTokenStore())
    for look in AppTheme.allCases {
      for (section, assistant) in [(AdminSection.assistant, true), (.assistant, false), (.huddles, true), (.bots, true)] {
        let session = try session(assistant: assistant, huddles: assistant)
        session.adminSection = section
        session.admin.section = section
        let name = "\(look.rawValue)-admin-ai-\(section.rawValue)\(assistant ? "" : "-off")"
        try base.render(themed(ServerSettingsView(app: app, session: session).frame(width: 860, height: 1400), look), name, width: 860, height: 1400)
      }
    }
  }

  func testEditors() throws {
    let app = AppModel(tokens: MemoryTokenStore())
    let editors: [(AIEditor, String)] = [
      (.assistantSetup, "setup"), (.ember, "ember"), (.agent(nil), "new-agent"), (.app(nil), "new-app"), (.bot(nil), "new-bot"),
      (.huddlesSetup, "huddles-keys"), (.relaySetup, "relay-keys"),
    ]
    for look in AppTheme.allCases {
      for (editor, name) in editors {
        let session = try session()
        let height: CGFloat = editor == .ember || editor == .agent(nil) ? 2600 : 1000
        try base.render(
          themed(AIEditorSheet(app: app, session: session, editor: editor).frame(width: 640, height: height), look), "\(look.rawValue)-admin-ai-editor-\(name)",
          width: 640, height: height)
      }
    }
  }

  /** A notice from a page over Server Settings shows on that page, and the dials show the levels they can't be set to. */
  func testEditorNoticeAndCappedDials() throws {
    let app = AppModel(tokens: MemoryTokenStore())
    for look in AppTheme.allCases {
      let session = try session()
      session.admin.say(AdminText.saved)
      try base.render(
        themed(AIEditorSheet(app: app, session: session, editor: .bot(nil)).frame(width: 640, height: 1000), look), "\(look.rawValue)-admin-ai-editor-notice",
        width: 640, height: 1000)
      let dials = Form {
        LevelDials(
          levels: AnswerLevels(thinking: .low, length: .short), most: AnswerLevels(thinking: .medium, length: .medium), modelName: "Claude Haiku 5.5",
          takes: [.off, .low, .high]
        ) { _ in }
      }
      .themedForm(look, .irc)
      try base.render(themed(dials.frame(width: 640, height: 400), look), "\(look.rawValue)-admin-ai-capped-dials", width: 640, height: 400)
    }
  }

  func testFirstRunHuddles() throws {
    for look in AppTheme.allCases {
      let session = try session(assistant: false, huddles: false)
      try base.render(themed(FirstRunHuddles(session: session) {}.frame(width: 560, height: 700), look), "\(look.rawValue)-first-run-huddles", width: 560, height: 700)
    }
  }
}
