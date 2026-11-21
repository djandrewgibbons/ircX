import AppCoreUI
import EmberKit
import SwiftUI

/**
 * First run's last step (web `SetupHuddles`): whether to turn on audio and video chat, then the same two
 * steps Server Settings' Set up huddles has, then that huddles are on, before Ember opens.
 */
struct FirstRunHuddles: View {
  enum Step { case question, steps, on }

  let session: InstanceSession
  let open: () -> Void
  @State private var step: Step = .question
  @State private var keys: CloudflareKeysModel
  @State private var problem: String?
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc

  init(session: InstanceSession, open: @escaping () -> Void) {
    self.session = session
    self.open = open
    _keys = State(initialValue: CloudflareKeysModel(session: session, kind: .huddles, huddles: nil))
  }

  var body: some View {
    Form {
      switch step {
      case .question: question
      case .steps: steps
      case .on: on
      }
    }
    .themedForm(look, irc)
    .onChange(of: keys.done) { _, done in if done { step = .on } }
    .task {
      // The account Ember is deployed to, for the dashboard's link, as far as Ember says (web: best effort).
      do {
        keys.accountId = try await session.api.workspaceSettings().cloudflareAccountId
      } catch {
        logger.error("Reading the deployed Cloudflare account failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private var titleFont: Font { look == .irc ? Theme.font(16, weight: .bold) : DesignFont.title }

  @ViewBuilder
  private var question: some View {
    Section {
      Text(AIText.firstRunQuestion).font(titleFont)
      Text(AIText.firstRunSubtitle).foregroundStyle(.secondary)
      ForEach(AIText.firstRunFacts, id: \.label) { fact in
        LabeledContent(fact.label) { Text(fact.text).multilineTextAlignment(.trailing) }
      }
      Explanation(AIText.firstRunLater)
      HStack {
        Button("Not Now", action: open)
        Spacer()
        Button("Set Up Huddles", systemImage: "arrow.right") { step = .steps }.buttonStyle(.borderedProminent)
      }
    }
  }

  @ViewBuilder
  private var steps: some View {
    Section {
      Text("Set Up Huddles").font(titleFont)
      Text(AIText.firstRunSteps).foregroundStyle(.secondary)
    }
    CloudflareKeysSteps(model: keys)
    Section {
      if let problem { StatusLine(problem, tone: .warning) }
      HStack {
        Button("Back") { step = .question }.disabled(keys.saving)
        Spacer()
        Button(keys.saving ? "Checking…" : "Save and Continue", systemImage: "arrow.right", action: save)
          .buttonStyle(.borderedProminent)
          .disabled(keys.saving || !keys.typed)
      }
    }
  }

  @ViewBuilder
  private var on: some View {
    Section {
      Text("Huddles Are On").font(titleFont)
      Text(AIText.firstRunOn).foregroundStyle(.secondary)
      Label(AIText.firstRunStart, systemImage: "headphones")
      Explanation(AIText.firstRunChange)
      Button("Open Ember", systemImage: "arrow.right", action: open).buttonStyle(.borderedProminent)
    }
  }

  /** Save and continue: whoever's been signed out meanwhile goes on into Ember, which has them sign in. */
  private func save() {
    problem = nil
    keys.save { error in
      logger.error("Setting up huddles on first run failed: \(error.localizedDescription, privacy: .public)")
      if (error as? EmberError) == .signedOut { return open() }
      problem = (error as? EmberError)?.problem == nil ? AIText.unreachable : error.localizedDescription
    }
  }
}
