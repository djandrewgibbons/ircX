import EmberKit
import HuddleMedia
import SwiftUI

/** A bracketed button, as IRC Classic's bars have them: `[mic]`. */
private struct Bracket: View {
  let text: String
  var color: Color?
  let help: String
  let action: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 0) {
        Text("[").foregroundStyle(theme.statusBracket)
        Text(text).foregroundStyle(color ?? theme.text)
        Text("]").foregroundStyle(theme.statusBracket)
      }
      .lineLimit(1)
      .fixedSize()
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(help)
  }
}

/** The topic bar's huddle button: `[huddle]`, `[huddle 3]` while others are in it, green while the app is. */
struct IRCHuddleTopicButton: View {
  let session: InstanceSession
  let room: Room
  @Environment(\.theme) private var theme

  var body: some View {
    if let center = session.huddleCenter, session.hasHuddles(room) {
      let here = center.call.map { $0.session === session && $0.roomId == room.id } == true
      let live = session.huddles[room.id]?.userIds ?? []
      let label = here ? "Leave huddle" : live.isEmpty ? "Start huddle" : "Join huddle"
      Bracket(text: live.isEmpty || here ? "huddle" : "huddle \(live.count)", color: here || !live.isEmpty ? theme.join : theme.dim, help: "\(label) (/huddle, ⌘⌥⇧H)") {
        if here { center.leave() } else { center.preview(room.id, in: session) }
      }
      .contextMenu {
        Button("Copy Huddle Link") { Pasteboard.copy(center.link(room.id, in: session)) }
      }
    }
  }
}

/**
 * The huddle's bar in IRC Classic (web huddle-bar.tsx), as a status line at the window's foot while the
 * app is in a huddle that isn't opened: where, who, and the tools in brackets.
 */
struct IRCHuddleBar: View {
  let call: HuddleCall
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: 6) {
      Bracket(text: "Huddle: \(call.name.replacingOccurrences(of: "Huddle ", with: "")) \(call.people.count)", color: theme.join, help: "Open the huddle (/huddle open)") {
        call.setOpen(true)
      }
      Text(call.status).foregroundStyle(theme.dim).lineLimit(1)
      Spacer(minLength: 0)
      IRCHuddleTools(call: call)
    }
    .font(Theme.font(11))
    .padding(.horizontal, 10)
    .frame(height: 22)
    .background(theme.statusBar)
  }
}

/** The huddle's tools in brackets, on its bar and along the opened huddle's foot. */
struct IRCHuddleTools: View {
  let call: HuddleCall
  @Environment(\.theme) private var theme
  @State private var choosingDevices = false
  @State private var choosingSticker = false

  var body: some View {
    if call.microphone {
      Bracket(text: call.muted ? "mic:off" : "mic:on", color: call.muted ? theme.part : theme.join, help: call.muted ? "Unmute (/unmute, ⌘⇧Space)" : "Mute (/mute, ⌘⇧Space)") {
        call.setMuted(!call.muted)
      }
    } else {
      Text("[no mic]").foregroundStyle(theme.dim).help("No microphone")
    }
    if call.session.account?.huddleCameras == true || call.camera != nil {
      Bracket(text: call.camera == nil ? "cam:off" : "cam:on", help: call.camera == nil ? "Turn on camera (/huddle cam on)" : "Turn off camera (/huddle cam off)") {
        call.setCamera(call.camera == nil)
      }
    }
    if call.screen != nil || (HuddleEngine.sharesScreens && call.session.account?.huddleScreens == true) {
      Bracket(text: call.screen == nil ? "scr:off" : "scr:on", help: call.screen == nil ? "Share screen (/huddle screen on)" : "Stop sharing screen (/huddle screen off)") {
        call.setScreen(call.screen == nil)
      }
    }
    Bracket(text: "dev", help: "Microphone, speaker and camera") { choosingDevices = true }
      .popover(isPresented: $choosingDevices) { IRCHuddleDevices(call: call).environment(\.theme, theme) }
    Bracket(text: (call.sticker ?? .hand).emoji, color: call.sticker == nil ? theme.dim : theme.ember, help: "\(HuddleSticker.raiseHandLabel(call.sticker)) (/hand)") {
      call.setSticker(call.sticker == nil ? .hand : nil)
    }
    Bracket(text: "▾", color: theme.dim, help: "Stickers. One stays on until you take it off. (/huddle sticker)") { choosingSticker = true }
      .popover(isPresented: $choosingSticker) {
        IRCStickerList(call: call) { choosingSticker = false }.padding(10).background(theme.buffer).environment(\.theme, theme)
      }
    if let privacy = call.privacy {
      HuddleSettingsButton(privacy: privacy) { call.privacy = nil }
    }
    Bracket(text: "leave", color: theme.part, help: "Leave the huddle (/huddle leave)") { call.leave() }
  }
}

