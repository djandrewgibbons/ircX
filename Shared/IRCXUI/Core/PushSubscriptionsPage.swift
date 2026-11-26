import AppCoreUI
import EmberKit
import SwiftUI

/** What notifications say, in both themes and `/push`. */
enum PushText {
  static let title = "Notifications"
  static let explained = "Notifies this device of messages, mentions and huddle invitations from this server, as its rooms' notification levels say."
  static let unconfigured = "Notifications aren't configured"
  static let unconfiguredExplained = "Ask your workspace administrator to configure push on this server."
  static let blocked = "Notifications are blocked"
  static let blockedExplained = "Allow notifications for ircX in System Settings, then try again."
  static let failed = "Couldn't enable notifications"
  static let failedExplained = "Check your connection and try again. Your room's notification settings haven't changed."
  static let testSent = "Sent a test notification"

  /** The state in a few words, as the switch's row and `/push` say it. */
  static func state(_ state: PushCenter.State) -> String {
    switch state {
    case .unconfigured: unconfigured
    case .blocked: blocked
    case .off: "Off"
    case .turningOn: "Turning on…"
    case .on: "On"
    case .failed: failed
    }
  }

  /** What to do about it, for `.help` and `/push`. */
  static func detail(_ state: PushCenter.State) -> String {
    switch state {
    case .unconfigured: unconfiguredExplained
    case .blocked: blockedExplained
    case .off, .turningOn, .on: explained
    case let .failed(reason): "\(reason). \(failedExplained)"
    }
  }

  /** The system's notification settings for ircX. */
  static var settingsURL: URL? {
    #if os(macOS)
    URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    #else
    URL(string: UIApplication.openNotificationSettingsURLString)
    #endif
  }
}

/**
 * The room header bell's way to notifications (web `NotificationBell` before it's on), under the level
 * choices in both themes: Enable Notifications while they're off, saying why in the room when they don't
 * come on; blocked or not configured, what's wrong, opening the Notifications page that says what to do.
 */
struct PushMenuItems: View {
  let session: InstanceSession
  let room: RoomModel

  var body: some View {
    let state = PushCenter.shared.state(of: session)
    switch state {
    case .on: EmptyView()
    case .turningOn:
      Divider()
      Text(PushText.state(state))
    case .off, .failed:
      Divider()
      Button("Enable Notifications", systemImage: "bell.badge") { Commander.runPush(.on, session: session, room: room) }
        .help(PushText.detail(state))
    case .blocked, .unconfigured:
      Divider()
      Button(state == .blocked ? "Notifications Blocked" : "Not Configured", systemImage: "bell.slash") { session.show(.pushSubscriptions) }
        .help(PushText.detail(state))
    }
  }
}

/**
 * Notifications (web `PushSubscriptionsPage`, `/users/me/push_subscriptions`), in place of the room in
 * either theme: this device's switch for this server, then each device and browser notified, oldest
 * first, with Send test notification and Delete.
 */
struct PushSubscriptionsPage: View {
  let session: InstanceSession
  @Environment(\.appTheme) private var look
  @Environment(\.theme) private var irc
  @Environment(\.openURL) private var openURL
  @State private var devices: [DeviceToken]?
  @State private var browsers: [SavedPushSubscription]?
  @State private var busy: Set<InputCommand.PushTarget> = []
  @State private var message: String?
  @State private var messageIsError = false
  private var push: PushCenter { PushCenter.shared }

