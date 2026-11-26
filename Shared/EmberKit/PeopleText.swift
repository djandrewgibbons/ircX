import Foundation

/** The words the people pages show, by their names in the web app, so both themes say the same. */
public enum PeopleText {
  // Sign in (sign-in-page.tsx)
  public static let couldNotReach = "Couldn't reach Ember. Check your connection and try again."
  public static let welcomeBack = "Welcome back. Pick up the conversation."
  public static func signInTo(_ workspace: String) -> String { "Sign in to \(workspace)" }
  public static let transferRefused = "That sign-in link has expired or doesn't work any more. Ask for a new one."
  public static func joinWithDomain(_ domains: [String]) -> String { "Have an address at \(EmberText.domainsInWords(domains))? Join with it" }
  public static let signInLinkExplained =
    "This is your own private sign-in URL, DO NOT SHARE IT. Use it to sign-in on another device or if you get locked out."

  // Profile (profile-page.tsx)
  public static let profileExplained = "Manage how you appear to the people in your workspace."
  public static let avatarChanged = "It may take up to 30 minutes to change everywhere."
  public static let saved = "\u{2713}"
  public static let usernameHelp = "People find you by typing @ and your username."
  public static let keepPassword = "Leave blank to keep your current password."
  public static let keepNoPassword = "Leave blank to keep signing in without a password."
  public static let currentPasswordHelp = "Needed to change your email address or password."
  public static func disconnectsWithNewPassword(memberful: Bool, sso: Bool) -> String {
    if memberful && sso { return " Changing it disconnects Memberful and single sign-on." }
    if memberful { return " Changing it disconnects Memberful." }
    return sso ? " Changing it disconnects single sign-on." : ""
  }

  // External connections (external-connection.tsx)
  public static func connectedAs(_ account: ElsewhereAccount, name: String) -> String {
    guard let described = account.described else { return "Your \(name) account is connected." }
    return "Connected as \(described)."
  }
  public static func signsYouIn(_ name: String) -> String { "You sign in with \(name)." }
  public static func signsInEither(_ name: String) -> String { "You can sign in with \(name) or your password." }
  public static let disconnectingSignsOut = "Disconnecting signs you out everywhere else."
  public static let disconnectingAsksAgain = "Disconnecting signs you out everywhere else. You'll be asked to connect again the next time you sign in."
  public static let addEmailToDisconnect = "To disconnect, add an email address above so you can still sign in with your password."
  public static func membersSignInWith(_ name: String) -> String { "Members sign in with \(name). Connect your \(name) account to keep signing in." }
  public static func connectToSignIn(_ name: String) -> String { "Connect your \(name) account to sign in with it." }
  public static func memberfulClosed(_ sso: String) -> String { "Signing in with Memberful is off while members sign in with \(sso)." }
  public static func ssoClosed(_ sso: String) -> String { "Signing in with \(sso) is off while members sign in with Memberful." }

  // Apps (your-apps.tsx, app-signed-in-page.tsx)
  public static let yourAppsExplained =
    "Sign in to an app yourself, and what an agent does with it in your direct conversation with that agent, it does as you, after asking you each time. Everywhere else, agents use the sign-in an administrator made."
  public static let notSignedIn = "You haven't signed in. Agents use the sign-in an administrator made."
  public static let signInEnded = "Your sign-in has ended. Until you sign in again, or sign out, agents can't use this app for you in your direct conversations with them."
  public static let wantsMore = "It has asked for more access than your sign-in has. Sign in again to allow it."
  public static let finishingOwnSignIn = "Ember is finishing your sign-in."
  public static let signInTurnedDown = "The sign-in was turned down there, so nothing has changed."
  public static let signInNotFinished = "The sign-in wasn't finished there, so nothing has changed. Start it again."
  public static func signedInYourself(_ app: String) -> String {
    "You're signed in to \(app). What an agent does with it in your direct conversation with that agent, it now does as you."
  }
  public static func signedOut(_ app: String, revoked: Bool) -> String {
    revoked
      ? "You're signed out of \(app), which took your sign-in back."
      : "You're signed out of \(app) here. Ember couldn't take your sign-in back there, so remove Ember's access at \(app) too."
  }
  /** `statusOf` */
  public static func status(of app: YourApp, at: (String) -> String) -> String {
    guard let signedInAt = app.signedInAt else { return notSignedIn }
    if app.ended { return signInEnded }
    let signed = "You signed in \(at(signedInAt))."
    return app.wantsMore ? "\(signed) \(wantsMore)" : signed
  }

  // AI apps (your-outside-ai.tsx)
  public static let outsideAiExplained =
    "Connect an AI app, such as Claude, to Ember by giving it this address as a connector or MCP server. It sends you to a page here that asks you first, and can then see the open rooms you're in, read their messages and search them, as you can, and send messages as you if you let it. It's kept out of your direct messages and private rooms unless you let it in."
  public static let nothingConnected = "No AI app is connected as you."
  public static func disconnected(_ name: String) -> String { "\(name) is disconnected. It can't use Ember as you any more." }
  /** `connectionStatus` */
  public static func status(of connection: OutsideConnection, at: (String) -> String) -> String {
    let write = connection.scopes.contains(.write) ? " It can send messages as you." : ""
    let both = connection.scopes.contains(.private) ? " It can use your direct messages and private rooms too." : ""
    let connected = "From \(connection.comesBackTo), connected \(at(connection.connectedAt)).\(write)\(both)"
    guard let usedAt = connection.usedAt else { return "\(connected) It hasn't asked Ember anything yet." }
    return "\(connected) It last asked Ember something \(at(usedAt))."
  }