/**
 * The huddle opened in IRC Classic: a topic line, a tile each in the theme's palette, the tools in
 * brackets, and the huddle's thread beside it where there's room.
 */
struct IRCHuddleView: View {
  let app: AppModel
  let call: HuddleCall
  @Environment(\.theme) private var theme
  @State private var reacting = false
  @State private var width: CGFloat = 0

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Text(call.name).font(Theme.font(14, weight: .bold)).foregroundStyle(theme.join)
          Text(HuddleWords.waitingToJoin(connected: call.connected, letIn: call.you != nil) ?? HuddleWords.people(call.people.count))
            .font(Theme.font(12)).foregroundStyle(theme.dim)
          Spacer()
          Bracket(text: "close", help: "Minimize the huddle (/huddle close)") { call.setOpen(false) }.font(Theme.font(12))
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.faint).frame(height: 1) }
        HuddleStageView(call: call, look: .irc(theme))
          .padding(12)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        ViewThatFits(in: .horizontal) {
          footer
          ScrollView(.horizontal, showsIndicators: false) { footer }
        }
        .font(Theme.font(12))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(theme.statusBar)
      }
      if width >= 900, call.showsThread, let room = HuddleThread.room(for: call) {
        Divider().overlay(theme.faint)
        IRCHuddleThread(app: app, call: call, room: room).frame(width: 340)
      }
    }
    .background(theme.buffer)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .task(id: call.messageId) { HuddleThread.open(for: call) }
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Bracket(text: "invite", help: "Invite people (/huddle invite)") { app.huddles.inviting = true }
      Spacer(minLength: 0)
      IRCHuddleTools(call: call)
      Bracket(text: "react", help: "React (/huddle react emoji)") { reacting = true }
        .popover(isPresented: $reacting) {
          IRCReactPanel(call: call) { reacting = false }.environment(\.theme, theme)
        }
      if call.messageId != nil, width >= 900 {
        Bracket(text: "thread", color: call.showsThread ? theme.ember : nil, help: "Thread (/huddle thread)") { call.showsThread.toggle() }
      }
    }
  }
}

/** The huddle's thread beside it in IRC Classic. */
private struct IRCHuddleThread: View {
  let app: AppModel
  let call: HuddleCall
  @Bindable var room: RoomModel
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Thread").font(Theme.font(13, weight: .bold))
        Spacer()
        Bracket(text: "x", help: "Close thread") { call.showsThread = false }
      }
      .padding(.horizontal, 12)
      .frame(height: 40)
      let intro = HuddleThread.intro(for: call, room: room)
      Text("-!- " + [intro.title, intro.text].compactMap { $0 }.joined(separator: ". "))
        .font(Theme.font(11)).foregroundStyle(theme.dim).padding(.horizontal, 12).fixedSize(horizontal: false, vertical: true)
      if let thread = room.thread {
        MessageList(
          session: call.session, room: room, lines: thread.lines, hasMore: thread.hasMore, onOlder: room.loadOlderReplies, openThread: { _ in }, inThread: true)
        ThreadStatusBar(room: room)
        if thread.parent != nil, !room.ended { InputLine(app: app, session: call.session, room: room, parentId: thread.parentId) }
      }
    }
    .background(theme.buffer)
    .roomRequests(room, composer: room.composer(thread: room.thread?.parentId), printsShortcuts: true)
  }
}

