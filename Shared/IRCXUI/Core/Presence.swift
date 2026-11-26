import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/**
 * Whether the app's in use, as the web's `watchUse` tells: in use until 10 minutes pass without a key,
 * click, scroll or touch (`AWAY_AFTER_MS`), and in use again at the next.
 */
@MainActor
final class UseWatcher {
  static let awayAfter: TimeInterval = 10 * 60

  private(set) var inUse = true
  var onChange: ((Bool) -> Void)?

  private var usedAt = Date()
  private var check: Task<Void, Never>?
  #if os(macOS)
  private var monitor: Any?
  #else
  private var watched: Set<ObjectIdentifier> = []
  #endif

  func start() {
    #if os(macOS)
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .scrollWheel]) { [weak self] event in
      self?.used()
      return event
    }
    #endif
    schedule(after: Self.awayAfter)
  }

  /** Notes a use, as focusing the app or touching it is. */
  func used() {
    usedAt = Date()
    guard !inUse else { return }
    inUse = true
    schedule(after: Self.awayAfter)
    onChange?(true)
  }

  #if os(iOS)
  /** Watches the app's windows for touches and key presses, without taking them from the views under them. */
  func watchWindows() {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    for window in windows where !watched.contains(ObjectIdentifier(window)) {
      watched.insert(ObjectIdentifier(window))
      let watcher = TouchWatcher { [weak self] in self?.used() }
      window.addGestureRecognizer(watcher)
    }
  }
  #endif

  private func schedule(after delay: TimeInterval) {
    check?.cancel()
    check = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      self?.checkUse()
    }
  }

  private func checkUse() {
    let unused = Date().timeIntervalSince(usedAt)
    guard unused >= Self.awayAfter else {
      schedule(after: Self.awayAfter - unused)
      return
    }
    inUse = false
    onChange?(false)
  }
}

#if os(iOS)
/** A recognizer that only notes touches and presses, then steps aside, so every other gesture still works. */
private final class TouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
  private let touched: () -> Void

  init(touched: @escaping () -> Void) {
    self.touched = touched
    super.init(target: nil, action: nil)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
    delegate = self
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    touched()
    state = .failed
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
    touched()
    state = .failed
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif
