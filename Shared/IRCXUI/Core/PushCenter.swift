import EmberKit
import Foundation
import Observation
import OSLog
@preconcurrency import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private let pushLogger = Logger(subsystem: "ai.dxnd.ircX", category: "push")

/**
 * Notifications from Ember's servers through APNs, as the web's push subscriptions do for a browser:
 * the system's permission, this device's token, which each server whose switch is on keeps (`POST
 * /api/device-tokens`, saved again at every launch and sign-in, as the web saves its subscription again),
 * opening the server, room and message a notification is about, and clearing a room's notifications
 * once it's read. Servers end a device with its session, so signing out needs nothing more.
 */
@MainActor
@Observable
public final class PushCenter: NSObject {
  public static let shared = PushCenter()

  /** What the system allows. */
  public enum Permission: Equatable, Sendable {
    case unknown, notDetermined, denied, allowed
  }

  public private(set) var permission: Permission = .unknown
  /** This device's APNs token, in hexadecimal, once the system gives it. */
  public private(set) var token: String?
  /** Why the system couldn't register for notifications. */
  public private(set) var registrationFailure: String?
  /** The device each server saved, by instance. */
  public private(set) var saved: [UUID: DeviceToken] = [:]
  /** The servers saving this device now. */
  public private(set) var saving: Set<UUID> = []
  /** Why saving this device on a server failed, by instance. */
  public private(set) var failures: [UUID: String] = [:]
  /** The servers whose switch is on, on this device. */
  public private(set) var wanted: Set<UUID>

  @ObservationIgnored private weak var app: AppModel?
  /** A notification opened before the app's model was made, opened once it is. */
  @ObservationIgnored private var pendingOpen: DevicePushData?
  /** Whether the app launched as an app, with a notification center; render tests and `swift test` never do. */
  @ObservationIgnored private var launched = false

  private static let wantedKey = "ircX.push.servers"

  override init() {
    // Nothing saved: no server's switch is on yet.
    if let ids = UserDefaults.standard.stringArray(forKey: Self.wantedKey) {
      wanted = Set(ids.compactMap(UUID.init(uuidString:)))
    } else {
      wanted = []
    }
    super.init()
  }

  // MARK: - The app

  /** The app finished launching: notifications come here, and a server switched on registers again (Apple asks for it at every launch). */
  func didLaunch() {
    launched = true
    UNUserNotificationCenter.current().delegate = self
    Task { await refreshPermission(registering: true) }
  }

  /** The app's model, which notifications open servers in. */
  func attach(_ app: AppModel) {
    self.app = app
    if let pending = pendingOpen {
      pendingOpen = nil
      app.openNotification(pending)
    }
  }

  func registered(_ deviceToken: Data) {
    token = Push.hex(deviceToken)
    registrationFailure = nil
    guard let app else { return }
    for session in app.sessions { save(session) }
  }

  func failedToRegister(_ error: Error) {
    pushLogger.error("Registering for notifications failed: \(error.localizedDescription, privacy: .public)")
    registrationFailure = error.localizedDescription
  }

