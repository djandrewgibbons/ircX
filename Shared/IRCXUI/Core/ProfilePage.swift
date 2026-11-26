import AppCoreUI
import EmberKit
import SwiftUI

/**
 * Your profile (web `ProfilePage`), in place of the room in either theme: your photo, the form, accounts
 * elsewhere, Ember AI, your apps and AI apps, huddle sounds, each conversation's notifications, the people
 * you've blocked, your sign-in link and Delete my account, with Log out in the top bar.
 */
struct ProfilePage: View {
  let session: InstanceSession
  @State private var model: ProfileModel
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  init(session: InstanceSession, model: ProfileModel? = nil) {
    self.session = session
    _model = State(initialValue: model ?? ProfileModel(session: session))
  }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: "Your profile", back: session.closePage) {
        Button(look == .irc ? "[/quit]" : "Log Out", systemImage: "rectangle.portrait.and.arrow.right") {
          session.attempt("Logging out") { try await session.signOut() }
        }
        .labelStyle(.titleOnly)
        .buttonStyle(.plain)
        .foregroundStyle(look == .irc ? irc.ember : Color.accentColor)
        .help("Log out of \(session.instance.host)")
      }
      if model.loaded {
        form
      } else if let failure = model.failure {
        Text(failure).foregroundStyle(SemanticColor.warning).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Color.clear.loadingActivity(true)
      }
    }
    .task {
      await model.load()
      followIntent()
    }
    // A command can ask for something while the profile is open already.
    .onChange(of: session.profileIntent) { _, _ in if model.loaded { followIntent() } }
    .onChange(of: model.changed) { _, changed in session.holdsChanges = changed }
    .onDisappear { session.holdsChanges = false }
    .sheet(item: $model.browser) { request in
      BrowserFlowSheet(request: request, instance: session.instance, customDomain: session.account?.customDomain) { model.finish($0) }
    }
  }

  /** Does what a command asked the profile to do as it opens. */
  private func followIntent() {
    switch session.profileIntent {
    case let .signIn(id):
      session.profileIntent = nil
      if let app = model.apps.first(where: { $0.id == id }) { model.signIn(to: app) }
    case let .connect(memberful):
      session.profileIntent = nil
      if !model.hasPassword { model.connect(memberful: memberful, currentPassword: "") }
    case nil:
      break
    }
  }

  @ViewBuilder
  private var form: some View {
    let form = Form {
      if look == .irc, let message = model.message {
        Text("-!- \(message)").foregroundStyle(model.messageIsError ? irc.part : irc.join).onTapGesture { model.message = nil }
      }
      Section {
        Text(PeopleText.profileExplained).foregroundStyle(.secondary)
        PicturePicker(session: session, model: model)
      }
      ProfileFieldsSection(model: model)
      if let memberful = model.memberful {
        ElsewhereSection(model: model, memberful: true, title: "Memberful", name: "Memberful", only: memberful.membersOnly, connected: memberful.connected,
          signsInOtherwise: !model.hasPassword && model.sso?.connected != nil ? Memberful.withSso : nil, closed: model.memberfulClosed)
      }
      if let sso = model.sso {
        ElsewhereSection(model: model, memberful: false, title: "Single sign-on", name: sso.name, only: sso.ssoOnly, connected: sso.connected,
          signsInOtherwise: !model.hasPassword && model.memberful?.connected != nil ? SSO.withMemberful : nil, closed: model.ssoClosed)
      }
      if let assistant = model.assistant { AnswerLevelsSection(model: model, assistant: assistant) }
      if !model.apps.isEmpty { YourAppsSection(model: model) }
      if let connections = model.outsideAi { YourOutsideAiSection(model: model, connections: connections) }
      if session.account?.huddles == true, session.sidebarLoaded { HuddleSoundsSection(session: session, model: model) }
      ConversationNotificationsSection(session: session)
      BlockedPeopleSection(session: session)
      if let link = model.signInLink { SignInLinkSection(link: link, isMe: true) }
      DeleteAccountSection(model: model)
    }
    .themedForm(look, irc)
    switch look {
    case .suite:
      #if os(macOS)
      form.settingsNotice(model.message, isError: model.messageIsError)
      #else
      form.safeAreaInset(edge: .bottom) {
        if let message = model.message {
          Notice(
            message, systemImage: model.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            tint: model.messageIsError ? SemanticColor.warning : SemanticColor.positive, onDismiss: { model.message = nil }
          )
          .padding(.horizontal, Spacing.lg)
        }
      }
      #endif
    case .irc: form
    }
  }
}

/** Your photo (web `PicturePicker`): saved as soon as it's picked, and Remove while you have one. */
private struct PicturePicker: View {
  let session: InstanceSession
  let model: ProfileModel
  @Environment(\.appTheme) private var look