/** Who's in the huddle, in the nick list's place: `*` speaking, `[m]` muted, `[c]` camera, `[s]` screen, and stickers. */
struct IRCHuddleRoster: View {
  let call: HuddleCall
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("huddle (\(call.people.count))").font(Theme.font(11, weight: .bold)).foregroundStyle(theme.join)
      ForEach(call.people, id: \.user.id) { person in
        HStack(spacing: 4) {
          Text(call.speaking.contains(person.user.id) ? "*" : " ").foregroundStyle(theme.join)
          Text(call.session.people[person.user.id]?.name ?? person.user.name).foregroundStyle(theme.nick(person.user.id)).lineLimit(1)
          if person.muted { Text("[m]").foregroundStyle(theme.dim) }
          if person.video { Text("[c]").foregroundStyle(theme.dim) }
          if person.screen { Text("[s]").foregroundStyle(theme.dim) }
          if let sticker = person.sticker { Text(sticker.emoji).help(sticker.shown) }
        }
        .font(Theme.font(12))
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottom) { Rectangle().fill(theme.faint).frame(height: 1) }
  }
}

/** The invitations that ring, as IRC Classic prints them: `*** sam invites you to a huddle in #general [decline] [join]`. */
struct IRCHuddleInvitations: View {
  let center: HuddleCenter
  let ringing: [(session: InstanceSession, invitation: HuddleInvitation)]
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      ForEach(ringing, id: \.invitation.id) { item in
        let room = item.session.rooms.first { $0.id == item.invitation.roomId }?.room
        let inviter = item.session.people[item.invitation.by]?.name ?? room?.members?.first { $0.id == item.invitation.by }?.name ?? "Someone"
        HStack(spacing: 6) {
          Text("*** \(inviter) \(HuddleWords.invites(room))").foregroundStyle(theme.join)
          Bracket(text: "decline", color: theme.part, help: "Decline (/huddle decline)") { center.answer(item.invitation, in: item.session, join: false) }
          Bracket(text: "join", color: theme.join, help: "Join (/huddle join)") { center.answer(item.invitation, in: item.session, join: true) }
        }
        .font(Theme.font(12))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.bar)
        .overlay(Rectangle().strokeBorder(theme.join.opacity(0.6)))
      }
    }
    .padding(12)
  }
}

/** A choice as IRC Classic lists one: `[x] name`, the chosen one in Ember's orange. */
private struct CheckRow: View {
  let text: String
  let on: Bool
  let action: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 0) {
        Text("[").foregroundStyle(theme.statusBracket)
        Text(on ? "x" : " ").foregroundStyle(theme.ember)
        Text("] ").foregroundStyle(theme.statusBracket)
        Text(text).foregroundStyle(on ? theme.ember : theme.text).lineLimit(1)
      }
    }
    .buttonStyle(.plain)
    .help(text)
    .accessibilityLabel(text)
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}

/** The stickers as IRC Classic lists them: `[x] ✋ Raise hand`, one on at a time, and `[off]`. */
private struct IRCStickerList: View {
  let call: HuddleCall
  let done: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("-!- stickers: one stays on until you take it off").foregroundStyle(theme.dim)
      ForEach(HuddleSticker.allCases, id: \.self) { sticker in
        let on = call.sticker == sticker
        CheckRow(text: "\(sticker.emoji) \(sticker.name)", on: on) {
          call.setSticker(on ? nil : sticker)
          done()
        }
      }
      if call.sticker != nil {
        Bracket(text: "off", color: theme.part, help: "Remove sticker") {
          call.setSticker(nil)
          done()
        }
      }
    }
    .font(Theme.font(12))
  }
}

