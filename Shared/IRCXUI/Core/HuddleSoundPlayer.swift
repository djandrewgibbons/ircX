import AVFoundation
import EmberKit
import Foundation

/**
 * A huddle's own sounds (web lib/huddle-sounds.ts, huddle-ring.ts), Ember's own files
 * (Resources/HuddleSounds, with their README and license): a chime as someone joins, the app's person
 * among them, another as someone leaves, music for whoever is alone in the huddle from five seconds on,
 * which goes on from where it stopped next time, and the ring of an invitation. Each plays only while
 * the person hears it (`HuddleSounds`), as they have it at the time.
 */
@MainActor
final class HuddleSoundPlayer {
  /** `MUSIC_AFTER_MS` */
  static let musicAfter = 5.0

  /** Which sounds the person hears now. */
  var hears: () -> HuddleSounds = { HuddleSounds.all }

  private var players: [String: AVAudioPlayer] = [:]
  private var alone = false
  private var due = false
  private var ended = true
  private var musicTimer: Task<Void, Never>?
  private var ringing = false

  private func player(_ name: String) -> AVAudioPlayer? {
    if let player = players[name] { return player }
    guard let url = Bundle.module.url(forResource: name, withExtension: "mp3", subdirectory: "HuddleSounds") else {
      huddleLog.error("The huddle sound \(name, privacy: .public) isn't in the app")
      return nil
    }
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.prepareToPlay()
      players[name] = player
      return player
    } catch {
      huddleLog.error("Loading the huddle sound \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  private func chime(_ name: String, last: Bool = false) {
    guard hears().chimes, last || !ended, let player = player(name) else { return }
    player.currentTime = 0
    player.play()
  }

  /** A huddle has begun for the app. */
  func startHuddle() {
    ended = false
    due = false
    alone = false
  }

  /** Someone joined the huddle. */
  func joined() { chime("joined") }

  /** Someone else left it. */
  func left() { chime("left") }

  /** Says whether the app's person is alone in the huddle now: the music starts five seconds on, and stops as soon as they aren't. */
  func setAlone(_ now: Bool) {
    alone = now
    cueMusic()
  }

  /** Starts or stops the music as the person's choice now says, which a change to their sounds asks again. */
  func cueMusic() {
    let now = alone && hears().music && !ended
    guard now != due else { return }
    due = now
    musicTimer?.cancel()
    musicTimer = nil
    guard due else {
      players["music"]?.pause()
      return
    }
    musicTimer = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.musicAfter))
      guard !Task.isCancelled, let self, self.due, let music = self.player("music") else { return }
      music.numberOfLoops = -1
      music.play()
    }
  }

  /** The huddle has ended for the app: the music stops, and the leaving sound plays if the room had let it in. */
  func endHuddle(letIn: Bool) {
    setAlone(false)
    ended = true
    if letIn { chime("left", last: true) }
  }

  /** Rings for invitations, over and over, until stopped; nothing while the person has the ring off. */
  func ring(_ on: Bool) {
    guard on != ringing else { return }
    ringing = on
    guard let player = player("invited") else { return }
    if on {
      player.numberOfLoops = -1
      player.currentTime = 0
      player.play()
    } else {
      player.stop()
    }
  }
}