  var body: some View {
    HStack(spacing: Spacing.lg) {
      ZStack {
        Circle().fill(SemanticColor.secondaryFill)
        Text(String(model.savedName.prefix(1)).uppercased()).font(DesignFont.title).foregroundStyle(.secondary)
        if let path = model.avatarUrl { AuthImage(api: session.api, path: path).scaledToFill() }
      }
      .frame(width: 72, height: 72)
      .clipShape(Circle())
      .opacity(model.savingPicture ? 0.5 : 1)
      VStack(alignment: .leading, spacing: Spacing.sm) {
        PhotoPickerButton(onPick: model.changeAvatar, onRefused: { model.say($0, error: true) }) {
          Label(look == .irc ? "[/avatar]" : "Choose Photo", systemImage: "camera")
        }
        .help("Choose a profile photo")
        .disabled(model.savingPicture)
        if model.hasAvatar {
          Button(look == .irc ? "[/avatar remove]" : "Remove Photo", systemImage: "trash", role: .destructive, action: model.removeAvatar)
            .help("Remove avatar")
            .disabled(model.savingPicture)
        }
      }
      .buttonStyle(.borderless)
    }
  }
}

/** Name, username, email address, passwords and bio, which Save changes saves (web profile form). */
private struct ProfileFieldsSection: View {
  @Bindable var model: ProfileModel

  var body: some View {
    Section {
      TextField("Name", text: $model.fields.name)
        .textContentType(.name)
        .onSubmit(model.save)
      TextField("Username", text: $model.fields.username, prompt: Text("@username"))
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .help(PeopleText.usernameHelp)
        .onSubmit(model.save)
      TextField("Email", text: $model.fields.emailAddress)
        .textContentTypeEmail()
        .onSubmit(model.save)
      if !model.signsInElsewhereAlone {
        SecureField("New Password", text: $model.password)
          .textContentType(.newPassword)
          .help(passwordHelp)
          .onSubmit(model.save)
      }
      if model.hasPassword {
        SecureField("Current Password", text: $model.currentPassword)
          .textContentType(.password)
          .help(PeopleText.currentPasswordHelp)
          .onSubmit(model.save)
      }
      TextField("Bio", text: $model.fields.bio, axis: .vertical)
        .lineLimit(3...6)
        .onChange(of: model.fields.bio) { _, bio in
          if bio.count > EmberLimits.maxBioLength { model.fields.bio = String(bio.prefix(EmberLimits.maxBioLength)) }
        }
      HStack {
        Spacer()
        Button(model.saving ? "Saving…" : "Save Changes", action: model.save)
          .buttonStyle(.borderedProminent)
          .disabled(!model.changed || model.saving)
      }
    } header: {
      Text("Profile")
    }
  }

  private var passwordHelp: String {
    let keep = model.hasPassword ? PeopleText.keepPassword : PeopleText.keepNoPassword
    guard model.hasPassword, !model.fields.emailAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return keep }
    return keep + PeopleText.disconnectsWithNewPassword(memberful: model.memberful?.connected != nil, sso: model.sso?.connected != nil)
  }
}

/** Memberful's or single sign-on's section (web `ExternalConnection`): connected, with Disconnect, or Connect. */
private struct ElsewhereSection: View {
  let model: ProfileModel
  let memberful: Bool
  let title: String
  let name: String
  let only: Bool
  let connected: ElsewhereAccount?
  let signsInOtherwise: String?
  let closed: String?
  @State private var password = ""

  private var key: String { memberful ? "memberful" : "sso" }
  private var signsInWithPassword: Bool { model.hasPassword && model.hasEmailAddress }
  private var signsYouIn: Bool { (only && model.membershipNeeded) || !signsInWithPassword }

  var body: some View {
    Section(title) {
      if let connected {
        Text(PeopleText.connectedAs(connected, name: name) + " " + (closed ?? (signsYouIn ? PeopleText.signsYouIn(name) : PeopleText.signsInEither(name))))
        if signsInWithPassword {
          Text(signsYouIn ? PeopleText.disconnectingAsksAgain : PeopleText.disconnectingSignsOut).foregroundStyle(.secondary)
          passwordField
          Button("Disconnect \(name)", role: .destructive) {
            model.disconnect(memberful: memberful, currentPassword: password)
            password = ""
          }
          .disabled(model.busy == key || password.isEmpty)
        } else if model.hasPassword {
          Text(PeopleText.addEmailToDisconnect).foregroundStyle(.secondary)
        }
      } else if let signsInOtherwise {
        Text(signsInOtherwise)
      } else {
        Text(model.membershipNeeded ? PeopleText.membersSignInWith(name) : PeopleText.connectToSignIn(name))
        if model.hasPassword { passwordField }
        Button("Connect \(name)") {
          model.connect(memberful: memberful, currentPassword: password)
          password = ""
        }
        .disabled(model.busy == key || (model.hasPassword && password.isEmpty))
      }
    }
  }