  /**
   * Asks the system what it allows. Once it allows notifications and a server's switch is on, registers
   * (at launch, or when there's no token yet, as after notifications were allowed in System Settings), or
   * saves this device on each server switched on that hasn't saved it.
   */
  func refreshPermission(registering: Bool) async {
    guard launched else { return }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined: permission = .notDetermined
    case .denied: permission = .denied
    default: permission = .allowed
    }
    guard permission == .allowed, !wanted.isEmpty else { return }
    if registering || token == nil {
      register()
    } else if let app {
      for session in app.sessions where saved[session.id] == nil { save(session) }
    }
  }

  private func register() {
    #if os(macOS)
    NSApplication.shared.registerForRemoteNotifications()
    #else
    UIApplication.shared.registerForRemoteNotifications()
    #endif
  }

  // MARK: - A server's switch

  /** What a server's notifications on this device are at. */
  public enum State: Equatable, Sendable {
    /** The server can't push through APNs (`Bootstrap.apnsPush`). */
    case unconfigured
    /** The system doesn't allow ircX's notifications. */
    case blocked
    case off
    case turningOn
    case on
    case failed(String)
  }

  public func isWanted(_ session: InstanceSession) -> Bool { wanted.contains(session.id) }

  public func state(of session: InstanceSession) -> State {
    guard session.bootstrap?.apnsPush == true else { return .unconfigured }
    guard wanted.contains(session.id) else { return .off }
    if permission == .denied { return .blocked }
    if let failure = failures[session.id] ?? registrationFailure { return .failed(failure) }
    return saved[session.id] == nil ? .turningOn : .on
  }

  /** Turns a server's notifications on here, asking the system first if it hasn't been asked. */
  public func turnOn(_ session: InstanceSession) async {
    setWanted(true, session)
    failures[session.id] = nil
    guard session.bootstrap?.apnsPush == true, launched else { return }
    if permission != .allowed {
      do {
        let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        permission = allowed ? .allowed : .denied
      } catch {
        pushLogger.error("Asking to notify failed: \(error.localizedDescription, privacy: .public)")
        failures[session.id] = error.localizedDescription
        return
      }
    }
    guard permission == .allowed else { return }
    if token == nil { register() } else { save(session) }
  }

  /** Why a server's notifications can't be turned off now. */
  public struct NotConnected: LocalizedError {
    let server: String
    public var errorDescription: String? { "Connect to \(server) to turn its notifications off" }
  }

  /**
   * Turns a server's notifications off here: the server forgets this device. Only once it's connected, so
   * it can forget it; a server signed out forgot it with the session.
   */
  public func turnOff(_ session: InstanceSession) async throws {
    switch session.phase {
    case .ready:
      if let device = try await thisDevice(on: session) { try await session.api.deleteDeviceToken(device.id) }
    case .signedOut: break
    case .checking, .unreachable, .notSetUp: throw NotConnected(server: session.name)
    }
    setWanted(false, session)
    failures[session.id] = nil
    saved[session.id] = nil
  }

  /** This device as the server lists it, if it does. */
  func thisDevice(on session: InstanceSession) async throws -> DeviceToken? {
    if let device = saved[session.id] { return device }
    guard let token else { return nil }
    return try await session.api.deviceTokens().first { $0.token == token }
  }

  private func setWanted(_ on: Bool, _ session: InstanceSession) {
    if on { wanted.insert(session.id) } else { wanted.remove(session.id) }
    UserDefaults.standard.set(wanted.map(\.uuidString).sorted(), forKey: Self.wantedKey)
  }

  /** Saves this device on a server whose switch is on, once it's signed in and can push. */
  func save(_ session: InstanceSession) {
    guard let token, wanted.contains(session.id), session.phase == .ready, session.bootstrap?.apnsPush == true, !saving.contains(session.id) else { return }
    saving.insert(session.id)
    let save = DeviceTokenSave(
      token: token, platform: Self.platform, environment: Self.environment, origin: session.instance.origin.lowercased(), deviceName: Self.deviceName)
    Task {
      defer { saving.remove(session.id) }
      do {
        saved[session.id] = try await session.api.saveDeviceToken(save)
        failures[session.id] = nil
      } catch {
        failures[session.id] = error.localizedDescription
        session.fail("Saving this device for notifications", error)
      }
    }
  }

  /** A server signed out here: its session took this device with it. */
  func signedOut(_ session: InstanceSession) {
    saved[session.id] = nil
  }

  /** Forgets this device's record of a server removed from the app. */
  func removed(_ session: InstanceSession) {
    saved[session.id] = nil
    failures[session.id] = nil
    setWanted(false, session)
  }

  /** Sends a test notification ("Ember Test") to a device or a browser. */
  public func test(_ target: InputCommand.PushTarget, on session: InstanceSession) async throws {
    switch target {
    case let .device(id): try await session.api.testDeviceToken(id)
    case let .browser(id): try await session.api.testPushSubscription(id)
    }
  }

  /** Forgets a device or a browser; this device's switch goes off with it, as deleting a browser's own subscription ends it on the web. */
  public func delete(_ target: InputCommand.PushTarget, on session: InstanceSession) async throws {
    switch target {
    case let .device(id):
      let mine = try await thisDevice(on: session)?.id == id
      try await session.api.deleteDeviceToken(id)
      if mine {
        saved[session.id] = nil
        setWanted(false, session)
      }
    case let .browser(id): try await session.api.deletePushSubscription(id)
    }
  }

  private static var platform: DevicePlatform {
    #if os(macOS)
    .macos
    #else
    .ios
    #endif
  }

  /** Which APNs host the token comes from: a debug build's is the sandbox's. */
  private static var environment: DeviceEnvironment {
    #if DEBUG
    .development
    #else
    .production
    #endif
  }

  private static var deviceName: String? {
    #if os(macOS)
    Host.current().localizedName
    #else
    UIDevice.current.name
    #endif
  }

  // MARK: - Delivered notifications

  /** Removes a room's notifications from the system's list once it's read in the app. */
  func clearDelivered(room: RoomID, origin: String) {
    guard launched else { return }
    let center = UNUserNotificationCenter.current()
    Task {
      let ids = await center.deliveredNotifications().filter { note in
        note.request.content.threadIdentifier == room && DevicePushData(userInfo: note.request.content.userInfo)?.origin == origin.lowercased()
      }
      .map(\.request.identifier)
      if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }
  }

  /** Whether a notification needs no banner: its room is on screen, or it's a huddle's invitation the app is ringing for. */
  func showsInApp(_ data: DevicePushData) -> Bool {
    guard let app, app.isActive, let roomId = data.roomId,
      let session = app.sessions.first(where: { $0.instance.origin.lowercased() == data.origin }), session.phase == .ready
    else { return false }
    if data.messageId == nil { return app.huddles.isRinging(for: roomId, in: session) }
    return session.isForeground && session.page == nil && session.selectedRoomID == roomId && data.parentId == nil
  }

  fileprivate func open(_ data: DevicePushData) {
    guard let app else {
      pendingOpen = data
      return
    }
    app.openNotification(data)
  }
}

