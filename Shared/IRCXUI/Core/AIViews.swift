import AppCoreUI
import EmberKit
import SwiftUI

// The pieces the AI assistant's pages share (web `model-picker.tsx`, `level-dials.tsx`, `prompt-preview.tsx`,
// `agent-tools.tsx`, `bots-page.tsx`'s `PostingCommands`), in either theme.

/** A line under a control: what's happening, what came of it, or why it was refused. */
struct StatusLine: View {
  enum Tone { case plain, positive, warning }

  let text: String
  var tone: Tone = .plain
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  init(_ text: String, tone: Tone = .plain) {
    self.text = text
    self.tone = tone
  }

  var body: some View {
    Text(look == .irc && tone != .plain ? "-!- \(text)" : text)
      .font(look == .irc ? Theme.font(11) : DesignFont.detail)
      .foregroundStyle(color)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var color: Color {
    switch (tone, look) {
    case (.plain, _): .secondary
    case (.positive, .irc): irc.join
    case (.positive, .suite): SemanticColor.positive
    case (.warning, .irc): irc.part
    case (.warning, .suite): SemanticColor.warning
    }
  }
}

/** A section's or card's heading, as each theme sets one. */
struct AIHeading: View {
  let title: String
  var trailing: String?
  @Environment(\.appTheme) private var look

  init(_ title: String, trailing: String? = nil) {
    self.title = title
    self.trailing = trailing
  }

