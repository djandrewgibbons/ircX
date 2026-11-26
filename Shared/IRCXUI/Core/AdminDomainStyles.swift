import AppCoreUI
import EmberKit
import SwiftUI

// Server Settings' Domain and Styles pages (web `custom-domain-settings.tsx`, `custom-styles-page.tsx`).

// MARK: - Domain

/**
 * Domain settings (web `CustomDomainSettings`): Ember's address, the addresses it moved away from with a
 * check each, Use, Go back, Stop using it, and the steps to a custom domain.
 */
struct DomainSettings: View {
  let app: AppModel
  let session: InstanceSession
  let admin: WorkspaceAdmin
  @State private var moving = false

  var body: some View {
    if !admin.isAdministrator {
      Section { Text(AdminText.adminsManageDomain).foregroundStyle(.secondary) }
    } else if let settings = admin.settings, let account = admin.account {
      let here = admin.here
      let hereCanBe = WorkspaceRules.isCustomDomainHost(here)
      let custom = account.customDomain
      let deployed = settings.addresses.deployed ?? (WorkspaceRules.isHost(here) && !hereCanBe ? here : nil)
      let worker = WorkspaceRules.worker(at: deployed ?? here)
      let left = hereCanBe && custom != nil && custom != here ? here : nil
      let listed = admin.otherAddresses(settings)
      let settingUpHere = !hereCanBe && (custom == nil || custom == here)
      let move = { (domain: String) in app.move(session, to: domain) }
      Section("Custom domain") {
        if let address = custom ?? (here == deployed ? here : nil) { Text("Ember's address is \(address).") }
        ForEach(listed, id: \.self) { other in
          HStack {
            Text(admin.otherSays(other))
            Spacer()
            if other != left {
              Button("Check") { admin.checkOther(other) }
                .disabled(admin.domainCheck != nil && admin.domainCheck?.reaches == nil)
                .accessibilityLabel("Check \(other)")
            }
          }
        }
        if !listed.isEmpty {
          HStack {
            Explanation("To turn one off, remove it from \(worker ?? "the Worker") in Cloudflare.")
            OpenLinkButton(
              title: worker.map { "Open \($0)'s domains" } ?? "Open the Cloudflare dashboard", url: worker.map(AdminText.workerDomains) ?? AdminText.workersDashboard)
          }
        }
        if let check = admin.domainCheck {
          switch check.reaches {
          case nil: Explanation("Checking \(check.address)…")
          case .ember?: Explanation("\(check.address) still reaches Ember.", isWarning: true)
          case _?: Explanation("\(check.address) no longer reaches Ember.")
          }
        }
        HStack {
          if hereCanBe, custom != here {
            Button("Use \(here)") { admin.useDomain(here, move: move) }.disabled(admin.changingDomain)
          }
          if let deployed, custom != deployed, !(custom == nil && settingUpHere) {
            Button("Go Back to \(deployed)") { admin.useDomain(deployed, move: move) }.disabled(admin.changingDomain)
          }
          if deployed == nil, custom != nil {
            Button("Stop Using It") { admin.useDomain(nil, move: move) }.disabled(admin.changingDomain)
          }
          if !settingUpHere, !moving {
            Button("Move to Another Domain") { moving = true }
          }
        }
        if let refusal = admin.useRefusal { Explanation(refusal, isWarning: true) }
        if let custom, let deployed, custom != deployed {
          Explanation("If \(custom) stops working, open Domain settings at \(deployed) and go back.")
        }
      }
      if settingUpHere || moving || admin.domainToSetUp != nil {
        CustomDomainSetUp(session: session, admin: admin, worker: worker, move: move)
      }
    }
  }
}

/** What Set up found of a domain: whether it reaches Ember, and where its DNS is. */
private struct FoundDomain {
  let domain: String
  let reaches: CustomDomainReach
  let lookup: CustomDomainLookup
}

