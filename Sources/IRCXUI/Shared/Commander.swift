import EmberKit
import Foundation

/** What the input line's commands do, whichever theme's input line they were typed in. */
@MainActor
enum Commander {
  static func run(_ command: InputCommand, app: AppModel, session: InstanceSession, room: RoomModel) {
    switch command {
    case let .say(text): room.send(text)
    case let .me(action): room.send(action, action: true)
    case let .join(name):
      Task { do { try await session.join(name) } catch { room.note(error.localizedDescription, kind: .error) } }
    case let .msg(nick, text):
      Task {
        do {
          let buffer = try await session.query(nick)
          if let text, let buffer {
            // Its socket opens as the buffer comes on screen; send once it has.
            for _ in 0..<50 where !buffer.isOpen { try? await Task.sleep(for: .milliseconds(100)) }
            buffer.send(text)
          }
        } catch {
          room.note(error.localizedDescription, kind: .error)
        }
      }
    case .part:
      session.selectedRoomID = nil
    case .names:
      let names = room.timeline.present.map(\.name).sorted().joined(separator: " ")
      room.note("[Users \(room.room.isDirect ? room.title : "#" + room.title)] \(names)")
    case let .whois(nick):
      if let person = session.people.values.first(where: { $0.name.caseInsensitiveCompare(nick) == .orderedSame }) {
        room.note("\(person.name) [\(person.role.rawValue), \(person.status.rawValue)]\(person.bio.map { " : \($0)" } ?? "")")
      } else {
        room.note("\(nick): No such nick", kind: .error)
      }
    case let .server(address):
      if let url = Instance.baseURL(from: address) {
        app.addInstance(at: url)
      } else {
        room.note("Not an address: \(address)", kind: .error)
      }
    case .help:
      room.note(InputCommand.helpText)
    case let .unknown(reason):
      room.note(reason, kind: .error)
    }
  }

  /** Steps through the selected instance's windows by `by`, as ⌥↑ and ⌥↓ do. */
  static func step(_ by: Int, in session: InstanceSession) {
    let windows = (session.starred + session.channels + session.directs).map(\.id)
    guard !windows.isEmpty else { return }
    let current = session.selectedRoomID.flatMap { windows.firstIndex(of: $0) } ?? -by
    session.selectedRoomID = windows[(current + by + windows.count) % windows.count]
  }
}
