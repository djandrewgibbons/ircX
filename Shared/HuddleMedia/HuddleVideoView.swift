import SwiftUI
@preconcurrency import WebRTC

/**
 * A picture as it plays: someone's camera or screen, or the app's own, at its own shape, filling
 * (`fill`, as a tile does) or fitting (as a screen shown large does) the space it's given, and
 * mirrored where it's the app's own front camera.
 */
public struct HuddleVideoView: View {
  let picture: HuddlePicture
  let fill: Bool
  let onShape: ((Double) -> Void)?
  @State private var size = CGSize(width: 16, height: 9)

  public init(picture: HuddlePicture, fill: Bool, onShape: ((Double) -> Void)? = nil) {
    self.picture = picture
    self.fill = fill
    self.onShape = onShape
  }

  public var body: some View {
    if picture.still {
      Rectangle().fill(Color.gray.opacity(0.35)).overlay { Image(systemName: "rectangle.on.rectangle").foregroundStyle(.secondary) }
    } else {
      playing
    }
  }

  private var playing: some View {
    GeometryReader { space in
      VideoSurface(track: picture.track) { shown in
        guard shown.width > 0, shown.height > 0 else { return }
        size = shown
        onShape?(Double(shown.width / shown.height))
      }
      .aspectRatio(size, contentMode: fill ? .fill : .fit)
      .frame(width: space.size.width, height: space.size.height)
      .scaleEffect(x: picture.mirrored ? -1 : 1, y: 1)
    }
    .clipped()
  }
}

#if os(macOS)
private struct VideoSurface: NSViewRepresentable {
  let track: RTCVideoTrack
  let sized: (CGSize) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(sized: sized) }

  func makeNSView(context: Context) -> RTCMTLNSVideoView {
    let view = RTCMTLNSVideoView(frame: .zero)
    view.delegate = context.coordinator
    track.add(view)
    context.coordinator.track = track
    return view
  }

  func updateNSView(_ view: RTCMTLNSVideoView, context: Context) {
    context.coordinator.sized = sized
    guard context.coordinator.track !== track else { return }
    context.coordinator.track?.remove(view)
    track.add(view)
    context.coordinator.track = track
  }

  static func dismantleNSView(_ view: RTCMTLNSVideoView, coordinator: Coordinator) {
    coordinator.track?.remove(view)
  }

  final class Coordinator: NSObject, RTCVideoViewDelegate {
    var sized: (CGSize) -> Void
    var track: RTCVideoTrack?

    init(sized: @escaping (CGSize) -> Void) { self.sized = sized }

    func videoView(_ videoView: any RTCVideoRenderer, didChangeVideoSize size: CGSize) {
      DispatchQueue.main.async { self.sized(size) }
    }
  }
}
#else
private struct VideoSurface: UIViewRepresentable {
  let track: RTCVideoTrack
  let sized: (CGSize) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(sized: sized) }

  func makeUIView(context: Context) -> RTCMTLVideoView {
    let view = RTCMTLVideoView(frame: .zero)
    view.videoContentMode = .scaleToFill
    view.delegate = context.coordinator
    track.add(view)
    context.coordinator.track = track
    return view
  }

  func updateUIView(_ view: RTCMTLVideoView, context: Context) {
    context.coordinator.sized = sized
    guard context.coordinator.track !== track else { return }
    context.coordinator.track?.remove(view)
    track.add(view)
    context.coordinator.track = track
  }

  static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
    coordinator.track?.remove(view)
  }

  final class Coordinator: NSObject, RTCVideoViewDelegate {
    var sized: (CGSize) -> Void
    var track: RTCVideoTrack?

    init(sized: @escaping (CGSize) -> Void) { self.sized = sized }

    func videoView(_ videoView: any RTCVideoRenderer, didChangeVideoSize size: CGSize) {
      DispatchQueue.main.async { self.sized(size) }
    }
  }
}
#endif
