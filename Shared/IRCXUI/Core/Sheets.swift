import AppCoreUI
import EmberKit
import OSLog
import SwiftUI

/** Adding an instance by its address, as /server does. */
struct AddInstanceView: View {
  let app: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var address = ""
  @State private var checking = false
  @State private var error: String?

  var body: some View {
    switch look {
    case .suite: suite
    case .irc: classic
    }
  }

  private var suite: some View {
    NavigationStack {
      Form {
        addressField
        if let error {
          Notice(error, systemImage: "exclamationmark.triangle.fill", tint: SemanticColor.warning)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Add Server")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Connect", systemImage: "checkmark", action: add)
            .buttonStyle(.glassProminent)
            .disabled(checking || address.isEmpty)
        }
      }
      .loadingActivity(checking)
    }
    .loadingActivityBar(color: SuiteTheme.ircX.accent)
    .frame(minWidth: 400, minHeight: 180)
  }

  private var classic: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("/server").font(Theme.font(18, weight: .bold)).foregroundStyle(irc.ember)
      Text("The address of an Ember instance, such as irc.dxnd.ai or chat.example.com.").foregroundStyle(irc.dim)
      addressField.textFieldStyle(.roundedBorder)
      if let error { Text("-!- \(error)").foregroundStyle(irc.part) }
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
        Button(checking ? "Checking…" : "Connect", action: add)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(checking || address.isEmpty)
      }
    }
    .font(Theme.font(13))
    .padding(24)
    .frame(minWidth: 380)
    .background(irc.buffer)
    .preferredColorScheme(.dark)
  }

  private var addressField: some View {
    TextField("Address", text: $address, prompt: Text("irc.dxnd.ai, or a link"))
      .help("A server's address, or a link from it: a join link, an invitation, a sign-in link or a setup link.")
      .autocorrectionDisabled()
      #if os(iOS)
      .textInputAutocapitalization(.never)
      .keyboardType(.URL)
      #endif
      .onSubmit(add)
  }

  /** Adds the server an address or a pasted link names, then follows the link: a join link, an invitation, a sign-in link. */
  private func add() {
    guard let link = EmberLink.parse(address) else {
      error = "That isn't an address."
      return
    }
    let url = link.baseURL
    checking = true
    Task {
      defer { checking = false }
      // Check it's Ember before keeping it.
      do {
        _ = try await EmberAPI(instance: Instance(baseURL: url), tokens: MemoryTokenStore()).bootstrap()
        app.follow(link)
        dismiss()
      } catch {
        logger.error("Adding \(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        self.error = "\(url.host() ?? address): \(error.localizedDescription)"
      }
    }
  }
}

/** ⌘K: jump to any room on any instance, as Slack's switcher does. */
struct QuickSwitcher: View {
  let app: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @State private var query = ""
  @State private var highlighted = 0
  @State private var linkFailure: String?

  private var matches: [(session: InstanceSession, room: SidebarRoom)] {
    let all = app.allRooms.sorted { a, b in a.session.isMarkedUnread(a.room) && !b.session.isMarkedUnread(b.room) }
    guard !query.isEmpty else { return Array(all.prefix(30)) }
    let q = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#@ "))
    return all.filter { $0.session.title(of: $0.room.room).lowercased().contains(q) || $0.session.name.lowercased().contains(q) }
  }

  private var font: Font { look == .irc ? Theme.font(13) : DesignFont.body }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: Spacing.md) {
        if look == .irc {
          Text("/window").foregroundStyle(irc.ember)
        } else {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        }
        TextField(look == .irc ? "goto" : "Jump To", text: $query, prompt: Text(look == .irc ? "goto, or paste a link" : "Jump To, or paste a link"))
          .textFieldStyle(.plain)
          .onSubmit { pick(highlighted) }
          #if os(macOS)
          .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(matches.count - 1, 0)); return .handled }
          .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
          #endif
      }
      .padding(Spacing.lg)
      Divider()
      if isLink {
        Text(linkFailure ?? "Return opens the link.")
          .foregroundStyle(linkFailure == nil ? Color.secondary : SemanticColor.warning)
          .padding(Spacing.lg)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array((isLink ? [] : matches).enumerated()), id: \.offset) { index, match in
            row(match, highlighted: index == highlighted)
              .contentShape(Rectangle())
              .onTapGesture { pick(index) }
          }
        }
      }
      .frame(minHeight: 240, maxHeight: 420)
    }
    .font(font)
    .frame(minWidth: 460)
    .background(look == .irc ? irc.sidebar : Color.clear)
    .preferredColorScheme(look == .irc ? .dark : nil)
    .onChange(of: query) {
      highlighted = 0
      linkFailure = nil
    }
  }

  private func row(_ match: (session: InstanceSession, room: SidebarRoom), highlighted: Bool) -> some View {
    HStack(spacing: Spacing.md) {
      if look == .irc {
        Text(match.room.room.isDirect ? "@" : "#").foregroundStyle(irc.dim)
      } else {
        Image(systemName: match.room.room.symbol).foregroundStyle(.secondary).frame(width: PaneGrid.iconColumn)
      }
      Text(match.session.title(of: match.room.room)).fontWeight(match.session.isMarkedUnread(match.room) ? .semibold : .regular)
      Spacer()
      Text(match.session.name).foregroundStyle(.secondary)
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.sm)
    .background(highlighted ? (look == .irc ? irc.ember.opacity(0.22) : Color.accentColor.opacity(0.18)) : Color.clear)
  }

  /** Whether what's typed is a link, such as a pasted permalink, which Return opens. */
  private var isLink: Bool { query.contains("://") }

  private func pick(_ index: Int) {
    if isLink {
      if app.openLink(query) {
        dismiss()
      } else {
        linkFailure = "No server here opens that link."
      }
      return
    }
    let list = matches
    guard list.indices.contains(index) else { return }
    app.open(list[index].room.id, in: list[index].session)
    dismiss()
  }
}

extension Room {
  /** The SF Symbol the Suite theme shows a room by: Ember's room icon isn't an SF Symbol, so by its kind. */
  var symbol: String {
    switch kind {
    case .open: "number"
    case .closed: "lock"
    case .direct: (members?.count ?? 0) > 2 ? "person.2" : "person"
    }
  }
}
