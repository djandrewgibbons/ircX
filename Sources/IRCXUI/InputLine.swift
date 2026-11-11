import EmberKit
import SwiftUI

/**
 * The input line: `[nick(#room)] ▸`, Return to send, Tab to complete a nick, ↑ and ↓ for what you sent
 * before, and the IRC commands `InputCommand` reads.
 */
struct InputLine: View {
  let app: AppModel
  let session: InstanceSession
  let room: RoomModel
  @Environment(\.theme) private var theme
  @AppStorage(Preferences.fontSize) private var fontSize = 13.0
  @State private var draft = ""
  @State private var history: [String] = []
  @State private var historyIndex: Int?
  @FocusState private var focused: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text("[\(session.me?.name ?? "?")(\(room.room.isDirect ? room.title : "#" + room.title))]")
        .foregroundStyle(theme.dim)
        .lineLimit(1)
      Text("▸").foregroundStyle(theme.ember)
      field
      #if os(iOS)
      Button {
        submit()
      } label: {
        Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
      }
      .foregroundStyle(draft.isEmpty ? theme.dim : theme.ember)
      .disabled(draft.isEmpty)
      #endif
    }
    .font(Theme.font(fontSize))
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(theme.input)
    .onAppear { focused = true }
  }

  @ViewBuilder
  private var field: some View {
    #if os(macOS)
    TextField("", text: $draft, axis: .vertical)
      .textFieldStyle(.plain)
      .lineLimit(1...8)
      .focused($focused)
      .onSubmit(submit)
      .onChange(of: draft) { _, new in if !new.isEmpty, !new.hasPrefix("/") { room.typed() } }
      .onKeyPress(.tab) {
        complete()
        return .handled
      }
      .onKeyPress(.upArrow) { recall(-1) ? .handled : .ignored }
      .onKeyPress(.downArrow) { recall(1) ? .handled : .ignored }
    #else
    TextField("Message", text: $draft)
      .textFieldStyle(.plain)
      .focused($focused)
      .submitLabel(.send)
      .autocorrectionDisabled()
      .textInputAutocapitalization(.sentences)
      .onSubmit(submit)
      .onChange(of: draft) { _, new in if !new.isEmpty, !new.hasPrefix("/") { room.typed() } }
    #endif
  }

  private func submit() {
    let text = draft
    guard let command = InputCommand.parse(text) else { return }
    history.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
    if history.count > 100 { history.removeFirst() }
    historyIndex = nil
    draft = ""
    focused = true
    run(command)
  }

  private func run(_ command: InputCommand) {
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

  /** Completes the nick being typed, as irssi does: `Ad⇥` becomes `Ada: ` at the start of the line, `Ada ` after. */
  private func complete() {
    let words = draft.split(separator: " ", omittingEmptySubsequences: false)
    guard let last = words.last, !last.isEmpty else { return }
    let prefix = last.hasPrefix("@") ? String(last.dropFirst()) : String(last)
    let candidates = (room.timeline.present.map(\.name) + session.mentionable.map(\.name))
    guard let match = candidates.first(where: { $0.lowercased().hasPrefix(prefix.lowercased()) && $0 != session.me?.name }) else { return }
    let head = words.dropLast().joined(separator: " ")
    let mention = (last.hasPrefix("@") ? "@" : "") + match
    draft = head.isEmpty ? mention + (last.hasPrefix("@") ? " " : ": ") : head + " " + mention + " "
  }

  /** Steps through what was sent before, and says whether it did. */
  private func recall(_ step: Int) -> Bool {
    guard !history.isEmpty, draft.isEmpty || historyIndex != nil else { return false }
    let next = (historyIndex ?? history.count) + step
    if next >= history.count {
      historyIndex = nil
      draft = ""
    } else if next >= 0 {
      historyIndex = next
      draft = history[next]
    }
    return true
  }
}
