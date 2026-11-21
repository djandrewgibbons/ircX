import AppCoreUI
import EmberKit
import HuddleMedia
import SwiftUI
#if os(iOS)
import AVKit
#endif

/**
 * How the huddle's shared views look in each theme: the Suite's tokens, or IRC Classic's palette and
 * fixed-width font (its `Theme`).
 */
@MainActor
struct HuddleLook {
  var tile: Color
  var text: Color
  var dim: Color
  var speaking: Color
  var font: Font
  var detail: Font
  var radius: CGFloat
  var face: @MainActor (User, CGFloat) -> AnyView

  static func suite(_ session: InstanceSession) -> HuddleLook {
    HuddleLook(
      tile: SemanticColor.secondaryFill, text: SemanticColor.label, dim: SemanticColor.secondaryLabel, speaking: SemanticColor.positive,
      font: DesignFont.body, detail: DesignFont.detail, radius: Radius.card,
      face: { user, size in AnyView(SuiteAvatar(session: session, user: session.people[user.id]?.user ?? user, size: size)) })
  }

  static func irc(_ theme: Theme) -> HuddleLook {
    HuddleLook(
      tile: theme.sidebar, text: theme.text, dim: theme.dim, speaking: theme.join, font: Theme.font(13), detail: Theme.font(11), radius: 2,
      face: { user, size in
        AnyView(
          Text(String(user.name.prefix(2)).uppercased())
            .font(Theme.font(size * 0.4, weight: .bold))
            .foregroundStyle(theme.nick(user.id))
            .frame(width: size, height: size)
            .background(theme.bar)
            .accessibilityHidden(true))
      })
  }
}

// MARK: - Tiles and the stage

/** One tile's worth: a person, or a screen shown in a tile. */
private struct HuddleTileItem: Identifiable {
  enum Kind { case person(HuddlePerson), screen(UserID) }
  var id: String
  var kind: Kind
  var picture: HuddlePicture?
  var caption: String
}

/**
 * The people in the huddle, a tile each (web `HuddleView`'s tiles, lib/huddle-tiles.ts), laid out to
 * show largest in the space there is, and while anyone shares a screen, that screen large with the
 * tiles beside it or under it, whichever shows it larger. Reactions rise from their base.
 */
struct HuddleStageView: View {
  let call: HuddleCall
  let look: HuddleLook
  /** The screen shown large, by whose it is, where its person picked one. */
  @State private var chosen: UserID?
  @State private var shapes: [UserID: Double] = [:]

  private var you: UserID? { call.you?.id }

  private func name(_ id: UserID, fallback: String) -> String { call.session.people[id]?.name ?? fallback }

  /** The screens shown: the app's own first, then the others' it watches, in the order they joined. */
  private var screens: [(id: UserID, picture: HuddlePicture, caption: String)] {
    var shown: [(UserID, HuddlePicture, String)] = []
    if let you, let own = call.screen { shown.append((you, own, "Your screen")) }
    for person in call.people where person.user.id != you {
      if let picture = call.screens[person.user.id] { shown.append((person.user.id, picture, "\(name(person.user.id, fallback: person.user.name))'s screen")) }
    }
    return shown
  }

  private var peopleTiles: [HuddleTileItem] {
    call.people.map { person in
      let mine = person.user.id == you
      return HuddleTileItem(
        id: "person-\(person.user.id)", kind: .person(person), picture: mine ? call.camera : call.watched[person.user.id],
        caption: name(person.user.id, fallback: person.user.name) + (mine ? " (you)" : ""))
    }
  }

