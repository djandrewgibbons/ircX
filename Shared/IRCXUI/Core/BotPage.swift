import AppCoreUI
import EmberKit
import SwiftUI

// Add a chat bot and a bot's settings (web `bot-settings-page.tsx`), and the huddles and relay keys dialogs
// (web `huddles-setup.tsx`, `huddles-steps.tsx`, `relay-setup.tsx`), which first-run setup's huddles step
// shares (`setup-huddles.tsx`).

// MARK: - Chat bots

@MainActor
@Observable
final class BotEditor {
  @ObservationIgnored unowned let session: InstanceSession
  let botId: UserID?
  var saved: BotSettings?
  var name = ""
  var webhookUrl = ""
  var everyOpenRoom = true
  var chosenRooms: [RoomID] = []
  var avatar: ChosenPhoto?
  var refusal: String?
  var saving = false
  var loadFailure: String?
  var incomingRoom: RoomID?

  init(session: InstanceSession, botId: UserID?) {
    self.session = session
    self.botId = botId
  }

  func load() async {
    guard let botId else { return }
    do {
      let bot = try await session.api.bot(botId)
      saved = bot
      name = bot.name
      if let url = bot.webhookUrl { webhookUrl = url }
      everyOpenRoom = bot.pickedRooms == nil
      chosenRooms = (bot.pickedRooms ?? []).map(\.id)
      incomingRoom = bot.rooms.first?.id
    } catch {
      logger.error("Loading a bot failed: \(error.localizedDescription, privacy: .public)")
      if (error as? EmberError) == .signedOut { return session.sessionEnded() }
      loadFailure = error.localizedDescription
    }
  }

  private var rooms: PickedRooms { everyOpenRoom ? .everyOpenRoom : .these(chosenRooms) }

  /** `changesOf`: only what's changed. */
  var changes: BotChanges {
    guard let saved else { return BotChanges(name: name, webhookUrl: webhookUrl, rooms: rooms) }
    var changes = BotChanges()
    if name.trimmingCharacters(in: .whitespaces) != saved.name { changes.name = name }
    let url = webhookUrl.trimmingCharacters(in: .whitespaces)
    if (url.isEmpty ? nil : url) != saved.webhookUrl { changes.webhookUrl = url }
    let same: Bool
    switch (rooms, saved.pickedRooms) {
    case (.everyOpenRoom, nil): same = true
    case let (.these(ids), kept?): same = ids.count == kept.count && kept.allSatisfy { ids.contains($0.id) }
    default: same = false
    }
    if !same { changes.rooms = rooms }
    return changes
  }

  var changed: Bool {
    guard !saving else { return false }
    if avatar != nil { return true }
    guard saved != nil else { return !name.trimmingCharacters(in: .whitespaces).isEmpty }
    let changes = changes
    return changes.name != nil || changes.webhookUrl != nil || changes.rooms != nil
  }

  /** Save changes: the bot made or changed, then the bots page again (web `BotForm`). */
  func save(then: @escaping @MainActor () -> Void) {
    let url = webhookUrl.trimmingCharacters(in: .whitespaces)
    if !url.isEmpty, !AppRules.isAppUrl(url) { return refusal = BotsRules.webhookUrlRefused }
    refusal = nil
    saving = true
    let changes = changes
    let photo = avatar
    Task {
      defer { saving = false }
      do {
        if let saved {
          try await session.api.changeBot(saved.id, changes, avatar: photo)
        } else {
          try await session.api.createBot(changes, avatar: photo)
        }
        await session.admin.loadBots()
        session.admin.say(AdminText.saved)
        then()
      } catch {
        if let problem = (error as? EmberError)?.problem, [413, 422].contains(problem.status) {
          logger.error("Saving the bot was refused: \(problem.message, privacy: .public)")
          refusal = problem.message
        } else {
          session.admin.failed("Saving the bot", error)
        }
      }
    }
  }
}

/** Add a chat bot, or a bot's page (web `BotForm`): its avatar, name, rooms, addresses, webhook URL, and for a saved one, Delete bot and Generate a new key. */
struct BotPage: View {
  let session: InstanceSession
  let onClose: () -> Void
  @State private var editor: BotEditor
  @State private var asking: AdminConfirmation?
  @Environment(\.appTheme) private var look

  init(session: InstanceSession, botId: UserID?, onClose: @escaping () -> Void) {
    self.session = session
    self.onClose = onClose
    _editor = State(initialValue: BotEditor(session: session, botId: botId))
  }

  private var ai: AIAdmin { session.admin.ai }

