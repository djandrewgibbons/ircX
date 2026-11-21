import AppCoreUI
import EmberKit
import SwiftUI

// Server Settings' Chat bots, AI assistant and Huddles sections (web `bots-page.tsx`, the AI assistant panel's
// `AssistantSettings`, `AgentList`, `AppList` and `OutsideAiSettings`, and the Huddles panel's
// `HuddlesSettings`, `HuddleSwitches` and `HuddleRelay`), which the web's settings navigation lists beside the
// workspace sections. Their pages and setup dialogs open over Server Settings (`AIEditorSheet`).

/** A row of the agents, apps or bots lists: a picture, a name, what it does, and its details. */
struct AIListRow: View {
  let session: InstanceSession
  var avatar: String?
  var systemImage = "cpu"
  let name: String
  var description: String?
  var details: [String] = []
  var warnings: [String] = []
  var tag: String?
  let open: () -> Void
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    Button(action: open) {
      HStack(alignment: .top, spacing: Spacing.md) {
        if look == .suite { AgentAvatar(session: session, path: avatar, size: 32, systemImage: systemImage) }
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          HStack(spacing: Spacing.xs) {
            Text(name).fontWeight(.semibold).foregroundStyle(look == .irc ? irc.text : Color.primary)
            if let tag {
              switch look {
              case .suite: StatusCapsule(text: tag, help: tag)
              case .irc: Text("[\(tag)]").foregroundStyle(irc.statusBracket)
              }
            }
          }
          if let description, !description.isEmpty { Text(description).foregroundStyle(.secondary).lineLimit(1).help(description) }
          if !details.isEmpty {
            Text(details.joined(separator: " · ")).font(look == .irc ? Theme.font(11) : DesignFont.detail).foregroundStyle(.secondary).lineLimit(1)
              .help(details.joined(separator: " · "))
          }
          ForEach(warnings, id: \.self) { StatusLine($0, tone: .warning) }
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .help("Edit \(name)")
  }
}

// MARK: - AI assistant

/** The AI assistant section (web `workspace-settings-page.tsx:673-701`): Ember AI, its agents and apps, and Outside AI. */
struct AssistantSettingsSection: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin

  private var ai: AIAdmin { admin.ai }

  var body: some View {
    let assistant = ai.assistant
    Section {
      Toggle("Ember AI", isOn: Binding(get: { assistant != nil && !ai.stoppingAssistant }, set: ai.flipAssistant))
        .disabled(ai.stoppingAssistant)
        .help(assistant == nil ? AdminText.assistantExplained : AdminText.agentsAnswer)
      Explanation(assistant == nil ? AdminText.assistantExplained : AdminText.agentsAnswer)
      if assistant != nil {
        Explanation(AIText.whatAgentsSend)
        Button("Change", systemImage: "key") { ai.editor = .assistantSetup }
          .help("Change the Cloudflare account, its API token, or @ember's model")
      }
    } header: {
      AIHeading("Ember AI")
    }
    if let assistant {
      agents(assistant)
      apps
    }
    outside
      .task(id: assistant == nil) { await ai.load() }
  }

  @ViewBuilder
  private func agents(_ assistant: AssistantSettings) -> some View {
    let full = ai.listedAgents.count >= AgentRules.maxAgents
    Section {
      Explanation(full ? AgentRules.full : AIText.agentsExplained)
      if let failure = ai.agentsFailure { StatusLine(failure, tone: .warning) }
      AIListRow(
        session: session, avatar: assistant.avatarUrl, systemImage: "flame.fill", name: "@ember", description: AgentRules.emberDoes,
        details: ai.emberDetails(assistant), tag: AIText.builtIn
      ) { ai.editor = .ember }
      if ai.agents == nil, ai.agentsFailure == nil { Color.clear.frame(height: 24).loadingActivity(true) }
      ForEach(ai.listedAgents) { agent in
        AIListRow(session: session, avatar: agent.avatarUrl, name: agent.name, description: agent.description, details: ai.agentDetails(agent)) {
          ai.editor = .agent(agent.id)
        }
      }
      Button("New Agent", systemImage: "plus") { ai.editor = .agent(nil) }
        .disabled(full)
        .help(full ? AgentRules.full : "Make an agent people mention by name")
    } header: {
      AIHeading("Agents")
    }
  }

