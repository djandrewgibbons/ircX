import EmberKit
import Foundation
import HuddleMedia
import Observation

/** A huddle's preview, asked for in a room (web `preview(roomId)`). */
public struct HuddlePreviewRequest: Identifiable {
  public let session: InstanceSession
  public let roomId: RoomID
  public var id: String { "\(session.id) \(roomId)" }
}

/**
 * The app's huddles: the one it's in (one at a time, on any server), the preview every start and join
 * goes through, Invite people, and the invitations that ring, from every server signed in, with the
 * one ring for them all (web workspace.tsx's huddle parts, huddle-invitations.tsx).
 */
@MainActor
@Observable
public final class HuddleCenter {
  public private(set) var call: HuddleCall?
  /** The preview to show, over whichever theme. */
  public var preview: HuddlePreviewRequest?
  /** Invite people, over the opened huddle. */
  public var inviting = false

  @ObservationIgnored let sounds = HuddleSoundPlayer()
  @ObservationIgnored weak var app: AppModel?

  init() {}

  // MARK: - Starting and joining

  /**
   * Starts or joins `room`'s huddle by its preview, as every way in does (the header's button, a
   * message's Join, the Huddles page, an invitation, a link, the shortcut), unless huddles are off.
   * The huddle the app is in already only opens.
   */
  public func preview(_ room: RoomID, in session: InstanceSession) {
    guard session.account?.huddles == true else { return session.notice = HuddleWords.off }
    guard let item = session.rooms.first(where: { $0.id == room }) else { return session.notice = NavigationText.roomNotFound }
    guard let me = session.me, HuddleRules.hasHuddles(item.room, me: me.id, joinsNone: session.joinsNoHuddle) else {
      return session.notice = HuddleWords.offInThisRoom
    }
    if let call, call.session === session, call.roomId == room { return call.setOpen(true) }
    preview = HuddlePreviewRequest(session: session, roomId: room)
  }

  /** Who a DM's huddle rings as it starts: the others in it, unless the app's person is in it already elsewhere. */
  func invitees(_ room: Room, in session: InstanceSession) -> [User] {
    guard room.isDirect, let me = session.me, session.huddles[room.id]?.userIds.contains(me.id) != true else { return [] }
    return Array(HuddleRules.huddledWith(room, me: me.id, joinsNone: session.joinsNoHuddle).prefix(Huddles.maxInvited))
  }

  /**
   * Joins `room`'s huddle, leaving any the app is in: with the microphone the preview found, or listening
   * only, and with the camera the preview opened, if it did.
   */
  public func join(_ roomId: RoomID, in session: InstanceSession, muted: Bool, microphone: Bool, camera: Bool) {
    call?.leave()
    let invite = session.rooms.first { $0.id == roomId }.map { invitees($0.room, in: session).map(\.id) } ?? []
    let joined = HuddleCall(session: session, roomId: roomId, muted: muted, microphone: microphone, invite: invite, sounds: sounds)
    joined.onOver = { [weak self, weak joined] in
      guard let self, self.call === joined else { return }
      self.call = nil
      self.inviting = false
      session.seeRinging()
    }
    call = joined
    joined.start(camera: camera)
    session.seeRinging()
  }

  /** Joins without a preview, as IRC Classic's `/huddle` does: it asks for the microphone, and the camera with `camera`. */
  public func joinNow(_ roomId: RoomID, in session: InstanceSession, muted: Bool, camera: Bool) async {
    let microphone = await HuddleEngine.microphoneAllowed()
    if microphone { HuddleDevices.useRemembered() } else { session.notice = HuddleWords.noMicrophone }
    var opened = false
    if camera, session.account?.huddleCameras == true {
      if await HuddleEngine.cameraAllowed() {
        do {
          try await HuddleEngine.shared.openCamera(UserDefaults.standard.string(forKey: HuddleDevices.camera))
          opened = true
        } catch {
          huddleLog.error("Opening the camera failed: \(error.localizedDescription, privacy: .public)")
          session.notice = HuddleWords.noCamera
        }
      } else {
        session.notice = HuddleWords.noCamera
      }
    }
    join(roomId, in: session, muted: muted, microphone: microphone, camera: opened)
  }