extension PushCenter: UNUserNotificationCenterDelegate {
  public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    guard let data = DevicePushData(userInfo: response.notification.request.content.userInfo) else {
      pushLogger.error("A notification without a server or page was opened")
      return
    }
    await MainActor.run { PushCenter.shared.open(data) }
  }

  public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions
  {
    guard let data = DevicePushData(userInfo: notification.request.content.userInfo) else { return [.banner, .list, .sound] }
    let inApp = await MainActor.run { PushCenter.shared.showsInApp(data) }
    return inApp ? [] : [.banner, .list, .sound]
  }
}

#if os(macOS)
/** The app's delegate, for what only an app delegate hears: launching, and the APNs token. */
public final class PushAppDelegate: NSObject, NSApplicationDelegate {
  public override init() { super.init() }

  public func applicationDidFinishLaunching(_ notification: Notification) {
    PushCenter.shared.didLaunch()
  }

  public func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    PushCenter.shared.registered(deviceToken)
  }

  public func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    PushCenter.shared.failedToRegister(error)
  }
}
#else
/** The app's delegate, for what only an app delegate hears: launching, and the APNs token. */
public final class PushAppDelegate: NSObject, UIApplicationDelegate {
  public override init() { super.init() }

  public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    PushCenter.shared.didLaunch()
    return true
  }

  public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    PushCenter.shared.registered(deviceToken)
  }

  public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    PushCenter.shared.failedToRegister(error)
  }
}
#endif