/** Choosing the microphone, the speaker and the camera, in IRC Classic's palette (Suite's tool menus). */
private struct IRCHuddleDevices: View {
  let call: HuddleCall
  @Environment(\.theme) private var theme
  /** Bumped as a choice is made, so the marks follow it. */
  @State private var chosen = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      let microphones = HuddleEngine.microphones
      if !microphones.isEmpty {
        Text("-!- microphone").foregroundStyle(theme.join)
        ForEach(microphones) { device in
          row(device, on: device.id == HuddleEngine.microphoneId) { call.chooseMicrophone(device.id) }
        }
      }
      #if os(macOS)
      let speakers = HuddleEngine.speakers
      if !speakers.isEmpty {
        Text("-!- speaker").foregroundStyle(theme.join)
        ForEach(speakers) { device in
          row(device, on: device.id == HuddleEngine.speakerId) { call.chooseSpeaker(device.id) }
        }
      }
      #else
      HStack(spacing: 6) {
        Text("-!- speaker").foregroundStyle(theme.join)
        HuddleRoutePicker().frame(width: 28, height: 28).help("Choose a speaker")
      }
      #endif
      let cameras = HuddleEngine.cameras
      if call.session.account?.huddleCameras == true, !cameras.isEmpty {
        Text("-!- camera").foregroundStyle(theme.join)
        ForEach(cameras) { device in
          row(device, on: device.id == call.cameraId) { call.chooseCamera(device.id) }
        }
        #if os(iOS)
        if call.camera != nil, cameras.count > 1 {
          Bracket(text: "switch camera", help: "Switch camera") { call.switchCamera() }
        }
        #endif
      }
    }
    .id(chosen)
    .font(Theme.font(12))
    .padding(10)
    .frame(minWidth: 260, alignment: .leading)
    .background(theme.buffer)
  }

  private func row(_ device: HuddleDevice, on: Bool, choose: @escaping () -> Void) -> some View {
    CheckRow(text: device.name, on: on) {
      choose()
      chosen += 1
    }
  }
}

/**
 * React, in IRC Classic's palette (web huddle-reactions.tsx): search all emoji, a grid by group, and the
 * stickers below; picking one sends it and closes.
 */
private struct IRCReactPanel: View {
  let call: HuddleCall
  let done: () -> Void
  @Environment(\.theme) private var theme
  @State private var query = ""
  @AppStorage("emojiSkinTone") private var tone: EmojiCatalog.SkinTone = .none

  private let columns = Array(repeating: GridItem(.fixed(26), spacing: 2), count: 10)

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 4) {
        Text("/react").foregroundStyle(theme.ember)
        TextField("search emoji", text: $query)
          .textFieldStyle(.plain)
          .foregroundStyle(theme.text)
          .padding(.horizontal, 4)
          .background(theme.input)
      }
      ScrollView {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
          if query.isEmpty {
            ForEach(EmojiCatalog.groups) { group in
              Section {
                ForEach(group.emoji) { cell($0) }
              } header: {
                Text("-- \(group.name.lowercased()) --").foregroundStyle(theme.dim).frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          } else {
            ForEach(EmojiCatalog.search(query)) { cell($0) }
          }
        }
      }
      IRCStickerList(call: call, done: done)
    }
    .font(Theme.font(12))
    .padding(10)
    .frame(width: 300, height: 400)
    .background(theme.buffer)
  }

  private func cell(_ emoji: EmojiCatalog.Emoji) -> some View {
    Button {
      call.react(emoji.glyph(in: tone))
      done()
    } label: {
      Text(emoji.glyph(in: tone)).font(.system(size: 18)).frame(width: 26, height: 26)
    }
    .buttonStyle(.plain)
    .help(emoji.name)
  }
}
