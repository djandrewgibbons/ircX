import EmberKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/** Signing in to an instance: with an email address and password, a sign-in link from your profile, or just a name where guests may. */
struct IRCSignInView: View {
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