  private var passwordField: some View {
    SecureField("Password", text: $password).textContentType(.password)
  }
}

/** How @ember answers you (web `AnswerLevels`): its model, while there's more than one, how much it thinks, and how long it answers. */
private struct AnswerLevelsSection: View {
  let model: ProfileModel
  let assistant: YourAssistant

  private var answering: AssistantModel? {
    let id = assistant.model ?? assistant.defaultModel
    return assistant.models.first { $0.id == id }
  }

  var body: some View {
    Section("Ember AI") {
      if assistant.models.count > 1 {
        Picker("Model", selection: Binding(get: { assistant.model }, set: { model.changeAssistant(YourAssistantChanges(model: .some($0))) })) {
          Text("Default (\(defaultName))").tag(String?.none)
          ForEach(assistant.models) { Text($0.name).tag(Optional($0.id)) }
        }
        .help("The model @ember answers you with. Default follows the one administrators chose.")
      }
      LevelDials(levels: assistant.levels, most: assistant.most, modelName: answering?.name, takes: answering?.thinkingLevels) { levels in
        model.changeAssistant(
          YourAssistantChanges(
            thinking: levels.thinking == assistant.levels.thinking ? nil : levels.thinking, length: levels.length == assistant.levels.length ? nil : levels.length))
      }
    }
  }

  private var defaultName: String {
    guard let found = assistant.models.first(where: { $0.id == assistant.defaultModel }) else { return assistant.defaultModel }
    return found.name
  }

}

/** Your own sign-ins to connected apps (web `YourApps`). */
private struct YourAppsSection: View {
  let model: ProfileModel

  var body: some View {
    Section {
      Text(PeopleText.yourAppsExplained).foregroundStyle(.secondary)
      ForEach(model.apps) { app in
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(app.name).fontWeight(.semibold)
          Text(PeopleText.status(of: app, at: ProfileDates.label)).foregroundStyle(.secondary)
          HStack {
            if app.signedInAt == nil || app.ended || app.wantsMore {
              Button(app.signedInAt == nil ? "Sign In" : "Sign In Again") { model.signIn(to: app) }
            }
            if app.signedInAt != nil {
              Button("Sign Out", role: .destructive) { model.signOut(of: app) }
            }
          }
          .buttonStyle(.bordered)
          .disabled(model.busy == app.id)
        }
      }
    } header: {
      Text("Apps")
    }
  }
}

/** The AI apps connected as you (web `YourOutsideAi`), and the address to give one. */
private struct YourOutsideAiSection: View {
  let model: ProfileModel
  let connections: [OutsideConnection]
  @State private var disconnecting: OutsideConnection?

  var body: some View {
    Section {
      Text(PeopleText.outsideAiExplained).foregroundStyle(.secondary)
      HStack {
        Text(model.mcpAddress).textSelection(.enabled).font(DesignFont.monoDetail).lineLimit(1)
        Spacer()
        Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(model.mcpAddress) }
          .labelStyle(.iconOnly)
          .help("Copy the address to give an AI app")
      }
      if connections.isEmpty {
        Text(PeopleText.nothingConnected).foregroundStyle(.secondary)
      }
      ForEach(connections) { connection in
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(connection.name).fontWeight(.semibold)
          Text(PeopleText.status(of: connection, at: ProfileDates.label)).foregroundStyle(.secondary)
          Button("Disconnect", role: .destructive) { disconnecting = connection }
            .buttonStyle(.bordered)
            .disabled(model.busy == connection.id)
        }
      }
    } header: {
      Text("AI Apps")
    }
    .confirmationDialog(
      "Disconnect \(disconnecting?.name ?? "it")?", isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
      titleVisibility: .visible, presenting: disconnecting
    ) { connection in
      Button("Disconnect", role: .destructive) { model.disconnect(connection) }
    } message: { connection in
      Text("\(connection.name) won't be able to use Ember as you any more.")
    }
  }
}

/** Which huddle sounds you hear (web `HuddleSoundSwitches`), each saved as it's switched. */
private struct HuddleSoundsSection: View {
  let session: InstanceSession
  let model: ProfileModel
  @State private var saving: HuddleSounds?

  private var sounds: HuddleSounds { saving ?? session.huddleSounds ?? HuddleSounds.all }

  var body: some View {
    Section {
      Text(PeopleText.huddleSoundsExplained).foregroundStyle(.secondary)
      Toggle("Music", isOn: binding(\.music, { HuddleSoundChanges(music: $0) })).help(PeopleText.musicExplained)
      Toggle("Chimes", isOn: binding(\.chimes, { HuddleSoundChanges(chimes: $0) })).help(PeopleText.chimesExplained)
      Toggle("Ring", isOn: binding(\.ring, { HuddleSoundChanges(ring: $0) })).help(PeopleText.ringExplained)
    } header: {
      Text("Huddle Sounds")
    }
  }

