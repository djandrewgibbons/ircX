import EmberKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/** Signing in to an instance: with an email address and password, a sign-in link from your profile, or just a name where guests may. */
struct SignInView: View {
  let app: AppModel
  let session: InstanceSession
  @Environment(\.theme) private var theme
  @State private var method = Method.password
  @State private var email = ""
  @State private var password = ""
  @State private var name = ""
  @State private var link = ""
  @State private var error: String?
  @State private var busy = false

  enum Method: String, CaseIterable, Identifiable {
    case password = "Password"
    case link = "Sign-in link"
    case guest = "Just a name"
    var id: String { rawValue }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("*** Connecting to \(session.instance.host)").foregroundStyle(theme.dim)
          Text("*** \(session.bootstrap?.account.name ?? session.name)").font(Theme.font(20, weight: .bold)).foregroundStyle(theme.ember)
          if let tagline = session.bootstrap?.account.tagline, !tagline.isEmpty {
            Text("*** \(tagline)").foregroundStyle(theme.dim)
          }
        }
        Picker("Sign in with", selection: $method) {
          ForEach(methods) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Group {
          switch method {
          case .password:
            field("email", text: $email, content: .emailAddress)
            SecureField("password", text: $password).onSubmit(go)
          case .link:
            Text("On the web, open your profile and copy the sign-in link under its QR code.").foregroundStyle(theme.dim)
            field("https://\(session.instance.host)/session/transfers#token=…", text: $link, content: .URL)
          case .guest:
            field("nick", text: $name, content: .nickname)
          }
        }
        .textFieldStyle(.roundedBorder)

        if let error {
          Text("-!- \(error)").foregroundStyle(theme.part)
        }
        HStack {
          Button(action: go) {
            Text(busy ? "Signing in…" : "/connect").frame(minWidth: 120)
          }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(busy)
          Spacer()
          Button("Remove server", role: .destructive) { Task { await app.remove(session) } }
            .buttonStyle(.borderless)
        }
        if session.bootstrap?.signInWithMemberful == true {
          Text("This server signs members in with Memberful, which ircX can't do yet: use a sign-in link from your profile on the web.")
            .foregroundStyle(theme.dim)
        }
      }
      .font(Theme.font(13))
      .padding(28)
      .frame(maxWidth: 480)
      .frame(maxWidth: .infinity)
    }
    .background(theme.buffer)
  }

  private var methods: [Method] {
    session.bootstrap?.guestSignIn == true ? Method.allCases : [.password, .link]
  }

  private func field(_ prompt: String, text: Binding<String>, content: TextContent) -> some View {
    TextField(prompt, text: text)
      .autocorrectionDisabled()
      .onSubmit(go)
      #if os(iOS)
      .textInputAutocapitalization(.never)
      .textContentType(content.ios)
      .keyboardType(content == .emailAddress ? .emailAddress : content == .URL ? .URL : .default)
      #endif
  }

  enum TextContent {
    case emailAddress, URL, nickname
    #if os(iOS)
    var ios: UITextContentType {
      switch self {
      case .emailAddress: .emailAddress
      case .URL: .URL
      case .nickname: .nickname
      }
    }
    #endif
  }

  private func go() {
    busy = true
    error = nil
    Task {
      defer { busy = false }
      do {
        switch method {
        case .password: try await session.signIn(emailAddress: email.trimmingCharacters(in: .whitespaces), password: password)
        case .link: try await session.signIn(transferLink: link)
        case .guest: try await session.signIn(name: name)
        }
        password = ""
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/** /server: adding an instance by its address. */
struct AddInstanceView: View {
  let app: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var address = ""
  @State private var checking = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("/server").font(Theme.font(18, weight: .bold)).foregroundStyle(theme.ember)
      Text("The address of an Ember instance, such as irc.dxnd.ai or chat.example.com.").foregroundStyle(theme.dim)
      TextField("irc.dxnd.ai", text: $address)
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.URL)
        #endif
        .onSubmit(add)
      if let error { Text("-!- \(error)").foregroundStyle(theme.part) }
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
    .background(theme.buffer)
    .preferredColorScheme(.dark)
  }

  private func add() {
    guard let url = Instance.baseURL(from: address) else {
      error = "That isn't an address."
      return
    }
    checking = true
    Task {
      defer { checking = false }
      // Check it's Ember before keeping it.
      do {
        _ = try await EmberAPI(instance: Instance(baseURL: url), tokens: MemoryTokenStore()).bootstrap()
        app.addInstance(at: url)
        dismiss()
      } catch {
        self.error = "\(url.host() ?? address): \(error.localizedDescription)"
      }
    }
  }
}

/** ⌘K: jump to any room on any instance, as Slack's switcher does. */
struct QuickSwitcher: View {
  let app: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var query = ""
  @State private var highlighted = 0

  private var matches: [(session: InstanceSession, room: SidebarRoom)] {
    let all = app.allRooms.sorted { a, b in a.room.unread && !b.room.unread }
    guard !query.isEmpty else { return Array(all.prefix(30)) }
    let q = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#@ "))
    return all.filter { $0.session.title(of: $0.room.room).lowercased().contains(q) || $0.session.name.lowercased().contains(q) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("/window").foregroundStyle(theme.ember)
        TextField("goto…", text: $query)
          .textFieldStyle(.plain)
          .onSubmit { pick(highlighted) }
          #if os(macOS)
          .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(matches.count - 1, 0)); return .handled }
          .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
          #endif
      }
      .padding(14)
      Divider().overlay(theme.faint)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
            HStack {
              Text(match.room.room.isDirect ? "@" : "#").foregroundStyle(theme.dim)
              Text(match.session.title(of: match.room.room)).fontWeight(match.room.unread ? .bold : .regular)
              Spacer()
              Text(match.session.name).foregroundStyle(theme.dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(index == highlighted ? theme.ember.opacity(0.22) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { pick(index) }
          }
        }
      }
      .frame(minHeight: 240, maxHeight: 420)
    }
    .font(Theme.font(13))
    .frame(minWidth: 460)
    .background(theme.sidebar)
    .preferredColorScheme(.dark)
    .onChange(of: query) { highlighted = 0 }
  }

  private func pick(_ index: Int) {
    let list = matches
    guard list.indices.contains(index) else { return }
    app.open(list[index].room.id, in: list[index].session)
    dismiss()
  }
}
