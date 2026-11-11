import Foundation

/**
 * A WebSocket to Ember that stays connected: it pings to keep the connection alive through proxies,
 * and connects again with backoff after it drops, asking `makeRequest` for a fresh address each time,
 * so a room socket can name the latest change it has seen. It stops for good on the close codes that
 * say access has ended.
 */
@MainActor
public final class EmberSocket {
  public enum State: Equatable, Sendable {
    case idle, connecting, open
    case waiting(retryIn: TimeInterval)
    case closed(CloseCode?)
  }

  public private(set) var state: State = .idle {
    didSet { onState?(state) }
  }

  public var onState: ((State) -> Void)?
  public var onOpen: (() -> Void)?
  public var onText: ((String) -> Void)?
  /** Called with Ember's close code when it ends access, after which the socket stays closed. */
  public var onEnded: ((CloseCode) -> Void)?
  /**
   * Called each time the socket drops and will connect again. Foundation reports Ember's own close codes
   * (4001, 4003, 4004) as invalid, so owners check over HTTP whether access has ended, and `disconnect()` if so.
   */
  public var onDropped: (() -> Void)?

  private let makeRequest: () -> URLRequest
  private let session: URLSession
  private let delegate = Delegate()
  private var task: URLSessionWebSocketTask?
  private var pinger: Task<Void, Never>?
  private var retry: Task<Void, Never>?
  private var attempts = 0
  private var generation = 0
  private let pingFrame: String

  public init(pingFrame: String = #"{"type":"ping"}"#, makeRequest: @escaping () -> URLRequest) {
    self.makeRequest = makeRequest
    self.pingFrame = pingFrame
    let config = URLSessionConfiguration.default
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.httpCookieStorage = nil
    session = URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
  }

  public func connect() {
    switch state {
    case .connecting, .open: return
    default: break
    }
    retry?.cancel()
    generation += 1
    let current = generation
    state = .connecting
    let task = session.webSocketTask(with: makeRequest())
    task.maximumMessageSize = 16 * 1024 * 1024
    self.task = task
    delegate.onOpen = { [weak self] in
      Task { @MainActor in self?.opened(generation: current) }
    }
    delegate.onClose = { [weak self] code in
      Task { @MainActor in self?.dropped(generation: current, code: code) }
    }
    task.resume()
    receive(on: task, generation: current)
  }

  /** Closes the socket and doesn't connect again until `connect()`. */
  public func disconnect() {
    generation += 1
    retry?.cancel()
    pinger?.cancel()
    task?.cancel(with: .normalClosure, reason: nil)
    task = nil
    state = .idle
  }

  /** Sends `text` if the socket is open, and says whether it did. */
  @discardableResult
  public func send(_ text: String) -> Bool {
    guard state == .open, let task else { return false }
    task.send(.string(text)) { _ in }
    return true
  }

  @discardableResult
  public func send(_ frame: ClientFrame) -> Bool {
    guard let text = try? frame.encoded() else { return false }
    return send(text)
  }

  private func opened(generation current: Int) {
    guard current == generation else { return }
    attempts = 0
    state = .open
    pinger?.cancel()
    pinger = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(25))
        guard let self, !Task.isCancelled else { return }
        self.send(self.pingFrame)
      }
    }
    onOpen?()
  }

  private func receive(on task: URLSessionWebSocketTask, generation current: Int) {
    task.receive { [weak self] result in
      Task { @MainActor in
        guard let self, current == self.generation else { return }
        switch result {
        case let .success(.string(text)):
          self.onText?(text)
          self.receive(on: task, generation: current)
        case let .success(.data(data)):
          self.onText?(String(decoding: data, as: UTF8.self))
          self.receive(on: task, generation: current)
        case .success:
          self.receive(on: task, generation: current)
        case .failure:
          self.dropped(generation: current, code: task.closeCode.rawValue)
        }
      }
    }
  }

  private func dropped(generation current: Int, code: Int) {
    guard current == generation else { return }
    generation += 1
    pinger?.cancel()
    task?.cancel()
    task = nil
    if let ended = CloseCode(rawValue: code), ended != .reconnect {
      state = .closed(ended)
      onEnded?(ended)
      return
    }
    onDropped?()
    // 0.5s, 1s, 2s ... up to 30s, with jitter so a restarted Worker isn't met by every client at once.
    let delay = min(30, 0.5 * pow(2, Double(attempts))) * Double.random(in: 0.8...1.2)
    attempts += 1
    state = .waiting(retryIn: delay)
    retry = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      self?.state = .idle
      self?.connect()
    }
  }

  private final class Delegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: (() -> Void)?
    var onClose: ((Int) -> Void)?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
      onOpen?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
      onClose?(closeCode.rawValue)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
      onClose?((task as? URLSessionWebSocketTask)?.closeCode.rawValue ?? 1006)
    }
  }
}