  public func leave() { call?.leave() }

  /** ⌘⌥⇧H: leaves the huddle of the room shown, or starts or joins it (web `togglesHuddle`). */
  public func toggle(in session: InstanceSession) {
    guard let room = session.selectedRoomID, session.page == nil else { return }
    if let call, call.session === session, call.roomId == room { return call.leave() }
    preview(room, in: session)
  }

  /** ⌘⇧Space: mutes or unmutes the huddle's microphone. */
  public func toggleMute() {
    guard let call else { return }
    call.setMuted(!call.muted)
  }

  /** Copies the link that opens a room's huddle (`huddlePath`). */
  public func link(_ room: RoomID, in session: InstanceSession) -> String { session.publicOrigin + Pages.huddlePath(room) }

  // MARK: - Invitations

  /** Join on an invitation: the preview, and the invitation stops ringing everywhere. */
  public func answer(_ invitation: HuddleInvitation, in session: InstanceSession, join: Bool) {
    session.stopRinging(invitation.roomId)
    Task {
      do {
        try await session.api.answerHuddleInvitation(in: invitation.roomId)
      } catch {
        huddleLog.error("Answering the huddle invitation failed: \(error.localizedDescription, privacy: .public)")
        session.notice = error.localizedDescription
      }
      guard join else { return }
      if !session.rooms.contains(where: { $0.id == invitation.roomId }) { await session.refreshSidebar() }
      preview(invitation.roomId, in: session)
    }
  }

  /** Every invitation that rings, on every server. */
  public var ringing: [(session: InstanceSession, invitation: HuddleInvitation)] {
    guard let app else { return [] }
    return app.sessions.flatMap { session in session.ringing.map { (session, $0) } }
  }

  /**
   * Rings while any invitation does, one sound for them all, unless the person is in a huddle already,
   * here or elsewhere, or has the ring off on that server (web `quiet`). Started once, it follows them.
   */
  func hearRinging() {
    guard let app else { return }
    withObservationTracking {
      sounds.ring(!isInHuddle(app) && app.sessions.contains { !$0.ringing.isEmpty && rings(in: $0) })
    } onChange: { [weak self] in
      Task { @MainActor in self?.hearRinging() }
    }
  }

  /** Whether the app is ringing for an invitation to `room`'s huddle, which then needs no notification's banner. */
  func isRinging(for room: RoomID, in session: InstanceSession) -> Bool {
    guard let app else { return false }
    return !isInHuddle(app) && rings(in: session) && session.ringing.contains { $0.roomId == room }
  }

  /** Whether the person is in a huddle, here or elsewhere. */
  private func isInHuddle(_ app: AppModel) -> Bool {
    call != nil || app.sessions.contains { session in
      guard let me = session.me?.id else { return false }
      return session.huddles.values.contains { $0.userIds.contains(me) }
    }
  }

  /** Whether a server's invitations ring: its sidebar loaded and its ring not off. */
  private func rings(in session: InstanceSession) -> Bool {
    session.sidebarLoaded && session.huddleSounds.map(\.ring) != false
  }
}

extension InstanceSession {
  /** Whether someone joins no huddle, as the directory lists them now (`useJoinsNoHuddle`). */
  func joinsNoHuddle(_ user: User) -> Bool { HuddleRules.joinsNone(user, listed: people[user.id]) }

  /** Whether `room` has a huddle button: huddles on here, and the room having them. */
  func hasHuddles(_ room: Room) -> Bool {
    guard account?.huddles == true, let me else { return false }
    return HuddleRules.hasHuddles(room, me: me.id, joinsNone: joinsNoHuddle)
  }
}