  var body: some View {
    SetupFrame(
      title: "Chat Bot Setup", systemImage: "gearshape.2", cancelTitle: "Cancel", actionTitle: editor.saving ? "Saving…" : "Save Changes", canAct: editor.changed,
      busy: editor.saving, onCancel: onClose, onAct: { editor.save(then: onClose) }
    ) {
      if let failure = editor.loadFailure {
        Section { StatusLine(failure, tone: .warning) }
      } else if editor.botId != nil, editor.saved == nil {
        Section { Color.clear.frame(height: 40).loadingActivity(true) }
      } else {
        form
      }
    }
    .task { await editor.load() }
    .confirmationDialog(
      asking?.title ?? "Are you sure?", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), titleVisibility: .visible,
      presenting: asking
    ) { confirmation in
      Button(confirmation.title, role: .destructive) {
        switch confirmation {
        case let .deleteBot(id, _): ai.deleteBot(id, then: onClose)
        case let .newBotKey(id, _): ai.newBotKey(id) { Task { await editor.load() } }
        default: break
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { confirmation in
      Text(confirmation.message)
    }
  }

  @ViewBuilder
  private var form: some View {
    @Bindable var editor = editor
    Section {
      Explanation(AIText.botSetupExplained)
      HStack(spacing: Spacing.lg) {
        AgentAvatar(session: session, path: editor.saved?.avatarUrl, picked: editor.avatar.map { $0.variant ?? $0.data }, size: 48, systemImage: "gearshape.2")
        PhotoPickerButton(onPick: { editor.avatar = $0 }, onRefused: { editor.refusal = $0 }) {
          Label(look == .irc ? "[upload avatar]" : "Upload Avatar", systemImage: "camera")
        }
      }
      SetupField("Bot name") {
        HStack(spacing: Spacing.sm) {
          TextField("Bot name", text: $editor.name)
          TranslationButton(key: "bot_name", account: session.account, classic: look == .irc)
        }
      }
    }
    .disabled(editor.saving)
    Section {
      Explanation(AIText.botRoomsExplained)
      RoomsPicker(
        everyOpenRoom: $editor.everyOpenRoom, chosen: $editor.chosenRooms, rooms: ai.roomsToPick(kept: editor.saved?.pickedRooms ?? []), disabled: editor.saving)
    } header: {
      AIHeading("Rooms")
    }
    Section {
      if let saved = editor.saved, !saved.rooms.isEmpty {
        Picker("Room", selection: $editor.incomingRoom) {
          ForEach(saved.rooms) { Text("#\($0.name)").tag(Optional($0.id)) }
        }
        if let room = saved.rooms.first(where: { $0.id == editor.incomingRoom }) { PostingCommands(session: session, room: room, key: saved.key) }
      } else {
        Explanation(editor.saved == nil ? AIText.addressesAfterSave : AIText.noAddresses)
      }
    } header: {
      AIHeading("Incoming")
    }
    Section {
      SetupField("Webhook URL") {
        HStack(spacing: Spacing.sm) {
          TextField("Webhook URL", text: $editor.webhookUrl, prompt: Text("https://example.com/ember"))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
          TranslationButton(key: "webhook_url", account: session.account, classic: look == .irc)
        }
      }
      Explanation(AIText.webhookExplained)
    } header: {
      AIHeading("Outgoing")
    }
    .disabled(editor.saving)
    if let refusal = editor.refusal { Section { StatusLine(refusal, tone: .warning) } }
    if let saved = editor.saved {
      Section {
        Button("Generate a New Key", systemImage: "key") { asking = .newBotKey(saved.id, name: saved.name) }
          .help(AIText.confirmNewKey)
        Button("Delete Bot", systemImage: "trash", role: .destructive) { asking = .deleteBot(saved.id, name: saved.name) }
          .help(AIText.confirmDeleteBot)
      }
      .disabled(editor.saving)
    }
  }
}

// MARK: - Huddles' and the relay's keys

/** The keys a huddles dialog asks for: the Realtime SFU app's, or the TURN key's (web `useHuddlesKeys`, `RelaySetup`). */
@MainActor
@Observable
final class CloudflareKeysModel {
  enum Kind { case huddles, relay }

  @ObservationIgnored unowned let session: InstanceSession
  let kind: Kind
  /** Whether keys are kept already, which the dialog says it replaces. */
  let changing: Bool
  var first = ""
  var second = ""
  var refusal: FormRefusal?
  var saving = false
  var done = false
  /** The Cloudflare account the dashboard opens in, when it's known. */
  var accountId: String?

  init(session: InstanceSession, kind: Kind, huddles: HuddlesSettings?) {
    self.session = session
    self.kind = kind
    accountId = session.admin.settings?.cloudflareAccountId
    switch kind {
    case .huddles:
      changing = huddles != nil
      if let appId = huddles?.appId { first = appId }
    case .relay:
      changing = huddles?.relayKeyId != nil
      if let keyId = huddles?.relayKeyId { first = keyId }
    }
  }

  var fields: (first: String, second: String) { kind == .huddles ? ("appId", "appSecret") : ("keyId", "apiToken") }
  var typed: Bool { !first.trimmingCharacters(in: .whitespaces).isEmpty && !second.trimmingCharacters(in: .whitespaces).isEmpty }

  /** Save: checked as the Worker checks them, then Cloudflare asked to start a session with them, or make the relay's servers. */
  func save(failed: @escaping @MainActor (Error) -> Void) {
    refusal = nil
    switch kind {
    case .huddles:
      guard let appId = Huddles.appId(of: first) else { return refusal = FormRefusal(field: "appId", error: Huddles.appIdRefused) }
      guard let secret = Huddles.appSecret(of: second) else { return refusal = FormRefusal(field: "appSecret", error: Huddles.appSecretRefused) }
      send(failed: failed) {
        let saved = try await self.session.api.saveHuddles(HuddlesSetup(appId: appId, appSecret: secret))
        self.session.admin.ai.huddlesSaved(saved)
      }
    case .relay:
      guard let keyId = Huddles.relayKeyId(of: first) else { return refusal = FormRefusal(field: "keyId", error: Huddles.relayKeyIdRefused) }
      guard let token = Huddles.relayApiToken(of: second) else { return refusal = FormRefusal(field: "apiToken", error: Huddles.relayApiTokenRefused) }
      send(failed: failed) {
        self.session.admin.settings?.huddles = try await self.session.api.saveHuddleRelay(HuddleRelaySetup(keyId: keyId, apiToken: token))
      }
    }
  }

  private func send(failed: @escaping @MainActor (Error) -> Void, _ request: @escaping @MainActor () async throws -> Void) {
    saving = true
    Task {
      defer { saving = false }
      do {
        try await request()
        second = ""
        done = true
      } catch {
        if let refused = FormRefusal.of(error, conflicts: true) {
          logger.error("Cloudflare's keys were refused: \(refused.error, privacy: .public)")
          refusal = refused
        } else {
          failed(error)
        }
      }
    }
  }
}

/** The two steps (web `HuddlesSteps`, `RelaySetup`'s): make the app or key in Cloudflare, then copy its keys here. */
struct CloudflareKeysSteps: View {
  let model: CloudflareKeysModel

  var body: some View {
    @Bindable var model = model
    let huddles = model.kind == .huddles
    let fields = model.fields
    Section {
      Text("1. \(huddles ? AIText.sfuStepTitle : AIText.turnStepTitle)").fontWeight(.semibold)
      Text(huddles ? AIText.sfuStep : AIText.turnStep)
      OpenLinkButton(title: "Open Cloudflare's Dashboard", url: huddles ? AIText.sfuDashboard(model.accountId) : AIText.turnDashboard(model.accountId))
    }
    Section {
      Text("2. \(huddles ? AIText.keysStepTitle : AIText.turnKeysStepTitle)").fontWeight(.semibold)
      SetupField(huddles ? "App ID" : "TURN Token ID") {
        TextField(huddles ? "App ID" : "TURN Token ID", text: $model.first)
          .autocorrectionDisabled()
          #if os(iOS)
          .textInputAutocapitalization(.never)
          #endif
          .onChange(of: model.first) { model.refusal = nil }
      }
      if let refused = model.refusal?.on(fields.first) { StatusLine(refused, tone: .warning) }
      SetupField(huddles ? "App Secret" : "API Token") {
        SecureField(huddles ? "App Secret" : "API Token", text: $model.second).onChange(of: model.second) { model.refusal = nil }
      }
      if let refused = model.refusal?.on(fields.second) {
        StatusLine(refused, tone: .warning)
      } else if model.saving {
        StatusLine(huddles ? AIText.checkingKeys : AIText.checkingRelay)
      } else if model.changing {
        Explanation(huddles ? AIText.keysKept : AIText.turnKeyKept)
      } else {
        Explanation(AIText.secretKept)
      }
      if let refusal = model.refusal, refusal.field != fields.first, refusal.field != fields.second { StatusLine(refusal.error, tone: .warning) }
    }
  }
}

/** Set up huddles, or the relay (web `HuddlesSetup`, `RelaySetup`): the steps, then that it's on. */
struct CloudflareKeysSheet: View {
  let session: InstanceSession
  let kind: CloudflareKeysModel.Kind
  let onClose: () -> Void
  @State private var model: CloudflareKeysModel

  init(session: InstanceSession, kind: CloudflareKeysModel.Kind, onClose: @escaping () -> Void) {
    self.session = session
    self.kind = kind
    self.onClose = onClose
    _model = State(initialValue: CloudflareKeysModel(session: session, kind: kind, huddles: session.admin.settings?.huddles))
  }

  private var title: String {
    switch (kind, model.done) {
    case (.huddles, true): "Huddles Are On"
    case (.huddles, false): "Set Up Huddles"
    case (.relay, true): "The Relay Is On"
    case (.relay, false): "Set Up the Relay"
    }
  }

  var body: some View {
    let huddles = kind == .huddles
    SetupFrame(
      title: title, systemImage: huddles ? "headphones" : "network", cancelTitle: model.done ? "Close" : "Cancel",
      actionTitle: model.done ? "Done" : model.saving ? "Checking…" : "Save", canAct: model.done || model.typed, busy: model.saving, onCancel: onClose,
      onAct: act
    ) {
      if model.done {
        Section { Text(huddles ? AIText.huddlesOn : AIText.relayOn) }
      } else {
        Section { Explanation(huddles ? AIText.huddlesSetupExplained : AIText.relaySetupExplained) }
        CloudflareKeysSteps(model: model)
      }
    }
  }

  private func act() {
    guard !model.done else { return onClose() }
    let doing = kind == .huddles ? "Setting up huddles" : "Setting up the relay"
    model.save { session.admin.failed(doing, $0) }
  }
}
