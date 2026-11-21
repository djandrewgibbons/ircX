import AppCoreUI
import EmberKit
import HuddleMedia
import SwiftUI

/**
 * The huddle button, first of a room's actions (web huddle-button.tsx): headphones that start the room's
 * huddle, join the one going on, or leave it once the app is in it, green while in it and outlined in
 * green, with how many are in it, while others are; its menu copies the huddle's link.
 */
struct SuiteHuddleButton: View {
  let app: AppModel
  let session: InstanceSession
  let room: Room

  var body: some View {
    let center = app.huddles
    let here = center.call.map { $0.session === session && $0.roomId == room.id } == true
    let live = session.huddles[room.id]?.userIds ?? []
    let others = here ? 0 : live.count
    let label = here ? "Leave huddle" : others > 0 ? "Join huddle" : "Start huddle"
    Menu {
      Button("Copy Huddle Link", systemImage: "link") { Pasteboard.copy(center.link(room.id, in: session)) }
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "headphones")
        if others > 0 { Text("\(others)").font(DesignFont.detail.weight(.semibold)).monospacedDigit() }
      }
      .foregroundStyle(here ? SemanticColor.background : others > 0 ? SemanticColor.positive : SemanticColor.label)
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xxs)
      .background(here ? SemanticColor.positive : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(others > 0 ? SemanticColor.positive : Color.clear)
      }
    } primaryAction: {
      if here { center.leave() } else { center.preview(room.id, in: session) }
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("\(label) (⌘⌥⇧H)")
    .accessibilityLabel(others > 0 ? "\(label), \(others) in it" : label)
  }
}

/** The tools both the bar and the opened huddle have (web huddle-tools.tsx). */
@MainActor
struct SuiteHuddleTools {
  let call: HuddleCall

  private var session: InstanceSession { call.session }

  /** Mutes or unmutes; says so when there's no microphone. */
  @ViewBuilder
  var microphone: some View {
    let silent = call.muted || !call.microphone
    let label = !call.microphone ? "No microphone" : call.muted ? "Unmute microphone" : "Mute microphone"
    tool(silent ? "mic.slash.fill" : "mic.fill", on: !silent, help: "\(label) (⌘⇧Space)") { call.setMuted(!call.muted) }
      .disabled(!call.microphone)
  }

  /** Turns the camera on or off; while administrators have cameras off it's there only to turn one off. */
  @ViewBuilder
  var camera: some View {
    let on = call.camera != nil
    if session.account?.huddleCameras == true || on {
      tool(on ? "video.fill" : "video.slash.fill", on: on, help: on ? "Turn off camera" : "Turn on camera") { call.setCamera(!on) }
        .disabled(call.openingCamera)
    }
  }

  /** Chooses the camera, where there's more than one, in the opened huddle. */
  @ViewBuilder
  var cameraMenu: some View {
    let cameras = HuddleEngine.cameras
    if session.account?.huddleCameras == true, cameras.count > 1 {
      Menu {
        Picker("Camera", selection: Binding<String?>(get: { call.cameraId }, set: { if let id = $0 { call.chooseCamera(id) } })) {
          ForEach(cameras) { Text($0.name).tag(Optional($0.id)) }
        }
        #if os(iOS)
        if call.camera != nil { Button("Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera") { call.switchCamera() } }
        #endif
      } label: {
        Image(systemName: "chevron.up")
      }
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Choose a camera")
    }
  }

