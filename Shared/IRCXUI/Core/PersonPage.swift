import AppCoreUI
import CoreImage.CIFilterBuiltins
import EmberKit
import SwiftUI

/**
 * Someone's page (web `PersonPage`): who they are, Ping, their sign-in link for administrators, and
 * Block, Report and Ban, as their state allows.
 */
struct PersonPage: View {
  let session: InstanceSession
  let userID: UserID
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var answer: PersonAnswer?
  @State private var failure: String?
  @State private var pinging = false
  @State private var reporting = false

  /** The directory's copy where it's newer, as the web's `asListed` keeps it. */
  private var person: Person? {
    guard var person = answer?.person else { return nil }
    if let listed = session.people[userID] {
      person.name = listed.name
      person.username = listed.username
      person.bio = listed.bio
      person.role = listed.role
      person.status = listed.status
      person.avatarUrl = listed.avatarUrl
    }
    return person
  }

  private var isMe: Bool { userID == session.me?.id }
  private var isAdministrator: Bool { session.me?.administrator == true }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: person?.name ?? "Person", back: session.closePage)
      if let person {
        Form { sections(person) }
          .themedForm(look, irc)
      } else if let failure {
        Text(failure).foregroundStyle(SemanticColor.warning).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Color.clear.loadingActivity(true)
      }
    }
    .task(id: "\(userID)-\(isAdministrator)") { await load() }
    .sheet(isPresented: $reporting) {
      if let person { ReportSheet(session: session, person: person).environment(\.appTheme, look) }
    }
  }

  @ViewBuilder
  private func sections(_ person: Person) -> some View {
    let blocked = session.isBlocked(person.id)
    let inactive = person.status == .deactivated || (person.status == .suspended && !isAdministrator)
    Section {
      HStack(spacing: Spacing.lg) {
        if look == .suite {
          SuiteAvatar(session: session, user: User(id: person.id, name: person.name), size: 64)
            .opacity(person.status == .banned ? 0.4 : 1)
        }
        VStack(alignment: .leading, spacing: Spacing.xs) {
          HStack {
            Text(person.name).font(look == .irc ? Theme.font(16, weight: .bold) : DesignFont.title)
            if person.agent == true || person.id == PeopleList.assistantId { AgentBadge() }
          }
          if let username = person.username { Text("@\(username)").foregroundStyle(.secondary) }
        }
      }
      if isMe {
        Button("Edit my profile", systemImage: "pencil") { session.show(.profile) }
      }
      if inactive {
        Text(NavigationText.noLongerHere(person.name)).foregroundStyle(.secondary)
      } else {
        if person.status == .suspended { Text(NavigationText.lapsed(person.name)).foregroundStyle(.secondary) }
        if person.status == .banned { Text("Banned").foregroundStyle(SemanticColor.destructive) }
        if let email = person.emailAddress, let url = URL(string: "mailto:\(email)") { Link(email, destination: url) }
        if let bio = person.bio, !bio.isEmpty { Text(bio) }
        if let agent = answer?.agent {
          Text(agent.description)
          Text(agent.about(me: session.me?.id, setUpByName: session.people[agent.setUpBy.id]?.name ?? agent.setUpBy.name))
            .foregroundStyle(.secondary)
        }
      }
    }
    if person.status == .active, !blocked {
      Section {
        if canAsk(person) {
          Button(pinging ? "Starting…" : "Ping \(person.name)", systemImage: "bubble.left.and.text.bubble.right", action: { ping(person) })
            .disabled(pinging)
        } else {
          Text(NavigationText.onlyAdministratorsAsk(person.name)).foregroundStyle(.secondary)
        }
      }
    }
    if let transfer = answer?.transferId, person.status == .active {
      SignInLinkSection(link: session.instance.origin + Pages.transferLink(transfer), isMe: isMe)
    }
    if !isMe {
      Section {
        if person.status == .active || blocked {
          Button(blocked ? "Unblock \(person.name)" : "Block \(person.name)", systemImage: "hand.raised") {
            session.attempt(blocked ? "Unblocking" : "Blocking") { try await session.setBlocked(!blocked, person.id) }
          }
        }
        if person.status == .active {
          Button("Report \(person.name)", systemImage: "flag") { reporting = true }
        }
        if isAdministrator, person.role != .bot || person.status == .banned {
          if person.status == .banned {
            Button("Remove ban", systemImage: "checkmark.shield", role: .destructive) { session.confirmation = .ban(person.id, false) }
          } else if person.status != .deactivated {
            Button("Ban \(person.name)", systemImage: "nosign", role: .destructive) { session.confirmation = .ban(person.id, true) }
              .help(NavigationText.banConfirm)
          }
        }
      }
    }
  }

  private func canAsk(_ person: Person) -> Bool { isAdministrator || person.adminsOnly != true }

  private func load() async {
    do {
      answer = try await session.api.person(userID)
    } catch {
      logger.error("Loading someone's page failed: \(error.localizedDescription, privacy: .public)")
      failure = error.localizedDescription
    }
  }

  private func ping(_ person: Person) {
    guard !pinging else { return }
    pinging = true
    Task {
      do {
        try await session.startDirect(with: isMe ? [] : [person.id])
      } catch {
        session.fail("Starting a DM", error)
      }
      pinging = false
    }
  }
}

/** A sign-in link and its QR code, to copy or share (web `SignInLink`). */
struct SignInLinkSection: View {
  let link: String
  let isMe: Bool

  var body: some View {
    Section("Sign-in link") {
      Text(isMe ? PeopleText.signInLinkExplained : NavigationText.signInLinkHint).foregroundStyle(.secondary)
      LinkShare(link: link, shareText: nil, name: "sign-in link")
    }
  }
}

/** A link as a read-only field with Copy, Share and its QR code (web `LinkButtons`). */
struct LinkShare: View {
  let link: String
  let shareText: String?
  let name: String
  @State private var showingCode = false

  var body: some View {
    Text(link).textSelection(.enabled).lineLimit(2).font(DesignFont.monoDetail)
    HStack {
      Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(link) }.help("Copy \(name)")
      if let url = URL(string: link) {
        ShareLink(item: url, message: shareText.map { Text($0) }) { Label("Share", systemImage: "square.and.arrow.up") }
          .help("Share \(name)")
      }
      Button("QR Code", systemImage: "qrcode") { showingCode.toggle() }.help("Show \(name) QR code")
    }
    .buttonStyle(.bordered)
    if showingCode, let code = QRCode.image(link) {
      code.interpolation(.none).resizable().scaledToFit().frame(width: 180, height: 180)
    }
  }
}

enum QRCode {
  /** A QR code of `text`, drawn by Core Image. */
  static func image(_ text: String) -> Image? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else {
      logger.error("A QR code didn't draw")
      return nil
    }
    return Image(decorative: cg, scale: 1)
  }
}