  @ViewBuilder
  private var apps: some View {
    let full = (ai.apps ?? []).count >= AppRules.maxApps
    Section {
      Explanation(full ? AppRules.full : AIText.appsExplained)
      if let failure = ai.appsFailure { StatusLine(failure, tone: .warning) }
      if let apps = ai.apps {
        if apps.isEmpty { Text(AIText.noApps).foregroundStyle(.secondary) }
        ForEach(apps) { app in
          AIListRow(session: session, systemImage: "puzzlepiece.extension", name: app.name, details: [address(app.url), AIText.tools(app.toolCount)], warnings: warnings(app)) {
            ai.editor = .app(app.id)
          }
        }
      } else if ai.appsFailure == nil {
        Color.clear.frame(height: 24).loadingActivity(true)
      }
      Button("Connect an App", systemImage: "plus") { ai.editor = .app(nil) }
        .disabled(full)
        .help(full ? AppRules.full : AIText.appExplained)
    } header: {
      AIHeading("Apps")
    }
  }

  /** `addressOf`: an app's host and path. */
  private func address(_ url: String) -> String {
    guard let parsed = URL(string: url), let host = parsed.host(percentEncoded: false) else { return url }
    return host + (parsed.path == "/" ? "" : parsed.path)
  }

  private func warnings(_ app: AppSummary) -> [String] {
    var lines: [String] = []
    if app.signInEnded { lines.append(AIText.signInEnded) } else if app.wantsAccess { lines.append(AIText.wantsAccess) }
    if app.setAside > 0 { lines.append(AIText.setAside(app.setAside)) }
    return lines
  }

  /** Outside AI (web `OutsideAiSettings`), shown whether or not Ember AI is on. */
  @ViewBuilder
  private var outside: some View {
    if let settings = admin.settings {
      let on = ai.movingOutside ?? settings.outsideAi
      Section {
        Toggle("Let AI Apps Connect", isOn: Binding(get: { on }, set: ai.flipOutside))
          .disabled(ai.movingOutside != nil)
          .help(AIText.outsideAiSettingExplained)
        Explanation(AIText.outsideAiSettingExplained)
        if on { CopyLine(title: "Address", text: ai.outsideAddress).help(AIText.outsideAiAddress(ai.outsideAddress)) }
      } header: {
        AIHeading("Outside AI")
      }
    }
  }
}

// MARK: - Chat bots

/**
 * Chat bots (web `BotsPage`): each bot by name, with its rooms, each room's posting commands and Slack
 * webhook URL to copy, and Add a chat bot.
 */
struct ChatBotsSettings: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  @Environment(\.appTheme) private var look

  var body: some View {
    Section {
      Explanation(AdminText.botsExplained)
      if let failure = admin.botsFailure { StatusLine(failure, tone: .warning) }
      if admin.bots == nil, admin.botsFailure == nil {
        Color.clear.frame(height: 24).loadingActivity(true)
      }
      ForEach(admin.listedBots) { bot in BotRow(session: session, admin: admin, bot: bot) }
      Button("Add a Chat Bot", systemImage: "plus") { admin.ai.editor = .bot(nil) }
    } header: {
      HStack(spacing: Spacing.sm) {
        Text(look == .irc ? "*** Chat Bots" : "Chat Bots")
        TranslationButton(key: "chat_bots", account: session.account, classic: look == .irc)
        Spacer()
      }
    }
    .task(id: session.peopleLoaded) { await admin.loadBots() }
  }
}

