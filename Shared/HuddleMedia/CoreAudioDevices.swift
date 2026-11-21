#if os(macOS)
import CoreAudio
import Foundation
import OSLog

/**
 * A Mac's audio devices, by CoreAudio: those that take sound in (microphones) or play it (speakers), the
 * default of each, which libwebrtc records from and plays through, and a watch on them changing.
 */
@MainActor
enum CoreAudioDevices {
  static let logger = Logger(subsystem: "ai.dxnd.ircX", category: "huddle")
  static let system = AudioObjectID(kAudioObjectSystemObject)

  static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  /** The devices that take sound in (`input`), or play it, by their ids and names. */
  static func list(input: Bool) -> [HuddleDevice] {
    var where_ = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(system, &where_, 0, nil, &size)
    guard status == noErr else {
      logger.error("Listing audio devices failed: \(status)")
      return []
    }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    status = AudioObjectGetPropertyData(system, &where_, 0, nil, &size, &ids)
    guard status == noErr else {
      logger.error("Listing audio devices failed: \(status)")
      return []
    }
    return ids.filter { hasStreams($0, input: input) }.compactMap { id in
      guard let uid = uid(id), let name = name(id) else { return nil }
      return HuddleDevice(id: uid, name: name)
    }
  }

  static func hasStreams(_ id: AudioObjectID, input: Bool) -> Bool {
    var where_ = address(kAudioDevicePropertyStreams, scope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(id, &where_, 0, nil, &size) == noErr && size > 0
  }

  static func uid(_ id: AudioObjectID) -> String? { text(id, kAudioDevicePropertyDeviceUID) }
  static func name(_ id: AudioObjectID) -> String? { text(id, kAudioObjectPropertyName) }

  private static func text(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var where_ = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &where_, 0, nil, &size, $0) }
    guard status == noErr, let value else {
      logger.error("Reading audio device \(id)'s property \(selector) failed: \(status)")
      return nil
    }
    return value.takeRetainedValue() as String
  }

  /** The Mac's default input (`input`) or output, or nil while there's none. */
  static func defaultDevice(input: Bool) -> AudioObjectID? {
    var where_ = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(system, &where_, 0, nil, &size, &id)
    guard status == noErr else {
      logger.error("Reading the default audio device failed: \(status)")
      return nil
    }
    return id == kAudioObjectUnknown ? nil : id
  }

  /** Makes the device `uid` the Mac's default input (`input`) or output. */
  static func makeDefault(_ uid: String, input: Bool) throws {
    var where_ = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &where_, 0, nil, &size) == noErr else { throw HuddleMediaError.noDevice }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &where_, 0, nil, &size, &ids) == noErr,
      var id = ids.first(where: { self.uid($0) == uid && hasStreams($0, input: input) })
    else { throw HuddleMediaError.noDevice }
    var chosen = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
    let status = AudioObjectSetPropertyData(system, &chosen, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
    guard status == noErr else { throw HuddleMediaError.coreAudio(status) }
  }

  /** Calls `changed` on the main queue as devices come and go, or the default input or output changes. */
  @MainActor
  final class Watch {
    private let block: AudioObjectPropertyListenerBlock
    private var watching: [AudioObjectPropertyAddress] = []

    init(_ changed: @escaping @MainActor () -> Void) {
      block = { _, _ in MainActor.assumeIsolated { changed() } }
      for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice] {
        var where_ = CoreAudioDevices.address(selector)
        let status = AudioObjectAddPropertyListenerBlock(CoreAudioDevices.system, &where_, .main, block)
        if status == noErr {
          watching.append(where_)
        } else {
          CoreAudioDevices.logger.error("Watching audio devices failed: \(status)")
        }
      }
    }

    func stop() {
      for var where_ in watching {
        let status = AudioObjectRemovePropertyListenerBlock(CoreAudioDevices.system, &where_, .main, block)
        if status != noErr { CoreAudioDevices.logger.error("Unwatching audio devices failed: \(status)") }
      }
      watching = []
    }
  }
}
#endif
