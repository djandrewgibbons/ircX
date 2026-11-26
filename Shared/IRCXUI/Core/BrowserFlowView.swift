import AppCoreUI
import EmberKit
import SwiftUI
import WebKit

// The flows Ember keeps in a browser's cookies, which ircX runs in a web view of its own with nothing
// kept after it closes: Memberful and single sign-on, connecting either to a profile, an app's own
// sign-in, and Turnstile's check. ircX watches where the web view goes and finishes natively once it
// reaches an Ember page, reading the session from the web view's cookies.

/** A browser-held flow to run: where it starts, and the cookies it needs before it does. */
struct BrowserFlowRequest: Identifiable {
  let id = UUID()
  let title: String
  let start: URL
  /** Cookies Ember set in a native answer, such as the OAuth state its callback checks. */
  var cookies: [StateCookie] = []
  /** The session to carry in, for a flow that connects an account to the person signed in. */
  var sessionToken: String?
}

/** How a browser-held flow ended: at an Ember page, with the session the web view then held, or canceled. */
enum BrowserFlowOutcome {
  case ended(BrowserFlowEnd, sessionToken: String?)
  case canceled
}

/** The web view sheet a flow runs in, with Cancel, in either theme. */
struct BrowserFlowSheet: View {
  let request: BrowserFlowRequest
  let instance: Instance
  /** The workspace's custom domain, where callbacks may come back to. */
  let customDomain: String?
  let finish: (BrowserFlowOutcome) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var loading = true

  private var hosts: Set<String> {
    var hosts: Set<String> = [instance.host.lowercased()]
    if let customDomain { hosts.insert(customDomain.lowercased()) }
    return hosts
  }

  var body: some View {
    NavigationStack {
      BrowserFlowWebView(request: request, instance: instance, hosts: hosts, loading: $loading) { outcome in
        dismiss()
        finish(outcome)
      }
      .loadingActivity(loading)
      .navigationTitle(request.title)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
            finish(.canceled)
          }
        }
      }
    }
    .frame(minWidth: 520, minHeight: 640)
  }
}

#if os(macOS)
typealias WebViewRepresentable = NSViewRepresentable
#else
typealias WebViewRepresentable = UIViewRepresentable
#endif

/** The web view itself, with no persistent store, which ends the flow at an Ember page. */
struct BrowserFlowWebView: WebViewRepresentable {
  let request: BrowserFlowRequest
  let instance: Instance
  let hosts: Set<String>
  @Binding var loading: Bool
  let finish: (BrowserFlowOutcome) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  #if os(macOS)
  func makeNSView(context: Context) -> WKWebView { makeWebView(context) }
  func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
  #else
  func makeUIView(context: Context) -> WKWebView { makeWebView(context) }
  func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
  #endif