/** Set up (web `SetUp`): the domain, then Save if it reaches Ember already, or where its DNS is and the steps from there. */
private struct CustomDomainSetUp: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  let worker: String?
  let move: (String) -> Void
  @State private var typed = ""
  @State private var refusal: String?
  @State private var checking: String?
  @State private var found: FoundDomain?
  @State private var provider: DnsProvider = .cloudflare
  @State private var onCloudflare = ""
  @State private var asked = 0

  var body: some View {
    Section("Set up") {
      HStack {
        TextField("Domain", text: $typed, prompt: Text("chat.example.com"))
          .autocorrectionDisabled()
          #if os(iOS)
          .textInputAutocapitalization(.never)
          #endif
          .onSubmit(setUp)
          .onChange(of: typed) {
            asked += 1
            checking = nil
            found = nil
          }
        Button("Set Up", action: setUp).disabled(checking != nil)
      }
      // `/domain setup <host>` types its host here.
      .task(id: admin.domainToSetUp) {
        guard let host = admin.domainToSetUp else { return }
        typed = host
      }
      if let refusal { Explanation(refusal, isWarning: true) }
      if let checking { Explanation("Checking \(checking)…") }
      if let found {
        if found.reaches == .ember {
          Text("\(found.domain) already reaches Ember.")
          UseButton(admin: admin, label: "Save", domain: found.domain, move: move)
        } else {
          Picker("DNS provider", selection: $provider) {
            ForEach(DnsProvider.allCases, id: \.self) { Text(DomainSteps.providerName($0)).tag($0) }
          }
          steps(found)
        }
      }
    }
  }

  /** The host name typed as a domain on Cloudflare (`hostnameTyped`), or nil while it isn't one. */
  private var namedOnCloudflare: String? {
    guard case let .success(domain) = WorkspaceRules.domainTyped(onCloudflare) else { return nil }
    let hostname = WorkspaceRules.hostname(of: domain)
    return hostname.contains(".") ? hostname : nil
  }

  @ViewBuilder
  private func steps(_ found: FoundDomain) -> some View {
    let hostname = WorkspaceRules.hostname(of: found.domain)
    let zone = found.lookup.zone ?? WorkspaceRules.registeredGuess(hostname)
    if provider == .cloudflare {
      let from = found.lookup.provider == .cloudflare ? nil : found.lookup.provider
      if let from {
        Explanation("This moves \(zone)'s DNS to Cloudflare, which copies its records.")
        DomainStep(number: 1, text: "Open Cloudflare, choose Onboard a domain, and paste \(zone).") {
          OpenLinkButton(title: "Open Cloudflare", url: AdminText.cloudflareDomains, copying: zone)
        }
        DomainStep(number: 2, text: DomainSteps.nameserversAt(from, zone: zone)) { EmptyView() }
      }
      let opening = from != nil ? "Once Cloudflare says \(zone) is active, open Cloudflare" : "Open Cloudflare"
      let choosing = worker == nil ? ", choose the Worker that runs Ember, then Domains > Add Domain" : ", choose Add Domain"
      DomainStep(number: from != nil ? 3 : 1, text: "\(opening)\(choosing), and paste \(hostname).") {
        OpenLinkButton(title: "Open Cloudflare", url: worker.map(AdminText.workerDomains) ?? AdminText.workersDashboard, copying: hostname)
      }
      UseButton(admin: admin, label: "Use \(found.domain)", domain: found.domain, move: move)
    } else {
      let keeping = "Keeping DNS \(provider == .other ? "where it is" : "at \(DomainSteps.providerName(provider))")"
      if hostname == zone {
        Text("\(keeping) takes a name under \(zone), such as chat.\(zone). Or choose Cloudflare above to move \(zone)'s DNS there instead.")
      } else {
        Text("\(keeping) takes another domain that's already on Cloudflare.")
        TextField("Domain on Cloudflare", text: $onCloudflare, prompt: Text("example.net"))
          .autocorrectionDisabled()
          #if os(iOS)
          .textInputAutocapitalization(.never)
          #endif
        if let saas = namedOnCloudflare, saas != zone, !saas.hasSuffix(".\(zone)") {
          saasSteps(found, hostname: hostname, zone: zone, saas: saas)
        } else {
          Explanation(namedOnCloudflare == nil ? "No domain on Cloudflare? Choose Cloudflare above to move \(zone)'s DNS there instead." : "Give a domain other than \(zone).")
        }
      }
    }
  }

  /** The steps through Cloudflare for SaaS on `saas`, a domain already on Cloudflare (web `SaasSteps`). */
  @ViewBuilder
  private func saasSteps(_ found: FoundDomain, hostname: String, zone: String, saas: String) -> some View {
    let origin = "\(AdminText.saasOrigin).\(saas)"
    let label = String(hostname.dropLast(zone.count + 1))
    let everything = "\u{2A}"
    DomainStep(number: 1, text: "In Cloudflare, add this record to \(saas), proxied: AAAA \(AdminText.saasOrigin) 100::") {
      OpenLinkButton(title: "Open Cloudflare", url: AdminText.cloudflareDnsRecords)
    }
    DomainStep(
      number: 2,
      text: "Under Custom Hostnames, enable Cloudflare for SaaS (it asks for a card, but 100 domains are free), and make \(origin) the fallback origin unless it has one. Then add \(hostname) with HTTP validation."
    ) {
      OpenLinkButton(title: "Open Cloudflare", url: AdminText.cloudflareCustomHostnames, copying: origin)
    }
    DomainStep(
      number: 3,
      text: "Under Workers Routes, route \(hostname)/\(everything) to \(worker ?? "the Worker that runs Ember"), and \(hostname)/.well-known/\(everything) to None, so Cloudflare can get it a certificate."
    ) { EmptyView() }
    DomainStep(number: 4, text: "\(DomainSteps.recordAt(provider, zone: zone)) CNAME \(label) \(origin)") {
      HStack {
        Button("Copy Name") { Pasteboard.copy(label) }
        Button("Copy Value") { Pasteboard.copy(origin) }
      }
    }
    UseButton(admin: admin, label: "Use \(found.domain)", domain: found.domain, move: move)
  }

  /** Set up: checks the domain and looks up its DNS at once; failing either says no more than nothing there yet. */
  private func setUp() {
    found = nil
    switch WorkspaceRules.domainTyped(typed) {
    case let .failure(refused):
      refusal = refused.message
    case let .success(domain):
      refusal = nil
      checking = domain
      asked += 1
      let ask = asked
      Task {
        async let reach = reaches(domain)
        async let lookup = lookUp(domain)
        let answered = await (reach, lookup)
        guard ask == asked else { return }
        checking = nil
        provider = answered.1.provider ?? .cloudflare
        found = FoundDomain(domain: domain, reaches: answered.0, lookup: answered.1)
      }
    }
  }

  private func reaches(_ domain: String) async -> CustomDomainReach {
    do {
      return try await session.api.checkCustomDomain(domain)
    } catch {
      logger.error("Checking \(domain, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
      return .nothing
    }
  }

  private func lookUp(_ domain: String) async -> CustomDomainLookup {
    do {
      return try await session.api.lookUpCustomDomain(domain)
    } catch {
      logger.error("Looking up \(domain, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
      return CustomDomainLookup(zone: nil, provider: nil)
    }
  }
}

/** A numbered step, with what it opens or copies. */
private struct DomainStep<Accessory: View>: View {
  let number: Int
  let text: String
  @ViewBuilder var accessory: () -> Accessory

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text("\(number). \(text)").textSelection(.enabled)
      accessory()
    }
  }
}