  // Outside connect (outside-connect-page.tsx)
  public static func connectTo(_ app: String, workspace: String) -> String { "Connect \(app) to \(workspace)?" }
  public static func actsAs(_ name: String) -> String { "It would act as you, \(name)." }
  public static let itWillBeAbleTo = "It will be able to:"
  public static let andIfYouLetIt = "And, if you let it:"
  public static func goesBackTo(_ host: String) -> String { "You'll go back to \(host). Allow this only if that's where you started." }
  public static let disconnectAnyTime = "You can disconnect it at any time on your profile."
  public static let cantConnect = "This app can't be connected"

  // Huddle sounds (huddle-sound-switches.tsx)
  public static let huddleSoundsExplained = "Choose which huddle sounds you hear. Your choices apply everywhere you're signed in."
  public static let musicExplained = "Play music when you're the only one in a huddle"
  public static let chimesExplained = "Play a sound when someone joins or leaves"
  public static let ringExplained = "Ring when someone invites you to a huddle"

  // Blocked people (blocked-people.tsx)
  public static let blockedExplained = "Their messages are collapsed for you, they can't notify you or start a direct message with you, and they aren't told."

  // Delete my account (delete-account.tsx)
  public static let deleteExplained =
    "This deletes your messages, files and reactions in every room and DM, and your name, photo, bio and email address. It can't be undone, and it can take a few minutes to reach every room."
  public static func typeYourName(_ name: String) -> String { "Type your name, \(name), to delete your account" }
  public static let accountDeleted = "Your account is deleted. It can take a few minutes for your messages to leave every room."

  // Report (report-dialog.tsx)
  public static let notReported = "Your report couldn't be sent. Please try again."
  public static let messageGone = "That message has been deleted."
  public static let personGone = "They're no longer in this community."
  public static func reportMessageExplained(_ name: String) -> String { "The administrators will see \(name)'s message as it is now. Nobody is told who reported it." }
  public static let reportPersonExplained = "For their name, picture or bio. Nobody is told who reported them."
  /** `administratorsNamed` */
  public static func administratorsNamed(_ names: [String]) -> String? {
    guard let last = names.last else { return nil }
    let list = names.count == 1 ? last : "\(names.dropLast().joined(separator: ", ")) and \(last)"
    return "\(list) \(names.count == 1 ? "is this community's administrator" : "are this community's administrators")."
  }
  public static func blockOffer(_ name: String) -> String { "You can block \(name) too: their messages collapse for you, and they can't start a DM with you." }

  // Join (join-page.tsx, email-sign-up-page.tsx, invitation-page.tsx)
  public static func joinTitle(_ workspace: String) -> String { "Join \(workspace)" }
  public static let joinExplained = "Create your account and join the conversation."
  public static let emailLinkExplained = "Enter your email address, and Ember will email you a link to join with it."
  public static func addressesCanJoin(_ domains: [String]) -> String { "Addresses at \(EmberText.domainsInWords(domains)) can join." }
  public static func checkEmailForLink(_ address: String) -> String {
    "Ember emailed \(address). Open the link in that email to go on. If it hasn't arrived in a few minutes, look in your spam folder."
  }
  public static let invitationForAddress = "Your invitation is for this address."
  public static let linkForAddress = "Your link is for this address."
  public static let pasteEmailedLink = "Paste the link from the email here."

  // Password reset (password-reset-page.tsx)
  public static let resetExplained = "Enter your email address, and Ember will email you a code to choose a new password with."
  public static func checkEmailForCode(_ address: String) -> String {
    "If \(address) has an account here, Ember emailed it a code that works for 15 minutes. If it hasn't arrived soon, look in your spam folder."
  }

  // Welcome (welcome-page.tsx)
  public static func welcomeTo(_ workspace: String) -> String { "Welcome to \(workspace)" }
  public static let welcomeExplained = "Choose how people here see you."

  // Setup (setup-page.tsx)
  public static let setupEnvironmentVariable = "EMBER_SETUP_PASSWORD"
  public static let setupClosed =
    "This deployment has no setup password, so nobody can set it up. Give it one: set EMBER_SETUP_PASSWORD in the Worker's secrets in the Cloudflare dashboard, then try again."
  public static let setupLinkNeeded = "Open the setup link that deploying Ember printed: paste it here. It's in the output of pnpm run deploy, or in the build's log in the Cloudflare dashboard."
  public static let setupPasswordHelp = "The one you gave Ember when you deployed it."
  public static let setupLinkStale = "That setup link is out of date. Type this Ember's setup password instead."
  public static let setupExplained = "Create the admin account for your workspace."
  public static let setupPasswordRule = "Must be at least 8 characters."
  public static let setupHuddlesQuestion = "Would you like to enable huddle chat?"
  public static let setupHuddlesExplained = "Huddles let people in a room talk to each other live."
  public static let setupHuddlesLater = "You can also turn it on later, in Admin under Huddles."
}