  private func binding(_ key: WritableKeyPath<HuddleSounds, Bool>, _ change: @escaping (Bool) -> HuddleSoundChanges) -> Binding<Bool> {
    Binding(get: { sounds[keyPath: key] }) { on in
      var shown = sounds
      shown[keyPath: key] = on
      saving = shown
      Task {
        do {
          try await session.changeHuddleSounds(change(on))
        } catch {
          logger.error("Saving huddle sounds failed: \(error.localizedDescription, privacy: .public)")
          model.say(error.localizedDescription, error: true)
        }
        saving = nil
      }
    }
  }
}

/** Your level in each room and DM (web `ConversationNotifications`): rooms by name, then DMs; hidden rooms dimmed, to show again. */
struct ConversationNotificationsSection: View {
  let session: InstanceSession
  @Environment(\.appTheme) private var look

  var body: some View {
    let order = RoomList.profileOrder(session.rooms, me: session.me?.id)
    Section("Conversation Notifications") {
      ForEach(order.shared) { row($0) }
    }
    // The DMs after a rule, as their own group.
    if !order.directs.isEmpty {
      Section { ForEach(order.directs) { row($0) } }
    }
  }

  private func row(_ item: SidebarRoom) -> some View {
    HStack {
      Button {
        session.open(room: item.id)
      } label: {
        Text((look == .irc && !item.room.isDirect ? "#" : "") + session.title(of: item.room)).lineLimit(1)
      }
      .buttonStyle(.plain)
      Spacer()
      Picker("Notifications", selection: Binding(get: { item.involvement }, set: { session.setInvolvement($0, for: item.id) })) {
        ForEach(Involvement.choices(in: item.room, current: item.involvement), id: \.self) { level in
          Label(level.sentence, systemImage: level.symbol).tag(level)
        }
      }
      .labelsHidden()
      .fixedSize()
      .disabled(session.involving.contains(item.id))
      .help(item.involvement.sentence)
    }
    .opacity(item.involvement == .invisible ? 0.5 : 1)
  }
}

/** The people you've blocked (web `BlockedPeople`), each with Unblock; hidden while you block nobody. */
struct BlockedPeopleSection: View {
  let session: InstanceSession
  @Environment(\.appTheme) private var look

  var body: some View {
    let blocked = PeopleList.byName(session.blocks.userIds.compactMap { session.people[$0] })
    if !blocked.isEmpty {
      Section {
        Text(PeopleText.blockedExplained).foregroundStyle(.secondary)
        ForEach(blocked) { person in
          HStack {
            Button {
              session.show(.person(person.id))
            } label: {
              PersonRow(session: session, person: person)
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Unblock") { session.attempt("Unblocking") { try await session.setBlocked(false, person.id) } }
              .buttonStyle(.bordered)
          }
        }
      } header: {
        Text("Blocked People")
      }
    }
  }
}

/** Delete my account (web `DeleteAccount`): asks once more in place, for your password or, without one, your name. */
private struct DeleteAccountSection: View {
  let model: ProfileModel
  @State private var asking = false
  @State private var confirming = false
  @State private var password = ""
  @State private var name = ""
  @State private var deleting = false

  var body: some View {
    Section {
      Text(PeopleText.deleteExplained).foregroundStyle(.secondary)
      if asking {
        if model.hasPassword {
          SecureField("Password", text: $password).textContentType(.password)
        } else {
          TextField(PeopleText.typeYourName(model.savedName), text: $name)
        }
        HStack {
          Button("Cancel") {
            asking = false
            password = ""
            name = ""
          }
          Spacer()
          Button(deleting ? "Deleting…" : "Delete My Account", role: .destructive) { confirming = true }
            .disabled(deleting || (model.hasPassword ? password.isEmpty : name.isEmpty))
        }
      } else {
        Button("Delete My Account", role: .destructive) { asking = true }
      }
    } header: {
      Text("Delete My Account")
    }
    .confirmationDialog("Delete your account?", isPresented: $confirming, titleVisibility: .visible) {
      Button("Delete My Account", role: .destructive, action: delete)
    } message: {
      Text(PeopleText.deleteExplained)
    }
  }

  private func delete() {
    deleting = true
    Task {
      let deleted = await model.deleteAccount(currentPassword: password, name: name)
      deleting = false
      if !deleted {
        password = ""
        name = ""
      }
    }
  }
}

enum ProfileDates {
  /** `dateTimeLabel`: a date and time as the profile says them. */
  static func label(_ iso: String) -> String {
    guard let date = EmberDate.parse(iso) else { return iso }
    return date.formatted(date: .abbreviated, time: .shortened)
  }
}
