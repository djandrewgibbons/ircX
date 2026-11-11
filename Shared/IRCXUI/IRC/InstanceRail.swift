import EmberKit
import SwiftUI

/** Slack's workspace rail: a tile per instance, ⌘1 to ⌘9, and + to add one. */
struct InstanceRail: View {
  @Bindable var app: AppModel
  var horizontal = false
  @Environment(\.theme) private var theme

  var body: some View {
    let tiles = ForEach(Array(app.sessions.enumerated()), id: \.element.id) { index, session in
      InstanceTile(session: session, selected: session.id == app.selectedID, index: index)
        .onTapGesture { app.selectedID = session.id }
        .contextMenu {
          Text(session.instance.host)
          if session.phase == .ready {
            Button("Sign out") { Task { await session.signOut() } }
          }
          Button("Remove server", role: .destructive) { Task { await app.remove(session) } }
        }
    }
    let add = Button {
      app.showingAddInstance = true
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 38, height: 38)
        .background(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.dim.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3])))
        .foregroundStyle(theme.dim)
    }
    .buttonStyle(.plain)
    .help("Add an Ember server")

    if horizontal {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) { tiles; add }.padding(.horizontal, 12).padding(.vertical, 8)
      }
      .background(theme.rail)
    } else {
      VStack(spacing: 10) {
        ScrollView(showsIndicators: false) {
          VStack(spacing: 10) { tiles }.padding(.top, 12)
        }
        add.padding(.bottom, 12)
      }
      .frame(width: 62)
      .background(theme.rail)
    }
  }
}

struct InstanceTile: View {
  let session: InstanceSession
  let selected: Bool
  let index: Int
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: 4) {
      Capsule()
        .fill(theme.text)
        .frame(width: 4, height: selected ? 30 : (session.hasUnread ? 8 : 0))
        .opacity(selected || session.hasUnread ? 1 : 0)
      Text(initials)
        .font(Theme.font(14, weight: .bold))
        .frame(width: 38, height: 38)
        .background(RoundedRectangle(cornerRadius: selected ? 11 : 9).fill(selected ? theme.ember : theme.bar))
        .foregroundStyle(selected ? Color.black : theme.text)
        .overlay(alignment: .bottomTrailing) { status }
    }
    .contentShape(Rectangle())
    .help("\(session.name) — \(session.instance.host)")
    .accessibilityLabel("\(session.name), \(session.unreadCount) unread")
  }

  private var initials: String {
    let words = session.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array(session.name.prefix(2))
    return String(letters).uppercased()
  }

  @ViewBuilder
  private var status: some View {
    switch session.phase {
    case .ready where session.socketState != .open:
      Circle().fill(Color.yellow).frame(width: 9, height: 9).overlay(Circle().stroke(theme.rail, lineWidth: 2)).offset(x: 3, y: 3)
    case .signedOut, .unreachable:
      Circle().fill(theme.part).frame(width: 9, height: 9).overlay(Circle().stroke(theme.rail, lineWidth: 2)).offset(x: 3, y: 3)
    default:
      EmptyView()
    }
  }
}
