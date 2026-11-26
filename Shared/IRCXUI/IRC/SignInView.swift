import EmberKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/**
 * Signing in to an instance under IRC Classic, as the web's sign-in page offers it: an email address and
 * password, a sign-in link, just a name where guests may, Memberful and single sign-on (`/connect sso`),
 * and `/register`, `/join-email` and `/reset` where the server lets people join or reset a password.
 */
struct IRCSignInView: View {
  let app: AppModel
  let session: InstanceSession

  var body: some View {
    IRCSignInForm(app: app, form: session.signInForm)
  }
}

private struct IRCSignInForm: View {
  let app: AppModel
  @Bindable var form: SignInModel
  @Environment(\.theme) private var theme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("*** Connecting to \(form.session.instance.host)").foregroundStyle(theme.dim)
          Text("*** \(PeopleText.signInTo(form.workspace))").font(Theme.font(20, weight: .bold)).foregroundStyle(theme.ember)
          if let tagline = form.account?.tagline, !tagline.isEmpty {
            Text("*** \(tagline)").foregroundStyle(theme.dim)
          }
        }
        if let notice = form.notice { Text("-!- \(notice)").foregroundStyle(theme.join) }
        if let unreachable = form.unreachable { Text("-!- \(unreachable)").foregroundStyle(theme.part) }

        if let only = form.onlyElsewhere {
          Button {
            form.signInElsewhere(memberful: only.memberful)
          } label: {
            Text("/connect \(only.memberful ? "memberful" : "sso")").frame(minWidth: 160)
          }
          .buttonStyle(.borderedProminent)
          .help("Sign in with \(only.name)")
          command("Have a password? Sign in with a password") { form.showsPasswordForm = true }
        } else {
          Picker("Sign in with", selection: $form.method) {
            ForEach(form.methods) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          fields.textFieldStyle(.roundedBorder)
        }

        if let problem = form.problem {
          Text("-!- \(problem)").foregroundStyle(theme.part)
        }
        if let elsewhere = form.elsewhere {
          ForEach(elsewhere.connection.connections(ssoName: form.ssoName), id: \.url) { connection in
            command("/connect \(connection.name)") { form.connect(connection.url, name: connection.name) }
          }
        }
        if form.onlyElsewhere == nil {
          HStack {
            Button(action: form.signIn) {
              Text(form.busy ? "Signing in…" : "/connect").frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(form.busy)
            Spacer()
            Button("Remove server", role: .destructive) { Task { await app.remove(form.session) } }
              .buttonStyle(.borderless)
          }
        }
        VStack(alignment: .leading, spacing: 6) {
          ForEach(form.otherElsewhere, id: \.title) { link in
            command("/connect \(link.memberful ? "memberful" : "sso")", help: link.title) { form.signInElsewhere(memberful: link.memberful) }
          }
          if form.offersReset { command("/reset", help: "Forgot your password? Reset it", action: form.openReset) }
          if let back = form.backToElsewhere {
            command("/connect", help: back) { form.showsPasswordForm = false }.disabled(form.busy)
          }
          if form.offersSignUp {
            command("/register", help: "New here? Create an account", action: form.openSignUp)
          } else if form.offersEmailSignUp {
            command("/join-email", help: PeopleText.joinWithDomain(form.emailDomains), action: form.openEmailSignUp)
          }
        }
      }
      .font(Theme.font(13))
      .padding(28)
      .frame(maxWidth: 480)
      .frame(maxWidth: .infinity)
    }
    .background(theme.buffer)
    .signInSheets(form)
  }

  @ViewBuilder
  private var fields: some View {
    switch form.method {
    case .password:
      HStack {
        field("email", text: $form.email, content: .emailAddress).textContentTypeEmail()
        TranslationButton(key: "email_address", account: form.account, classic: true)
      }
      HStack {
        SecureField("password", text: $form.password)
          .textContentType(.password)
          .onSubmit(form.signIn)
          .onChange(of: form.password) { _, typed in
            let capped = EmberRules.capped(password: typed)
            if capped != typed { form.password = capped }
          }
        TranslationButton(key: "password", account: form.account, classic: true)
      }
    case .link:
      Text("On the web, open your profile and copy the sign-in link under its QR code.").foregroundStyle(theme.dim)
      field("https://\(form.session.instance.host)/session/transfers#token=…", text: $form.link, content: .URL)
    case .guest:
      Text("Pick the name people will see next to your messages.").foregroundStyle(theme.dim)
      field("nick", text: $form.name, content: .nickname)
    }
  }

  /** A link written as the command it is, with what it does beside it. */
  private func command(_ name: String, help: String? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Text(name).foregroundStyle(theme.ember)
        if let help { Text(help).foregroundStyle(theme.dim) }
      }
    }
    .buttonStyle(.plain)
    .help(help ?? name)
  }

  private func field(_ prompt: String, text: Binding<String>, content: TextContent) -> some View {
    TextField(prompt, text: text)
      .autocorrectionDisabled()
      .onSubmit(form.signIn)
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
}