  var body: some View {
    HStack {
      Text(look == .irc ? "*** \(title)" : title)
      Spacer()
      if let trailing { Text(trailing).foregroundStyle(.secondary) }
    }
  }
}

/** A person's round picture, from the instance, or a picked one while it uploads. */
struct AgentAvatar: View {
  let session: InstanceSession
  let path: String?
  var picked: Data?
  var size: CGFloat = 40
  var systemImage = "cpu"
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    ZStack {
      Circle().fill(look == .irc ? irc.bar : SemanticColor.secondaryFill)
      if let picked, let image = PlatformImage(data: picked) {
        #if os(macOS)
        Image(nsImage: image).resizable().scaledToFill()
        #else
        Image(uiImage: image).resizable().scaledToFill()
        #endif
      } else if let path {
        AuthImage(api: session.api, path: path).scaledToFill()
      } else {
        Image(systemName: systemImage).font(.system(size: size * 0.4)).foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}

// MARK: - The model picker

/**
 * The menu of the models Ember offers, by their makers, then Workers AI's, with the one kept if Ember no
 * longer offers it, and under it what the one chosen costs (web `ModelPicker`).
 */
struct ModelPicker: View {
  /** nil while the Worker lists them. */
  let models: [OfferedModel]?
  /** The model kept already, which the menu lists after the others when it isn't offered. */
  var kept: AssistantModel?
  @Binding var chosen: String
  var refusal: String?
  var disabled = false
  let accountId: String?
  var workersAi: String?

  var body: some View {
    if let models {
      Picker("Model", selection: $chosen) {
        ForEach(AssistantRules.grouped(models), id: \.label) { group in
          Section(group.label) {
            ForEach(group.models) { Text(AssistantRules.entry($0)).tag($0.id) }
          }
        }
        if let kept, AssistantRules.offeredModel(kept.id, in: models) == nil {
          Text(AssistantRules.noLongerOffered(kept.id, offered: models, workersAi: workersAi) ? "\(kept.name) (\(AIText.noLongerOffered))" : kept.name).tag(kept.id)
        }
      }
      .disabled(disabled)
      .help("The model it answers with, and what a million tokens read and written cost")
      if let refusal { StatusLine(refusal, tone: .warning) }
      let cost = AssistantRules.cost(of: chosen, offered: models, workersAi: workersAi, accountId: accountId)
      Explanation(cost.text)
      if let title = cost.linkTitle, let link = cost.link { OpenLinkButton(title: title, url: link) }
      if let workersAi { Explanation(workersAi) }
    } else {
      LabeledContent("Model") { Text(AIText.listingModels).foregroundStyle(.secondary) }
        .loadingActivity(true)
    }
  }
}

// MARK: - Level dials

/**
 * Thinking and Answer length (web `LevelDials`): the levels up to `most`, and of thinking, those the model
 * takes, with what the one chosen does under each.
 */
struct LevelDials: View {
  let levels: AnswerLevels
  var most: AnswerLevels = .top
  /** The model answering at these levels, by name, with the levels of thinking it takes. */
  var modelName: String?
  var takes: [ThinkingLevel]?
  var disabled = false
  let onChange: (AnswerLevels) -> Void
  @Environment(\.appTheme) private var look

  /**
   * Whether a dial's level can be chosen (web `Dial`): not above the most the administrators allow, and for
   * Thinking, one the model takes. Every level shows; the others are greyed.
   */
  private func allows(_ level: ThinkingLevel) -> Bool {
    guard let top = ThinkingLevel.allCases.firstIndex(of: most.thinking), let index = ThinkingLevel.allCases.firstIndex(of: level), index <= top else {
      return false
    }
    guard let takes, !takes.isEmpty else { return true }
    return takes.contains(level)
  }

  private func allows(_ length: AnswerLength) -> Bool {
    guard let top = AnswerLength.allCases.firstIndex(of: most.length), let index = AnswerLength.allCases.firstIndex(of: length) else { return false }
    return index <= top
  }

  var body: some View {
    dial("Thinking", ThinkingLevel.allCases.map { ($0.name, $0, allows($0)) }, levels.thinking) {
      onChange(AnswerLevels(thinking: $0, length: levels.length))
    }
    Explanation(AssistantRules.thinkingNote(levels.thinking, modelName: modelName, takes: takes))
    dial("Answer Length", AnswerLength.allCases.map { ($0.name, $0, allows($0)) }, levels.length) {
      onChange(AnswerLevels(thinking: levels.thinking, length: $0))
    }
    Explanation(AssistantRules.lengthNote(levels.length))
  }

  /** A dial of every level, `options` naming each and whether it can be chosen; one that can't is refused. */
  @ViewBuilder
  private func dial<Value: Hashable>(_ title: String, _ options: [(String, Value, Bool)], _ value: Value, _ set: @escaping (Value) -> Void) -> some View {
    let allowed = Set(options.filter(\.2).map(\.1))
    let binding = Binding(get: { value }, set: { if $0 != value, allowed.contains($0) { set($0) } })
    let capped = options.filter { !$0.2 }.map(\.0)
    switch look {
    case .suite:
      LabeledContent(title) {
        PillSegmentedControl(options.map { PillSegmentedControl.Segment($0.0, value: $0.1) }, selection: binding, titles: .all)
          .fixedSize()
      }
      .disabled(disabled)
      .help(capped.isEmpty ? title : "\(title): \(capped.joined(separator: ", ")) can't be chosen")
    case .irc:
      Picker(title, selection: binding) {
        ForEach(options, id: \.1) { option in
          Text(option.0).tag(option.1).disabled(!option.2)
        }
      }
      .pickerStyle(.segmented)
      .disabled(disabled)
    }
  }
}

// MARK: - What Ember adds around the instructions

/**
 * What Ember adds around the instructions (web `PromptPreview`): closed at first, the prompt as it reads with
 * the instructions' place marked, and Modify, with caution, which opens the template to change, with the
 * placeholders to insert and Use Ember's own.
 */
struct PromptPreview: View {
  /** What the page calls whoever answers. */
  let name: String
  let prompt: Prompt?
  @Binding var template: String
  let ownTemplate: String
  var refusal: String?
  var disabled = false
  /** Saves the template on a page that saves it on its own, as @ember's does. */
  var save: (() -> Void)?
  var canSave = false
  @State private var open = false
  @State private var modifying = false
  @State private var selection: TextSelection?
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  private var modified: Bool { template.trimmingCharacters(in: .whitespacesAndNewlines) != ownTemplate }

  var body: some View {
    DisclosureGroup(isExpanded: $open) {
      Explanation(AIText.aroundExplained(name))
      if let prompt { preview(prompt) }
      if modifying || modified {
        PromptEditor("Around the instructions", text: $template, selection: $selection, monospaced: true, minHeight: 200, maxHeight: 420) {
          TemplateVariablesButton(
            variables: AIText.placeholderMeanings.map { TemplateVariable(token: Prompts.placeholder($0.name), detail: $0.meaning) },
            footnote: AIText.placeholdersExplained(name)
          ) { token in
            let end = insertTemplateVariable(token, into: &template, selection: selection)
            selection = TextSelection(insertionPoint: end)
          }
        }
        .disabled(disabled)
        StatusLine(AssistantRules.length(of: template))
        if let refusal { StatusLine(refusal, tone: .warning) }
        HStack {
          Button("Use Ember's Own") { template = ownTemplate }
            .disabled(!modified || disabled)
            .help("Go back to what Ember adds of its own, which follows Ember's updates")
          if let save { Button("Save", action: save).disabled(!canSave || disabled) }
        }
      } else {
        Explanation(AIText.cautionFor(name), isWarning: true)
        Button("Modify", systemImage: "exclamationmark.triangle") { modifying = true }
          .help("Modify with caution: \(AIText.cautionFor(name))")
          .disabled(disabled)
      }
    } label: {
      HStack {
        Text("Around the Instructions")
        if modified {
          switch look {
          case .suite: StatusCapsule(text: "Modified", tint: SemanticColor.warning, help: "What Ember adds differs from Ember's own")
          case .irc: Text("[modified]").foregroundStyle(irc.part)
          }
        }
      }
      .help("What Ember adds around them")
    }
    .onChange(of: refusal) { _, now in if now != nil { open = true } }
  }

  private func preview(_ prompt: Prompt) -> some View {
    let marker = Text("[\(AIText.yourInstructions)]").bold().foregroundStyle(look == .irc ? irc.ember : SuiteTheme.ircX.accent)
    return ScrollView {
      Text("\(prompt.before)\(marker)\(prompt.after)")
        .font(look == .irc ? Theme.font(11) : DesignFont.monoDetail)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxHeight: 260)
  }
}

// MARK: - Rooms

/** Every room, or Only the rooms I choose, with the open rooms to choose from (web `Rooms`). */
struct RoomsPicker: View {
  @Binding var everyOpenRoom: Bool
  @Binding var chosen: [RoomID]
  let rooms: [NamedRoom]
  var disabled = false
  @Environment(\.appTheme) private var look

  var body: some View {
    Picker("Rooms", selection: $everyOpenRoom) {
      Text("Every Room").tag(true)
      Text("Only the Rooms I Choose").tag(false)
    }
    .pickerStyle(.inline)
    .labelsHidden()
    .disabled(disabled)
    if !everyOpenRoom {
      ForEach(rooms) { room in
        Toggle(
          look == .irc ? "#\(room.name)" : room.name,
          isOn: Binding(
            get: { chosen.contains(room.id) },
            set: { on in
              if on { chosen.append(room.id) } else { chosen.removeAll { $0 == room.id } }
            })
        )
        .disabled(disabled)
      }
    }
  }
}

// MARK: - Copying

/** A line to copy, such as a bot's posting command, with its Copy button. */
struct CopyLine: View {
  let title: String
  let text: String
  @State private var copied = false
  @Environment(\.appTheme) private var look

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(title).font(look == .irc ? Theme.font(11) : DesignFont.detail).foregroundStyle(.secondary)
        Text(text).font(look == .irc ? Theme.font(11) : DesignFont.monoDetail).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
      }
      Spacer()
      Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
        Pasteboard.copy(text)
        copied = true
      }
      .labelStyle(.iconOnly)
      .help("Copy: \(title)")
    }
  }
}

