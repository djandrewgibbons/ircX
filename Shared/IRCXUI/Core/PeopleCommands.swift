import EmberKit
import Foundation
import SwiftUI

/**
 * The input line's commands about you (IRC Classic's way to the profile): each prints what it did as a
 * line, and any that needs a password or a web view opens the profile, where nothing is printed.
 */
@MainActor
enum PeopleCommands {
  static func run(_ command: InputCommand, session: InstanceSession, room: RoomModel) {
    switch command {
    case .ignored:
      let names = PeopleList.byName(session.blocks.userIds.compactMap { session.people[$0] }).map(\.name)
      room.note(names.isEmpty ? "You haven't blocked anyone" : "Blocked: \(names.joined(separator: ", ")) · /unignore nick")
    case let .profile(link):
      guard link else { return session.show(.profile) }
      Task {
        do {
          let answer = try await session.api.profile()
          let address = session.instance.origin + Pages.transferLink(answer.transferId)
          Pasteboard.copy(address)
          room.print(["Copied your sign-in link. \(PeopleText.signInLinkExplained)"])
        } catch {
          room.note(error.localizedDescription, kind: .error)
        }
      }
    case let .profileElsewhere(connect, memberful):
      elsewhere(connect: connect, memberful: memberful, session: session, room: room)
    case let .setProfile(field, value):
      change(field, to: value, session: session, room: room)
    case .passwd:
      room.note("Change your password on your profile, where it's never printed")
      session.show(.profile)
    case let .avatar(remove):
      guard remove else {
        room.note("Choose a photo on your profile")
        return session.show(.profile)
      }
      Task {
        do {
          _ = try await session.api.removeAvatar()
          room.note("Photo removed")
        } catch {
          room.note(error.localizedDescription, kind: .error)
        }
      }
    case let .apps(action):
      apps(action, session: session, room: room)
    case let .ai(name):
      ai(disconnect: name, session: session, room: room)
    case let .sounds(sound, on):
      sounds(sound, on, session: session, room: room)
    case let .appearance(name):
      guard let name else {
        let current = UserDefaults.standard.string(forKey: Preferences.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        return room.note("Appearance: \(current.name). IRC Classic keeps its own palette; it applies to the Suite theme.")
      }
      guard let appearance = Appearance(rawValue: name) else { return room.note("/appearance takes light, dark or system", kind: .error) }
      UserDefaults.standard.set(appearance.rawValue, forKey: Preferences.appearance)
      room.note("Appearance: \(appearance.name), for the Suite theme")
    case .quit:
      session.attempt("Logging out") { try await session.signOut() }
    case .deleteAccount:
      room.note("Delete my account is at the foot of your profile; it asks for your password or name first")
      session.show(.profile)
    default:
      return
    }
  }

  private static func change(_ field: InputCommand.ProfileField, to value: String, session: InstanceSession, room: RoomModel) {
    var changes = ProfileChanges()
    switch field {
    case .name: changes.name = value
    case .username: changes.username = EmberRules.username(of: value)
    case .bio: changes.bio = String(value.prefix(EmberLimits.maxBioLength))
    case .emailAddress: changes.emailAddress = value
    }
    if let username = changes.username, !username.isEmpty, !EmberRules.isUsername(username) {
      return room.note(EmberText.usernameRefused, kind: .error)
    }
    Task {
      do {
        let answer = try await session.api.changeProfile(changes)
        session.adoptName(answer.profile.name)
        switch field {
        case .name: room.note("You're now known as \(answer.profile.name)")
        case .username: room.note(answer.profile.username.map { "Your username is @\($0)" } ?? "Your username is removed")
        case .bio: room.note("Bio saved")
        case .emailAddress: room.note("Email address saved")
        }
      } catch let EmberError.problem(problem) where problem.message == EmberText.currentPasswordNeeded {
        room.note("\(problem.message) Change it on your profile.", kind: .error)
        session.show(.profile)
      } catch {
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }

  /**
   * Connects or disconnects Memberful or single sign-on (web `ExternalConnection`), on the profile: its
   * password is typed there, never on the input line, and connecting without one starts at once.
   */
  private static func elsewhere(connect: Bool, memberful: Bool, session: InstanceSession, room: RoomModel) {
    Task {
      do {
        let profile = try await session.api.profile().profile
        let name = memberful ? "Memberful" : (profile.sso?.name ?? "single sign-on")
        let offered = memberful ? profile.memberful != nil : profile.sso != nil
        let connected = memberful ? profile.memberful?.connected != nil : profile.sso?.connected != nil
        guard offered else { return room.note("\(name) isn't offered here", kind: .error) }
        if connect {
          guard !connected else { return room.note("Your \(name) account is connected already") }
          if profile.password {
            room.note("Type your password under \(name) on your profile, then Connect \(name)")
          } else {
            session.profileIntent = .connect(memberful: memberful)
          }
        } else {
          guard connected else { return room.note("Your \(name) account isn't connected", kind: .error) }
          room.note("Type your password under \(name) on your profile, then Disconnect \(name)")
        }
        session.show(.profile)
      } catch {
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }

  private static func apps(_ action: InputCommand.AppsAction, session: InstanceSession, room: RoomModel) {
    Task {
      do {
        let apps = try await session.api.profile().profile.apps
        func named(_ name: String) -> YourApp? { apps.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        switch action {
        case .list:
          guard !apps.isEmpty else { return room.note("No apps to sign in to") }
          room.print(apps.map { "\($0.name): \(PeopleText.status(of: $0, at: ProfileDates.label))" } + ["/apps signin app · /apps signout app"])
        case let .signIn(name):
          guard let app = named(name) else { return room.note("\(name): No such app", kind: .error) }
          session.profileIntent = .signIn(app.id)
          session.show(.profile)
        case let .signOut(name):
          guard let app = named(name) else { return room.note("\(name): No such app", kind: .error) }
          let answer = try await session.api.signOutOfApp(app.id)
          room.note(PeopleText.signedOut(app.name, revoked: answer.revoked), kind: answer.revoked ? .info : .error)
        }
      } catch {
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }

  private static func ai(disconnect name: String?, session: InstanceSession, room: RoomModel) {
    Task {
      do {
        guard let connections = try await session.api.profile().profile.outsideAi else {
          return room.note(Outside.off, kind: .error)
        }
        guard let name else {
          var lines = ["Give an AI app this address: \(session.instance.origin)\(Outside.mcpPath)"]
          lines += connections.isEmpty ? [PeopleText.nothingConnected] : connections.map { "\($0.name): \(PeopleText.status(of: $0, at: ProfileDates.label))" }
          return room.print(lines)
        }
        guard let connection = connections.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
          return room.note("\(name): No such AI app", kind: .error)
        }
        _ = try await session.api.disconnectOutside(connection.id)
        room.note(PeopleText.disconnected(connection.name))
      } catch {
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }

  private static func sounds(_ sound: InputCommand.HuddleSound?, _ on: Bool?, session: InstanceSession, room: RoomModel) {
    guard session.account?.huddles == true else { return room.note("Huddles are off here", kind: .error) }
    let sounds = session.huddleSounds ?? HuddleSounds.all
    guard let sound, let on else {
      let state = { (on: Bool) in on ? "on" : "off" }
      return room.note("Huddle sounds: music \(state(sounds.music)) · chimes \(state(sounds.chimes)) · ring \(state(sounds.ring))")
    }
    let changes: HuddleSoundChanges
    switch sound {
    case .music: changes = HuddleSoundChanges(music: on)
    case .chimes: changes = HuddleSoundChanges(chimes: on)
    case .ring: changes = HuddleSoundChanges(ring: on)
    }
    Task {
      do {
        try await session.changeHuddleSounds(changes)
        room.note("Huddle \(sound.rawValue) \(on ? "on" : "off")")
      } catch {
        room.note(error.localizedDescription, kind: .error)
      }
    }
  }
}

/** Something the profile does as it opens, which a command asked for. */
public enum ProfileIntent: Equatable, Sendable {
  /** Sign in to a connected app yourself. */
  case signIn(AppID)
  /** Connect Memberful (or else single sign-on) without a password, which has none to ask for. */
  case connect(memberful: Bool)
}
