import AppCoreUI
import EmberKit
import SwiftUI

/**
 * The welcome card (web `InvitationCard`): at the top of the workspace's first room while it's new, for
 * an administrator who hasn't dismissed it, with the join link to share.
 */
struct WelcomeCard: View {
  let session: InstanceSession
  let room: RoomModel
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  /** The invitation, while the card shows: the first room's timeline from its start, and a join link that lets people in. */
  static func invitation(_ session: InstanceSession, _ room: RoomModel) -> Invitation? {
    guard let invitation = session.invitation, invitation.roomId == room.id, !room.timeline.hasMore, session.account?.joinsWithLink == true else {
      return nil
    }
    return invitation
  }

  var body: some View {
    if let invitation = Self.invitation(session, room) {
      let link = session.joinLink(invitation.joinCode)
      switch look {
      case .suite:
        PaneCard(NavigationText.welcomeTitle, systemImage: "flame") {
          VStack(alignment: .leading, spacing: Spacing.md) {
            Text(NavigationText.welcomeText).font(DesignFont.body)
            LinkShare(link: link, shareText: NavigationText.joinShareText, name: "join link")
          }
        } trailing: {
          PaneIconButton(systemImage: "xmark", help: "Dismiss welcome card", action: dismiss)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
      case .irc:
        VStack(alignment: .leading, spacing: 2) {
          Text("-!- \(NavigationText.welcomeTitle). \(NavigationText.welcomeText)")
          Text("-!- Join link: \(link)").textSelection(.enabled)
          HStack(spacing: 12) {
            Button("[copy]") { Pasteboard.copy(link) }.help("Copy join link")
            if let url = URL(string: link) {
              ShareLink(item: url, message: Text(NavigationText.joinShareText)) { Text("[share]") }.help("Share join link")
            }
            Button("[dismiss]", action: dismiss).help("Dismiss welcome card")
            Text("or /dismiss").foregroundStyle(irc.dim)
          }
          .buttonStyle(.plain)
          .foregroundStyle(irc.ember)
        }
        .font(Theme.font(12))
        .foregroundStyle(irc.join)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
      }
    }
  }

  private func dismiss() {
    session.attempt("Dismissing the welcome card") { try await session.dismissInvitation() }
  }
}

/**
 * The instance's notices over its pages (web `Notices`): Ember moved to its custom domain, and Ember was
 * updated, each closable.
 */
struct InstanceNotices: View {
  let app: AppModel
  let session: InstanceSession
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    VStack(spacing: Spacing.xs) {
      if let domain = session.movedTo {
        notice(NavigationText.moved(to: domain), action: "Switch", perform: { app.move(session, to: domain) }, close: session.closeMovedNotice)
      }
      if session.updated {
        notice(NavigationText.updated, action: "Reload", perform: session.reloadAfterUpdate, close: session.closeUpdatedNotice)
      }
    }
  }

  @ViewBuilder
  private func notice(_ text: String, action: String, perform: @escaping () -> Void, close: (() -> Void)?) -> some View {
    switch look {
    case .suite:
      Notice(text, systemImage: "info.circle", tint: SemanticColor.accent, actionTitle: action, action: perform, onDismiss: close)
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
    case .irc:
      HStack(spacing: 8) {
        Text("-!- \(text)").foregroundStyle(irc.ember)
        Button("[\(action.lowercased())]", action: perform).buttonStyle(.plain).foregroundStyle(irc.link)
        if let close { Button("[x]", action: close).buttonStyle(.plain).foregroundStyle(irc.dim).help("Close") }
        Spacer()
      }
      .font(Theme.font(12))
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .background(irc.statusBar)
    }
  }
}