  init(session: InstanceSession, devices: [DeviceToken]? = nil, browsers: [SavedPushSubscription]? = nil) {
    self.session = session
    _devices = State(initialValue: devices)
    _browsers = State(initialValue: browsers)
  }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: PushText.title, back: session.closePage)
      Form {
        if let message {
          switch look {
          case .suite:
            Notice(
              message, systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
              tint: messageIsError ? SemanticColor.warning : SemanticColor.positive, onDismiss: { self.message = nil })
          case .irc:
            Text("-!- \(message)").foregroundStyle(messageIsError ? irc.part : irc.join).onTapGesture { self.message = nil }
          }
        }
        thisDevice
        if let devices, !devices.isEmpty {
          Section {
            ForEach(devices) { device in
              row(
                Push.label(device), detail: device.origin, target: .device(device.id), mine: push.token == device.token,
                deleteHelp: "Delete device")
            }
          } header: {
            Text("Devices")
          }
        }
        if let browsers, !browsers.isEmpty {
          Section {
            ForEach(browsers) { browser in
              row(Push.label(browser), detail: browser.endpoint, target: .browser(browser.id), mine: false, deleteHelp: "Delete subscription")
            }
          } header: {
            Text("Browsers")
          }
        }
      }
      .themedForm(look, irc)
      .loadingActivity(devices == nil && browsers == nil && message == nil)
    }
    .task(id: push.saved[session.id]?.id) { await load() }
  }

  /** This device's switch for this server, and what it's at. */
  private var thisDevice: some View {
    let state = push.state(of: session)
    return Section {
      Toggle(isOn: Binding(get: { push.isWanted(session) }, set: { on in switchTo(on) })) {
        Text(PushText.title)
      }
      .disabled(state == .unconfigured)
      .help(PushText.detail(state))
      if state != .off {
        HStack {
          Text(PushText.state(state)).lineLimit(1).foregroundStyle(stateColor(state)).help(PushText.detail(state))
          Spacer()
          if state == .blocked, let url = PushText.settingsURL {
            Button("Open Settings") { openURL(url) }.help(PushText.blockedExplained)
          }
        }
      }
    } header: {
      Text("This Device")
    }
  }

  private func stateColor(_ state: PushCenter.State) -> Color {
    switch (look, state) {
    case (.suite, .on): SemanticColor.positive
    case (.suite, .blocked), (.suite, .failed), (.suite, .unconfigured): SemanticColor.warning
    case (.suite, _): .secondary
    case (.irc, .on): irc.join
    case (.irc, .blocked), (.irc, .failed), (.irc, .unconfigured): irc.part
    case (.irc, _): irc.dim
    }
  }

  /** A device or browser: its name, where it's notified at, Send test notification and Delete. */
  private func row(_ title: String, detail: String, target: InputCommand.PushTarget, mine: Bool, deleteHelp: String) -> some View {
    HStack(spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack(spacing: Spacing.sm) {
          Text(title).font(look == .irc ? Theme.font(13, weight: .bold) : DesignFont.bodyEmphasized).lineLimit(1)
          if mine {
            switch look {
            case .suite: StatusCapsule(text: "This device", help: "The device you're using")
            case .irc: Text("[this device]").foregroundStyle(irc.join)
            }
          }
        }
        Text(detail).font(look == .irc ? Theme.font(11) : DesignFont.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
          .help(detail)
      }
      Spacer(minLength: 0)
      switch look {
      case .suite:
        PaneIconButton(systemImage: "bell.fill", help: "Send test notification") { test(target) }
          .disabled(busy.contains(target))
        PaneIconButton(systemImage: "minus.circle", help: deleteHelp, role: .destructive) { delete(target) }
          .disabled(busy.contains(target))
      case .irc:
        Button("[test]") { test(target) }.buttonStyle(.plain).foregroundStyle(irc.ember).help("Send test notification")
          .disabled(busy.contains(target))
        Button("[del]") { delete(target) }.buttonStyle(.plain).foregroundStyle(irc.part).help(deleteHelp)
          .disabled(busy.contains(target))
      }
    }
  }

  private func switchTo(_ on: Bool) {
    message = nil
    Task {
      if on {
        await push.turnOn(session)
      } else {
        do {
          try await push.turnOff(session)
        } catch {
          show(error, doing: "Turning notifications off")
        }
      }
      await load()
    }
  }

  private func test(_ target: InputCommand.PushTarget) {
    busy.insert(target)
    Task {
      defer { busy.remove(target) }
      do {
        try await push.test(target, on: session)
        message = PushText.testSent
        messageIsError = false
      } catch {
        show(error, doing: "Sending a test notification")
      }
    }
  }

  private func delete(_ target: InputCommand.PushTarget) {
    busy.insert(target)
    Task {
      defer { busy.remove(target) }
      do {
        try await push.delete(target, on: session)
        switch target {
        case let .device(id): devices?.removeAll { $0.id == id }
        case let .browser(id): browsers?.removeAll { $0.id == id }
        }
      } catch {
        show(error, doing: "Deleting a device")
      }
    }
  }

  private func load() async {
    do {
      async let devices = session.api.deviceTokens()
      async let browsers = session.api.pushSubscriptions()
      (self.devices, self.browsers) = try await (devices, browsers)
    } catch {
      show(error, doing: "Loading devices")
    }
  }

  private func show(_ error: Error, doing: String) {
    logger.error("\(doing, privacy: .public) on \(session.instance.host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    message = error.localizedDescription
    messageIsError = true
  }
}