  /** Chooses the microphone and the speaker (web's microphone arrow menu); an iPhone's speaker is the system's route picker. */
  @ViewBuilder
  var microphoneMenu: some View {
    let microphones = HuddleEngine.microphones
    #if os(macOS)
    let speakers = HuddleEngine.speakers
    if !microphones.isEmpty || !speakers.isEmpty {
      Menu {
        if !microphones.isEmpty {
          Picker("Microphone", selection: Binding<String?>(get: { HuddleEngine.microphoneId }, set: { if let id = $0 { call.chooseMicrophone(id) } })) {
            ForEach(microphones) { Text($0.name).tag(Optional($0.id)) }
          }
        }
        if !speakers.isEmpty {
          Picker("Speaker", selection: Binding<String?>(get: { HuddleEngine.speakerId }, set: { if let id = $0 { call.chooseSpeaker(id) } })) {
            ForEach(speakers) { Text($0.name).tag(Optional($0.id)) }
          }
        }
      } label: {
        Image(systemName: "chevron.up")
      }
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Microphone and speaker")
    }
    #else
    if microphones.count > 1 {
      Menu {
        Picker("Microphone", selection: Binding<String?>(get: { HuddleEngine.microphoneId }, set: { if let id = $0 { call.chooseMicrophone(id) } })) {
          ForEach(microphones) { Text($0.name).tag(Optional($0.id)) }
        }
      } label: {
        Image(systemName: "chevron.up")
      }
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Choose a microphone")
    }
    HuddleRoutePicker().frame(width: 32, height: 32).help("Choose a speaker")
    #endif
  }

  /** Opens Settings where the system wouldn't let ircX use a device, while that's so. */
  @ViewBuilder
  var settings: some View {
    if let privacy = call.privacy {
      HuddleSettingsButton(privacy: privacy) { call.privacy = nil }
    }
  }

  /** Shares the screen, from a Mac, or stops sharing; while screens are off it's there only to stop. */
  @ViewBuilder
  var screen: some View {
    let shared = call.screen != nil
    if shared || (HuddleEngine.sharesScreens && session.account?.huddleScreens == true) {
      tool("rectangle.on.rectangle", on: shared, help: shared ? "Stop sharing screen" : "Share screen") { call.setScreen(!shared) }
        .disabled(call.choosingScreen)
    }
  }