/** Use: makes the domain Ember's address and goes there, or says why not. */
private struct UseButton: View {
  let admin: WorkspaceAdmin
  let label: String
  let domain: String
  let move: (String) -> Void

  var body: some View {
    HStack {
      Button(label) { admin.useDomain(domain, move: move) }.disabled(admin.changingDomain)
      Explanation(AdminText.signsInAgain)
    }
  }
}

/** Where each provider keeps nameservers and records, in the words of its own help (web `NAMESERVERS_AT`, `RECORD_AT`). */
enum DomainSteps {
  static func providerName(_ provider: DnsProvider) -> String {
    switch provider {
    case .cloudflare: "Cloudflare"
    case .godaddy: "GoDaddy"
    case .namecheap: "Namecheap"
    case .squarespace: "Squarespace"
    case .porkbun: "Porkbun"
    case .route53: "Amazon Route 53"
    case .hover: "Hover"
    case .ionos: "IONOS"
    case .other: "Another provider"
    }
  }

  static func nameserversAt(_ provider: DnsProvider, zone: String) -> String {
    switch provider {
    case .godaddy:
      "At GoDaddy, open Domain Portfolio, choose \(zone), then DNS > Nameservers. Choose I'll use my own nameservers and enter Cloudflare's two nameservers."
    case .namecheap:
      "At Namecheap, open Domain List and choose Manage beside \(zone). Under Nameservers, choose Custom DNS, enter Cloudflare's two nameservers, and save with the check mark."
    case .squarespace:
      "At Squarespace, open Domains, choose \(zone), then DNS > Domain Nameservers > Use Custom Nameservers, and enter Cloudflare's two nameservers."
    case .porkbun: "At Porkbun, open Domain Management, then Details beside \(zone), and edit Nameservers. Replace them with Cloudflare's two."
    case .route53:
      "Where you registered \(zone), replace its nameservers with Cloudflare's two. If that's Route 53, open Registered domains in its console, choose \(zone), then Actions > Edit name servers."
    case .hover: "At Hover, choose \(zone), then Edit beside Nameservers, and enter Cloudflare's two nameservers."
    case .ionos: "At IONOS, choose the gear beside \(zone) under Actions, then Name Server > Use Custom Name Servers, and enter Cloudflare's two nameservers."
    case .other, .cloudflare: "Where you registered \(zone), replace its nameservers with Cloudflare's two."
    }
  }

