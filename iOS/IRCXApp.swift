import IRCXUI
import SwiftUI

@main
struct IRCXApp: App {
  // Hears the APNs token and launching, which only an app delegate is told.
  @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var delegate

  var body: some Scene {
    IRCXScene()
  }
}