  var body: some View {
    GeometryReader { space in
      let shown = screens
      if let large = shown.first(where: { $0.id == chosen }) ?? shown.first {
        let small = shown.filter { $0.id != large.id }.map { HuddleTileItem(id: "screen-\($0.id)", kind: .screen($0.id), picture: $0.picture, caption: $0.caption) }
        let items = small + peopleTiles
        let shape = shapes[large.id] ?? HuddleLayout.screenShape
        let stage = HuddleLayout.stage(items.count, shape: shape, width: space.size.width, height: space.size.height)
        let screen = VStack(alignment: .leading, spacing: Spacing.xs) {
          HuddleVideoView(picture: large.picture, fill: false) { shapes[large.id] = $0 }
            .frame(width: stage.screen, height: stage.screen / shape)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: look.radius, style: .continuous))
          Text(large.caption).font(look.detail).foregroundStyle(look.dim).lineLimit(1)
        }
        Group {
          if stage.beside {
            HStack(alignment: .top, spacing: HuddleLayout.gap) {
              screen
              grid(items, stage.tiles)
            }
          } else {
            VStack(spacing: HuddleLayout.gap) {
              screen
              grid(items, stage.tiles)
            }
          }
        }
        // The tiles beside a screen are small, mostly, and the room is told so (`takeCamerasSmall`).
        .onChange(of: HuddleLayout.showsCamerasSmall(stage.tiles), initial: true) { _, small in call.setSmall(small) }
      } else {
        let tiles = HuddleLayout.tiles(peopleTiles.count, width: space.size.width, height: space.size.height)
        grid(peopleTiles, tiles)
          .frame(width: space.size.width, height: space.size.height)
          .onChange(of: HuddleLayout.showsCamerasSmall(tiles), initial: true) { _, small in call.setSmall(small) }
      }
    }
    .overlay { HuddleRising(call: call, look: look) }
  }

  private func grid(_ items: [HuddleTileItem], _ tiles: HuddleTiles) -> some View {
    ScrollView {
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(tiles.width), spacing: HuddleLayout.gap), count: max(1, tiles.columns)), spacing: HuddleLayout.gap) {
        ForEach(items) { item in
          tile(item)
            .frame(width: tiles.width, height: tiles.height)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  @ViewBuilder
  private func tile(_ item: HuddleTileItem) -> some View {
    switch item.kind {
    case let .person(person):
      HuddleTile(
        person: person, picture: item.picture, caption: item.caption, speaking: call.speaking.contains(person.user.id), look: look,
        removeSticker: person.user.id == you ? { call.setSticker(nil) } : nil)
    case let .screen(id):
      Button {
        chosen = id
      } label: {
        ZStack(alignment: .bottomLeading) {
          look.tile
          if let picture = item.picture { HuddleVideoView(picture: picture, fill: false) }
          Text(item.caption).font(look.detail).foregroundStyle(look.text).padding(Spacing.sm)
        }
        .clipShape(RoundedRectangle(cornerRadius: look.radius, style: .continuous))
      }
      .buttonStyle(.plain)
      .help("Show \(item.caption) larger")
    }
  }
}

/** One person's tile (web `Tile`): their camera, or their face; muted, name, sticker; ringed while speaking. */
struct HuddleTile: View {
  let person: HuddlePerson
  let picture: HuddlePicture?
  let caption: String
  let speaking: Bool
  let look: HuddleLook
  let removeSticker: (() -> Void)?

  var body: some View {
    GeometryReader { space in
      ZStack {
        look.tile
        if let picture {
          HuddleVideoView(picture: picture, fill: true)
        } else {
          look.face(person.user, min(space.size.width, space.size.height) * 0.4)
        }
      }
      .overlay(alignment: .bottomLeading) {
        HStack(spacing: Spacing.xs) {
          if person.muted { Image(systemName: "mic.slash.fill").accessibilityLabel("Muted") }
          Text(caption).lineLimit(1)
        }
        .font(look.detail)
        .foregroundStyle(look.text)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(look.tile.opacity(0.8), in: Capsule())
        .padding(Spacing.sm)
      }
      .overlay(alignment: .topTrailing) {
        if let sticker = person.sticker {
          let label = HStack(spacing: Spacing.xs) {
            Text(sticker.emoji)
            if space.size.width >= 176 { Text(sticker.name).font(look.detail) }
          }
          .foregroundStyle(look.text)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.xxs)
          .background(look.tile.opacity(0.9), in: Capsule())
          .padding(Spacing.sm)
          if let removeSticker {
            Button(action: removeSticker) { label }.buttonStyle(.plain).help("Remove sticker")
          } else {
            label
          }
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: look.radius, style: .continuous).strokeBorder(speaking ? look.speaking : Color.clear, lineWidth: 2)
      }
      .clipShape(RoundedRectangle(cornerRadius: look.radius, style: .continuous))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(person.sticker.map { "\(caption): \($0.shown)" } ?? caption)
    .accessibilityValue(speaking ? "Speaking" : "Not speaking")
  }
}

/**
 * The reactions that rise from the base of the people for four seconds (web huddle-rising.tsx), each
 * over its sender's name, from five places along it, held still where motion is reduced; and the pills
 * of the emoji rising, in the corner, which send the same again.
 */
struct HuddleRising: View {
  let call: HuddleCall
  let look: HuddleLook
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { space in
      ZStack(alignment: .bottomLeading) {
        ForEach(call.reactions.rising) { reaction in
          RisingReactionView(emoji: reaction.emoji, name: firstName(reaction.userId), look: look, height: space.size.height, still: reduceMotion)
            .position(x: space.size.width * (Double(reaction.place) + 0.5) / 5, y: space.size.height - 40)
            .accessibilityLabel("\(name(reaction.userId)) reacted with \(reaction.emoji)")
        }
      }
      .frame(width: space.size.width, height: space.size.height)
      .allowsHitTesting(false)
    }
    .overlay(alignment: .topTrailing) {
      HStack(spacing: Spacing.xs) {
        ForEach(call.reactions.runs) { run in
          Button {
            call.react(run.emoji)
          } label: {
            Text("\(run.emoji) \(run.first == call.you?.id ? "You" : firstName(run.first))\(run.more > 0 ? " + \(run.more)" : "")")
              .font(look.detail)
              .foregroundStyle(look.text)
              .padding(.horizontal, Spacing.sm)
              .padding(.vertical, Spacing.xxs)
              .background(look.tile, in: Capsule())
          }
          .buttonStyle(.plain)
          .help("React with \(run.emoji)")
        }
      }
      .padding(Spacing.sm)
    }
  }

  private func name(_ id: UserID) -> String {
    if let person = call.session.people[id] { return person.name }
    if let person = call.people.first(where: { $0.user.id == id }) { return person.user.name }
    return "Someone"
  }

  private func firstName(_ id: UserID) -> String {
    let full = name(id)
    guard let first = full.split(separator: " ").first else { return full }
    return String(first)
  }
}

