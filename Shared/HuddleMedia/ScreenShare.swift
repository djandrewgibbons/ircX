#if os(macOS)
import CoreMedia
import Foundation
import ScreenCaptureKit
@preconcurrency import WebRTC

/**
 * A screen, or a window, shared through ScreenCaptureKit: the system's picker asks what to share each
 * time (`SCContentSharingPicker`), and each frame goes to the huddle's screen source, at most 15 a second
 * and 1920 by 1080, as the web's `getDisplayMedia` asks.
 */
final class ScreenShare: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  private let source: RTCVideoSource
  private let capturer: RTCVideoCapturer
  private var stream: SCStream?
  private var picked: CheckedContinuation<SCContentFilter?, Error>?
  private let frames = DispatchQueue(label: "ai.dxnd.ircX.screen")
  /** Called on the main actor as sharing stops other than by `stop()`. */
  var onEnded: (@MainActor () -> Void)?

  init(source: RTCVideoSource) {
    self.source = source
    capturer = RTCVideoCapturer(delegate: source)
  }

  /** Asks what to share and shares it; false when the person picks nothing. */
  @MainActor
  func start() async throws -> Bool {
    let picker = SCContentSharingPicker.shared
    var configuration = SCContentSharingPickerConfiguration()
    configuration.allowedPickerModes = [.singleDisplay, .singleWindow, .singleApplication]
    picker.defaultConfiguration = configuration
    picker.add(self)
    picker.isActive = true
    let filter = try await withCheckedThrowingContinuation { (done: CheckedContinuation<SCContentFilter?, Error>) in
      picked = done
      picker.present()
    }
    picker.remove(self)
    picker.isActive = false
    guard let filter else { return false }
    let scale = Double(filter.pointPixelScale)
    var width = Double(filter.contentRect.width) * scale
    var height = Double(filter.contentRect.height) * scale
    let fit = min(1, 1920 / max(width, 1), 1080 / max(height, 1))
    width = (width * fit).rounded()
    height = (height * fit).rounded()
    let settings = SCStreamConfiguration()
    settings.width = Int(width)
    settings.height = Int(height)
    settings.minimumFrameInterval = CMTime(value: 1, timescale: 15)
    settings.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    settings.showsCursor = true
    settings.queueDepth = 5
    let stream = SCStream(filter: filter, configuration: settings, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frames)
    try await stream.startCapture()
    self.stream = stream
    return true
  }

  @MainActor
  func stop() {
    guard let stream else { return }
    self.stream = nil
    Task {
      do {
        try await stream.stopCapture()
      } catch {
        HuddleEngine.logger.error("Stopping the screen share failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func answer(_ result: Result<SCContentFilter?, Error>) {
    DispatchQueue.main.async {
      let done = self.picked
      self.picked = nil
      done?.resume(with: result)
    }
  }

  func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
    answer(.success(filter))
  }

  func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
    answer(.success(nil))
  }

  func contentSharingPickerStartDidFailWithError(_ error: Error) {
    answer(.failure(error))
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, sampleBuffer.isValid, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let buffer = RTCCVPixelBuffer(pixelBuffer: pixels)
    let frame = RTCVideoFrame(buffer: buffer, rotation: ._0, timeStampNs: Int64(CMTimeGetSeconds(time) * 1_000_000_000))
    source.capturer(capturer, didCapture: frame)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    HuddleEngine.logger.error("The screen share stopped: \(error.localizedDescription, privacy: .public)")
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        guard self.stream != nil else { return }
        self.stream = nil
        self.onEnded?()
      }
    }
  }
}
#endif
