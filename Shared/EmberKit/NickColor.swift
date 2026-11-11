import Foundation

/**
 * Which of the theme's nick colors someone gets: the same for a person on every instance and device,
 * by a stable hash of their id (Swift's `hashValue` changes each launch).
 */
public enum NickColor {
  public static func index(for userID: String, among count: Int) -> Int {
    guard count > 0 else { return 0 }
    // FNV-1a, 32-bit.
    var hash: UInt32 = 2_166_136_261
    for byte in userID.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* 16_777_619
    }
    return Int(hash % UInt32(count))
  }
}