private struct RisingReactionView: View {
  let emoji: String
  let name: String
  let look: HuddleLook
  let height: CGFloat
  let still: Bool
  @State private var risen = false

  var body: some View {
    VStack(spacing: Spacing.xxs) {
      Text(emoji).font(DesignFont.scaled(40))
      Text(name).font(look.detail).foregroundStyle(look.text).padding(.horizontal, Spacing.sm).background(look.tile, in: Capsule())
    }
    .offset(y: risen && !still ? -height * 0.6 : 0)
    .opacity(risen ? 0 : 1)
    .onAppear {
      withAnimation(.easeIn(duration: HuddleReactions.showsFor)) { risen = true }
    }
  }
}

// MARK: - The preview

/**
 * The preview a huddle starts from (web huddle-preview.tsx): who's in it, the app's person's face, or
 * their camera, over the switches for the microphone and the camera, what to speak and be seen
 * through, then Cancel and Start Huddle or Join Huddle. Opening it asks for the microphone, so the
 * huddle starts with it, or listening only where there's none; the camera stays off until switched on.
 */
struct HuddlePreviewSheet: View {
  let request: HuddlePreviewRequest
  let center: HuddleCenter
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @Environment(\.dismiss) private var dismiss
  /** Nil while the system asks; then whether there's a microphone to use. */
  @State private var microphone: Bool?
  @State private var muted = false
  @State private var camera: HuddlePicture?
  @State private var cameraNote: String?
  @State private var cameraId: String?
  @State private var microphoneId: String?
  @State private var speakerId: String?
  @State private var privacy: HuddlePrivacy?
  @State private var joined = false

