import AppCoreUI
import EmberKit
import SwiftUI

/** Signing in to a server under the Suite theme: a stock grouped form. */
struct SuiteSignInView: View {
  let app: AppModel
  let session: InstanceSession
  @State private var method = SignInMethod.password
  @State private var email = ""
  @State private var password = ""
  @State private var name = ""
  @State private var link = ""
  @State private var error: String?
  @State private var busy = false

  var body: some View {
    Form {
      Section {
        LabeledContent("Server", value: session.instance.host)
        Picker("Sign In With", selection: $method) {
          ForEach(SignInMethod.offered(guests: session.bootstrap?.guestSignIn == true)) { Text($0.title).tag($0) }
        }
      } header: {
        Text(session.bootstrap?.account.name ?? session.name).font(DesignFont.title)
      }
      Section {
        switch method {
        case .password:
          TextField("Email", text: $email)
            .textContentTypeEmail()
          SecureField("Password", text: $password)
            .onSubmit(go)
        case .link:
          TextField("Sign-In Link", text: $link)
            .help("Copy it from under the QR code on your profile on the web.")
        case .guest:
          TextField("Name", text: $name)
        }
      }
      .autocorrectionDisabled()
      if let error {
        Notice(error, systemImage: "exclamationmark.triangle.fill", tint: SemanticColor.warning)
      }
      Section {
        HStack {
          Button("Remove Server", systemImage: "trash", role: .destructive) { Task { await app.remove(session) } }
            .buttonStyle(.glass)
          Spacer()
          Button("Sign In", systemImage: "arrow.right.circle", action: go)
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(busy)
        }
      }
    }
    .formStyle(.grouped)
    .loadingActivity(busy)
    .frame(maxWidth: 520)
    .frame(maxWidth: .infinity)
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

/** The ways a server lets people sign in, as both themes offer them. */
enum SignInMethod: String, CaseIterable, Identifiable {
  case password, link, guest

  var id: String { rawValue }

  var title: String {
    switch self {
    case .password: "Password"
    case .link: "Sign-In Link"
    case .guest: "Just a Name"
    }
  }

  static func offered(guests: Bool) -> [SignInMethod] {
    guests ? allCases : [.password, .link]
  }
}

extension View {
  func textContentTypeEmail() -> some View {
    #if os(iOS)
    self.textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
    #else
    self.textContentType(.username)
    #endif
  }
}