// MARK: - Tools

/** An agent's tools (web `AgentTools`): what it may use of each connected app's, each saved as it's picked. */
@MainActor
@Observable
final class ToolsModel {
  @ObservationIgnored unowned let session: InstanceSession
  let agent: UserID
  var apps: [OfferedApp]?
  var saving = false
  var refusal: String?
  var failure: String?

  init(session: InstanceSession, agent: UserID) {
    self.session = session
    self.agent = agent
  }

  var picked: Int {
    guard let apps else { return 0 }
    return apps.flatMap(\.tools).filter(\.picked).count
  }

  func load() async {
    do {
      apps = try await session.api.agentTools(agent)
      failure = nil
    } catch {
      logger.error("Loading an agent's tools failed: \(error.localizedDescription, privacy: .public)")
      if (error as? EmberError) == .signedOut { return session.sessionEnded() }
      failure = error.localizedDescription
    }
  }

  /** The picks `apps` make, as the Worker takes them. */
  static func picks(_ apps: [OfferedApp]) -> [ToolPick] {
    apps.flatMap { app in
      app.tools.filter(\.picked).map { ToolPick(appId: app.id, name: $0.name, fingerprint: $0.fingerprint, alwaysAllowed: $0.alwaysAllowed) }
    }
  }

  /** Picks or unpicks a tool, or always allows it, saving every pick at once (web `save`). */
  func set(_ app: AppID, _ tool: String, picked: Bool? = nil, alwaysAllowed: Bool? = nil) async throws {
    guard var apps, !saving else { return }
    let before = apps
    guard let a = apps.firstIndex(where: { $0.id == app }), let t = apps[a].tools.firstIndex(where: { $0.name == tool }) else {
      throw EmberError.refused(404, "\(app) has no tool \(tool)")
    }
    if let picked {
      apps[a].tools[t].picked = picked
      if picked { apps[a].tools[t].changed = false } else { apps[a].tools[t].alwaysAllowed = false }
    }
    if let alwaysAllowed { apps[a].tools[t].alwaysAllowed = alwaysAllowed }
    self.apps = apps
    saving = true
    refusal = nil
    defer { saving = false }
    do {
      self.apps = try await session.api.pickAgentTools(agent, Self.picks(apps))
    } catch {
      if let refused = FormRefusal.of(error, conflicts: true) {
        refusal = refused.error
        await load()
      } else {
        self.apps = before
      }
      throw error
    }
  }