  static func recordAt(_ provider: DnsProvider, zone: String) -> String {
    switch provider {
    case .godaddy: "At GoDaddy, open Domain Portfolio, choose \(zone), then DNS > Add New Record:"
    case .namecheap: "At Namecheap, open Domain List and choose Manage beside \(zone). Under Advanced DNS, choose Add New Record:"
    case .squarespace: "At Squarespace, open Domains, choose \(zone), then DNS Settings, and under Custom records, Add record:"
    case .porkbun: "At Porkbun, open Domain Management, then DNS beside \(zone), and add:"
    case .route53: "In Route 53's console, open Hosted zones, choose \(zone), then Create record:"
    case .hover: "At Hover, choose \(zone), then DNS > Add a record:"
    case .ionos: "At IONOS, choose the gear beside \(zone) under Actions, then DNS > Add record:"
    case .other, .cloudflare: "Where \(zone)'s DNS is, add:"
    }
  }
}

// MARK: - Styles

/** Custom styles (web `CustomStylesPage`): the navigation icons, then the custom CSS, which ircX's own chrome doesn't apply. */
struct StylesSettings: View {
  let session: InstanceSession
  let admin: WorkspaceAdmin
  @State private var choosing: NavigationSlot?
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    if !admin.isAdministrator {
      Section { Text("Only administrators can change the workspace").foregroundStyle(.secondary) }
    } else if let account = admin.account {
      Section {
        ForEach(NavigationSlot.allCases) { slot in
          HStack {
            CatalogIconView(api: session.api, name: admin.icon(slot))
            Text(slot.label)
            Spacer()
            Button("Choose") { choosing = slot }.accessibilityLabel("Choose \(slot.label) icon")
          }
        }
        Button(admin.savingIcons ? "Saving…" : "Save Changes", action: admin.saveIcons).disabled(admin.iconDraft.isEmpty || admin.savingIcons)
      } header: {
        Text("Navigation icons").help(AdminText.navigationIconsExplained)
      }
      .sheet(item: $choosing) { slot in
        NavigationIconPicker(api: session.api, slot: slot, current: admin.icon(slot)) { admin.choose($0, for: slot) }
          .environment(\.appTheme, look)
      }
      Section {
        Group {
          let styles = Binding(get: { admin.shownStyles(account) }, set: { admin.typedStyles = $0 })
          switch look {
          case .suite: PromptEditor("Custom CSS", text: styles, monospaced: true, minHeight: 240, maxHeight: 480)
          case .irc: TextEditor(text: styles).font(Theme.font(12)).scrollContentBackground(.hidden).background(irc.input).frame(minHeight: 240)
          }
        }
        .autocorrectionDisabled()
        .task { await admin.loadStyles() }
        if let refusal = admin.stylesRefusal { Explanation(refusal, isWarning: true) }
        Button(admin.savingStyles ? "Saving…" : "Save Changes", action: admin.saveStyles)
          .disabled(admin.savingStyles || admin.typedStyles == nil)
          .keyboardShortcut(.return, modifiers: .command)
      } header: {
        Text("Custom CSS").help("Add custom CSS styles. \(AdminText.customStylesCaution)")
      } footer: {
        Explanation(AdminText.customStylesCaution, isWarning: true)
      }
    }
  }
}

extension NavigationSlot: Identifiable {
  public var id: String { rawValue }

  /** `SLOT_LABELS` */
  var label: String {
    switch self {
    case .home: "Home"
    case .dms: "DMs"
    case .activity: "Activity"
    case .search: "Search"
    case .admin: "Admin"
    case .light: "Light mode"
    case .dark: "Dark mode"
    case .system: "System appearance"
    }
  }
}

/**
 * The icon picker for a navigation slot (web `IconDialog` in its navigation context): the catalog in its
 * navigation order, the recommendations first, in All, Lucide and Iconoir tabs, searched by name then tag,
 * and Default icon.
 */
private struct NavigationIconPicker: View {
  let api: EmberAPI
  let slot: NavigationSlot
  let current: String
  let choose: (String?) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  var body: some View {
    switch look {
    case .suite:
      SheetFrame(title: "Choose a navigation icon", systemImage: "square.grid.2x2", onClose: { dismiss() }) {
        IconCatalogGrid(api: api, context: .navigation, current: current, choose: { picked in
          choose(picked)
          dismiss()
        }, defaultLabel: "Default Icon")
      }
      .frame(minWidth: 420, minHeight: 520)
      .suiteTheme(.ircX)
    case .irc:
      NavigationStack {
        IconCatalogGrid(api: api, context: .navigation, current: current, choose: { picked in
          choose(picked)
          dismiss()
        }, defaultLabel: "[default icon]")
        .padding(Spacing.lg)
        .background(irc.buffer)
        .navigationTitle("\(slot.label) icon")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
      }
      .frame(minWidth: 420, minHeight: 520)
      .preferredColorScheme(.dark)
      .tint(irc.ember)
    }
  }
}