/** A bot's row (web `BotItem`): its rooms disclosed, each disclosing its three addresses. */
private struct BotRow: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let bot: Bot
  @State private var open = false

  var body: some View {
    DisclosureGroup(isExpanded: Binding(get: { open || bot.rooms.count == 1 }, set: { open = $0 })) {
      ForEach(bot.rooms) { room in
        DisclosureGroup("#\(room.name)") { PostingCommands(session: session, room: room, key: bot.key) }
      }
    } label: {
      AIListRow(
        session: session, avatar: bot.avatarUrl, systemImage: "gearshape.2", name: bot.name,
        details: [bot.rooms.isEmpty ? AdminText.noRooms : AgentReach.names(bot.rooms)]
      ) { admin.ai.editor = .bot(bot.id) }
    }
  }
}

/** A bot's room's addresses (web `PostingCommands`): post text, post a file, and the Slack-compatible webhook URL. */
struct PostingCommands: View {
  let session: InstanceSession
  let room: NamedRoom
  let key: String

  var body: some View {
    let messages = session.publicOrigin + BotsRules.messagesPath(room: room.id, key: key)
    CopyLine(title: "Post text", text: AIText.curlText(messages))
    CopyLine(title: "Post a file", text: AIText.curlUpload(messages))
    CopyLine(title: "Slack webhook URL", text: session.publicOrigin + BotsRules.slackPath(room: room.id, key: key))
  }
}

// MARK: - Huddles

/** Huddles (web `HuddlesSettings`, `HuddleSwitches`, `HuddleRelay`): on or off, cameras and screens, and the relay. */
struct HuddlesSettingsSection: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin

  private var ai: AIAdmin { admin.ai }

  var body: some View {
    let huddles = ai.huddles
    Section {
      Toggle("Huddles", isOn: Binding(get: { huddles != nil && !ai.stoppingHuddles }, set: ai.flipHuddles))
        .disabled(ai.stoppingHuddles)
        .help(huddles.map { AdminText.huddlesRunThrough($0.appId) } ?? AdminText.huddlesExplained)
      Explanation(huddles.map { AdminText.huddlesRunThrough($0.appId) } ?? AdminText.huddlesExplained)
      if huddles != nil {
        Button("Change Keys", systemImage: "key") { ai.editor = .huddlesSetup }
          .help("Give another Realtime SFU app's keys")
      }
    } header: {
      AIHeading(AIText.huddleChatTitle)
    }
    if let huddles, let account = admin.account {
      Section {
        Toggle(isOn: Binding(get: { ai.movedCameras ?? account.huddleCameras }, set: ai.setCameras)) {
          Label("Cameras", systemImage: "video")
        }
        .disabled(ai.movedCameras != nil)
        .help(AdminText.camerasExplained)
        Explanation(AdminText.camerasExplained)
        Toggle(isOn: Binding(get: { ai.movedScreens ?? account.huddleScreens }, set: ai.setScreens)) {
          Label("Screen Sharing", systemImage: "rectangle.on.rectangle")
        }
        .disabled(ai.movedScreens != nil)
        .help(AdminText.screensExplained)
        Explanation(AdminText.screensExplained)
      }
      Section {
        Toggle("Relay", isOn: Binding(get: { huddles.relayKeyId != nil && !ai.stoppingRelay }, set: ai.flipRelay))
          .disabled(ai.stoppingRelay)
          .help(huddles.relayKeyId.map(AIText.relayOnExplained) ?? AIText.relayExplained)
        Explanation(huddles.relayKeyId.map(AIText.relayOnExplained) ?? AIText.relayExplained)
        if huddles.relayKeyId != nil {
          Button("Change Key", systemImage: "key") { ai.editor = .relaySetup }
            .help("Give another TURN key")
        }
      } header: {
        AIHeading(AIText.relayTitle)
      }
    }
  }
}