  /** `set`, from a control, which shows a failure on the page. */
  func flip(_ app: AppID, _ tool: String, picked: Bool? = nil, alwaysAllowed: Bool? = nil) {
    Task {
      do {
        try await set(app, tool, picked: picked, alwaysAllowed: alwaysAllowed)
      } catch where FormRefusal.of(error, conflicts: true) == nil {
        session.admin.failed("Saving the agent's tools", error)
      } catch {
        logger.error("Saving the agent's tools was refused: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}

/** The Tools card (web `AgentTools`), for @ember and each saved agent. */
struct ToolsSection: View {
  let model: ToolsModel
  let name: String
  let connectApp: () -> Void
  @Environment(\.appTheme) private var look

  var body: some View {
    Section {
      Explanation(AIText.toolsExplained(name))
      if let failure = model.failure { StatusLine(failure, tone: .warning) }
      if let refusal = model.refusal { StatusLine(refusal, tone: .warning) }
      if let apps = model.apps {
        if apps.isEmpty {
          Text(AIText.noAppsToPick).foregroundStyle(.secondary)
          Button("Connect an App", systemImage: "plus", action: connectApp)
        }
        ForEach(apps) { app in
          Text(look == .irc ? "[\(app.name)]" : app.name).fontWeight(.semibold)
          if app.tools.isEmpty { Explanation(AIText.noToolsToPick) }
          ForEach(app.tools, id: \.name) { tool in row(app, tool) }
        }
      } else if model.failure == nil {
        Color.clear.frame(height: 24).loadingActivity(true)
      }
    } header: {
      AIHeading("Tools", trailing: AIText.picked(model.picked))
    }
    .disabled(model.saving)
    .task { await model.load() }
  }

  @ViewBuilder
  private func row(_ app: OfferedApp, _ tool: OfferedTool) -> some View {
    let full = model.picked >= AppRules.maxAgentTools && !tool.picked
    Toggle(isOn: Binding(get: { tool.picked }, set: { model.flip(app.id, tool.name, picked: $0) })) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack {
          Text(tool.name).font(look == .irc ? Theme.font(12) : DesignFont.monoBody)
          if let title = tool.title { Text(title).foregroundStyle(.secondary) }
        }
        Text(tool.description).font(look == .irc ? Theme.font(11) : DesignFont.detail).foregroundStyle(.secondary).lineLimit(3).help(tool.description)
        if tool.changed { StatusLine(AIText.toolChanged, tone: .warning) }
      }
    }
    .disabled(full)
    if tool.picked {
      Toggle("Always Allow \(tool.name)", isOn: Binding(get: { tool.alwaysAllowed }, set: { model.flip(app.id, tool.name, alwaysAllowed: $0) }))
        .padding(.leading, Spacing.xl)
        .help(AIText.alwaysAllowExplained(name))
      #if os(iOS)
      Explanation(AIText.alwaysAllowExplained(name))
        .padding(.leading, Spacing.xl)
      #endif
    }
  }
}