  private func makeWebView(_ context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    context.coordinator.begin(view)
    return view
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {
    var parent: BrowserFlowWebView
    private var ended = false

    init(_ parent: BrowserFlowWebView) {
      self.parent = parent
    }

    /** Seeds the cookies the flow needs, then loads its first page. */
    func begin(_ view: WKWebView) {
      let parent = parent
      Task {
        let store = view.configuration.websiteDataStore.httpCookieStore
        var cookies = parent.request.cookies
        if let token = parent.request.sessionToken {
          cookies.append(StateCookie(name: parent.instance.isSecure ? "__Host-session_token" : "session_token", value: token, secure: parent.instance.isSecure, httpOnly: true))
        }
        for host in parent.hosts {
          for cookie in cookies {
            guard let made = Self.cookie(cookie, host: host, secure: parent.instance.isSecure) else {
              logger.error("A sign-in cookie for \(host, privacy: .public) couldn't be made")
              continue
            }
            await store.setCookie(made)
          }
        }
        view.load(URLRequest(url: parent.request.start))
      }
    }

    static func cookie(_ cookie: StateCookie, host: String, secure: Bool) -> HTTPCookie? {
      var properties: [HTTPCookiePropertyKey: Any] = [.name: cookie.name, .value: cookie.value, .path: cookie.path, .domain: host]
      if cookie.secure || secure { properties[.secure] = "TRUE" }
      if cookie.httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
      if let maxAge = cookie.maxAge { properties[.maximumAge] = String(maxAge) }
      return HTTPCookie(properties: properties)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
      guard !ended, let url = navigationAction.request.url, let end = BrowserFlow.end(of: url, hosts: parent.hosts) else { return .allow }
      ended = true
      let token = await sessionToken(in: webView)
      parent.finish(.ended(end, sessionToken: token))
      return .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.loading = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      parent.loading = false
      // A navigation the flow canceled itself isn't a failure.
      guard !ended else { return }
      logger.error("A sign-in page didn't load: \(error.localizedDescription, privacy: .public)")
    }

    /** The session cookie the flow left, which a redirect's `Set-Cookie` may store a moment after its navigation starts. */
    private func sessionToken(in webView: WKWebView) async -> String? {
      let names: Set<String> = ["__Host-session_token", "session_token"]
      for attempt in 0..<10 {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        if let found = cookies.first(where: { names.contains($0.name) && parent.hosts.contains($0.domain.lowercased()) && !$0.value.isEmpty }) {
          return found.value
        }
        if attempt < 9 { try? await Task.sleep(for: .milliseconds(100)) }
      }
      return nil
    }
  }
}

/**
 * Turnstile's check (the Worker's `/account/turnstile_check` page), which sends its token, its expiry or
 * its failure with `postMessage`: the token goes in the form, good for one try (web `TurnstileCheck`).
 */
struct TurnstileCheck: View {
  let instance: Instance
  let siteKey: String
  @Binding var token: String?
  /** Changing it draws a new check, as each try spends the token. */
  let attempt: Int
  /** Hears why the check failed, its error code or that it didn't load, in place of the line it shows otherwise. */
  var onProblem: ((_ code: String?, _ unavailable: Bool) -> Void)?
  @Environment(\.colorScheme) private var colorScheme
  @State private var problem: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      TurnstileWebView(page: page, token: $token, problem: $problem, onProblem: onProblem)
        .id("\(attempt)-\(colorScheme == .dark)")
        .frame(height: 72)
      if let problem { Text(problem).font(DesignFont.detail).foregroundStyle(SemanticColor.warning) }
    }
  }

  private var page: URL {
    var parts = URLComponents(url: instance.baseURL, resolvingAgainstBaseURL: false)
    parts?.path = Pages.turnstileCheckPath
    parts?.fragment = "site_key=\(URIComponent.encode(siteKey))&theme=\(colorScheme == .dark ? "dark" : "light")&size=flexible"
    guard let url = parts?.url else { preconditionFailure("Unaddressable Turnstile check") }
    return url
  }
}

private struct TurnstileWebView: WebViewRepresentable {
  let page: URL
  @Binding var token: String?
  @Binding var problem: String?
  let onProblem: ((_ code: String?, _ unavailable: Bool) -> Void)?

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  #if os(macOS)
  func makeNSView(context: Context) -> WKWebView { make(context) }
  func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
  #else
  func makeUIView(context: Context) -> WKWebView { make(context) }
  func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
  #endif

  private func make(_ context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let forward = """
      window.addEventListener("message", function (event) {
        if (event.origin === location.origin && event.data && event.data.turnstileCheck) {
          window.webkit.messageHandlers.turnstile.postMessage(JSON.stringify(event.data.turnstileCheck));
        }
      });
      """
    configuration.userContentController.addUserScript(WKUserScript(source: forward, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    configuration.userContentController.add(context.coordinator, name: "turnstile")
    let view = WKWebView(frame: .zero, configuration: configuration)
    token = nil
    view.load(URLRequest(url: page))
    return view
  }

  @MainActor
  final class Coordinator: NSObject, WKScriptMessageHandler {
    var parent: TurnstileWebView

    init(_ parent: TurnstileWebView) {
      self.parent = parent
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
      struct Check: Decodable {
        let token: String?
        let expired: Bool?
        let error: String?
        let unavailable: Bool?
      }
      guard let text = message.body as? String else {
        logger.error("Turnstile's check sent something that wasn't text")
        return
      }
      let check: Check
      do {
        check = try JSONDecoder().decode(Check.self, from: Data(text.utf8))
      } catch {
        logger.error("Turnstile's check sent something unreadable: \(error.localizedDescription, privacy: .public)")
        parent.problem = EmberText.turnstileFailed
        return
      }
      if let token = check.token {
        parent.token = token
        parent.problem = nil
      } else {
        parent.token = nil
        if check.error != nil || check.unavailable == true {
          logger.error("Turnstile's check failed: \(check.error ?? "unavailable", privacy: .public)")
          if let onProblem = parent.onProblem {
            onProblem(check.error, check.unavailable == true)
          } else {
            parent.problem = EmberText.turnstileFailed
          }
        }
      }
    }
  }
}
