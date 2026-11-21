import AppCoreUI
import EmberKit
import SwiftUI

/**
 * Signing in to a server under the Suite theme (web `SignInPage`): a grouped form offering what the server
 * offers, Memberful and single sign-on, and the ways to join or reset a password it links to.
 */
struct SuiteSignInView: View {
  let app: AppModel
  let session: InstanceSession

  var body: some View {
    SuiteSignInForm(app: app, form: session.signInForm)
  }
}

private struct SuiteSignInForm: View {
  let app: AppModel
  @Bindable var form: SignInModel

  var body: some View {
    Form {
      Section {
        LabeledContent("Server", value: form.session.instance.host)
        if form.onlyElsewhere == nil {
          Picker("Sign In With", selection: $form.method) {
            ForEach(form.methods) { Text($0.title).tag($0) }
          }
        }
      } header: {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(PeopleText.signInTo(form.workspace)).font(DesignFont.title)
          Text(PeopleText.welcomeBack).font(DesignFont.body).foregroundStyle(.secondary)
        }
      }
      if let notice = form.notice {
        Notice(notice, systemImage: "checkmark.circle.fill", tint: SemanticColor.positive, onDismiss: { form.notice = nil })
      }
      if let unreachable = form.unreachable {
        Notice(unreachable, systemImage: "wifi.exclamationmark", tint: SemanticColor.warning, onDismiss: { form.unreachable = nil })
      }
      if let only = form.onlyElsewhere {
        Section {
          Button("Sign in with \(only.name)", systemImage: "person.badge.key") { form.signInElsewhere(memberful: only.memberful) }
            .buttonStyle(.glassProminent)
          Button("Have a password? Sign in with a password") { form.showsPasswordForm = true }
            .buttonStyle(.borderless)
        }
      } else {
        Section { fields }
          .autocorrectionDisabled()
      }
      if let problem = form.problem {
        Notice(problem, systemImage: "exclamationmark.triangle.fill", tint: SemanticColor.warning)
      }
      if let elsewhere = form.elsewhere {
        Section {
          ForEach(elsewhere.connection.connections(ssoName: form.ssoName), id: \.url) { connection in
            Button("Connect \(connection.name)") { form.connect(connection.url, name: connection.name) }
              .buttonStyle(.glassProminent)
          }
        }
      }
      Section {
        if form.onlyElsewhere == nil {
          HStack {
            Button("Remove Server", systemImage: "trash", role: .destructive) { Task { await app.remove(form.session) } }
              .buttonStyle(.glass)
            Spacer()
            Button("Sign In", systemImage: "arrow.right.circle", action: form.signIn)
              .buttonStyle(.glassProminent)
              .keyboardShortcut(.defaultAction)
              .disabled(form.busy)
          }
        }
        links
      }
    }
    .formStyle(.grouped)
    .loadingActivity(form.busy)
    .frame(maxWidth: 520)
    .frame(maxWidth: .infinity)
    .signInSheets(form)
  }

  @ViewBuilder
  private var fields: some View {
    switch form.method {
    case .password:
      HStack {
        TextField("Email", text: $form.email).textContentTypeEmail()
        TranslationButton(key: "email_address", account: form.account)
      }
      HStack {
        SecureField("Password", text: $form.password)
          .textContentType(.password)
          .onSubmit(form.signIn)
          .onChange(of: form.password) { _, typed in
            let capped = EmberRules.capped(password: typed)
            if capped != typed { form.password = capped }
          }
        TranslationButton(key: "password", account: form.account)
      }
    case .link:
      TextField("Sign-In Link", text: $form.link)
        .help("Copy it from under the QR code on your profile on the web.")
        .onSubmit(form.signIn)
    case .guest:
      TextField("Name", text: $form.name)
        .textContentType(.name)
        .help("Pick the name people will see next to your messages.")
        .onSubmit(form.signIn)
    }
  }

  @ViewBuilder
  private var links: some View {
    ForEach(form.otherElsewhere, id: \.title) { link in
      Button(link.title) { form.signInElsewhere(memberful: link.memberful) }.buttonStyle(.borderless)
    }
    if form.offersReset {
      Button("Forgot your password? Reset it", action: form.openReset).buttonStyle(.borderless)
    }
    if form.offersSignUp {
      Button("New here? Create an account", action: form.openSignUp).buttonStyle(.borderless)
    } else if form.offersEmailSignUp {
      Button(PeopleText.joinWithDomain(form.emailDomains), action: form.openEmailSignUp).buttonStyle(.borderless)
    }
    if let back = form.backToElsewhere {
      Button(back) { form.showsPasswordForm = false }.buttonStyle(.borderless).disabled(form.busy)
    }
  }
}

extension View {
  func textContentTypeEmail() -> some View {
    #if os(iOS)
    self.textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never)
    #else
    self.textContentType(.username)
    #endif
  }
}