  private var session: InstanceSession { request.session }
  private var item: SidebarRoom? { session.rooms.first { $0.id == request.roomId } }
  private var camerasAllowed: Bool { session.account?.huddleCameras == true }
  private var inIt: [UserID] { session.huddles[request.roomId]?.userIds ?? [] }
  private var going: Bool { !inIt.isEmpty }

  private var title: String {
    guard let room = item?.room else { return "Huddle" }
    return HuddleWords.previewTitle(place: HuddleRules.place(room, name: session.title(of: room)), going: going)
  }

  private var description: String? {
    guard let room = item?.room, let me = session.me else { return nil }
    let others = inIt.filter { $0 != me.id }
    return HuddleWords.previewDescription(
      room: room, roomName: session.title(of: room), others: others.compactMap { session.people[$0]?.name }, othersCount: others.count, going: going,
      moving: inIt.count > others.count, invited: center.invitees(room, in: session).map { session.people[$0.id]?.name ?? $0.name },
      inAnother: center.call != nil)
  }

  private var status: String? {
    switch microphone {
    case nil: HuddleWords.askingForMicrophone
    case false?: HuddleWords.noMicrophone
    case true?: nil
    }
  }

  var body: some View {
    Group {
      switch look {
      case .suite:
        SheetFrame(title: title, systemImage: "headphones") {
          content
        } footer: {
          EditorFooter(
            canSave: microphone != nil, canCancel: true, saveHelp: going ? "Join Huddle" : "Start Huddle",
            saveTitle: EditorActionTitle(going ? "Join Huddle" : "Start Huddle", widest: "Start Huddle"), onCancel: { dismiss() }, onSave: join)
        }
      case .irc:
        VStack(alignment: .leading, spacing: 10) {
          Text("/huddle \(title)").font(Theme.font(16, weight: .bold)).foregroundStyle(irc.ember)
          content
          HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button(going ? "Join Huddle" : "Start Huddle", action: join)
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
              .disabled(microphone == nil)
          }
        }
        .font(Theme.font(13))
        .padding(24)
        .background(irc.buffer)
        .preferredColorScheme(.dark)
      }
    }
    .frame(minWidth: 420)
    .task {
      let allowed = await HuddleEngine.microphoneAllowed()
      if allowed { HuddleDevices.useRemembered() } else { privacy = .microphone }
      microphoneId = HuddleEngine.microphoneId
      #if os(macOS)
      speakerId = HuddleEngine.speakerId
      #endif
      microphone = allowed
    }
    // Cameras turned off meanwhile take the preview's down (`cameraNote`).
    .onChange(of: camerasAllowed) { _, allowed in
      guard !allowed, camera != nil else { return }
      turnCameraOff()
      cameraNote = Huddles.camerasOff
    }
    .onDisappear {
      // A camera the preview opened goes off with it, unless the huddle took it.
      if !joined, camera != nil, center.call?.camera == nil { HuddleEngine.shared.closeCamera() }
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      if let description { Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
      ZStack(alignment: .bottom) {
        Group {
          if let camera {
            HuddleVideoView(picture: camera, fill: true)
          } else if let me = session.me {
            (look == .suite ? HuddleLook.suite(session) : HuddleLook.irc(irc)).face(me.user, 88)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        HStack(spacing: Spacing.md) {
          let silent = muted || microphone != true
          switchButton(silent ? "mic.slash.fill" : "mic.fill", on: !silent, help: silent ? "Unmute microphone" : "Mute microphone") { muted.toggle() }
            .disabled(microphone != true)
          if camerasAllowed {
            switchButton(camera == nil ? "video.slash.fill" : "video.fill", on: camera != nil, help: camera == nil ? "Turn on camera" : "Turn off camera") {
              if camera == nil { Task { await turnCameraOn(cameraId) } } else { turnCameraOff() }
            }
          }
        }
        .padding(Spacing.md)
      }
      .aspectRatio(16 / 9, contentMode: .fit)
      .background(look == .suite ? SemanticColor.secondaryBackground : irc.sidebar)
      .clipShape(RoundedRectangle(cornerRadius: look == .suite ? Radius.card : 2, style: .continuous))
      devices
      if let status { Text(status).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
      if let cameraNote { Text(cameraNote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
      if let privacy { HuddleSettingsButton(privacy: privacy) }
    }
  }

  @ViewBuilder
  private var devices: some View {
    if microphone == true, !HuddleEngine.microphones.isEmpty {
      Picker("Microphone", selection: Binding<String?>(get: { microphoneId }, set: { if let id = $0 { chooseMicrophone(id) } })) {
        ForEach(HuddleEngine.microphones) { Text($0.name).tag(Optional($0.id)) }
      }
    }
    #if os(iOS)
    if microphone == true {
      LabeledContent("Speaker") { HuddleRoutePicker().frame(width: 32, height: 32) }
    }
    #else
    if microphone != nil, !HuddleEngine.speakers.isEmpty {
      Picker("Speaker", selection: Binding<String?>(get: { speakerId }, set: { if let id = $0 { chooseSpeaker(id) } })) {
        ForEach(HuddleEngine.speakers) { Text($0.name).tag(Optional($0.id)) }
      }
    }
    #endif
    if camera != nil, HuddleEngine.cameras.count > 1 {
      Picker("Camera", selection: Binding<String?>(get: { cameraId }, set: { id in Task { await turnCameraOn(id) } })) {
        ForEach(HuddleEngine.cameras) { Text($0.name).tag(Optional($0.id)) }
      }
    }
  }

  private func chooseMicrophone(_ id: String) {
    do {
      try HuddleEngine.useMicrophone(id)
      UserDefaults.standard.set(id, forKey: HuddleDevices.microphone)
      microphoneId = HuddleEngine.microphoneId
    } catch {
      huddleLog.error("Choosing a microphone failed: \(error.localizedDescription, privacy: .public)")
      cameraNote = HuddleWords.noOtherMicrophone
    }
  }

  #if os(macOS)
  private func chooseSpeaker(_ id: String) {
    do {
      try HuddleEngine.useSpeaker(id)
      UserDefaults.standard.set(id, forKey: HuddleDevices.speaker)
      speakerId = HuddleEngine.speakerId
    } catch {
      huddleLog.error("Choosing a speaker failed: \(error.localizedDescription, privacy: .public)")
      cameraNote = HuddleWords.noOtherSpeaker
    }
  }
  #endif

  private func switchButton(_ symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .frame(width: 40, height: 40)
        .foregroundStyle(on ? SemanticColor.background : SemanticColor.label)
        .background(on ? SemanticColor.label : SemanticColor.secondaryFill, in: Circle())
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(help)
  }

  private func turnCameraOn(_ id: String?) async {
    cameraNote = nil
    guard await HuddleEngine.cameraAllowed() else {
      privacy = .camera
      return cameraNote = HuddleWords.noCamera
    }
    do {
      try await HuddleEngine.shared.openCamera(id ?? UserDefaults.standard.string(forKey: HuddleDevices.camera))
      camera = HuddleEngine.shared.camera
      cameraId = HuddleEngine.shared.cameraDevice?.uniqueID
      if let cameraId { UserDefaults.standard.set(cameraId, forKey: HuddleDevices.camera) }
    } catch {
      huddleLog.error("Opening the camera failed: \(error.localizedDescription, privacy: .public)")
      camera = nil
      cameraNote = HuddleWords.noCamera
    }
  }

  private func turnCameraOff() {
    HuddleEngine.shared.closeCamera()
    camera = nil
  }

  private func join() {
    joined = true
    let withCamera = camera != nil && camerasAllowed
    // A camera the huddle won't show, cameras having been turned off, goes off now, its light with it.
    if camera != nil, !withCamera { turnCameraOff() }
    center.join(request.roomId, in: session, muted: muted, microphone: microphone == true, camera: withCamera)
    dismiss()
  }
}

#if os(iOS)
/** Where the huddle plays, AirPods or the speaker: the system's own route picker. */
struct HuddleRoutePicker: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
  func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#endif

// MARK: - Invite people

/**
 * Invite people (web huddle-invite-dialog.tsx): the room's people who aren't in the huddle, by name, 20
 * at a time with a search past that, one picked already where there's only one; Send Invite rings them.
 */
struct HuddleInviteSheet: View {
  let call: HuddleCall
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @Environment(\.dismiss) private var dismiss
  @State private var candidates: [User]?
  @State private var failed = false
  @State private var picked: Set<UserID> = []
  @State private var query = ""
  @State private var shown = HuddleWords.invitePage
  @State private var note: String?

  private var session: InstanceSession { call.session }

  private var roomName: String {
    guard let room = call.room else { return "this room" }
    return session.title(of: room)
  }

  private var matches: [User] {
    let all = candidates ?? []
    let sought = query.trimmingCharacters(in: .whitespaces).lowercased()
    return sought.isEmpty ? all : all.filter { $0.name.lowercased().contains(sought) }
  }

  private var status: String {
    if let note { return note }
    if failed { return HuddleWords.couldNotLoadPeople }
    guard let candidates, let room = call.room else { return HuddleWords.loadingPeople }
    if candidates.isEmpty { return HuddleWords.nobodyToInvite(room, name: roomName) }
    if matches.isEmpty { return HuddleWords.noPeopleFound }
    return HuddleWords.selected(picked.count)
  }

  var body: some View {
    Group {
      switch look {
      case .suite:
        SheetFrame(title: "Invite people", systemImage: "person.badge.plus") {
          content
        } footer: {
          EditorFooter(
            canSave: !picked.isEmpty, canCancel: true, saveHelp: "Send Invite", saveTitle: EditorActionTitle("Send Invite"), onCancel: { dismiss() },
            onSave: send)
        }
      case .irc:
        VStack(alignment: .leading, spacing: 10) {
          Text("/huddle invite").font(Theme.font(16, weight: .bold)).foregroundStyle(irc.ember)
          content
          HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Send Invite", action: send).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(picked.isEmpty)
          }
        }
        .font(Theme.font(13))
        .padding(24)
        .background(irc.buffer)
        .preferredColorScheme(.dark)
      }
    }
    .frame(minWidth: 400, minHeight: 420)
    .task { await load() }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      if let room = call.room { Text(HuddleWords.inviteExplained(room, name: roomName)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
      if let candidates, candidates.count > HuddleWords.invitePage {
        TextField("Search by name", text: $query).textFieldStyle(.roundedBorder).onChange(of: query) { shown = HuddleWords.invitePage }
      }
      List {
        ForEach(matches.prefix(shown)) { person in
          Toggle(isOn: Binding(get: { picked.contains(person.id) }, set: { on in toggle(person.id, on) })) {
            HStack(spacing: Spacing.sm) {
              (look == .suite ? HuddleLook.suite(session) : HuddleLook.irc(irc)).face(session.people[person.id]?.user ?? person, 24)
                .clipShape(RoundedRectangle(cornerRadius: look == .suite ? Radius.section : 2, style: .continuous))
              Text(session.people[person.id]?.name ?? person.name)
            }
          }
          #if os(macOS)
          .toggleStyle(.checkbox)
          #endif
        }
        if matches.count > shown {
          Button("Show more people") { shown += HuddleWords.invitePage }
        }
      }
      .listStyle(.plain)
      .frame(minHeight: 200)
      HStack {
        Text(status).foregroundStyle(.secondary)
        if failed { Button("Try again") { Task { await load() } } }
      }
    }
  }

  private func toggle(_ id: UserID, _ on: Bool) {
    note = nil
    if on, picked.count < Huddles.maxInvited { picked.insert(id) } else if !on { picked.remove(id) }
  }

  private func load() async {
    failed = false
    guard let room = call.room, let me = session.me else { return }
    let inIt = Set(call.people.map(\.user.id))
    do {
      let members: [User] =
        room.isDirect ? (room.members ?? []) : try await session.api.roomSettings(room.id).people.filter(\.member).map { User(id: $0.id, name: $0.name) }
      let invitable = HuddleRules.invitable(members, me: me.id, inIt: inIt, joinsNone: session.joinsNoHuddle)
      candidates = invitable.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      if invitable.count == 1, let only = invitable.first { picked = [only.id] }
    } catch {
      huddleLog.error("Loading the people to invite failed: \(error.localizedDescription, privacy: .public)")
      failed = true
    }
  }

  private func send() {
    let ids = Array(picked)
    guard call.invite(ids) else { return note = HuddleWords.inviteWhileReconnecting }
    let names = ids.compactMap { id in candidates?.first { $0.id == id }.map { session.people[id]?.name ?? $0.name } }
    session.notice = HuddleWords.invitedNow(names)
    dismiss()
  }
}

// MARK: - The thread beside the huddle

/**
 * The huddle's thread (web huddle-thread.tsx): its message's thread, over a socket of its own that's
 * apart from the room, which neither counts the app as there nor reads anything through it.
 */
enum HuddleThread {
  /** The room as the thread shows it, once the room has said which message is the huddle's. */
  @MainActor
  static func room(for call: HuddleCall) -> RoomModel? {
    guard call.messageId != nil else { return nil }
    return call.session.apartBuffer(call.roomId)
  }

  /** Connects the thread's socket and opens it on the huddle's message. */
  @MainActor
  static func open(for call: HuddleCall) {
    guard let messageId = call.messageId, let room = call.session.apartBuffer(call.roomId) else { return }
    room.activate()
    if room.thread?.parentId != messageId { room.openThread(messageId) }
  }

  /** The intro over the thread's replies: what a huddle's thread is, or that its message is gone. */
  @MainActor
  static func intro(for call: HuddleCall, room: RoomModel) -> (title: String?, text: String) {
    let place = call.room.map { HuddleRules.place($0, name: call.session.title(of: $0)) } ?? "its room"
    if room.thread?.parent?.deleted == true { return (nil, HuddleWords.threadGone(place: place)) }
    return (HuddleWords.threadTitle, HuddleWords.threadExplained(place: place))
  }
}

// MARK: - Settings, where the system wouldn't let ircX

/** Opens the place in Settings that lets ircX use the microphone, the camera or the screen, in either theme. */
struct HuddleSettingsButton: View {
  let privacy: HuddlePrivacy
  var done: (() -> Void)?
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button {
      guard let url = privacy.settings else { return huddleLog.error("There's no Settings address for huddles' privacy") }
      openURL(url)
      done?()
    } label: {
      switch look {
      case .suite: Label("Open Settings", systemImage: "gearshape")
      case .irc:
        HStack(spacing: 0) {
          Text("[").foregroundStyle(irc.statusBracket)
          Text("settings").foregroundStyle(irc.ember)
          Text("]").foregroundStyle(irc.statusBracket)
        }
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(look == .suite ? SemanticColor.accent : irc.ember)
    .help(privacy.help)
    .accessibilityLabel("Open Settings")
    .accessibilityHint(privacy.help)
  }
}
