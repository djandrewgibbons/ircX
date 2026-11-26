import EmberKit
import Foundation
import HuddleMedia

/** What `/huddle` and its aliases do, in either theme's input line. */
@MainActor
enum HuddleCommander {
  static func run(_ action: InputCommand.HuddleAction, app: AppModel, session: InstanceSession, room: RoomModel) {
    let center = app.huddles
    let call = center.call
    func inCall(_ act: (HuddleCall) -> Void) {
      guard let call else { return room.note("You're in no huddle", kind: .error) }
      act(call)
    }
    switch action {
    case let .start(muted, camera, preview):
      guard session.hasHuddles(room.room) else {
        return room.note(session.account?.huddles == true ? HuddleWords.offInThisRoom : HuddleWords.off, kind: .error)
      }
      if preview { return center.preview(room.id, in: session) }
      if let call, call.session === session, call.roomId == room.id { return room.note("You're in this huddle already") }
      room.note("Joining the huddle…")
      Task { await center.joinNow(room.id, in: session, muted: muted, camera: camera) }
    case let .join(name):
      if let name {
        guard let target = session.room(named: name) else { return room.note("#\(name): No such channel", kind: .error) }
        return answerOrPreview(target.id, center: center, session: session)
      }
      answerOrPreview(session.ringing.last?.roomId ?? room.id, center: center, session: session)
    case let .decline(name):
      let target = name.flatMap { session.room(named: $0)?.id }
      guard let invitation = session.ringing.last(where: { target == nil || $0.roomId == target }) else { return room.note("No invitation is ringing", kind: .error) }
      center.answer(invitation, in: session, join: false)
    case .leave:
      inCall { $0.leave() }
    case .link:
      let link = center.link(room.id, in: session)
      Pasteboard.copy(link)
      room.note("Copied \(link)")
    case .open:
      inCall { $0.setOpen(true) }
    case .close:
      inCall { $0.setOpen(false) }
    case .list:
      list(session: session, room: room)
    case .who:
      inCall { call in
        let names = call.people.map { person in
          var name = session.people[person.user.id]?.name ?? person.user.name
          if person.user.id == call.you?.id { name += " (you)" }
          if person.muted { name += " [m]" }
          if person.video { name += " [c]" }
          if person.screen { name += " [s]" }
          if let sticker = person.sticker { name += " \(sticker.emoji)" }
          if call.speaking.contains(person.user.id) { name = "*" + name }
          return name
        }
        room.note("\(call.name): \(names.joined(separator: ", "))")
      }
    case .thread:
      inCall { call in
        guard let messageId = call.messageId else { return room.note("This huddle has no thread", kind: .error) }
        call.session.show(call.roomId, messageId: nil, threadId: messageId)
      }
    case let .mute(muted):
      inCall { call in
        guard call.microphone else { return room.note("No microphone", kind: .error) }
        call.setMuted(muted)
      }
    case let .camera(on):
      inCall { call in
        guard !on || session.account?.huddleCameras == true else { return room.note(Huddles.camerasOff, kind: .error) }
        call.setCamera(on)
      }
    case let .screen(on):
      inCall { call in
        guard !on || HuddleEngine.sharesScreens else { return room.note("This device can't share its screen", kind: .error) }
        guard !on || session.account?.huddleScreens == true else { return room.note(Huddles.screensOff, kind: .error) }
        call.setScreen(on)
      }
    case .hand:
      inCall { $0.setSticker($0.sticker == nil ? .hand : nil) }
    case let .sticker(sticker):
      inCall { $0.setSticker(sticker) }
    case let .react(emoji):
      inCall { $0.react(emoji) }
    case let .invite(nicks):
      inCall { call in
        guard !nicks.isEmpty else { return center.inviting = true }
        var ids: [UserID] = []
        for nick in nicks {
          guard let person = session.person(named: nick) else { return room.note("\(nick): No such nick", kind: .error) }
          ids.append(person.id)
        }
        guard call.invite(ids) else { return room.note(HuddleWords.inviteWhileReconnecting, kind: .error) }
        room.note(HuddleWords.invitedNow(ids.compactMap { session.people[$0]?.name }))
      }
    }
  }

  /** Joins an invitation's huddle by its preview, answering it, or the room's own. */
  private static func answerOrPreview(_ id: RoomID, center: HuddleCenter, session: InstanceSession) {
    if let invitation = session.ringing.last(where: { $0.roomId == id }) { return center.answer(invitation, in: session, join: true) }
    center.preview(id, in: session)
  }

  /** `/huddle list`: the huddles going on, and recent ones, printed (web huddles-page.tsx). */
  private static func list(session: InstanceSession, room: RoomModel) {
    let going = HuddleList.goingOn(session.rooms, live: session.huddles)
    if session.account?.huddles == true {
      room.note(going.isEmpty ? "Happening now: none" : "Happening now:")
      for item in going {
        let names = item.huddle.userIds.compactMap { session.people[$0]?.name }
        room.note("  \(session.title(of: item.room.room)) [LIVE] \(MessageWords.inItsHuddle(names, count: item.huddle.userIds.count, you: false)) (/huddle join #\(session.title(of: item.room.room)))")
      }
    }
    Task {
      do {
        let past = try await session.api.pastHuddles()
        let listed = Dictionary(session.rooms.filter { $0.involvement != .invisible }.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let recent = past.filter { listed[$0.roomId] != nil && session.huddles[$0.roomId]?.startedAt != $0.startedAt }
        room.note(recent.isEmpty ? NavigationText.noHuddlesYet : "Recent huddles:")
        for huddle in recent {
          guard let item = listed[huddle.roomId] else { continue }
          var line = "  \(session.title(of: item.room))"
          if let start = EmberDate.parse(huddle.startedAt), let end = EmberDate.parse(huddle.endedAt) {
            line += " · \(MessageWords.dateTime(start)) · \(MessageWords.huddleLasted(from: start, to: end))"
          }
          if huddle.replies > 0 { line += " · \(MessageWords.replies(huddle.replies))" }
          room.note(line)
        }
      } catch {
        huddleLog.error("Loading huddles failed: \(error.localizedDescription, privacy: .public)")
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }
}