  /** Raises the hand, or takes off the sticker shown; its menu has the other stickers. */
  @ViewBuilder
  var raiseHand: some View {
    let shown = call.sticker
    Menu {
      ForEach(HuddleSticker.allCases, id: \.self) { sticker in
        Toggle(isOn: Binding(get: { call.sticker == sticker }, set: { call.setSticker($0 ? sticker : nil) })) {
          Text("\(sticker.emoji) \(sticker.name)")
        }
      }
    } label: {
      Text((shown ?? .hand).emoji)
        .frame(width: 32, height: 32)
        .background(shown != nil ? SemanticColor.label.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    } primaryAction: {
      call.setSticker(shown == nil ? .hand : nil)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("\(HuddleSticker.raiseHandLabel(shown)). One sticker stays on until you take it off.")
  }

  func tool(_ symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .frame(width: 32, height: 32)
        .background(on ? SemanticColor.label.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(help)
  }

  /** Leave, in red and in words. */
  var leave: some View {
    Button(role: .destructive) {
      call.leave()
    } label: {
      Text("Leave")
        .font(DesignFont.bodyEmphasized)
        .foregroundStyle(Color.white)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(SemanticColor.destructive, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
    .buttonStyle(.plain)
    .help("Leave the huddle")
  }
}

/**
 * The huddle's bar (web huddle-bar.tsx), at the window's base while the app is in a huddle and it isn't
 * opened: the headphones and its name over who's in it, the first four faces, ringed while speaking,
 * the tools, open, and Leave.
 */
struct SuiteHuddleBar: View {
  let call: HuddleCall

  var body: some View {
    let tools = SuiteHuddleTools(call: call)
    HStack(spacing: Spacing.md) {
      Button {
        call.setOpen(true)
      } label: {
        HStack(spacing: Spacing.sm) {
          Image(systemName: "headphones")
            .foregroundStyle(SemanticColor.background)
            .frame(width: 32, height: 32)
            .background(SemanticColor.positive, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
          VStack(alignment: .leading, spacing: 0) {
            Text(call.name).font(DesignFont.bodyEmphasized).lineLimit(1)
            Text(call.status).font(DesignFont.detail).foregroundStyle(.secondary).lineLimit(1)
          }
        }
      }
      .buttonStyle(.plain)
      .help("Open the huddle")
      #if os(macOS)
      HStack(spacing: -Spacing.sm) {
        ForEach(call.people.prefix(4), id: \.user.id) { person in
          SuiteAvatar(session: call.session, user: person.user, size: 24)
            .overlay {
              RoundedRectangle(cornerRadius: Radius.section, style: .continuous)
                .strokeBorder(call.speaking.contains(person.user.id) ? SemanticColor.positive : Color.clear, lineWidth: 2)
            }
            .accessibilityLabel(call.speaking.contains(person.user.id) ? "\(person.user.name), speaking" : person.user.name)
        }
      }
      #endif
      Spacer(minLength: 0)
      tools.microphone
      #if os(macOS)
      tools.camera
      tools.screen
      #endif
      tools.raiseHand
      tools.settings
      tools.tool("arrow.up.left.and.arrow.down.right", on: false, help: "Open the huddle") { call.setOpen(true) }
      tools.leave
    }
    .padding(.horizontal, PaneGrid.leadingEdge)
    .padding(.vertical, Spacing.sm)
    .frame(maxWidth: .infinity)
    #if os(macOS)
    .panelCard()
    #else
    .background(.bar)
    #endif
  }
}

/**
 * The huddle opened (web huddle-view.tsx), over the room: its name and how many are in it, a tile each,
 * the tools along its foot, and its thread beside it where the window has room.
 */
struct SuiteHuddleView: View {
  let app: AppModel
  let call: HuddleCall
  @State private var reacting = false
  @State private var width: CGFloat = 0

  /** The thread shows beside the huddle where the window has room for it (the web's 1180 wide, less the sidebar). */
  private var threadFits: Bool { width >= 900 }

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        PaneHeaderBar {
          HStack(spacing: Spacing.sm) {
            PaneIconButton(systemImage: "arrow.down.right.and.arrow.up.left", help: "Minimize the huddle") { call.setOpen(false) }
            Image(systemName: "headphones").foregroundStyle(SemanticColor.positive)
            Text(call.name).font(DesignFont.cardTitle).lineLimit(1)
            Text(HuddleWords.waitingToJoin(connected: call.connected, letIn: call.you != nil) ?? HuddleWords.people(call.people.count))
              .font(DesignFont.detail).foregroundStyle(.secondary)
          }
        } trailing: {
          EmptyView()
        }
        HuddleStageView(call: call, look: .suite(call.session))
          .padding(PaneGrid.cardInset)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        footer
      }
      if threadFits, call.showsThread, let room = HuddleThread.room(for: call) {
        SuiteHuddleThread(app: app, call: call, room: room)
          .frame(width: 340)
      }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .task(id: call.messageId) { HuddleThread.open(for: call) }
  }

  private var footer: some View {
    let tools = SuiteHuddleTools(call: call)
    return HStack(spacing: Spacing.md) {
      #if os(macOS)
      tools.tool("person.badge.plus", on: false, help: "Invite people") { app.huddles.inviting = true }
        .disabled(call.room == nil)
      #endif
      Spacer(minLength: 0)
      HStack(spacing: Spacing.xxs) {
        tools.microphone
        tools.microphoneMenu
      }
      HStack(spacing: Spacing.xxs) {
        tools.camera
        tools.cameraMenu
      }
      tools.screen
      tools.raiseHand
      tools.tool("face.smiling", on: reacting, help: "React") { reacting = true }
        .popover(isPresented: $reacting) {
          SuiteEmojiPanel { emoji in
            call.react(emoji)
            reacting = false
          }
        }
      if call.messageId != nil, threadFits {
        tools.tool("text.bubble", on: call.showsThread, help: "Thread") { call.showsThread.toggle() }
      }
      tools.settings
      #if os(iOS)
      Menu {
        Button("Invite People", systemImage: "person.badge.plus") { app.huddles.inviting = true }.disabled(call.room == nil)
      } label: {
        Image(systemName: "ellipsis").frame(width: 32, height: 32)
      }
      .help("More")
      #endif
      Spacer(minLength: 0)
      tools.leave
    }
    .padding(.horizontal, PaneGrid.cardInset)
    .padding(.vertical, Spacing.md)
  }
}

/** The huddle's thread beside it (web huddle-thread.tsx): what it is, then the thread's replies and composer. */
struct SuiteHuddleThread: View {
  let app: AppModel
  let call: HuddleCall
  @Bindable var room: RoomModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PaneHeaderBar(title: "Thread", systemImage: "bubble.left.and.bubble.right") {
        PaneIconButton(systemImage: "xmark", help: "Close thread") { call.showsThread = false }
      }
      let intro = HuddleThread.intro(for: call, room: room)
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if let title = intro.title { Text(title).font(DesignFont.bodyEmphasized) }
        Text(intro.text).font(DesignFont.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, PaneGrid.leadingEdge)
      .padding(.bottom, Spacing.sm)
      if let thread = room.thread {
        SuiteMessageList(
          session: call.session, room: room, lines: thread.lines, hasMore: thread.hasMore, onOlder: room.loadOlderReplies, openThread: { _ in },
          inThread: true)
        SuiteThreadNotice(room: room)
        if thread.parent != nil, !room.ended {
          SuiteComposer(app: app, session: call.session, room: room, placeholder: "Reply\u{2026}", parentId: thread.parentId)
        }
      }
    }
    .roomRequests(room, composer: room.composer(thread: room.thread?.parentId))
  }
}

/**
 * The invitations that ring (web huddle-invitations.tsx), in the window's corner under its header, over
 * whatever shows: the inviter's face with the headphones, who and where, then Decline and Join. Each
 * rings for half a minute; the focus stays where it is.
 */
struct SuiteHuddleInvitations: View {
  let center: HuddleCenter
  let ringing: [(session: InstanceSession, invitation: HuddleInvitation)]

  var body: some View {
    VStack(alignment: .trailing, spacing: Spacing.sm) {
      ForEach(ringing, id: \.invitation.id) { item in
        card(item.session, item.invitation)
      }
    }
    .padding(Spacing.lg)
  }

  private func card(_ session: InstanceSession, _ invitation: HuddleInvitation) -> some View {
    let room = session.rooms.first { $0.id == invitation.roomId }?.room
    let inviter = session.people[invitation.by]?.user ?? room?.members?.first { $0.id == invitation.by } ?? User(id: invitation.by, name: "Someone")
    let what = HuddleWords.invites(room)
    return VStack(alignment: .leading, spacing: Spacing.md) {
      HStack(spacing: Spacing.md) {
        SuiteAvatar(session: session, user: inviter, size: 44)
          .overlay(alignment: .bottomTrailing) {
            Image(systemName: "headphones")
              .font(DesignFont.detail)
              .foregroundStyle(SemanticColor.background)
              .padding(Spacing.xxs)
              .background(SemanticColor.positive, in: Circle())
              .offset(x: Spacing.xs, y: Spacing.xs)
          }
        VStack(alignment: .leading, spacing: 0) {
          Text(inviter.name).font(DesignFont.bodyEmphasized).lineLimit(1)
          Text(what).font(DesignFont.detail).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      HStack(spacing: Spacing.sm) {
        Button("Decline") { center.answer(invitation, in: session, join: false) }
          .buttonStyle(.bordered)
          .frame(maxWidth: .infinity)
        Button {
          center.answer(invitation, in: session, join: true)
        } label: {
          SuiteJoinLabel().frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
      }
    }
    .padding(PaneGrid.cardInset)
    .frame(width: 320)
    .background(SemanticColor.background, in: RoundedRectangle(cornerRadius: Radius.column, style: .continuous))
    .shadow(radius: 12)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(inviter.name) \(what)")
  }
}

/** Join, in green, on a live huddle's message, unless the app is in that huddle or huddles are off. */
struct SuiteHuddleJoin: View {
  let session: InstanceSession
  let message: Message

  var body: some View {
    if let center = session.huddleCenter, message.huddle?.endedAt == nil, session.account?.huddles == true,
      center.call.map({ $0.session === session && $0.roomId == message.roomId }) != true
    {
      Button {
        center.preview(message.roomId, in: session)
      } label: {
        SuiteJoinLabel()
      }
      .buttonStyle(.plain)
      .help("Join the huddle")
    }
  }
}

/** Join, in green with the headphones, as a huddle that can be joined is. */
struct SuiteJoinLabel: View {
  var body: some View {
    Label("Join", systemImage: "headphones")
      .font(DesignFont.bodyEmphasized)
      .foregroundStyle(Color.white)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)
      .background(SemanticColor.positive, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
  }
}
